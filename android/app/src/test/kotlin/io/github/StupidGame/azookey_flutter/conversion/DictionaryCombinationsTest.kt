package io.github.StupidGame.azookey_flutter.conversion

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class DictionaryCombinationsTest {
    @Test
    fun combinesSharedAndPersonalWordsAcrossUnregisteredKana() {
        val candidates = dictionaryCombinationCandidates(
            "まきなとれいな",
            listOf(
                DictionaryCombinationEntry("まきな", "マキナ"),
                DictionaryCombinationEntry("れいな", "レイナ"),
            ),
        )
        assertEquals("マキナとレイナ", candidates.first())
    }

    @Test
    fun allowsParticleEndingButRejectsUnmatchedWords() {
        val entries = listOf(
            DictionaryCombinationEntry("まきな", "マキナ"),
            DictionaryCombinationEntry("れいな", "レイナ"),
        )
        assertTrue(dictionaryCombinationCandidates("あまきなとれいな", entries).isEmpty())
        assertTrue(dictionaryCombinationCandidates("まきなぴょれいな", entries).isEmpty())
        assertTrue(dictionaryCombinationCandidates("まきなとれいなぴょ", entries).isEmpty())
        assertEquals("マキナとレイナ", dictionaryCombinationCandidates(
            "まきなとれいな", entries,
        ).first())
        assertEquals("マキナとレイナも", dictionaryCombinationCandidates(
            "まきなとれいなも", entries,
        ).first())
        assertTrue("マキナとレイナぴょ" in incompleteDictionaryCombinations(
            "まきなとれいなぴょ", entries,
        ))
        assertTrue(usesMultipleRegisteredValues(
            "マキナとレイナピョ", entries.map { it.value },
        ))
        assertTrue(!usesMultipleRegisteredValues(
            "マキナとレイナピョ", entries.map { it.value }, setOf("マキナとレイナピョ"),
        ))
    }

    @Test
    fun doesNotInventACombinationFromOneRegisteredWord() {
        assertTrue(dictionaryCombinationCandidates(
            "まきなとれいな",
            listOf(DictionaryCombinationEntry("まきな", "マキナ")),
        ).isEmpty())
    }
}
