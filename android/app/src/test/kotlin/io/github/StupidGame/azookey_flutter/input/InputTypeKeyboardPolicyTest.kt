package io.github.StupidGame.azookey_flutter.input

import org.junit.Assert.assertEquals
import org.junit.Test

class InputTypeKeyboardPolicyTest {
    @Test
    fun choosesSpecializedKeyboardsFromTheInputClass() {
        assertEquals(RequestedKeyboardMode.NUMBER, requestedKeyboardMode(0x00000002))
        assertEquals(RequestedKeyboardMode.PHONE, requestedKeyboardMode(0x00000003))
        assertEquals(RequestedKeyboardMode.DATE_TIME, requestedKeyboardMode(0x00000004))
    }

    @Test
    fun numberFlagsDoNotChangeTheRequestedKeyboard() {
        val signedDecimalNumber = 0x00000002 or 0x00001000 or 0x00002000
        assertEquals(
            RequestedKeyboardMode.NUMBER,
            requestedKeyboardMode(signedDecimalNumber),
        )
    }

    @Test
    fun choosesEnglishForAsciiOrEnglishLocalizedTextFields() {
        assertEquals(
            RequestedKeyboardMode.ENGLISH,
            requestedKeyboardMode(0x00000001 or 0x00000020),
        )
        assertEquals(
            RequestedKeyboardMode.ENGLISH,
            requestedKeyboardMode(0x00000001 or 0x00000010),
        )
        assertEquals(
            RequestedKeyboardMode.ENGLISH,
            requestedKeyboardMode(
                0x00000001,
                hintLocaleTags = listOf("en-US", "ja-JP"),
            ),
        )
        assertEquals(
            RequestedKeyboardMode.ENGLISH,
            requestedKeyboardMode(0x00000001, imeOptions = Int.MIN_VALUE),
        )
    }

    @Test
    fun keepsOrdinaryAndJapaneseLocalizedTextInJapaneseMode() {
        assertEquals(RequestedKeyboardMode.JAPANESE, requestedKeyboardMode(0x00000001))
        assertEquals(
            RequestedKeyboardMode.JAPANESE,
            requestedKeyboardMode(0x00000001, hintLocaleTags = listOf("ja-JP")),
        )
        assertEquals(RequestedKeyboardMode.JAPANESE, requestedKeyboardMode(0))
    }

    @Test
    fun identifiesPasswordVariationsAsSensitive() {
        assertEquals(true, isSensitiveInputType(0x00000001 or 0x00000080))
        assertEquals(true, isSensitiveInputType(0x00000001 or 0x000000e0))
        assertEquals(false, isSensitiveInputType(0x00000001 or 0x00000020))
        assertEquals(false, isSensitiveInputType(0x00000002))
    }
}
