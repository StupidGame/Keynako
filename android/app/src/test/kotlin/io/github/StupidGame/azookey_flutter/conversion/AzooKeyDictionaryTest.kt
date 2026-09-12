package io.github.StupidGame.azookey_flutter.conversion

import java.io.File
import org.junit.Assert.assertTrue
import org.junit.Test

class AzooKeyDictionaryTest {
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
    fun createsPredictionsFromTheOfficialAzooKeyDictionary() {
        val predictions = dictionary.candidates("こんに", predictionLimit = 16).predictions

        assertTrue("predictions should not be empty", predictions.isNotEmpty())
        assertTrue(
            "predictions should extend the input: $predictions",
            predictions.any { it.length > "こんに".length },
        )
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
