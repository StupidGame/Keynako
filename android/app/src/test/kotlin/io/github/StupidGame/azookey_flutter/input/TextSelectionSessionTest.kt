package io.github.StupidGame.azookey_flutter.input

import android.view.inputmethod.ExtractedText
import android.view.inputmethod.InputConnection
import java.lang.reflect.Proxy
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TextSelectionSessionTest {
    @Test
    fun replacesAnExistingSelectionBeforeInput() {
        val commits = mutableListOf<Pair<String, Int>>()
        val extracted = ExtractedText().apply {
            text = "selected text"
            selectionStart = 2
            selectionEnd = 10
        }
        val connection = inputConnection(extracted, commits = commits)

        assertTrue(replaceCurrentSelection(connection))
        assertEquals(listOf("" to 1), commits)

        extracted.selectionEnd = extracted.selectionStart
        assertFalse(replaceCurrentSelection(connection))
        assertEquals(1, commits.size)
    }

    @Test
    fun movesAndSelectsInBothDirectionsWithoutSplittingSurrogatePairs() {
        val selections = mutableListOf<Pair<Int, Int>>()
        val commits = mutableListOf<Pair<String, Int>>()
        val extracted = ExtractedText().apply {
            text = "A😀BC"
            startOffset = 10
            selectionStart = 3
            selectionEnd = 3
        }
        val connection = inputConnection(extracted, selections, commits)

        val session = requireNotNull(TextSelectionSession.capture(connection))

        assertTrue(session.moveCursor(-1))
        assertEquals(11 to 11, selections.last())
        assertTrue(session.moveCursor(1))
        assertEquals(14 to 14, selections.last())
        assertTrue(session.select(-2))
        assertEquals(13 to 10, selections.last())
        assertTrue(session.select(2))
        assertEquals(13 to 15, selections.last())
        assertTrue(session.deleteSelection())
        assertEquals("" to 1, commits.single())
    }

    private fun inputConnection(
        extracted: ExtractedText,
        selections: MutableList<Pair<Int, Int>> = mutableListOf(),
        commits: MutableList<Pair<String, Int>> = mutableListOf(),
    ): InputConnection = Proxy.newProxyInstance(
            InputConnection::class.java.classLoader,
            arrayOf(InputConnection::class.java),
        ) { _, method, arguments ->
            when (method.name) {
                "getExtractedText" -> extracted
                "setSelection" -> {
                    selections += (arguments[0] as Int) to (arguments[1] as Int)
                    true
                }
                "commitText" -> {
                    commits += arguments[0].toString() to (arguments[1] as Int)
                    true
                }
                else -> when (method.returnType) {
                    Boolean::class.javaPrimitiveType -> false
                    Int::class.javaPrimitiveType -> 0
                    else -> null
                }
            }
        } as InputConnection
}
