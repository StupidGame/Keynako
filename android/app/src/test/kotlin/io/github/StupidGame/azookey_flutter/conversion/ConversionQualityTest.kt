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

    @Test fun personalWordPreferencesCannotSplitBundledWordsAfterLatticeRanking() {
        for ((reading, normal, preference) in listOf(
            Triple("ふるふれっくす", "フルフレックス", "ふ" to "不"),
            Triple("ふるふれっくすせいど", "フルフレックス制度", "ふ" to "不"),
            Triple("せんせいにいわれたから", "先生に言われたから", "せい" to "姓"),
            Triple("きょうあめりかにいく", "今日アメリカに行く", "あめ" to "雨"),
        )) for (learned in listOf(false, true)) {
            val entries = listOf(AzooKeyHotfixDictionaryEntry(
                preference.second, preference.first, -5.0, 1285, 1285, 501, isLearned = learned,
            ))
            val result = dictionary.candidates(reading, 0, additionalEntries = entries)
            assertTrue("$reading: ${result.preferredSentenceConversions}",
                result.preferredSentenceConversions.isEmpty())
            assertNull(dictionary.preferredSentenceConversion(reading, normal, entries))
            // Both bundled models generate these complete spellings. No
            // artificial personal-word path may push them back down afterward.
            val generated = completeZenzaiCandidate(reading, normal, result.conversions, emptySet()) {
                dictionary.validatesConversion(reading, it, entries)
            }
            assertEquals(normal, generated)
            val base = (listOfNotNull(generated) + result.conversions).distinct()
            val ranked = rerankedJapaneseCandidates(
                reading, base, base, emptyMap(), emptyMap(),
                dictionaryCandidates = result.preferredSentenceConversions.toList(),
                preferredZenzaiCandidate = generated,
                exactRegistrationTexts = result.preferredSentenceConversions,
            )
            assertEquals(normal, finalJapaneseCandidateSpellings(
                ranked, result.canonicalConversion,
                registeredTexts = result.preferredSentenceConversions, modelPreferredText = generated,
            ).first())
        }
    }

    @Test fun theSameShortRegistrationStillWorksWhenItIsAWholeWord() {
        val entries = listOf(AzooKeyHotfixDictionaryEntry("不", "ふ", -5.0, 1285, 1285, 501))
        assertEquals("不を書く", dictionary.preferredSentenceConversion("ふをかく", "符を書く", entries))
    }

    @Test fun registeredAndLearnedWordsReplaceOnlyTheirAlignedSpansInSentences() {
        val reading = "きょうさとうさんととうきょうにいく"
        val original = "今日佐藤さんと東京に行く"
        val entries = listOf(
            AzooKeyHotfixDictionaryEntry("佐東", "さとう", -5.0, 1285, 1285, 501, isLearned = true),
            AzooKeyHotfixDictionaryEntry("TOKYO", "とうきょう", -9.0, 1285, 1285, 501),
        )
        assertEquals("今日佐東さんとTOKYOに行く",
            dictionary.preferredSentenceConversion(reading, original, entries))
        assertTrue(dictionary.validatesConversion(reading, "今日佐東さんとTOKYOに行く", entries))
        val actual = dictionary.candidates(reading, 0, additionalEntries = entries)
        assertTrue(actual.preferredSentenceConversions.isNotEmpty())
        assertTrue(actual.conversions.first().contains("佐東"))
        assertTrue(actual.conversions.first().contains("TOKYO"))
    }

    @Test fun sentencePreferencesDoNotSplitTeachersOrReuseTheWrongReadingOfRawFish() {
        val entries = listOf(AzooKeyHotfixDictionaryEntry("姓", "せい", -9.0, 1285, 1285, 501))
        assertNull(dictionary.preferredSentenceConversion(
            "せんせいがなまのさかなをかう", "先生が生の魚を買う", entries,
        ))
    }

    @Test fun aLearnedPhraseCannotHideARegisteredWordInsideIt() {
        val entries = listOf(
            AzooKeyHotfixDictionaryEntry("佐藤に会う", "さとうにあう", -1.0, 1285, 1285, 501, isLearned = true),
            AzooKeyHotfixDictionaryEntry("佐東", "さとう", -9.0, 1285, 1285, 501),
        )
        assertEquals("佐東に会う", dictionary.preferredSentenceConversion("さとうにあう", "佐藤に会う", entries))
    }

    @Test fun wordPreferenceAlignmentDoesNotChangeTheIncrementalLatticeOrAcceptPredictions() {
        val entries = listOf(AzooKeyHotfixDictionaryEntry("TOKYO", "とうきょう", -9.0, 1285, 1285, 501))
        val reading = "きょうとうきょうにいく"
        dictionary.candidates(reading, 0, additionalEntries = entries)
        assertNull(dictionary.preferredSentenceConversion("とう", "東京", entries))
        dictionary.preferredSentenceConversion(reading, "今日東京に行く", entries)
        val next = dictionary.candidates(reading + "ので", 0, additionalEntries = entries)
        val fresh = AzooKeyDictionary(DictionaryAssetSource { path ->
            val root = generateSequence(File(requireNotNull(System.getProperty("user.dir"))).absoluteFile) { it.parentFile }
                .map { File(it, "third_party/azookey_dictionary_storage/Dictionary") }.first(File::isDirectory)
            File(root, path).readBytes()
        }).candidates(reading + "ので", 0, additionalEntries = entries)
        assertEquals(fresh.conversions, next.conversions)
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

    @Test fun parsedVerbsSurviveIncompleteRegisteredCombinationChecks() {
        val reading = "いってきた"
        val entries = listOf(
            DictionaryCombinationEntry("いって", "言って"),
            DictionaryCombinationEntry("た", "た"),
        )
        val result = dictionary.candidates(reading, 0, additionalEntries = entries.map {
            AzooKeyHotfixDictionaryEntry(it.value, it.reading, -9.0, 1285, 1285, 501)
        })
        assertTrue(result.parsedInflectionConversions.containsAll(listOf("行ってきた", "言ってきた")))
        val incomplete = incompleteDictionaryCombinations(reading, entries)
            .mapTo(mutableSetOf(), ::katakanaToHiragana)
        assertTrue("The registered-word heuristic must exercise the original rejection", "言ってきた" in incomplete)
        assertFalse(isAllowedCombinationCandidate(
            "言ってきた", emptySet(), incomplete, entries.map { it.value }, emptySet(),
        ))
        val remainingIncomplete = incomplete - result.parsedInflectionConversions.map(::katakanaToHiragana).toSet()
        assertTrue(isAllowedCombinationCandidate(
            "言ってきた", result.parsedInflectionConversions, remainingIncomplete, entries.map { it.value }, emptySet(),
        ))
        val generated = completeZenzaiCandidate(reading, "言ってきた", result.conversions, remainingIncomplete) {
            dictionary.validatesConversion(reading, it)
        }
        val ranked = rerankedJapaneseCandidates(
            reading, result.conversions, result.conversions, emptyMap(), emptyMap(),
            preferredZenzaiCandidate = generated,
        )
        val final = finalJapaneseCandidateSpellings(ranked, result.canonicalConversion, modelPreferredText = generated)
        assertEquals("言ってきた", final.first())
        assertTrue("行ってきた" in final)
        assertEquals("言ってきた", compositionCommitText(reading, final, true))
    }

    @Test fun unparsedRegisteredWordTailsAreNotPromotedToParsedInflections() {
        val entries = listOf(
            DictionaryCombinationEntry("まきな", "マキナ"), DictionaryCombinationEntry("れいな", "レイナ"),
        )
        val reading = "まきなとれいなぴょ"
        val result = dictionary.candidates(reading, 0, additionalEntries = entries.map {
            AzooKeyHotfixDictionaryEntry(it.value, it.reading, -9.0, 1285, 1285, 501)
        })
        assertFalse("Unclassified literal kana cannot prove a complete grammatical conversion",
            "マキナとレイナピョ" in result.parsedInflectionConversions)
        val incomplete = incompleteDictionaryCombinations(reading, entries)
            .mapTo(mutableSetOf(), ::katakanaToHiragana) -
            result.parsedInflectionConversions.map(::katakanaToHiragana).toSet()
        assertFalse(isAllowedCombinationCandidate(
            "マキナとレイナピョ", result.parsedInflectionConversions, incomplete,
            entries.map { it.value }, emptySet(),
        ))
    }

    @Test fun aNounFollowedByPastTenseCannotDisplaceTheActualVerb() {
        val reading = "いってきた"
        val result = dictionary.candidates(reading, 0)
        val invalid = result.invalidInflectionConversions
        assertTrue("一滴た" in result.conversions)
        assertTrue("一滴た" in invalid)
        assertTrue("Reading validation alone is not a default spelling preference",
            dictionary.validatesConversion(reading, "一滴た"))
        assertFalse("言ってきた" in invalid)
        assertFalse("行ってきた" in invalid)
        assertNull(completeZenzaiCandidate(reading, "一滴た", result.conversions, invalid) { true })
        val ranked = listOf("一滴た", "言ってきた", "行ってきた")
        val final = finalJapaneseCandidateSpellings(
            ranked, result.canonicalConversion, modelPreferredText = "一滴た", invalidInflectionTexts = invalid,
        )
        assertEquals("言ってきた", final.first())
        assertTrue("一滴た" in final)
        assertEquals("言ってきた", compositionCommitText(reading, final, true))
        assertEquals("一滴た", finalJapaneseCandidateSpellings(
            ranked, result.canonicalConversion, registeredTexts = setOf("一滴た"), invalidInflectionTexts = invalid,
        ).first())
    }

    @Test fun ordinaryPredicatesAndRegisteredVerbStemsAreNotClassifiedAsInvalidPastTense() {
        for ((reading, expected) in listOf(
            "ねこだ" to "猫だ", "すきだった" to "好きだった", "たべた" to "食べた",
            "よんだ" to "読んだ", "たかかった" to "高かった", "いってきた" to "言ってきた",
        )) {
            val result = dictionary.candidates(reading, 0)
            assertTrue("$reading must retain $expected", expected in result.conversions)
            assertFalse("$expected cannot be marked invalid", expected in result.invalidInflectionConversions)
        }
        val result = dictionary.candidates("おとした", 0, additionalEntries = listOf(
            AzooKeyHotfixDictionaryEntry("落とし", "おとし", -3.0, 1285, 1285, 501),
        ))
        assertTrue("落とした" in result.conversions)
        assertFalse("落とした" in result.invalidInflectionConversions)
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
