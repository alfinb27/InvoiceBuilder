package app.invoicebuilder.core.drive

import app.invoicebuilder.core.domain.backup.CloudBackupError
import app.invoicebuilder.core.domain.backup.CloudBackupException
import app.invoicebuilder.core.domain.backup.CloudBackupTarget
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.net.URI
import java.net.URLDecoder

/** Drive requests against a scripted server (`spec/backup.md` §7, ADR-0021). iOS: `GoogleDriveTests`. */
class GoogleDriveTests {
    class FakeAuth : DriveAuth {
        var token = "access-1"
        var refreshed = 0
        override suspend fun signIn() {}
        override suspend fun accessToken(forceRefresh: Boolean): String {
            if (forceRefresh) { refreshed++; token = "access-2" }
            return token
        }
        override suspend fun signOut() {}
    }

    class FakeHttp(private val handler: (HttpRequest) -> HttpResponse) : HttpTransport {
        val sent = mutableListOf<HttpRequest>()
        override suspend fun send(request: HttpRequest): HttpResponse { sent += request; return handler(request) }
    }

    private fun json(text: String, status: Int = 200, headers: Map<String, String> = emptyMap()) =
        HttpResponse(status, headers, text.toByteArray())

    private fun query(request: HttpRequest): Map<String, String> =
        (URI(request.url).rawQuery ?: "").split("&").filter { it.isNotEmpty() }.associate {
            val (key, value) = it.split("=", limit = 2)
            key to URLDecoder.decode(value, "UTF-8")
        }

    private fun path(request: HttpRequest) = URI(request.url).path

    @Test
    fun theFolderIsReusedFoundOrCreated() = runTest {
        var http = FakeHttp { json("""{"id":"folder-1","trashed":false}""") }
        assertEquals("folder-1", GoogleDriveDestination(FakeAuth(), http).folder("folder-1"))

        http = FakeHttp { request ->
            when (request.method to path(request)) {
                "GET" to "/drive/v3/files/folder-1" -> json("""{"id":"folder-1","trashed":true}""")
                "GET" to "/drive/v3/files" -> json("""{"files":[]}""")
                "POST" to "/drive/v3/files" -> json("""{"id":"folder-2"}""")
                else -> { fail("unexpected $request"); json("{}", 500) }
            }
        }
        assertEquals("folder-2", GoogleDriveDestination(FakeAuth(), http).folder("folder-1"))
        val created = Json.parseToJsonElement(http.sent[2].body!!.toString(Charsets.UTF_8)).jsonObject
        assertEquals("InvoiceBuilder backups", created["name"]!!.jsonPrimitive.content)
        assertEquals("application/vnd.google-apps.folder", created["mimeType"]!!.jsonPrimitive.content)
        assertTrue(http.sent.all { it.headers["Authorization"] == "Bearer access-1" })
    }

    @Test
    fun listingReadsEveryPageAndTheAppProperties() = runTest {
        val http = FakeHttp { request ->
            val values = query(request)
            assertEquals("'folder-1' in parents and trashed = false", values["q"])
            if (values["pageToken"] == "p2") json("""{"files":[{"id":"f2","name":"manual.json"}]}""")
            else json("""{"nextPageToken":"p2","files":[{"id":"f1","name":"InvoiceBackup-2026-10-10.invoicebackup",
                "appProperties":{"ibDeviceId":"dev-1","ibCreatedAt":"1791600000000","ibPlatform":"ios","ibInvoices":"12",
                "ibClients":"4","ibBusinesses":"Rao Traders"}}]}""")
        }
        val entries = GoogleDriveDestination(FakeAuth(), http).list("folder-1")
        assertEquals(listOf("f1", "f2"), entries.map { it.id })
        assertTrue(entries[0].isTagged)
        assertEquals("ios", entries[0].platform)
        assertEquals(12, entries[0].invoiceCount)
        assertFalse(entries[1].isTagged)
    }

    @Test
    fun aNewBackupIsAResumableUploadIntoTheFolder() = runTest {
        val http = FakeHttp { request ->
            if (request.method == "POST") HttpResponse(200, mapOf("location" to "https://upload.example/session-1"))
            else { assertEquals("https://upload.example/session-1", request.url); json("""{"id":"file-9"}""") }
        }
        val id = GoogleDriveDestination(FakeAuth(), http).upload("{}".toByteArray(), "InvoiceBackup-2026-10-10.invoicebackup",
            mapOf("ibDeviceId" to "dev-1"), CloudBackupTarget.Create, "folder-1")
        assertEquals("file-9", id)
        val start = http.sent[0]
        assertEquals("https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&fields=id", start.url)
        assertEquals("2", start.headers["X-Upload-Content-Length"])
        val metadata = Json.parseToJsonElement(start.body!!.toString(Charsets.UTF_8)).jsonObject
        assertEquals(listOf("folder-1"), metadata["parents"]!!.jsonArray.map { it.jsonPrimitive.content })
        assertEquals("dev-1", metadata["appProperties"]!!.jsonObject["ibDeviceId"]!!.jsonPrimitive.content)
        assertEquals("PUT", http.sent[1].method)
        assertEquals("{}", http.sent[1].body!!.toString(Charsets.UTF_8))
        assertNull(http.sent[1].headers["Authorization"]) // the session URL carries the authorization
    }

    @Test
    fun todaysFileIsUpdatedInPlace() = runTest {
        val http = FakeHttp { request ->
            if (request.method == "PATCH") HttpResponse(200, mapOf("Location" to "https://upload.example/s")) else json("""{"id":"file-3"}""")
        }
        GoogleDriveDestination(FakeAuth(), http).upload(ByteArray(0), "n", emptyMap(), CloudBackupTarget.Update("file-3"), "folder-1")
        assertEquals("/upload/drive/v3/files/file-3", path(http.sent[0]))
        val metadata = Json.parseToJsonElement(http.sent[0].body!!.toString(Charsets.UTF_8)).jsonObject
        assertNull(metadata["parents"]) // a PATCH can't set parents
    }

    @Test
    fun a401RefreshesOnceAndRetries() = runTest {
        val auth = FakeAuth()
        var calls = 0
        val http = FakeHttp { if (++calls == 1) json("{}", 401) else json("""{"id":"folder-1","trashed":false}""") }
        assertEquals("folder-1", GoogleDriveDestination(auth, http).folder("folder-1"))
        assertEquals(1, auth.refreshed)
        assertEquals("Bearer access-2", http.sent.last().headers["Authorization"])
    }

    @Test
    fun aFullDriveIsQuotaExceeded() = runTest {
        val http = FakeHttp { json("""{"error":{"code":403,"errors":[{"reason":"storageQuotaExceeded"}]}}""", 403) }
        try {
            GoogleDriveDestination(FakeAuth(), http).upload(ByteArray(0), "n", emptyMap(), CloudBackupTarget.Create, "f")
            fail("expected an error")
        } catch (error: CloudBackupException) {
            assertEquals(CloudBackupError.QuotaExceeded, error.error)
        }
    }

    @Test
    fun aRevokedGrantIsSignedOut() {
        assertEquals(CloudBackupError.SignedOut, GoogleError.map(400, """{"error":"invalid_grant"}""".toByteArray()))
        assertEquals(CloudBackupError.Other, GoogleError.map(500, ByteArray(0)))
    }
}
