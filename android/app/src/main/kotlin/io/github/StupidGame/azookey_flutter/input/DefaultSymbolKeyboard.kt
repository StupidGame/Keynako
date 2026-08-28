package io.github.StupidGame.azookey_flutter.input

internal data class DefaultSymbolKey(
    val halfWidth: String,
    val fullWidth: String,
)

/** Tap values stay half-width; an upward flick selects the paired full-width value. */
internal val defaultSymbolKeyboardRows = listOf(
    listOf(
        DefaultSymbolKey("1", "１"),
        DefaultSymbolKey("2", "２"),
        DefaultSymbolKey("3", "３"),
        DefaultSymbolKey("4", "４"),
        DefaultSymbolKey("5", "５"),
        DefaultSymbolKey("6", "６"),
        DefaultSymbolKey("7", "７"),
        DefaultSymbolKey("8", "８"),
        DefaultSymbolKey("9", "９"),
        DefaultSymbolKey("0", "０"),
    ),
    listOf(
        DefaultSymbolKey("-", "－"),
        DefaultSymbolKey("/", "／"),
        DefaultSymbolKey(":", "："),
        DefaultSymbolKey(";", "；"),
        DefaultSymbolKey("(", "（"),
        DefaultSymbolKey(")", "）"),
        DefaultSymbolKey("¥", "￥"),
        DefaultSymbolKey("&", "＆"),
        DefaultSymbolKey("@", "＠"),
        DefaultSymbolKey("\"", "＂"),
    ),
    listOf(
        DefaultSymbolKey("｡", "。"),
        DefaultSymbolKey("､", "、"),
        DefaultSymbolKey("?", "？"),
        DefaultSymbolKey("!", "！"),
        DefaultSymbolKey("...", "…"),
        DefaultSymbolKey("･", "・"),
        DefaultSymbolKey("~", "〜"),
        DefaultSymbolKey("#", "＃"),
        DefaultSymbolKey("%", "％"),
    ),
)
