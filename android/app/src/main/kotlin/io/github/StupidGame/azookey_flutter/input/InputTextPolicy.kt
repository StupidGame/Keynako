package io.github.StupidGame.azookey_flutter.input

internal fun punctuationForInputMode(value: String, mode: String): String = when (mode) {
    "japanese" -> value.replace("?", "？").replace("!", "！")
    "english" -> value.replace("？", "?").replace("！", "!")
    else -> value
}

/** Returns the closing delimiter inserted beside a standalone opening delimiter. */
internal fun closingDelimiterFor(value: String): String? = when (value) {
    "「" -> "」"
    "『" -> "』"
    "(" -> ")"
    "（" -> "）"
    "[" -> "]"
    "［" -> "］"
    "{" -> "}"
    "｛" -> "｝"
    "【" -> "】"
    "〈" -> "〉"
    "《" -> "》"
    else -> null
}
