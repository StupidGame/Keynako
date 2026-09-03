package io.github.StupidGame.azookey_flutter.input

import android.view.inputmethod.ExtractedTextRequest
import android.view.inputmethod.InputConnection

/** Replaces a non-collapsed editor selection before a new composition starts. */
internal fun replaceCurrentSelection(connection: InputConnection?): Boolean {
    connection ?: return false
    val extracted = connection.getExtractedText(ExtractedTextRequest(), 0) ?: return false
    val start = extracted.selectionStart
    val end = extracted.selectionEnd
    if (start < 0 || end < 0 || start == end) return false
    return connection.commitText("", 1)
}

/** Captures an editor selection and applies horizontal key-drag operations. */
internal class TextSelectionSession private constructor(
    private val connection: InputConnection,
    private val positions: List<Int>,
    private val anchorIndex: Int,
) {
    private var currentIndex = anchorIndex

    val hasSelection: Boolean
        get() = currentIndex != anchorIndex

    fun moveCursor(offset: Int): Boolean {
        val targetIndex = (anchorIndex + offset).coerceIn(positions.indices)
        if (targetIndex == currentIndex) return false
        currentIndex = targetIndex
        return connection.setSelection(positions[targetIndex], positions[targetIndex])
    }

    fun select(offset: Int): Boolean {
        val targetIndex = (anchorIndex + offset).coerceIn(positions.indices)
        if (targetIndex == currentIndex) return false
        currentIndex = targetIndex
        return connection.setSelection(positions[anchorIndex], positions[targetIndex])
    }

    fun deleteSelection(): Boolean {
        if (!hasSelection) return false
        return connection.commitText("", 1)
    }

    fun cancel() {
        connection.setSelection(positions[anchorIndex], positions[anchorIndex])
    }

    companion object {
        fun capture(connection: InputConnection?): TextSelectionSession? {
            connection ?: return null
            val extracted = connection.getExtractedText(ExtractedTextRequest(), 0) ?: return null
            val text = extracted.text?.toString() ?: return null
            val positions = buildList {
                add(extracted.startOffset)
                var index = 0
                while (index < text.length) {
                    index += Character.charCount(Character.codePointAt(text, index))
                    add(extracted.startOffset + index)
                }
            }
            val absoluteCursor = extracted.startOffset + extracted.selectionEnd
            val anchorIndex = positions.indexOf(absoluteCursor).takeIf { it >= 0 }
                ?: positions.indices.minByOrNull { kotlin.math.abs(positions[it] - absoluteCursor) }
                ?: return null
            return TextSelectionSession(connection, positions, anchorIndex)
        }
    }
}
