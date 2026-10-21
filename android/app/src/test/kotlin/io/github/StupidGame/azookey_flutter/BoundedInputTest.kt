package io.github.StupidGame.azookey_flutter

import java.io.ByteArrayInputStream
import java.io.InputStream
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class BoundedInputTest {
    @Test fun acceptsTheExactLimitAndEmptyStreams() {
        assertArrayEquals(byteArrayOf(1, 2, 3), ByteArrayInputStream(byteArrayOf(1, 2, 3)).readBoundedBytes(3))
        assertArrayEquals(byteArrayOf(), ByteArrayInputStream(byteArrayOf()).readBoundedBytes(0))
    }

    @Test fun rejectsOversizedResponsesWithoutDrainingThem() {
        val input = ByteArrayInputStream(ByteArray(100_000))
        assertNull(input.readBoundedBytes(64 * 1024))
        assertEquals(100_000 - 64 * 1024 - 1, input.available())
    }

    @Test fun handlesShortAndZeroByteReadsWithoutTruncationOrHanging() {
        val input = object : InputStream() {
            var next = 1
            var zero = true
            override fun read(): Int = if (next <= 9) next++ else -1
            override fun read(bytes: ByteArray, offset: Int, length: Int): Int {
                zero = !zero
                if (!zero) return 0
                return super.read(bytes, offset, minOf(length, 2))
            }
        }
        assertArrayEquals(ByteArray(9) { (it + 1).toByte() }, input.readBoundedBytes(9))
    }
}
