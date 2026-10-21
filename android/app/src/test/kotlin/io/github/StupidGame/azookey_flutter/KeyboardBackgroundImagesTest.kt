package io.github.StupidGame.azookey_flutter

import android.graphics.Bitmap
import androidx.exifinterface.media.ExifInterface
import java.io.File
import java.nio.file.Files
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.ConscryptMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], manifest = Config.NONE)
@ConscryptMode(ConscryptMode.Mode.OFF)
class KeyboardBackgroundImagesTest {
    @get:Rule val temporary = TemporaryFolder()

    @Test fun exportAndDecodeRejectFilesOutsideTheImageStoreIncludingSymlinks() {
        val directory = temporary.newFolder("images")
        val images = KeyboardBackgroundImages(directory)
        val outside = temporary.newFile("private.image").apply { writeText("private sentinel") }
        assertNull(images.read(outside.path))
        assertNull(images.managedFile(File(directory, "../private.image").path))
        val symlink = File(directory, "linked.image")
        Files.createSymbolicLink(symlink.toPath(), outside.toPath())
        assertNull(images.managedFile(symlink.path))
        assertNull(images.decode(symlink.path))
        assertNull(images.read(File(directory, "state.json").path))
    }

    @Test fun aHighlyCompressedLargeImageIsDownsampledBeforeDisplay() {
        val directory = temporary.newFolder("images")
        val file = File(directory, "large.image")
        val original = Bitmap.createBitmap(4096, 3072, Bitmap.Config.ARGB_8888)
        file.outputStream().use { assertTrue(original.compress(Bitmap.CompressFormat.PNG, 100, it)) }
        original.recycle()
        val images = KeyboardBackgroundImages(directory)
        assertTrue(file.length() < KeyboardBackgroundImages.MAXIMUM_BYTES)
        assertArrayEquals(file.readBytes(), images.read(file.path))
        val decoded = images.decode(file.path)!!
        assertEquals(2048, decoded.width)
        assertEquals(1536, decoded.height)
        decoded.recycle()
    }

    @Test fun downsamplingPreservesExifRotation() {
        val directory = temporary.newFolder("images")
        val file = File(directory, "rotated.image")
        val original = Bitmap.createBitmap(40, 20, Bitmap.Config.ARGB_8888)
        file.outputStream().use { original.compress(Bitmap.CompressFormat.JPEG, 90, it) }
        original.recycle()
        ExifInterface(file.path).apply {
            setAttribute(ExifInterface.TAG_ORIENTATION, "6")
            saveAttributes()
        }
        val decoded = KeyboardBackgroundImages(directory).decode(file.path)!!
        assertEquals(20, decoded.width)
        assertEquals(40, decoded.height)
        decoded.recycle()
    }

    @Test fun rejectsInvalidAndOversizedDimensionsWithoutIntegerOverflow() {
        assertTrue(KeyboardBackgroundImages.validDimensions(16384, 12288)) // 200 MP camera
        assertFalse(KeyboardBackgroundImages.validDimensions(Int.MAX_VALUE, Int.MAX_VALUE))
        assertFalse(KeyboardBackgroundImages.validDimensions(0, 20))
        assertFalse(KeyboardBackgroundImages.validDimensions(-1, 20))
        assertEquals(1, backgroundImageSampleSize(2048, 100))
        assertEquals(4, backgroundImageSampleSize(4097, 100))
        assertEquals(1 shl 20, backgroundImageSampleSize(Int.MAX_VALUE, 1))
    }
}
