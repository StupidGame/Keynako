package io.github.StupidGame.azookey_flutter.conversion

import java.io.File
import java.io.InputStream

/** Replaces an interrupted model copy without exposing a partially written file. */
internal fun prepareZenzaiModelFile(
    destination: File,
    expectedSize: Long,
    openAsset: () -> InputStream,
): File {
    require(expectedSize > 0)
    if (destination.isFile && destination.length() == expectedSize) return destination
    val directory = checkNotNull(destination.parentFile)
    check(directory.isDirectory || directory.mkdirs() || directory.isDirectory) {
        "Could not create the Zenzai model directory"
    }
    val temporary = File.createTempFile(".model-", ".tmp", directory)
    try {
        openAsset().use { input ->
            temporary.outputStream().use { output -> input.copyTo(output, 1024 * 1024) }
        }
        check(temporary.length() == expectedSize) { "Copied Zenzai model has an unexpected size" }
        // Both files are in the same Android filesystem: rename replaces the
        // directory entry atomically, preserving any existing mmap of the old file.
        check(temporary.renameTo(destination)) { "Could not replace the Zenzai model" }
    } finally {
        temporary.delete()
    }
    return destination
}
