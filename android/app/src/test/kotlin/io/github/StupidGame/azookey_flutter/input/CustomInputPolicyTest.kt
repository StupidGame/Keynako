package io.github.StupidGame.azookey_flutter.input

import org.junit.Assert.assertEquals
import org.junit.Test

class CustomInputPolicyTest {
    @Test
    fun customLayoutLanguageSelectsTheComposingMode() {
        assertEquals(
            CustomLayoutSelection("english", "qwerty"),
            customLayoutSelection("en_US", "direct", "japanese", "flick"),
        )
        assertEquals(
            CustomLayoutSelection("japanese", "qwerty"),
            customLayoutSelection("ja_JP", "roman2kana", "english", "qwerty"),
        )
        assertEquals(
            CustomLayoutSelection("number", "tenkey"),
            customLayoutSelection("none", "direct", "number", "tenkey"),
        )
    }

    @Test
    fun shiftedLabelRequiresOneMatchingInputAction() {
        assertEquals("A", shiftedInputLabel("a", "input", "a", 1, true))
        assertEquals("a", shiftedInputLabel("a", "input", "b", 1, true))
        assertEquals("a", shiftedInputLabel("a", "direct_input", "a", 1, true))
        assertEquals("a", shiftedInputLabel("a", "input", "a", 2, true))
        assertEquals("abc", shiftedInputLabel("abc", "input", "abc", 1, true))
        assertEquals("a", shiftedInputLabel("a", "input", "a", 1, false))
    }
}
