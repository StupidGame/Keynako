package io.github.StupidGame.azookey_flutter.input

import android.view.KeyEvent
import android.view.inputmethod.InputConnection

/**
 * Deletes editor text through the API best suited to the current input target.
 * Raw-input targets such as terminals expect key events, while ordinary text
 * editors normally implement deleteSurroundingText. A rejected ordinary edit
 * falls back to key events for custom and partially implemented connections.
 */
internal fun deleteEditorText(
    connection: InputConnection?,
    beforeCursor: Int,
    afterCursor: Int,
    preferKeyEvents: Boolean = false,
): Boolean {
    connection ?: return false
    val before = beforeCursor.coerceAtLeast(0)
    val after = afterCursor.coerceAtLeast(0)
    if (replaceCurrentSelection(connection)) return true
    if (before == 0 && after == 0) return true

    if (preferKeyEvents && sendDeleteKeyEvents(connection, before, after)) {
        return true
    }
    val deleted = runCatching {
        connection.deleteSurroundingText(before, after)
    }.getOrDefault(false)
    if (deleted) return true
    return !preferKeyEvents && sendDeleteKeyEvents(connection, before, after)
}

private fun sendDeleteKeyEvents(
    connection: InputConnection,
    beforeCursor: Int,
    afterCursor: Int,
): Boolean {
    // InputConnection counts UTF-16 units, while a DEL key event removes a
    // character. Count code points only when the key-event path is needed.
    val beforeText = if (beforeCursor > 0) {
        runCatching { connection.getTextBeforeCursor(beforeCursor, 0)?.toString() }.getOrNull()
    } else null
    val afterText = if (afterCursor > 0) {
        runCatching { connection.getTextAfterCursor(afterCursor, 0)?.toString() }.getOrNull()
    } else null
    val beforeEvents = beforeText?.takeIf { it.length == beforeCursor }
        ?.let { it.codePointCount(0, it.length) } ?: beforeCursor
    val afterEvents = afterText?.takeIf { it.length == afterCursor }
        ?.let { it.codePointCount(0, it.length) } ?: afterCursor
    var accepted = false
    for (keyCode in deleteKeyCodes(beforeEvents, afterEvents)) {
        val down = connection.sendKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, keyCode))
        val up = connection.sendKeyEvent(KeyEvent(KeyEvent.ACTION_UP, keyCode))
        accepted = accepted || down || up
    }
    return accepted
}

internal fun deleteKeyCodes(beforeCursor: Int, afterCursor: Int): List<Int> =
    buildList {
        repeat(beforeCursor.coerceAtLeast(0)) { add(KeyEvent.KEYCODE_DEL) }
        repeat(afterCursor.coerceAtLeast(0)) { add(KeyEvent.KEYCODE_FORWARD_DEL) }
    }
