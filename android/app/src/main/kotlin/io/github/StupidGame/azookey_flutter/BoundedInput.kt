package io.github.StupidGame.azookey_flutter

import java.io.ByteArrayOutputStream
import java.io.InputStream

/** Reads at most [maximumBytes] plus one byte, including on Android before API 33. */
internal fun InputStream.readBoundedBytes(maximumBytes: Int): ByteArray? {
    require(maximumBytes in 0 until Int.MAX_VALUE)
    val output = ByteArrayOutputStream()
    val buffer = ByteArray(4096)
    while (output.size() <= maximumBytes) {
        val count = read(buffer, 0, minOf(buffer.size, maximumBytes + 1 - output.size()))
        if (count < 0) return output.toByteArray()
        if (count == 0) {
            val byte = read()
            if (byte < 0) return output.toByteArray()
            output.write(byte)
        } else {
            output.write(buffer, 0, count)
        }
    }
    return null
}
