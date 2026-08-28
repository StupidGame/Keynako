package io.github.StupidGame.azookey_flutter.input

import org.junit.Assert.assertEquals
import org.junit.Test

class KanaCharacterFormsTest {
    @Test
    fun plainVoicedAndSemiVoicedFormsRepeatInOrder() {
        val cycles = listOf(
            listOf("は", "ば", "ぱ"), listOf("ひ", "び", "ぴ"),
            listOf("ふ", "ぶ", "ぷ"), listOf("へ", "べ", "ぺ"),
            listOf("ほ", "ぼ", "ぽ"), listOf("ハ", "バ", "パ"),
            listOf("ヒ", "ビ", "ピ"), listOf("フ", "ブ", "プ"),
            listOf("ヘ", "ベ", "ペ"), listOf("ホ", "ボ", "ポ"),
        )

        for ((plain, voiced, semiVoiced) in cycles) {
            assertEquals(voiced, kanaCharacterFormReplacement(plain))
            assertEquals(semiVoiced, kanaCharacterFormReplacement(voiced))
            assertEquals(plain, kanaCharacterFormReplacement(semiVoiced))
        }
    }

    @Test
    fun otherKanaFormsKeepTheirExistingCycles() {
        assertEquals("ぁ", kanaCharacterFormReplacement("あ"))
        assertEquals("あ", kanaCharacterFormReplacement("ぁ"))
        assertEquals("ゎ", kanaCharacterFormReplacement("わ"))
        assertEquals("わ", kanaCharacterFormReplacement("ゎ"))
        assertEquals("ヮ", kanaCharacterFormReplacement("ワ"))
        assertEquals("ワ", kanaCharacterFormReplacement("ヮ"))
        assertEquals("が", kanaCharacterFormReplacement("か"))
        assertEquals("か", kanaCharacterFormReplacement("が"))
    }
}
