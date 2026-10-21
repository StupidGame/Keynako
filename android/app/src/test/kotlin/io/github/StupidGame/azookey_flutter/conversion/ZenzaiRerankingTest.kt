package io.github.StupidGame.azookey_flutter.conversion

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ZenzaiRerankingTest {
    @Test fun halfWidthKanaNeverDisplacesACompleteLongSentenceAfterModelRanking() {
        val reading = "せんせいにいわれたからしゅくだいをしました"
        val converted = "先生に言われたから宿題をしました"
        val halfWidth = katakanaToHalfWidth(hiraganaToKatakana(reading))
        val base = listOf(converted, reading, hiraganaToKatakana(reading), halfWidth)
        for (learning in listOf(emptyMap(), mapOf("$reading\t$halfWidth" to 3))) {
            val result = rerankedJapaneseCandidates(
                reading, listOf(halfWidth) + base, base, emptyMap(), learning,
                preferredZenzaiCandidate = halfWidth,
            )
            assertEquals(converted, result.first())
            assertTrue("Half-width input must still be selectable", halfWidth in result)
        }
        assertTrue(halfWidth !in zenzaiRerankingCandidates(reading, base))
        assertEquals(converted, bestLiveJapaneseConversion(
            reading, base.toSet(), listOf(halfWidth, converted),
        ))
        assertEquals(halfWidth, rerankedJapaneseCandidates(
            reading, listOf(halfWidth) + base, base, emptyMap(), emptyMap(),
            dictionaryCandidates = listOf(halfWidth), exactRegistrationTexts = setOf(halfWidth),
        ).first())
    }

    @Test fun parsedKanaEndingsSurviveModelRankingAtTheEndAndInsideSentences() {
        for ((reading, conversion, fragmented) in listOf(
            Triple("いわれたから", "言われたから", "言われ財"),
            Triple("くらって", "食らって", "食らっ手"),
            Triple("つくった", "作った", "作っタ"),
            Triple("いわれなかった", "言われなかった", "言われなかっ他"),
            Triple("たべさせられた", "食べさせられた", "食べさせられ他"),
            Triple("いわれたからかえった", "言われたから帰った", "言われ財帰った"),
            Triple("せんせいにいわれたからしゅくだいをしました",
                "先生に言われたから宿題をしました", "先生に言われたから宿題を島下"),
        )) {
            val result = rerankedJapaneseCandidates(
                reading, listOf(fragmented, conversion), listOf(conversion, fragmented),
                emptyMap(), emptyMap(), preferredZenzaiCandidate = fragmented,
            )
            assertEquals(reading, conversion, result.first())
            assertTrue("An alternative must remain selectable", fragmented in result)
        }
    }

    @Test fun explicitChoicesAndLexicalAmbiguitiesRemainAvailable() {
        val reference = "食らって"
        val alternative = "食らっ手"
        for (learning in listOf(emptyMap(), mapOf("くらって\t$alternative" to 1),
            mapOf("くらって\t$alternative" to 4))) {
            val result = rerankedJapaneseCandidates(
                "くらって", listOf(alternative, reference), listOf(reference, alternative),
                emptyMap(), learning,
            )
            assertEquals(if ((learning.values.firstOrNull() ?: 0) >= 4) alternative else reference, result.first())
        }
        assertEquals(alternative, rerankedJapaneseCandidates(
            "くらって", listOf(alternative, reference), listOf(reference, alternative),
            emptyMap(), emptyMap(), dictionaryCandidates = listOf(alternative),
            exactRegistrationTexts = setOf(alternative),
        ).first())
        for ((base, ranked) in listOf(
            "昨日会った" to "昨日合った", "食らって" to "喰らって",
            "今日は帰る" to "今日は変える", "書いて" to "描いて",
        )) {
            assertEquals(listOf(ranked, base), preserveDictionaryKana(base, listOf(ranked, base), emptySet()))
        }
    }

    @Test fun modelBudgetGoesToConversionsInsteadOfLiteralsAndCompletions() {
        val reading = "センセイニイワレタカラシュクダイヲシマシタ"
        val complete = "先生に言われたから宿題をしました"
        val completion = complete + "が"
        val partial = "先生にいわれたからしゅくだいをしました"
        val pool = zenzaiRerankingCandidates(
            reading, listOf(reading, katakanaToHiragana(reading), completion, partial, complete),
            setOf(completion, partial),
        )
        assertEquals(listOf(complete), pool)
        assertTrue(zenzaiRerankingCandidates(reading + "k", listOf(complete + "k")).isEmpty())
        assertEquals(listOf(complete), zenzaiRerankingCandidates(reading, listOf(complete)))
    }

    @Test fun longSentencesBoundTheAmountOfWholeSentenceScoring() {
        val reading = "せんせいにいわれたからしゅくだいをしました".repeat(6)
        val candidates = (1..48).map { "先生に言われたから宿題をしました".repeat(6) + it }
        val pool = zenzaiRerankingCandidates(reading, candidates)
        assertTrue(pool.isNotEmpty())
        assertTrue("Long text still scores all candidates", pool.size * reading.length <= 384)
        assertEquals(candidates.take(pool.size), pool)
    }
}
