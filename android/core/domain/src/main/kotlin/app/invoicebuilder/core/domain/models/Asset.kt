package app.invoicebuilder.core.domain.models

import kotlinx.serialization.KSerializer
import kotlinx.serialization.Required
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import java.util.Base64

/** An image kept in the database (logo or signature), so backups carry it (`spec/setup.md` §9). iOS: `Asset`. */
@Serializable
data class Asset(
    val id: String,
    @Required val createdAt: Long = 0,
    @Required val updatedAt: Long = 0,
    val deletedAt: Long? = null,
    val businessId: String,
    val kind: AssetKind,
    /** `image/png` or `image/jpeg`. */
    val mime: String,
    /** Lowercase hex SHA-256 of [data]. */
    val sha256: String,
    /** Backups carry the bytes as base64. */
    @SerialName("dataBase64") @Serializable(with = Base64Serializer::class) val data: ByteArray,
) {
    override fun equals(other: Any?): Boolean = other is Asset && other.id == id && other.createdAt == createdAt &&
        other.updatedAt == updatedAt && other.deletedAt == deletedAt && other.businessId == businessId &&
        other.kind == kind && other.mime == mime && other.sha256 == sha256 && other.data.contentEquals(data)

    override fun hashCode(): Int = id.hashCode() * 31 + data.contentHashCode()
}

/** Processed image bytes waiting to be stored as an [Asset]. */
data class ImagePayload(val mime: String, val data: ByteArray) {
    override fun equals(other: Any?): Boolean = other is ImagePayload && other.mime == mime && other.data.contentEquals(data)
    override fun hashCode(): Int = mime.hashCode() * 31 + data.contentHashCode()

    companion object {
        const val PNG = "image/png"
        const val JPEG = "image/jpeg"
    }
}

/** Standard base64 with padding, rejecting anything else (≈ `JSONDecoder`'s default `Data` strategy). */
object Base64Serializer : KSerializer<ByteArray> {
    override val descriptor = PrimitiveSerialDescriptor("Base64", PrimitiveKind.STRING)
    override fun serialize(encoder: Encoder, value: ByteArray) = encoder.encodeString(Base64.getEncoder().encodeToString(value))
    override fun deserialize(decoder: Decoder): ByteArray = Base64.getDecoder().decode(decoder.decodeString())
}
