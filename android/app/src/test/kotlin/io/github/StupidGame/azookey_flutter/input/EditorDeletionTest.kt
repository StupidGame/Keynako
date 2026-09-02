package io.github.StupidGame.azookey_flutter.input

import android.view.KeyEvent
import android.view.inputmethod.InputConnection
import java.lang.reflect.Proxy
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class EditorDeletionTest {
    @Test
    fun ordinaryEditorsUseSurroundingTextDeletion() {
        val deletions = mutableListOf<Pair<Int, Int>>()
        val events = mutableListOf<KeyEvent>()
        val connection = inputConnection(true, deletions, events)

        assertTrue(deleteEditorText(connection, 2, 1))
        assertEquals(listOf(2 to 1), deletions)
        assertTrue(events.isEmpty())
    }

    @Test
    fun rejectedSurroundingDeletionFallsBackToKeyEvents() {
        val deletions = mutableListOf<Pair<Int, Int>>()
        val events = mutableListOf<KeyEvent>()
        val connection = inputConnection(false, deletions, events)

        assertTrue(deleteEditorText(connection, 1, 1))
        assertEquals(listOf(1 to 1), deletions)
        assertEquals(4, events.size)
        assertEquals(
            listOf(KeyEvent.KEYCODE_DEL, KeyEvent.KEYCODE_FORWARD_DEL),
            deleteKeyCodes(1, 1),
        )
    }

    @Test
    fun rawInputEditorsReceiveDeleteKeyEventsFirst() {
        val deletions = mutableListOf<Pair<Int, Int>>()
        val events = mutableListOf<KeyEvent>()
        val connection = inputConnection(true, deletions, events)

        assertTrue(deleteEditorText(connection, 1, 0, preferKeyEvents = true))
        assertTrue(deletions.isEmpty())
        assertEquals(2, events.size)
    }

    private fun inputConnection(
        surroundingDeleteResult: Boolean,
        deletions: MutableList<Pair<Int, Int>>,
        events: MutableList<KeyEvent>,
    ): InputConnection = Proxy.newProxyInstance(
        InputConnection::class.java.classLoader,
        arrayOf(InputConnection::class.java),
    ) { _, method, arguments ->
        when (method.name) {
            "deleteSurroundingText" -> {
                deletions += (arguments[0] as Int) to (arguments[1] as Int)
                surroundingDeleteResult
            }
            "sendKeyEvent" -> {
                events += arguments[0] as KeyEvent
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
