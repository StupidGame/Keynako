package io.github.StupidGame.azookey_flutter.conversion

import java.io.File
import java.net.HttpURLConnection
import java.net.URI
import java.util.zip.ZipInputStream
import org.json.JSONObject

/** Immutable snapshots: readers never see a half-downloaded dictionary. */
internal class OfficialDictionary(private val cache: File) {
    fun current(): File? = runCatching {
        val sha = File(cache, "current").readText().trim()
        require(sha.matches(Regex("[0-9a-f]{40}")))
        File(cache, "$sha/Dictionary").takeIf { File(it, "louds/charID.chid").isFile }
    }.getOrNull()

    fun refreshIfDue() {
        cache.mkdirs()
        val checked = File(cache, "checked")
        if (checked.exists() && System.currentTimeMillis() - checked.lastModified() < 86_400_000) return
        // Retries after an interrupted or failed download wait one hour.
        val attempt = File(cache, "attempt")
        if (attempt.exists() && System.currentTimeMillis() - attempt.lastModified() < 3_600_000) return
        attempt.writeText("")
        val sha = request("https://api.github.com/repos/azooKey/azooKey_dictionary_storage/commits/main") {
            JSONObject(it.inputStream.bufferedReader().use { reader -> reader.readText() }).getString("sha")
        }
        require(sha.matches(Regex("[0-9a-f]{40}")))
        if (current()?.parentFile?.name != sha) {
            val staging = File(cache, "staging-${System.nanoTime()}").apply { mkdirs() }
            try {
                request("https://codeload.github.com/azooKey/azooKey_dictionary_storage/zip/$sha") { connection ->
                    ZipInputStream(connection.inputStream.buffered()).use { zip ->
                        var total = 0L
                        var count = 0
                        while (true) {
                            val entry = zip.nextEntry ?: break
                            require(++count <= 5000)
                            val prefix = "azooKey_dictionary_storage-$sha/"
                            require(entry.name.startsWith(prefix))
                            val name = entry.name.removePrefix(prefix)
                            require(!name.startsWith('/') && !name.contains('\\'))
                            require(name.split('/').none { it == ".." || it == "." })
                            if (entry.isDirectory || !(name.startsWith("Dictionary/") || name == "LICENSE")) continue
                            val target = File(staging, name)
                            target.parentFile?.mkdirs()
                            target.outputStream().buffered().use { output ->
                                val buffer = ByteArray(65536)
                                while (true) {
                                    val size = zip.read(buffer)
                                    if (size < 0) break
                                    total += size
                                    require(total <= 256L * 1024 * 1024)
                                    output.write(buffer, 0, size)
                                }
                            }
                        }
                    }
                }
                validate(staging)
                val destination = File(cache, sha)
                if (!destination.exists()) check(staging.renameTo(destination))
                val marker = File(cache, "current.tmp")
                marker.writeText(sha)
                check(marker.renameTo(File(cache, "current")))
            } finally {
                staging.deleteRecursively()
            }
        }
        checked.writeText(sha)
    }

    private fun <T> request(url: String, action: (HttpURLConnection) -> T): T {
        val connection = URI(url).toURL().openConnection() as HttpURLConnection
        connection.connectTimeout = 15_000
        connection.readTimeout = 60_000
        connection.setRequestProperty("User-Agent", "Keynako-dictionary")
        try {
            check(connection.responseCode == 200)
            return action(connection)
        } finally {
            connection.disconnect()
        }
    }

    companion object {
        internal fun validate(repo: File) {
            require(File(repo, "LICENSE").readText().contains("Apache License"))
            val root = File(repo, "Dictionary")
            require(File(root, "louds/charID.chid").length() in 1..1024)
            val characters = File(root, "louds/charID.chid").readText().codePoints().toArray()
            require(characters.size <= 256 && characters.toSet().size == characters.size)
            require(File(root, "mm.binary").length() >= 1_008_020)
            for (cid in 0 until 1319) {
                val size = File(root, "cb/$cid.binary").length()
                require(size > 0 && size % 8 == 0L)
            }
            val shards = File(root, "louds").listFiles { file -> file.extension == "louds" }.orEmpty()
            require(shards.isNotEmpty())
            for (shard in shards) {
                require(shard.length() > 0 && shard.length() % 8 == 0L)
                require(File(shard.parentFile, "${shard.nameWithoutExtension}.loudschars2").length() > 0)
                require(File(shard.parentFile, "${shard.nameWithoutExtension}0.loudstxt3").length() > 0)
            }
        }
    }
}
