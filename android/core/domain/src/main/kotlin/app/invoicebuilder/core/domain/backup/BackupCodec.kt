package app.invoicebuilder.core.domain.backup

import app.invoicebuilder.core.domain.decimal.Outcome
import app.invoicebuilder.core.domain.support.SpecJson
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import java.math.BigDecimal
import java.security.MessageDigest

/** Reads and writes `.invoicebackup` files (`spec/backup.md`). Pure: bytes in, a preview or an error out. iOS: `BackupCodec`. */
object BackupCodec {
    /** Writing: sorted keys are not required for equality, but UTF-8 JSON with every field is (§1). */
    private val writer = Json(from = SpecJson) { prettyPrint = false }

    fun encode(file: BackupFile): ByteArray = writer.encodeToString(BackupFile.serializer(), file).toByteArray(Charsets.UTF_8)

    /** §3: the checks in order; the first failure wins. */
    fun validate(bytes: ByteArray, appSchemaVersion: Int): Outcome<BackupPreview, BackupError> = try {
        Outcome.Success(BackupPreview(decodeChecked(bytes, appSchemaVersion)))
    } catch (error: BackupError) {
        Outcome.Failure(error)
    }

    /** Lowercase hex SHA-256 (asset hashes, `spec/setup.md` §9). */
    fun sha256Hex(data: ByteArray): String =
        MessageDigest.getInstance("SHA-256").digest(data).joinToString("") { "%02x".format(it) }

    private fun decodeChecked(bytes: ByteArray, appSchemaVersion: Int): BackupFile {
        // 1–4: the envelope, read loosely so a wrong file gets the right code rather than a decoding error.
        val text = bytes.toString(Charsets.UTF_8)
        val element = try { Json.parseToJsonElement(text) } catch (_: SerializationException) { null }
        val root = element as? JsonObject ?: throw BackupError(BackupError.Code.NotJSON)
        if ((root["format"] as? JsonPrimitive)?.takeIf { it.isString }?.contentOrNull != BackupFile.FORMAT) {
            throw BackupError(BackupError.Code.NotABackup, "format")
        }
        val formatVersion = integer(root["formatVersion"])
        if (formatVersion == null || formatVersion < 1) throw BackupError(BackupError.Code.NotABackup, "formatVersion")
        if (formatVersion > BackupFile.FORMAT_VERSION) throw BackupError(BackupError.Code.NewerFormat, "formatVersion $formatVersion")
        val schemaVersion = integer(root["dbSchemaVersion"])
        if (schemaVersion == null || schemaVersion < 1) throw BackupError(BackupError.Code.InvalidRecord, "dbSchemaVersion")
        if (schemaVersion > appSchemaVersion) throw BackupError(BackupError.Code.NewerSchema, "dbSchemaVersion $schemaVersion > $appSchemaVersion")

        // 5: every record decodes (unknown keys are ignored).
        val file = try {
            SpecJson.decodeFromJsonElement(BackupFile.serializer(), root)
        } catch (error: SerializationException) {
            throw BackupError(BackupError.Code.InvalidRecord, error.message)
        } catch (error: IllegalArgumentException) {
            throw BackupError(BackupError.Code.InvalidRecord, error.message)
        }
        // kotlinx.serialization reads "1000" as a number; Swift's decoder does not. Every value the file shares
        // with its decoded form must have the same JSON type, so both platforms reject the same files.
        typeMismatch(root, SpecJson.encodeToJsonElement(BackupFile.serializer(), file), "")?.let {
            throw BackupError(BackupError.Code.InvalidRecord, it)
        }
        val data = file.data

        // 6: counts
        if (file.counts != data.counts) {
            val name = file.counts.named().zip(data.counts.named()).firstOrNull { it.first.second != it.second.second }?.first?.first
            throw BackupError(BackupError.Code.CountMismatch, name)
        }

        // 7: unique ids
        unique(data.businesses.map { it.id }, "businesses")
        unique(data.clients.map { it.id }, "clients")
        unique(data.catalogItems.map { it.id }, "catalogItems")
        unique(data.numberingSeries.map { it.id }, "numberingSeries")
        unique(data.documents.map { it.id }, "documents")
        unique(data.payments.map { it.id }, "payments")
        unique(data.assets.map { it.id }, "assets")
        for (document in data.documents) unique(document.lines.map { it.id }, "documents ${document.id} lines")

        // 8: asset hashes
        for (asset in data.assets) {
            if (sha256Hex(asset.data) != asset.sha256.lowercase()) throw BackupError(BackupError.Code.AssetHashMismatch, asset.id)
        }

        // 9: references resolve inside the file
        val businesses = data.businesses.map { it.id }.toSet()
        val clients = data.clients.map { it.id }.toSet()
        val items = data.catalogItems.map { it.id }.toSet()
        val series = data.numberingSeries.map { it.id }.toSet()
        val documents = data.documents.map { it.id }.toSet()
        val assets = data.assets.map { it.id }.toSet()
        fun check(id: String?, ids: Set<String>, what: () -> String) {
            if (id != null && id !in ids) throw BackupError(BackupError.Code.DanglingReference, "${what()} → $id")
        }
        for (business in data.businesses) {
            check(business.logoAssetId, assets) { "business ${business.id} logoAssetId" }
            check(business.signatureAssetId, assets) { "business ${business.id} signatureAssetId" }
        }
        for (client in data.clients) check(client.businessId, businesses) { "client ${client.id}" }
        for (item in data.catalogItems) check(item.businessId, businesses) { "catalog item ${item.id}" }
        for (row in data.numberingSeries) check(row.businessId, businesses) { "series ${row.id}" }
        for (asset in data.assets) check(asset.businessId, businesses) { "asset ${asset.id}" }
        for (document in data.documents) {
            check(document.businessId, businesses) { "document ${document.id} businessId" }
            check(document.clientId, clients) { "document ${document.id} clientId" }
            check(document.seriesId, series) { "document ${document.id} seriesId" }
            check(document.convertedFromId, documents) { "document ${document.id} convertedFromId" }
            for (line in document.lines) check(line.catalogItemId, items) { "line ${line.id} catalogItemId" }
        }
        for (payment in data.payments) {
            check(payment.businessId, businesses) { "payment ${payment.id} businessId" }
            check(payment.documentId, documents) { "payment ${payment.id} documentId" }
        }
        return file
    }

    /** The first path where [original] and [decoded] disagree on the type of a value they both have. */
    private fun typeMismatch(original: kotlinx.serialization.json.JsonElement, decoded: kotlinx.serialization.json.JsonElement, path: String): String? {
        return when {
            original is JsonObject && decoded is JsonObject -> decoded.keys.firstNotNullOfOrNull { key ->
                original[key]?.let { typeMismatch(it, decoded[key]!!, "$path.$key") }
            }
            original is kotlinx.serialization.json.JsonArray && decoded is kotlinx.serialization.json.JsonArray ->
                original.indices.firstNotNullOfOrNull { index ->
                    decoded.getOrNull(index)?.let { typeMismatch(original[index], it, "$path[$index]") }
                }
            original is kotlinx.serialization.json.JsonNull || decoded is kotlinx.serialization.json.JsonNull -> null
            original is JsonPrimitive && decoded is JsonPrimitive ->
                if (original.isString != decoded.isString || (original.booleanOrNull == null) != (decoded.booleanOrNull == null)) path else null
            else -> path
        }
    }

    private fun integer(element: kotlinx.serialization.json.JsonElement?): Int? {
        val primitive = element as? JsonPrimitive ?: return null
        if (primitive.isString || primitive.booleanOrNull != null) return null
        val value = primitive.contentOrNull?.let { runCatching { BigDecimal(it) }.getOrNull() } ?: return null
        return runCatching { value.intValueExact() }.getOrNull()
    }

    private fun unique(ids: List<String>, collection: String) {
        val seen = mutableSetOf<String>()
        for (id in ids) if (!seen.add(id)) throw BackupError(BackupError.Code.DuplicateID, "$collection $id")
    }
}
