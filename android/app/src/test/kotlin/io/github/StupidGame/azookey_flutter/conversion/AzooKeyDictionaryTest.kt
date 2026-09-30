package io.github.StupidGame.azookey_flutter.conversion

import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AzooKeyDictionaryTest {
    private fun entry(word: String, ruby: String, cid: Int = 100) =
        AzooKeyHotfixDictionaryEntry(word, ruby, 0.0, cid, cid, 501)

    private fun syntheticDictionary() = AzooKeyDictionary(DictionaryAssetSource { path ->
        val score = when (path) {
            "cb/0.binary" -> 0f
            "cb/100.binary" -> -10f
            "cb/200.binary" -> 0f
            else -> error("No bundled entry in this fixture: $path")
        }
        ByteBuffer.allocate(8).order(ByteOrder.LITTLE_ENDIAN)
            .putInt(if (path == "cb/0.binary") -1 else 1316).putFloat(score).array()
    })

    @Test
    fun ranksCompleteWordsUsingEndConnectionsAndCompletionLength() {
        val dictionary = syntheticDictionary()
        val entries = listOf(entry("弱い終端", "てすと", 100), entry("強い終端", "てすと", 200))
        assertEquals("強い終端", dictionary.candidates("てすと", 0, additionalEntries = entries).conversions.first())
        val result = dictionary.candidates("てす", 2, additionalEntries = listOf(
            entry("長い補完", "てすとけーす", 200), entry("短い補完", "てすと", 200),
        ))
        assertEquals(listOf("短い補完", "長い補完"), result.predictions)
        assertEquals("てすと", result.predictionReadings["短い補完"])
        assertEquals("てすとけーす", result.predictionReadings["長い補完"])
    }

    @Test
    fun cacheRespectsLimitsAndUnversionedDictionaryChanges() {
        val dictionary = syntheticDictionary()
        val entries = listOf(entry("旧候補", "てすと", 200), entry("別候補", "てすと", 100))
        assertEquals(1, dictionary.candidates("てすと", 0, 1, entries).conversions.size)
        assertTrue(dictionary.candidates("てすと", 0, 5, entries).conversions.size > 1)
        assertTrue(dictionary.candidates("てすと", 0, 0, entries).conversions.isEmpty())
        val updated = dictionary.candidates("てすと", 0, 5, listOf(entry("新候補", "てすと", 200))).conversions
        assertEquals("新候補", updated.first())
        assertTrue("旧候補" !in updated)
    }

    @Test
    fun personalEntryConvertsTheStartAndMiddleOfLongerReadings() {
        val dictionary = syntheticDictionary()
        val personal = listOf(entry("登録語", "てすと", 200))

        assertEquals(
            "登録語かな",
            dictionary.candidates("てすとかな", 0, additionalEntries = personal).conversions.first(),
        )
        assertEquals(
            "あ登録語い",
            dictionary.candidates("あてすとい", 0, additionalEntries = personal).conversions.first(),
        )
    }

    private val dictionaryRoot: File by lazy {
        val workingDirectory = requireNotNull(System.getProperty("user.dir"))
        generateSequence(File(workingDirectory).absoluteFile) { it.parentFile }
            .map { File(it, "third_party/azookey_dictionary_storage/Dictionary") }
            .firstOrNull(File::isDirectory)
            ?: error("azooKey dictionary submodule was not found")
    }

    private val dictionary by lazy {
        AzooKeyDictionary(
            DictionaryAssetSource { path -> resolveExactCase(dictionaryRoot, path).readBytes() },
        )
    }

    private fun resolveExactCase(root: File, relativePath: String): File =
        relativePath.split('/').fold(root) { directory, component ->
            directory.listFiles()
                ?.singleOrNull { it.name == component }
                ?: error("Dictionary path has the wrong case or is missing: $relativePath")
        }

    @Test
    fun convertsWithTheOfficialAzooKeyDictionary() {
        val candidates = dictionary.candidates("きょう", predictionLimit = 0).conversions

        assertTrue("今日 should be a conversion candidate: $candidates", "今日" in candidates)
        assertTrue("conversion candidates should be rich: $candidates", candidates.size >= 10)
    }

    @Test
    fun longSentenceStartsWithTheCommonCompleteConversion() {
        val candidates = dictionary.candidates(
            "わたしはきょうとうきょうのえきでともだちとあいました",
            predictionLimit = 0,
        ).conversions
        assertEquals("私は今日東京の駅で友達と会いました", candidates.first())
    }

    @Test
    fun createsPredictionsFromTheOfficialAzooKeyDictionary() {
        val predictions = dictionary.candidates("こんに", predictionLimit = 16).predictions

        assertTrue("predictions should not be empty", predictions.isNotEmpty())
        assertTrue(
            "predictions should extend the input: $predictions",
            predictions.any { it.length > "こんに".length },
        )
    }

    @Test
    fun commonCompletionsOutrankUnfinishedInflections() {
        for ((reading, expected) in listOf("よろ" to "よろしく", "にほ" to "日本", "こんに" to "こんにちは")) {
            assertEquals(expected, dictionary.candidates(reading, predictionLimit = 1).predictions.first())
        }
        val requests = dictionary.candidates("おねが", predictionLimit = 3).predictions
        assertTrue("お願いします" in requests)
        assertTrue("お願いし" !in requests)
    }

    @Test
    fun includesAzooKeyHotfixEntriesInConversionAndPrediction() {
        val entry = AzooKeyHotfixDictionaryEntry(
            word = "KeynakoHotfix",
            ruby = "ほっとふぃっくてすと",
            wordWeight = -5.0,
            lcid = 1288,
            rcid = 1288,
            mid = 501,
        )

        val conversion = dictionary.candidates(
            "ほっとふぃっくてすと",
            predictionLimit = 0,
            additionalEntries = listOf(entry),
            additionalDictionaryVersion = "test-v1",
        ).conversions
        val prediction = dictionary.candidates(
            "ほっとふぃっく",
            predictionLimit = 16,
            additionalEntries = listOf(entry),
            additionalDictionaryVersion = "test-v1",
        ).predictions

        assertTrue("hotfix conversion should be included: $conversion", "KeynakoHotfix" in conversion)
        assertTrue("hotfix prediction should be included: $prediction", "KeynakoHotfix" in prediction)
    }
}
