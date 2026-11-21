package io.github.StupidGame.azookey_flutter.conversion

import java.io.File
import java.nio.file.Files
import org.junit.Assert.*
import org.junit.Test

class OfficialDictionaryTest {
    @Test
    fun readsOnlyACompleteRevisionDirectory() {
        val cache = Files.createTempDirectory("official-dictionary").toFile()
        try {
            val sha = "0123456789012345678901234567890123456789"
            val store = OfficialDictionary(cache)
            File(cache, "current").writeText("../outside")
            assertNull(store.current())
            File(cache, "current").writeText(sha)
            assertNull(store.current())
            val characters = File(cache, "$sha/Dictionary/louds/charID.chid")
            characters.parentFile!!.mkdirs()
            characters.writeText("アイ")
            assertEquals(characters.parentFile!!.parentFile, store.current())
        } finally {
            cache.deleteRecursively()
        }
    }

    @Test
    fun recentCheckAndFailedAttemptSkipNetwork() {
        val cache = Files.createTempDirectory("official-dictionary").toFile()
        try {
            val store = OfficialDictionary(cache)
            File(cache, "checked").writeText("")
            store.refreshIfDue()
            assertFalse(File(cache, "attempt").exists())
            File(cache, "checked").delete()
            File(cache, "attempt").writeText("")
            store.refreshIfDue()
            assertFalse(File(cache, "checked").exists())
        } finally {
            cache.deleteRecursively()
        }
    }

    @Test
    fun validatesTheBundledOfficialDictionary() {
        val root = generateSequence(File(System.getProperty("user.dir"))) { it.parentFile }
            .map { File(it, "third_party/azookey_dictionary_storage") }
            .first { File(it, "Dictionary/mm.binary").isFile }
        OfficialDictionary.validate(root)
    }

    @Test(expected = IllegalArgumentException::class)
    fun rejectsAnIncompleteDictionary() {
        val root = Files.createTempDirectory("invalid-official-dictionary").toFile()
        try {
            File(root, "LICENSE").writeText("Apache License")
            OfficialDictionary.validate(root)
        } finally {
            root.deleteRecursively()
        }
    }
}
