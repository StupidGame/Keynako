package io.github.StupidGame.azookey_flutter.conversion

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class JapaneseTextTransformsTest {
    @Test
    fun pinsFullHiraganaAndKatakanaBeforeRankedCandidates() {
        assertEquals(
            listOf("きょう", "キョウ", "今日", "教", "京"),
            pinJapaneseKanaCandidates(
                reading = "キョウ",
                ranked = listOf("今日", "きょう", "教", "キョウ", "京"),
            ),
        )
    }

    @Test
    fun preservesTheExistingOrderAfterPinnedKanaCandidates() {
        assertEquals(
            listOf("にほんご", "ニホンゴ", "学習候補", "辞書候補", "Zenzai候補"),
            pinJapaneseKanaCandidates(
                reading = "にほんご",
                ranked = listOf("学習候補", "辞書候補", "Zenzai候補"),
            ),
        )
    }

    @Test
    fun prioritizesALiveConversionBeforePinnedKanaCandidates() {
        assertEquals(
            listOf("今日", "きょう", "キョウ", "教", "京"),
            pinJapaneseKanaCandidates(
                reading = "きょう",
                ranked = listOf("今日", "教", "京"),
                liveCandidate = "今日",
            ),
        )
    }

    @Test
    fun placesLearnedChoicesBeforeZenzaiAndKana() {
        val learned = exactLearnedJapaneseCandidates(
            "きょう",
            mapOf("きょう\t京" to 3, "きょう\t今日" to 8, "きょうか\t強化" to 20),
        )
        assertEquals(listOf("今日", "京"), learned)
        assertEquals(
            listOf("今日", "京", "教", "きょう", "キョウ", "強化"),
            pinJapaneseKanaCandidates(
                reading = "きょう",
                ranked = listOf("教", "強化", "今日", "京"),
                liveCandidate = "教",
                learnedCandidates = learned,
            ),
        )
    }

    @Test
    fun doesNotTreatRawKatakanaAsALiveConversion() {
        assertEquals(
            listOf("きょう", "キョウ", "今日"),
            pinJapaneseKanaCandidates(
                reading = "キョウ",
                ranked = listOf("キョウ", "今日"),
                liveCandidate = "キョウ",
            ),
        )
    }

    @Test
    fun prefersTheExistingHiraganaEndingAfterModelReranking() {
        val candidates = pinJapaneseKanaCandidates(
            reading = "つくった",
            ranked = listOf("作っタ", "創った", "作った"),
            liveCandidate = "作っタ",
        )

        assertEquals("作った", candidates.first())
        assertTrue("The original spelling must remain selectable", "作っタ" in candidates)
        assertEquals(candidates.size, candidates.distinct().size)
        assertEquals("作った", compositionCommitText("つくった", candidates, useCandidate = true))
        assertEquals(
            "作っタ",
            compositionCommitText("つくった", candidates, true, candidates.indexOf("作っタ")),
        )
    }

    @Test
    fun prefersTheExistingHiraganaSpellingOverAccidentallyLearnedKatakana() {
        val candidates = pinJapaneseKanaCandidates(
            reading = "つくったよ",
            ranked = listOf("作ったヨ", "作ったよ"),
            liveCandidate = "作ったヨ",
            learnedCandidates = exactLearnedJapaneseCandidates(
                "つくったよ", mapOf("つくったよ\t作ったヨ" to 32),
            ),
        )

        assertEquals("作ったよ", candidates.first())
        assertTrue("作ったヨ" in candidates)
    }

    @Test
    fun prefersHiraganaForIsolatedKatakanaInsideSentences() {
        for ((reading, mixed, natural) in listOf(
            Triple("つくったもの", "作っタもの", "作ったもの"),
            Triple("つくったよ", "作ったヨ", "作ったよ"),
            Triple("わたしはつくった", "私ハ作っタ", "私は作った"),
        )) {
            assertEquals(
                natural,
                pinJapaneseKanaCandidates(reading, listOf(mixed, natural), mixed).first(),
            )
        }
    }

    @Test
    fun preservesKatakanaWordsAndSmallKanaCounters() {
        for ((reading, preferred, alternative) in listOf(
            Triple("ぱんをかった", "パンを買った", "ぱんを買った"),
            Triple("ばすにのった", "バスに乗った", "ばすに乗った"),
            Triple("いっかしょ", "一ヶ所", "一ゖ所"),
            Triple("いっかしょ", "一ヵ所", "一ゕ所"),
            Triple("か", "カ", "か"),
        )) {
            assertEquals(
                preferred,
                pinJapaneseKanaCandidates(
                    reading, listOf(preferred, alternative), learnedCandidates = listOf(preferred),
                ).first(),
            )
        }
    }

    @Test
    fun doesNotInventAHiraganaSpellingMissingFromTheCandidates() {
        assertEquals(
            listOf("私ハ作った", "わたしはつくった", "ワタシハツクッタ", "私は造った"),
            pinJapaneseKanaCandidates(
                reading = "わたしはつくった",
                ranked = listOf("私ハ作った", "私は造った"),
                liveCandidate = "私ハ作った",
            ),
        )
    }

    @Test
    fun commitsSymbolsAndSpacingWithoutConversion() {
        listOf("、", "。", "？", "！", "「」", "　", "\t", "😊", "＋").forEach { value ->
            assertTrue("$value should bypass conversion", shouldDirectCommitJapaneseInput(value))
        }
        val fullWidthSymbols = "！＂＃＄％＆＇（）＊＋，－．／：；＜＝＞？＠［＼］＾＿｀｛｜｝～￥"
        assertTrue(
            "full-width symbols should bypass conversion",
            shouldDirectCommitJapaneseInput(fullWidthSymbols),
        )
    }

    @Test
    fun commitsDecimalDigitsWithoutConversion() {
        listOf("123", "１２３", "٣٤٥").forEach { value ->
            assertTrue("$value should bypass conversion", shouldDirectCommitJapaneseInput(value))
            assertTrue(
                "$value from a Custard input action should bypass conversion",
                shouldDirectCommitJapaneseInput(
                    value,
                    JapaneseInputContext.CUSTARD_ACTION_SEQUENCE,
                ),
            )
        }
    }

    @Test
    fun keepsJapaneseReadingsInTheConversionPipeline() {
        listOf("きょう", "キョウ", "ー", "きょう？", "第3", "12a").forEach { value ->
            assertFalse("$value should remain convertible", shouldDirectCommitJapaneseInput(value))
        }
    }

    @Test
    fun keepsCustardSymbolMarkersInTheActionSequence() {
        listOf("・", "？", "＋").forEach { value ->
            assertFalse(
                "$value must remain available to a following replace_last_characters action",
                shouldDirectCommitJapaneseInput(
                    value,
                    JapaneseInputContext.CUSTARD_ACTION_SEQUENCE,
                ),
            )
        }
    }
}
