package io.github.StupidGame.azookey_flutter.input

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

class DefaultSymbolKeyboardTest {
    @Test
    fun tapValuesAreHalfWidth() {
        assertEquals(
            listOf(
                listOf("1", "2", "3", "4", "5", "6", "7", "8", "9", "0"),
                listOf("-", "/", ":", ";", "(", ")", "¥", "&", "@", "\""),
                listOf("｡", "､", "?", "!", "...", "･", "~", "#", "%"),
            ),
            defaultSymbolKeyboardRows.map { row -> row.map(DefaultSymbolKey::halfWidth) },
        )
    }

    @Test
    fun upwardFlickValuesAreFullWidth() {
        assertEquals(
            listOf(
                listOf("１", "２", "３", "４", "５", "６", "７", "８", "９", "０"),
                listOf("－", "／", "：", "；", "（", "）", "￥", "＆", "＠", "＂"),
                listOf("。", "、", "？", "！", "…", "・", "〜", "＃", "％"),
            ),
            defaultSymbolKeyboardRows.map { row -> row.map(DefaultSymbolKey::fullWidth) },
        )
        defaultSymbolKeyboardRows.flatten().forEach { value ->
            assertNotEquals(value.halfWidth, value.fullWidth)
        }
    }
}
