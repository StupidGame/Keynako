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
    fun doesNotInventACombinationFromOneRegisteredWord() {
        assertTrue(dictionaryCombinationCandidates(
            "まきなとれいな",
            listOf(DictionaryCombinationEntry("まきな", "マキナ")),
        ).isEmpty())
    }
}
