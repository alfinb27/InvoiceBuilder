package app.invoicebuilder.android.common

import android.content.ContentResolver
import androidx.core.graphics.scale
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.net.Uri
import androidx.exifinterface.media.ExifInterface
import app.invoicebuilder.core.domain.models.ImagePayload
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * Prepares logos and signatures for storage (`spec/setup.md` §9): orientation applied, longest side ≤ 1024 px, PNG
 * when transparent, otherwise JPEG, at most 300 KB. Re-encoding drops EXIF metadata such as GPS. iOS: `ImageProcessing`.
 */
object ImageProcessing {
    const val MAX_PIXEL_SIZE = 1024
    const val MAX_BYTES = 300 * 1024
    private val jpegQualities = listOf(85, 70, 55, 40)

    class UnreadableImage : Exception("unreadable image")

    suspend fun logo(uri: Uri, resolver: ContentResolver): ImagePayload = withContext(Dispatchers.Default) {
        val bytes = resolver.openInputStream(uri)?.use { it.readBytes() } ?: throw UnreadableImage()
        encodeLogo(bytes)
    }

    fun encodeLogo(data: ByteArray): ImagePayload {
        var image = thumbnail(data) ?: throw UnreadableImage()
        val transparent = hasTransparency(image)
        while (true) {
            if (transparent) {
                encode(image, Bitmap.CompressFormat.PNG, 100).takeIf { it.size <= MAX_BYTES }?.let { return ImagePayload(ImagePayload.PNG, it) }
            } else {
                for (quality in jpegQualities) {
                    encode(image, Bitmap.CompressFormat.JPEG, quality).takeIf { it.size <= MAX_BYTES }?.let { return ImagePayload(ImagePayload.JPEG, it) }
                }
            }
            if (image.width <= 32) throw UnreadableImage()
            image = scaled(image, 0.75)
        }
    }

    /** A signature PNG, scaled down so its longest side is at most 1024 px. */
    fun signature(image: Bitmap): ImagePayload {
        val longest = max(image.width, image.height)
        val sized = if (longest > MAX_PIXEL_SIZE) scaled(image, MAX_PIXEL_SIZE.toDouble() / longest) else image
        return ImagePayload(ImagePayload.PNG, encode(sized, Bitmap.CompressFormat.PNG, 100))
    }

    /** Decoded, oriented (EXIF) and no larger than [MAX_PIXEL_SIZE] on its longest side. Never upscales. */
    fun thumbnail(data: ByteArray): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(data, 0, data.size, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        var sample = 1
        while (max(bounds.outWidth, bounds.outHeight) / (sample * 2) >= MAX_PIXEL_SIZE) sample *= 2
        val decoded = BitmapFactory.decodeByteArray(data, 0, data.size, BitmapFactory.Options().apply { inSampleSize = sample }) ?: return null
        val rotation = runCatching { ExifInterface(ByteArrayInputStream(data)).rotationDegrees }.getOrDefault(0)
        val oriented = if (rotation != 0) {
            Bitmap.createBitmap(decoded, 0, 0, decoded.width, decoded.height, Matrix().apply { postRotate(rotation.toFloat()) }, true)
        } else decoded
        val longest = max(oriented.width, oriented.height)
        return if (longest > MAX_PIXEL_SIZE) scaled(oriented, MAX_PIXEL_SIZE.toDouble() / longest) else oriented
    }

    /** True when any pixel is not fully opaque. */
    fun hasTransparency(image: Bitmap): Boolean {
        if (!image.hasAlpha()) return false
        val pixels = IntArray(image.width * image.height)
        image.getPixels(pixels, 0, image.width, 0, 0, image.width, image.height)
        return pixels.any { (it ushr 24) < 255 }
    }

    fun encode(image: Bitmap, format: Bitmap.CompressFormat, quality: Int): ByteArray =
        ByteArrayOutputStream().also { image.compress(format, quality, it) }.toByteArray()

    fun scaled(image: Bitmap, factor: Double): Bitmap =
        image.scale(max(1, (image.width * factor).roundToInt()), max(1, (image.height * factor).roundToInt()))
}
