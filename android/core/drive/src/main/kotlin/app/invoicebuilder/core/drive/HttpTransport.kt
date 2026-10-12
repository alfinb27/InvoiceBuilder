package app.invoicebuilder.core.drive

import app.invoicebuilder.core.domain.backup.CloudBackupError
import app.invoicebuilder.core.domain.backup.CloudBackupException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.net.UnknownHostException

data class HttpRequest(
    val url: String,
    val method: String = "GET",
    val headers: Map<String, String> = emptyMap(),
    val body: ByteArray? = null,
)

data class HttpResponse(val status: Int, val headers: Map<String, String> = emptyMap(), val body: ByteArray = ByteArray(0)) {
    /** Header names are case-insensitive. */
    fun header(name: String): String? = headers.entries.firstOrNull { it.key.equals(name, ignoreCase = true) }?.value
}

/** One HTTP exchange (iOS: `HTTPClient`). [UrlConnectionTransport] in the app; tests script the responses. */
fun interface HttpTransport {
    suspend fun send(request: HttpRequest): HttpResponse
}

/** `HttpURLConnection` on the IO dispatcher; no networking library. */
class UrlConnectionTransport : HttpTransport {
    override suspend fun send(request: HttpRequest): HttpResponse = withContext(Dispatchers.IO) {
        try {
            val connection = URL(request.url).openConnection() as HttpURLConnection
            try {
                // HttpURLConnection has no PATCH: Google accepts the override header.
                if (request.method == "PATCH") {
                    connection.requestMethod = "POST"
                    connection.setRequestProperty("X-HTTP-Method-Override", "PATCH")
                } else {
                    connection.requestMethod = request.method
                }
                connection.connectTimeout = 30_000
                connection.readTimeout = 60_000
                request.headers.forEach { (name, value) -> connection.setRequestProperty(name, value) }
                request.body?.let { body ->
                    connection.doOutput = true
                    connection.setFixedLengthStreamingMode(body.size)
                    connection.outputStream.use { it.write(body) }
                }
                val status = connection.responseCode
                val stream = if (status >= 400) connection.errorStream else connection.inputStream
                val body = stream?.use { it.readBytes() } ?: ByteArray(0)
                val headers = connection.headerFields.filterKeys { it != null }.mapValues { it.value.joinToString(",") }
                HttpResponse(status, headers, body)
            } finally {
                connection.disconnect()
            }
        } catch (error: UnknownHostException) {
            throw CloudBackupException(CloudBackupError.NetworkUnavailable)
        } catch (error: IOException) {
            throw CloudBackupException(CloudBackupError.NetworkUnavailable)
        }
    }
}

/** Google's error bodies mapped to [CloudBackupError] (`spec/backup.md` §7.5). iOS: `GoogleError`. */
object GoogleError {
    fun map(status: Int, body: ByteArray): CloudBackupError {
        val json = runCatching { Json.parseToJsonElement(body.toString(Charsets.UTF_8)).jsonObject }.getOrNull()
        val error = json?.get("error")
        val oauth = (error as? kotlinx.serialization.json.JsonPrimitive)?.contentOrNull
        val reasons = ((error as? JsonObject)?.get("errors")?.jsonArray ?: emptyList())
            .mapNotNull { it.jsonObject["reason"]?.jsonPrimitive?.contentOrNull }.toSet()
        return when {
            oauth == "invalid_grant" || status == 401 -> CloudBackupError.SignedOut
            "storageQuotaExceeded" in reasons || "quotaExceeded" in reasons -> CloudBackupError.QuotaExceeded
            else -> CloudBackupError.Other
        }
    }
}
