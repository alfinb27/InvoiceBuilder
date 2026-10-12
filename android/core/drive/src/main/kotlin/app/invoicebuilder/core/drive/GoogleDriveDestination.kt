package app.invoicebuilder.core.drive

import app.invoicebuilder.core.domain.backup.CloudBackupDestination
import app.invoicebuilder.core.domain.backup.CloudBackupEntry
import app.invoicebuilder.core.domain.backup.CloudBackupError
import app.invoicebuilder.core.domain.backup.CloudBackupException
import app.invoicebuilder.core.domain.backup.CloudBackupTarget
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.putJsonObject
import java.net.URLEncoder

/** Access tokens for the `drive.file` scope ([GoogleAuth] in the app; tests fake it). iOS: `GoogleAuth`. */
interface DriveAuth {
    /** Asks for consent (a Google sheet) when needed. Throws `Cancelled` when the user closes it. */
    suspend fun signIn()
    /** A valid token; [forceRefresh] drops the cached one first (after a 401). Throws `SignedOut` without consent. */
    suspend fun accessToken(forceRefresh: Boolean = false): String
    /** Revokes the grant (best effort) and forgets the account. */
    suspend fun signOut()
}

/**
 * Backups in a visible "InvoiceBuilder backups" folder of the user's Google Drive (`spec/backup.md` §7), through
 * Drive REST v3 with the `drive.file` scope: the app sees only the files it created. iOS: `GoogleDriveDestination`.
 */
class GoogleDriveDestination(private val auth: DriveAuth, private val http: HttpTransport) : CloudBackupDestination {
    companion object {
        const val API = "https://www.googleapis.com/drive/v3/"
        const val UPLOAD_API = "https://www.googleapis.com/upload/drive/v3/"
        const val FOLDER_NAME = "InvoiceBuilder backups"
        const val FOLDER_TYPE = "application/vnd.google-apps.folder"
        const val FILE_TYPE = "application/json"
    }

    /** A 404 from Drive (a file or folder that is gone). */
    private class NotFound : Exception()

    override suspend fun connect(): String {
        auth.signIn()
        // `about` answers with any Drive scope, so no extra profile scope is needed for the email.
        val about = json(get("about", mapOf("fields" to "user(emailAddress)")))
        return about["user"]?.jsonObject?.get("emailAddress")?.jsonPrimitive?.contentOrNull ?: "Google Drive"
    }

    override suspend fun disconnect() = auth.signOut()

    override suspend fun folder(knownID: String?): String {
        if (knownID != null) {
            try {
                val meta = json(get("files/$knownID", mapOf("fields" to "id,trashed")))
                if (meta["trashed"]?.jsonPrimitive?.booleanOrNull != true) return meta["id"]!!.jsonPrimitive.content
            } catch (_: NotFound) {
            }
        }
        val query = "mimeType = '$FOLDER_TYPE' and name = '$FOLDER_NAME' and trashed = false and 'root' in parents"
        val found = json(get("files", mapOf("q" to query, "orderBy" to "createdTime", "fields" to "files(id)", "spaces" to "drive")))
        found["files"]?.jsonArray?.firstOrNull()?.let { return it.jsonObject["id"]!!.jsonPrimitive.content }
        val body = buildJsonObject {
            put("name", FOLDER_NAME)
            put("mimeType", FOLDER_TYPE)
            putJsonArray("parents") { add(JsonPrimitive("root")) }
        }
        val created = json(authorized(HttpRequest("${API}files?fields=id", "POST",
            mapOf("Content-Type" to "application/json; charset=UTF-8"), body.toString().toByteArray())))
        return created["id"]!!.jsonPrimitive.content
    }

    override suspend fun list(folderID: String): List<CloudBackupEntry> {
        val entries = mutableListOf<CloudBackupEntry>()
        var pageToken: String? = null
        do {
            val query = mutableMapOf("q" to "'$folderID' in parents and trashed = false", "pageSize" to "200", "spaces" to "drive",
                "fields" to "nextPageToken,files(id,name,appProperties)")
            pageToken?.let { query["pageToken"] = it }
            val page = json(get("files", query))
            page["files"]?.jsonArray?.forEach { element ->
                val file = element.jsonObject
                val properties = file["appProperties"]?.jsonObject?.mapValues { it.value.jsonPrimitive.content } ?: emptyMap()
                entries += CloudBackupEntry.of(file["id"]!!.jsonPrimitive.content, file["name"]?.jsonPrimitive?.contentOrNull ?: "", properties)
            }
            pageToken = page["nextPageToken"]?.jsonPrimitive?.contentOrNull
        } while (pageToken != null)
        return entries
    }

    /** A resumable upload (one session request, then the bytes), so any backup size works. */
    override suspend fun upload(data: ByteArray, name: String, properties: Map<String, String>, target: CloudBackupTarget, folderID: String): String {
        val metadata = buildJsonObject {
            put("name", name)
            put("mimeType", FILE_TYPE)
            putJsonObject("appProperties") { properties.forEach { (key, value) -> put(key, value) } }
            if (target is CloudBackupTarget.Create) putJsonArray("parents") { add(JsonPrimitive(folderID)) }
        }
        val (path, method) = when (target) {
            CloudBackupTarget.Create -> "files" to "POST"
            is CloudBackupTarget.Update -> "files/${target.id}" to "PATCH"
        }
        val session = send(authorized(HttpRequest("$UPLOAD_API$path?uploadType=resumable&fields=id", method, mapOf(
            "Content-Type" to "application/json; charset=UTF-8", "X-Upload-Content-Type" to FILE_TYPE,
            "X-Upload-Content-Length" to data.size.toString(),
        ), metadata.toString().toByteArray())))
        val location = session.header("Location") ?: throw CloudBackupException(CloudBackupError.Other)
        val uploaded = json(HttpRequest(location, "PUT", mapOf("Content-Type" to FILE_TYPE), data))
        return uploaded["id"]!!.jsonPrimitive.content
    }

    override suspend fun download(id: String): ByteArray =
        try { send(get("files/$id", mapOf("alt" to "media"))).body } catch (_: NotFound) { throw CloudBackupException(CloudBackupError.Other) }

    override suspend fun delete(id: String) {
        try { send(authorized(HttpRequest("${API}files/$id", "DELETE"))) } catch (_: NotFound) {}
    }

    // Requests

    private suspend fun get(path: String, query: Map<String, String>): HttpRequest {
        val encoded = query.toSortedMap().entries.joinToString("&") { (key, value) ->
            "$key=${URLEncoder.encode(value, "UTF-8").replace("+", "%20")}"
        }
        return authorized(HttpRequest("$API$path?$encoded"))
    }

    private suspend fun authorized(request: HttpRequest): HttpRequest =
        request.copy(headers = request.headers + ("Authorization" to "Bearer ${auth.accessToken()}"))

    private suspend fun json(request: HttpRequest): JsonObject =
        runCatching { Json.parseToJsonElement(send(request).body.toString(Charsets.UTF_8)).jsonObject }
            .getOrElse { if (it is NotFound || it is CloudBackupException) throw it else throw CloudBackupException(CloudBackupError.Other) }

    /** Sends with the current token; on a 401 refreshes once and retries (the access token expired early). */
    private suspend fun send(request: HttpRequest): HttpResponse {
        var response = http.send(request)
        if (response.status == 401 && request.headers.containsKey("Authorization")) {
            val retry = request.copy(headers = request.headers + ("Authorization" to "Bearer ${auth.accessToken(forceRefresh = true)}"))
            response = http.send(retry)
        }
        return when (response.status) {
            in 200..299 -> response
            404 -> throw NotFound()
            else -> throw CloudBackupException(GoogleError.map(response.status, response.body))
        }
    }
}
