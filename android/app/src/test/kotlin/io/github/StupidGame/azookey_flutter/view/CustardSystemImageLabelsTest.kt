package io.github.StupidGame.azookey_flutter.view

import org.junit.Assert.assertEquals
import org.junit.Test

class CustardSystemImageLabelsTest {
    @Test
    fun rendersDirectionalImagesAsArrows() {
        assertEquals("←", custardSystemImageLabel("arrow.left"))
        assertEquals("↑", custardSystemImageLabel("arrow.up"))
        assertEquals("→", custardSystemImageLabel("arrow.right"))
        assertEquals("↓", custardSystemImageLabel("arrow.down"))
    }

    @Test
    fun ignoresCaseAndSurroundingWhitespace() {
        assertEquals("↑", custardSystemImageLabel(" arrow.Up "))
    }

    @Test
    fun rendersEveryAdditionalSystemImageUsedBy123Jp() {
        val expected = mapOf(
            "delete.left" to "⌫",
            "delete.left.fill" to "⌫",
            "delete.right" to "⌦",
            "delete.right.fill" to "⌦",
            "globe.asia.australia" to "🌐",
            "capslock.fill" to "⇪",
            "globe.europe.africa" to "🌐",
            "chevron.left" to "←",
            "chevron.left.2" to "←",
            "chevron.right" to "→",
            "chevron.right.2" to "→",
            "keyboard.chevron.compact.down.fill" to "⌄",
            "textformat.123" to "123",
            "textformat.superscript" to "x²",
            "face.smiling" to "🙂",
            "doc.on.clipboard" to "📋",
            "list.bullet.clipboard" to "📋",
            "space" to "空白",
        )

        expected.forEach { (name, label) ->
            assertEquals(name, label, custardSystemImageLabel(name))
        }
    }

    @Test
    fun preservesUnknownNamesWithoutOuterWhitespace() {
        assertEquals("custom.image", custardSystemImageLabel(" custom.image "))
    }
}
