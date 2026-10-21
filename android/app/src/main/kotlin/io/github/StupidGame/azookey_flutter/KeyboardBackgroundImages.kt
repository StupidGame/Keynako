package io.github.StupidGame.azookey_flutter

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import androidx.exifinterface.media.ExifInterface
import io.github.StupidGame.azookey_flutter.input.backgroundImageOrientationTransform
import java.io.File

/** The only files the keyboard and backup exporter may load as theme images. */
internal class KeyboardBackgroundImages(private val directory: File) {
    fun managedFile(path: String): File? = runCatching {
        File(path).canonicalFile.takeIf {
            it.parentFile == directory.canonicalFile && it.extension == "image"
        }
    }.getOrNull()

    fun read(path: String): ByteArray? = runCatching {
        val file = managedFile(path)?.takeIf { it.isFile && it.length() <= MAXIMUM_BYTES }
            ?: return null
        val bytes = file.inputStream().use { it.readBoundedBytes(MAXIMUM_BYTES) } ?: return null
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        bytes.takeIf { validDimensions(bounds.outWidth, bounds.outHeight) }
    }.getOrNull()

    fun decode(path: String): Bitmap? = runCatching {
        val file = managedFile(path)?.takeIf { it.isFile && it.length() <= MAXIMUM_BYTES }
            ?: return null
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.absolutePath, bounds)
        if (!validDimensions(bounds.outWidth, bounds.outHeight)) return null
        val options = BitmapFactory.Options().apply {
            inSampleSize = backgroundImageSampleSize(bounds.outWidth, bounds.outHeight)
        }
        val source = BitmapFactory.decodeFile(file.absolutePath, options) ?: return null
        val orientation = runCatching {
            ExifInterface(file.absolutePath).getAttributeInt(
                ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL,
            )
        }.getOrDefault(ExifInterface.ORIENTATION_NORMAL)
        val transform = backgroundImageOrientationTransform(orientation)
        if (transform.rotationDegrees == 0 && !transform.flipHorizontally) return source
        val matrix = Matrix().apply {
            if (transform.flipHorizontally) postScale(-1f, 1f)
            if (transform.rotationDegrees != 0) postRotate(transform.rotationDegrees.toFloat())
        }
        Bitmap.createBitmap(source, 0, 0, source.width, source.height, matrix, true).also {
            if (it !== source) source.recycle()
        }
    }.getOrNull()

    companion object {
        const val MAXIMUM_BYTES = 8 * 1024 * 1024

        // Includes 200 MP phone photos while rejecting extreme decompression work.
        fun validDimensions(width: Int, height: Int): Boolean =
            width > 0 && height > 0 && width.toLong() * height <= 250_000_000L
    }
}

/** Power-of-two sampling bounds the decoded bitmap to 2048 x 2048 pixels. */
internal fun backgroundImageSampleSize(width: Int, height: Int): Int {
    var sample = 1
    while ((width.toLong() + sample - 1) / sample > 2048 ||
        (height.toLong() + sample - 1) / sample > 2048) sample *= 2
    return sample
}
