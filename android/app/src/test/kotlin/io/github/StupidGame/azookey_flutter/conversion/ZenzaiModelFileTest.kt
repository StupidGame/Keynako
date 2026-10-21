package io.github.StupidGame.azookey_flutter.conversion

import java.io.ByteArrayInputStream
import java.io.File
import java.io.IOException
import java.io.InputStream
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class ZenzaiModelFileTest {
    @get:Rule val temporary = TemporaryFolder()

    @Test fun repairsAnInterruptedCopyInAnExistingDirectory() {
        val directory = temporary.newFolder("models")
        val destination = File(directory, "model.gguf").apply { writeBytes(byteArrayOf(1)) }
        val bytes = byteArrayOf(1, 2, 3, 4)
        assertEquals(destination, prepareZenzaiModelFile(destination, 4) { ByteArrayInputStream(bytes) })
        assertArrayEquals(bytes, destination.readBytes())
        assertEquals(listOf("model.gguf"), directory.list()!!.toList())
    }

    @Test fun aFailedOrTruncatedCopyDoesNotModifyTheOldFileAndCanBeRetried() {
        val directory = temporary.newFolder("models")
        val destination = File(directory, "model.gguf").apply { writeBytes(byteArrayOf(9)) }
        assertThrows(IOException::class.java) {
            prepareZenzaiModelFile(destination, 4) {
                object : InputStream() {
                    override fun read(): Int = throw IOException("interrupted fixture")
                }
            }
        }
        assertThrows(IllegalStateException::class.java) {
            prepareZenzaiModelFile(destination, 4) { ByteArrayInputStream(byteArrayOf(2, 3)) }
        }
        assertArrayEquals(byteArrayOf(9), destination.readBytes())
        assertEquals(listOf("model.gguf"), directory.list()!!.toList())
        prepareZenzaiModelFile(destination, 4) { ByteArrayInputStream(byteArrayOf(1, 2, 3, 4)) }
        assertArrayEquals(byteArrayOf(1, 2, 3, 4), destination.readBytes())
    }

    @Test fun reusesCompleteModelsAndCreatesMissingDirectories() {
        val destination = File(temporary.root, "missing/models/model.gguf")
        prepareZenzaiModelFile(destination, 4) { ByteArrayInputStream(byteArrayOf(1, 2, 3, 4)) }
        prepareZenzaiModelFile(destination, 4) { error("A complete model must not be copied again") }
        assertArrayEquals(byteArrayOf(1, 2, 3, 4), destination.readBytes())
    }
}
