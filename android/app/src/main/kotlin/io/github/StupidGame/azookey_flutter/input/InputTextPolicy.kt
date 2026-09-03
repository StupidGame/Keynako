package io.github.StupidGame.azookey_flutter.input

internal fun punctuationForInputMode(value: String, mode: String): String = when (mode) {
    "japanese" -> value.replace("?", "？").replace("!", "！")
    "english" -> value.replace("？", "?").replace("！", "!")
    else -> value
}
