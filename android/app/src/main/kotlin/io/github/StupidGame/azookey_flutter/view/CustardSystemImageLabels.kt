package io.github.StupidGame.azookey_flutter.view

import java.util.Locale

/** Converts azooKey Custard system-image names into compact Android key labels. */
internal fun custardSystemImageLabel(name: String): String {
    val trimmedName = name.trim()
    return when (trimmedName.lowercase(Locale.ROOT)) {
        "delete.left", "delete.left.fill" -> "⌫"
        "delete.right", "delete.right.fill" -> "⌦"
        "xmark" -> "×"
        "globe", "globe.europe.africa" -> "🌐"
        "return", "return.left" -> "↵"
        "space" -> "空白"
        "list.bullet" -> "☰"
        "arrow.left", "chevron.left", "chevron.left.2" -> "←"
        "arrow.up" -> "↑"
        "arrow.right", "chevron.right", "chevron.right.2" -> "→"
        "arrow.down" -> "↓"
        "arrowtriangle.left.and.line.vertical.and.arrowtriangle.right" -> "↔"
        "keyboard.chevron.compact.down.fill" -> "⌄"
        "textformat.123" -> "123"
        "textformat.superscript" -> "x²"
        "face.smiling" -> "🙂"
        "doc.on.clipboard", "list.bullet.clipboard" -> "📋"
        "shift", "shift.fill" -> "⇧"
        else -> trimmedName
    }
}
