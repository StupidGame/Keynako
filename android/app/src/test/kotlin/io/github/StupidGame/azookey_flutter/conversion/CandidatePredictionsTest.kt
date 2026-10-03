package io.github.StupidGame.azookey_flutter.conversion

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CandidatePredictionsTest {

    @Test
    fun completeConversionsLeadLiveInputWithoutPromotingCompletions() {
        assertEquals(
            "今日の予定",
            bestLiveJapaneseConversion(
                "きょうのよてい",
                setOf("今日の予定", "きょうのよてい"),
                listOf("先の予測", "きょうのよてい", "今日の予定"),
            ),
        )
    }

    @Test
    fun longReadingsUseRerankingBeforeGenerationWouldBeTruncated() {
        assertEquals(96, zenzaiGenerationTokenBudget(40, 1))
        assertTrue(!shouldGenerateZenzaiCandidate(40, 96))
        assertTrue(shouldGenerateZenzaiCandidate(8, zenzaiGenerationTokenBudget(8, 1)))
    }

    @Test
    fun novelModelOutputDoesNotDisplaceEstablishedConversions() {
        assertEquals(
            listOf("今日は晴れる", "今日は晴れ", "きょうははれる", "奇妙な候補"),
            placeNovelGeneratedCandidate(
                listOf("奇妙な候補", "今日は晴れる", "今日は晴れ", "きょうははれる"),
                "奇妙な候補",
                setOf("今日は晴れる", "今日は晴れ", "きょうははれる"),
            ),
        )
    }

    @Test
    fun commitsTheRawReadingWhenCandidateConversionIsDisabled() {
        assertEquals(
            "かめん",
            compositionCommitText(
                reading = "かめん",
                candidates = listOf("仮面", "画面"),
                useCandidate = false,
            ),
        )
        assertEquals(
            "仮面",
            compositionCommitText(
                reading = "かめん",
                candidates = listOf("仮面", "画面"),
                useCandidate = true,
            ),
        )
    }

    @Test
    fun englishPredictionsKeepTypedTextFirstAndCompleteItsPrefix() {
        assertEquals(
            listOf("hel", "hello", "help"),
            englishPredictionCandidates("hel"),
        )
    }

    @Test
    fun englishPredictionsPreserveTheTypedCapitalization() {
        assertEquals(
            listOf("Hel", "Hello", "Help"),
            englishPredictionCandidates("Hel"),
        )
        assertEquals(
            listOf("HEL", "HELLO", "HELP"),
            englishPredictionCandidates("HEL"),
        )
    }

    @Test
    fun caseFormsKeepCustomLayoutTextAvailableForContinuedConversion() {
        assertEquals("HEL", caseConvertedComposition("Hel", "uppercase"))
        assertEquals("hello", caseConvertedComposition("Hello", "lowercase"))
        assertEquals(
            listOf("HEL", "HELLO", "HELP"),
            englishPredictionCandidates(
                checkNotNull(caseConvertedComposition("hel", "uppercase")),
            ),
        )
        assertNull(caseConvertedComposition("かな", "katakana"))
    }

    @Test
    fun returnsWordsWhoseReadingStartsWithThePartialInput() {
        val values = prefixPredictionValues(
            reading = "かめん",
            entries = listOf(
                "かめん" to listOf("仮面"),
                "かめんらいだー" to listOf("仮面ライダー"),
                "かみなり" to listOf("雷"),
            ),
            limit = 8,
        )

        assertEquals(listOf("仮面ライダー"), values)
        assertEquals(listOf("仮面ライダー"), prefixPredictionValues(
            reading = "かめ",
            entries = listOf("かめんらいだー" to listOf("仮面ライダー")),
            limit = 8,
        ))
    }

    @Test
    fun registeredWordPredictsFromKameAndKamen() {
        val entry = ReadingPrediction("かめんらいだー", "仮面ライダー")
        for (reading in listOf("かめ", "かめん")) {
            assertEquals(listOf("仮面ライダー"),
                rankUserPrefixPredictions(reading, listOf(entry), 32).map { it.text })
        }
    }

    @Test
    fun placesPredictionsAfterTheLeadingConversionCandidates() {
        val values = prioritizePrefixPredictions(
            conversions = listOf("仮面", "画面", "かめん"),
            predictions = listOf("仮面ライダー"),
        )

        assertEquals(listOf("仮面", "画面", "仮面ライダー", "かめん"), values)
    }

    @Test
    fun normalizesAndPrefersShorterCompletions() {
        assertEquals(listOf("テスト", "テストケース"), prefixPredictionValues(
            "てす", listOf("テストケース" to listOf("テストケース"), "テスト" to listOf("テスト")), 2,
        ))
        assertEquals("てすと", prefixPredictionEntries(
            "てす", listOf("テスト" to listOf("テスト")), 1,
        ).single().reading)
    }

    @Test
    fun aNearbyUserCompletionCanOutrankAMuchLongerOne() {
        assertEquals(
            listOf("近い", "遠い"),
            rankUserPrefixPredictions("てす", listOf(
                ReadingPrediction("てすとけーすながいよそく", "遠い", 5),
                ReadingPrediction("てすと", "近い", 4),
            ), 2).map { it.text },
        )
    }

    @Test
    fun predictionsDoNotPromoteDuplicateConversions() {
        assertEquals(listOf("一", "二", "予測", "三", "四"), prioritizePrefixPredictions(
            listOf("一", "二", "三", "四"), listOf("四", "予測"),
        ))
    }

    @Test
    fun recallsLearnedWordsAndKeepsLongerReadingsAsPredictions() {
        val learning = mapOf("キーナコ\tKeynako" to 4)
        assertEquals("Keynako", rankJapaneseCandidates("きーなこ", listOf("きーなこ"), emptyList(), learning).first())
        assertEquals(listOf("きー", "キー", "Keynako"), rankJapaneseCandidates(
            "きー", listOf("きー", "キー"), emptyList(), learning,
        ))
        assertEquals(listOf("きー"), rankJapaneseCandidates("きー", listOf("きー"), emptyList(), learning, 0))
        assertEquals(listOf("ほか"), rankJapaneseCandidates("ほか", listOf("ほか"), emptyList(), learning))
    }

    @Test
    fun learnedLongReadingAppearsFromBothShortPrefixes() {
        val learning = mapOf("かめんらいだー\t仮面ライダー" to 8)
        for (reading in listOf("かめ", "かめん")) {
            val learned = learnedJapanesePrefixPredictions(reading, learning)
            assertEquals(listOf("仮面ライダー"), learned.map { it.text })
            assertEquals("かめんらいだー", learned.single().reading)
            val ranked = rankJapaneseCandidates(
                reading, listOf("仮面", reading, hiraganaToKatakana(reading)), emptyList(), learning,
            )
            val pinned = pinJapaneseKanaCandidates(
                reading, ranked, liveCandidate = "仮面",
                prominentPredictions = learned.map { it.text },
            )
            assertEquals(listOf("仮面", "仮面ライダー"), pinned.take(2))
        }
    }

    @Test
    fun learningAndDeduplicationAreAppliedBeforePredictionLimit() {
        assertEquals(listOf("てす", "テストケース"), rankJapaneseCandidates(
            "てす", listOf("てす"), listOf("てす", "テスト", "テスト"),
            mapOf("てすとけーす\tテストケース" to 5, "てすと\t" to 99), 1,
        ))
    }
}
