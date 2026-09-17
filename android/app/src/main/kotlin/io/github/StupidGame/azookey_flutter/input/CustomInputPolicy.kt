package io.github.StupidGame.azookey_flutter.input

import java.util.Locale

internal data class CustomLayoutSelection(
    val mode: String,
    val layout: String,
)

/** Resolves the composing mode used by a Keynako tab or imported Custard. */
internal fun customLayoutSelection(
    language: String,
    inputStyle: String,
    currentMode: String,
    currentLayout: String,
): CustomLayoutSelection = when (language) {
    "en_US" -> CustomLayoutSelection(mode = "english", layout = "qwerty")
    "ja_JP" -> CustomLayoutSelection(
        mode = "japanese",
        layout = if (inputStyle == "roman2kana") "qwerty" else "flick",
    )
    else -> CustomLayoutSelection(mode = currentMode, layout = currentLayout)
}

/**
 * Mirrors azooKey's compound-label Shift behavior: only a one-character label
 * backed by exactly one matching input action is uppercased.
 */
internal fun shiftedInputLabel(
    label: String,
    actionType: String,
    inputValue: String?,
    actionCount: Int,
    uppercaseEnabled: Boolean,
): String {
    if (
        !uppercaseEnabled ||
        label.codePointCount(0, label.length) != 1 ||
        actionCount != 1 ||
        actionType != "input" ||
        label != inputValue
    ) return label
    return label.uppercase(Locale.ROOT)
}
