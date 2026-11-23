package io.github.StupidGame.azookey_flutter.conversion

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class SentenceWordPreferencesTest {
    @Test fun alternativeParsesCannotInventWordBoundariesForPersonalSpellings() {
        assertNull(preferredSentenceSpelling(
            "ふるふれっくす", "不るフレックス", listOf(
                ConversionWordSpan(0, 1, 0, 1), ConversionWordSpan(1, 2, 1, 2),
                ConversionWordSpan(2, 7, 2, 7),
            ), listOf(SentenceWordPreference("ふ", "不", learned = true)),
            referenceWords = listOf(ConversionWordSpan(0, 2, 0, 2), ConversionWordSpan(2, 7, 2, 7)),
        ))
    }

    @Test fun replacesTheMiddleAndBothRepeatedOccurrencesWithoutChangingTheRest() {
        val spans = listOf(
            ConversionWordSpan(0, 3, 0, 2), // 今日
            ConversionWordSpan(3, 6, 2, 4), // 佐藤
            ConversionWordSpan(6, 7, 4, 5), // と
            ConversionWordSpan(7, 10, 5, 7), // 佐藤
            ConversionWordSpan(10, 11, 7, 8), // に
            ConversionWordSpan(11, 13, 8, 10), // 会う
        )
        assertEquals("今日佐東と佐東に会う", preferredSentenceSpelling(
            "きょうさとうとさとうにあう", "今日佐藤と佐藤に会う", spans,
            listOf(SentenceWordPreference("さとう", "佐東", learned = true)),
        )?.text)
    }

    @Test fun registrationsWinOverLearnedOverlapsAndLongerRegistrationsWin() {
        val spans = listOf(ConversionWordSpan(0, 3, 0, 2), ConversionWordSpan(3, 4, 2, 3))
        assertEquals("佐東に", preferredSentenceSpelling("さとうに", "佐藤に", spans, listOf(
            SentenceWordPreference("さとうに", "佐藤煮", learned = true, weight = 10.0),
            SentenceWordPreference("さとう", "佐東"),
        ))?.text)
        assertEquals("佐東へ", preferredSentenceSpelling("さとうに", "佐藤に", spans, listOf(
            SentenceWordPreference("さとう", "佐東"),
            SentenceWordPreference("さとうに", "佐東へ"),
        ))?.text)
    }

    @Test fun aReadingInsideAnotherWordAndAnUnrelatedHomographAreLeftAlone() {
        val spans = listOf(
            ConversionWordSpan(0, 4, 0, 2), // 先生 / せんせい
            ConversionWordSpan(4, 5, 2, 3), // が
            ConversionWordSpan(5, 7, 3, 4), // 生 / なま
        )
        assertNull(preferredSentenceSpelling("せんせいがなま", "先生が生", spans,
            listOf(SentenceWordPreference("せい", "姓"))))
    }

    @Test fun equalPriorityChoicesKeepTheExistingSpelling() {
        assertEquals("強い終端", preferredSentenceSpelling("てすと", "強い終端",
            listOf(ConversionWordSpan(0, 3, 0, 4)), listOf(
                SentenceWordPreference("てすと", "弱い終端"),
                SentenceWordPreference("てすと", "強い終端"),
            ))?.text)
    }

    @Test fun preferredWordSpellingsKeepTheModelsSentenceOrderAndExactRegistrationPriority() {
        val first = "今日佐東さんに会う"
        val second = "今日は佐東さんに会う"
        assertEquals(listOf("登録した全文", second, first, "他の候補"), prioritizeRegisteredJapaneseCandidates(
            candidates = listOf("他の候補", second, first, "登録した全文"),
            dictionaryCandidates = listOf("登録した全文", first, second),
            exactRegistrationTexts = setOf("登録した全文", first, second),
            sentencePreferenceTexts = setOf(first, second),
        ))
    }

    @Test fun verifiedPrefixReplacementsLeadCombinationsWithoutHidingExactRegistrations() {
        val exact = "登録した全文"
        val combination = "辞書語を組み合わせた文"
        val middle = "今日佐東さんに会う"
        val prefix = "佐東さんに会う"
        val secondPrefix = "佐東さんに遭う"
        val base = listOf(exact, combination, middle, prefix, secondPrefix, "予測候補", "通常候補")
        val ranks = listOf("通常候補", middle, secondPrefix, combination, prefix, exact, "予測候補")
        val sentences = setOf(middle, prefix, secondPrefix)
        val prefixes = setOf(prefix, secondPrefix)
        val priority = listOf(exact, combination, middle, prefix, secondPrefix, "予測候補")
        val exactTexts = sentences + exact
        assertEquals(listOf(exact, prefix, secondPrefix, combination, middle), prioritizeRegisteredJapaneseCandidates(
            candidates = base, dictionaryCandidates = priority, predictionTexts = setOf("予測候補"),
            exactRegistrationTexts = exactTexts, sentencePreferenceTexts = sentences, prefixPreferenceTexts = prefixes,
        ).take(5))
        assertEquals(listOf(exact, secondPrefix, prefix, combination, middle), rerankedJapaneseCandidates(
            reading = "さとうさんにあう", ranked = ranks, baseCandidates = base,
            predictionReadings = mapOf("予測候補" to "さとうさんにあうとき"), learning = emptyMap(),
            dictionaryCandidates = priority, exactRegistrationTexts = exactTexts,
            sentencePreferenceTexts = sentences, prefixPreferenceTexts = prefixes,
        ).take(5))
    }
}
