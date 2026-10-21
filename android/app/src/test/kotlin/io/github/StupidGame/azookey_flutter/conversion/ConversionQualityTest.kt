package io.github.StupidGame.azookey_flutter.conversion

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ConversionQualityTest {
    private val dictionary by lazy {
        val root = generateSequence(File(requireNotNull(System.getProperty("user.dir"))).absoluteFile) { it.parentFile }
            .map { File(it, "third_party/azookey_dictionary_storage/Dictionary") }
            .first(File::isDirectory)
        AzooKeyDictionary(DictionaryAssetSource { path ->
            path.split('/').fold(root) { directory, component ->
                requireNotNull(directory.listFiles()).single { it.name == component }
            }.readBytes()
        })
    }

    @Test fun unlearnedInputKeepsVerbEndingsAndKatakanaWordsAfterEveryRankingStage() {
        for ((reading, expected, fragmented) in listOf(
            Triple("おとした", "落とした", "落としタ"),
            Triple("ますこっと", "マスコット", "真スコット"),
            Triple("すまほをおとした", "スマホを落とした", "スマホを落としタ"),
            Triple("かわいいますこっとをつくってほしい", "可愛いマスコットを作ってほしい",
                "可愛い真スコットを作ってほしい"),
            Triple("きのうすまほをおとしたからがめんがわれてしまった",
                "昨日スマホを落としたから画面が割れてしまった",
                "昨日スマホを落としタから画面が割れてしまっタ"),
        )) {
            val result = dictionary.candidates(reading, 0)
            assertEquals(reading, expected, result.canonicalConversion)
            val values = (listOf(fragmented) + result.conversions).distinct()
            val final = finalJapaneseCandidateSpellings(values, result.canonicalConversion)
            assertEquals(reading, expected, final.first())
            assertTrue(fragmented in final)
            assertEquals(expected, compositionCommitText(reading, final, true))
            assertEquals(fragmented, compositionCommitText(reading, final, true, final.indexOf(fragmented)))
        }
    }

    @Test fun learnedPathsCannotPruneTheReferenceSpellingAndValidationDoesNotPoisonIncrementalInput() {
        val reading = "おとしたからがめんがわれてしまった"
        val learned = listOf(AzooKeyHotfixDictionaryEntry(
            "落としタ", "おとした", -1.0, 1285, 1285, 501, isLearned = true,
        ))
        val baseline = dictionary.candidates(reading, 0).conversions.first()
        val result = dictionary.candidates(reading, 0, additionalEntries = learned)
        assertEquals(baseline, result.canonicalConversion)
        assertTrue(baseline in result.conversions)
        assertTrue(dictionary.validatesConversion("かかされてしまった", "書かされてしまった"))
        val repeated = dictionary.candidates(reading + "ので", 0, additionalEntries = learned)
        assertTrue(repeated.canonicalConversion!!.startsWith("落としたから"))
        val final = finalJapaneseCandidateSpellings(result.conversions, result.canonicalConversion)
        assertEquals(baseline, final.first())
    }

    @Test fun aGeneratedInflectionOutsideTheInitialBeamCanBecomeACompleteConversion() {
        for ((reading, generated) in listOf(
            "かかされてしまった" to "書かされてしまった",
            "せんせいにさくぶんをかかされてしまった" to "先生に作文を書かされてしまった",
        )) {
            val result = dictionary.candidates(reading, 0)
            assertFalse("Regression no longer exercises a pruned path", generated in result.conversions)
            assertTrue(dictionary.validatesConversion(reading, generated))
            val grounded = listOf(generated) + result.conversions
            val ranked = rerankedJapaneseCandidates(
                reading, grounded, grounded, emptyMap(), emptyMap(), preferredZenzaiCandidate = generated,
            )
            assertEquals(generated, finalJapaneseCandidateSpellings(ranked, result.canonicalConversion).first())
        }
    }

    @Test fun proposalsMustMatchEveryPartOfTheReading() {
        for ((reading, proposal) in listOf(
            "おとした" to "食べた", "くらって" to "作って",
            "せんせいにさくぶんをかかされてしまった" to "先生に作文を書かされて",
            "おとした" to "落としたので", "ますこっと" to "マスカット",
        )) assertFalse("$reading accepted $proposal", dictionary.validatesConversion(reading, proposal))
    }

    @Test fun aCorrectKatakanaWordIsNotDiscardedAsAnUnconvertedFallback() {
        val result = dictionary.candidates("ますこっと", 0)
        assertEquals("マスコット", result.conversions.first())
        // Both bundled models generate マスコット and score it above 真スコット.
        // The previous grouping still discarded it as literal kana afterward.
        val ranked = rerankedJapaneseCandidates(
            "ますこっと", result.conversions, result.conversions, emptyMap(), emptyMap(),
            preferredZenzaiCandidate = "マスコット",
        )
        assertEquals("マスコット", ranked.first())
        assertEquals("マスコット", finalJapaneseCandidateSpellings(ranked, result.canonicalConversion).first())
    }

    @Test fun singleKanaParticlesSurviveRerankingWithoutLearning() {
        for ((reading, expected, fragmented) in listOf(
            Triple("ぱすたに", "パスタに", "パスタ煮"),
            Triple("ぱすたが", "パスタが", "パスタ画"),
            Triple("ぱすたで", "パスタで", "パスタ出"),
            Triple("すまほに", "スマホに", "スマホ煮"),
            Triple("ともだちに", "友達に", "友達二"),
            Triple("ぱすたにちーずをかける", "パスタにチーズをかける", "パスタ煮チーズをかける"),
            Triple("ぱすたにした", "パスタにした", "パスタ煮した"),
        )) {
            val result = dictionary.candidates(reading, 0)
            assertEquals(reading, expected, result.canonicalConversion)
            val ranked = rerankedJapaneseCandidates(
                reading, listOf(fragmented) + result.conversions, result.conversions,
                emptyMap(), emptyMap(),
            )
            val final = finalJapaneseCandidateSpellings(ranked, result.canonicalConversion)
            assertEquals(reading, expected, final.first())
            assertTrue(fragmented in final)
            assertEquals(expected, compositionCommitText(reading, final, true))
            assertEquals(fragmented, compositionCommitText(reading, final, true, final.indexOf(fragmented)))
            // Context preferences run after model ranking. Apply the same
            // protection there, using the independently retained dictionary path.
            assertEquals(expected, finalJapaneseCandidateSpellings(
                listOf(fragmented) + final, result.canonicalConversion, modelPreferredText = expected,
            ).first())
        }
    }

    @Test fun confirmedNounSuffixesAndRegisteredSpellingsCanStillUseKanji() {
        for ((reading, noun) in listOf(
            "みそに" to "味噌煮", "かくに" to "角煮", "にこみ" to "煮込み", "さかなをにる" to "魚を煮る",
        )) {
            val result = dictionary.candidates(reading, 0)
            val generated = completeZenzaiCandidate(reading, noun, result.conversions, emptySet()) {
                dictionary.validatesConversion(reading, it)
            }
            assertEquals(noun, generated)
            val base = (listOf(noun) + result.conversions).distinct()
            val ranked = rerankedJapaneseCandidates(
                reading, base, base, emptyMap(), emptyMap(), preferredZenzaiCandidate = generated,
            )
            assertEquals(noun, finalJapaneseCandidateSpellings(
                ranked, result.canonicalConversion, modelPreferredText = generated,
            ).first())
        }
        assertEquals("パスタ煮", finalJapaneseCandidateSpellings(
            listOf("パスタ煮", "パスタに"), "パスタに", registeredTexts = setOf("パスタ煮"),
            modelPreferredText = "パスタに",
        ).first())
    }

    @Test fun runtimeAcceptsOnlyCompleteDictionaryGroundedProposalsAndKeepsFullWidthKana() {
        for ((reading, proposal) in listOf(
            "になる" to "になる", "ますこっと" to "マスコット",
            "せんせいにさくぶんをかかされてしまった" to "先生に作文を書かされてしまった",
        )) {
            val base = dictionary.candidates(reading, 0).conversions
            assertEquals(proposal, completeZenzaiCandidate(
                hiraganaToKatakana(reading), proposal, base, emptySet(),
            ) { dictionary.validatesConversion(reading, it) })
        }
        val reading = "せんせいにさくぶんをかかされてしまった"
        val base = dictionary.candidates(reading, 0).conversions
        for (proposal in listOf(
            "先生に作文を書かされて", "先生に作文を書かされてしまったので",
            katakanaToHalfWidth(hiraganaToKatakana(reading)),
        )) assertNull(completeZenzaiCandidate(reading, proposal, base, emptySet()) {
            dictionary.validatesConversion(reading, it)
        })
        assertNull(completeZenzaiCandidate(reading, base.first(), base, setOf(base.first())) { true })
    }

    @Test fun modelConfirmedHiraganaIsNotReplacedByKanji() {
        for ((reading, alternative) in listOf("になる" to "に成る", "なる" to "成る")) {
            val result = dictionary.candidates(reading, 0)
            assertEquals(reading, result.canonicalConversion)
            val ranked = rerankedJapaneseCandidates(
                reading, listOf(alternative) + result.conversions,
                listOf(alternative) + result.conversions, emptyMap(), emptyMap(),
                preferredZenzaiCandidate = reading, dictionaryLedLiteral = true,
            )
            val final = finalJapaneseCandidateSpellings(ranked, result.canonicalConversion)
            assertEquals(reading, final.first())
            assertEquals(reading, compositionCommitText(reading, final, true))
            assertTrue(alternative in final)
        }
    }

    @Test fun completeModelChoicesKeepThoughtAndItsInflectionsWithoutLearning() {
        for ((reading, expected, alternative) in listOf(
            Triple("おもった", "思った", "重った"),
            Triple("そうなるとおもった", "そうなると思った", "そうなると重った"),
            Triple("せんせいになるとおもった", "先生になると思った", "先生に成ると重った"),
        )) {
            val result = dictionary.candidates(reading, 0)
            assertEquals(reading, expected, result.canonicalConversion)
            assertTrue(dictionary.validatesConversion(reading, expected))
            val base = (listOf(alternative) + result.conversions).distinct()
            val ranked = rerankedJapaneseCandidates(
                reading, base, base, emptyMap(), emptyMap(), preferredZenzaiCandidate = expected,
            )
            assertEquals(expected, finalJapaneseCandidateSpellings(ranked, result.canonicalConversion).first())
        }
    }

    @Test fun explicitRegistrationsAndOrdinaryLearnedSpellingChoicesRemainPreferred() {
        assertEquals("落としタ", finalJapaneseCandidateSpellings(
            listOf("落としタ", "落とした"), "落とした", registeredTexts = setOf("落としタ"),
        ).first())
        assertEquals("真スコット", finalJapaneseCandidateSpellings(
            listOf("真スコット", "マスコット"), "マスコット", registeredTexts = setOf("真スコット"),
        ).first())
        assertEquals("話し手", finalJapaneseCandidateSpellings(
            listOf("話し手", "話して"), "話して", learnedTexts = setOf("話し手"),
        ).first())
        assertEquals("書かされた", finalJapaneseCandidateSpellings(
            listOf("書かされた", "欠かされた"), "欠かされた", learnedTexts = setOf("書かされた"),
        ).first())
    }
}
