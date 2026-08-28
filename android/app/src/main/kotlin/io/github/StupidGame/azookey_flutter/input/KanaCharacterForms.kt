package io.github.StupidGame.azookey_flutter.input

private val kanaCharacterFormReplacements = mapOf(
    "あ" to "ぁ", "ぁ" to "あ", "い" to "ぃ", "ぃ" to "い",
    "う" to "ぅ", "ぅ" to "ゔ", "ゔ" to "う", "え" to "ぇ", "ぇ" to "え",
    "お" to "ぉ", "ぉ" to "お", "つ" to "っ", "っ" to "づ", "づ" to "つ",
    "や" to "ゃ", "ゃ" to "や", "ゆ" to "ゅ", "ゅ" to "ゆ", "よ" to "ょ", "ょ" to "よ",
    "わ" to "ゎ", "ゎ" to "わ",
    "か" to "が", "が" to "か", "き" to "ぎ", "ぎ" to "き", "く" to "ぐ", "ぐ" to "く",
    "け" to "げ", "げ" to "け", "こ" to "ご", "ご" to "こ",
    "さ" to "ざ", "ざ" to "さ", "し" to "じ", "じ" to "し", "す" to "ず", "ず" to "す",
    "せ" to "ぜ", "ぜ" to "せ", "そ" to "ぞ", "ぞ" to "そ",
    "た" to "だ", "だ" to "た", "ち" to "ぢ", "ぢ" to "ち", "て" to "で", "で" to "て",
    "と" to "ど", "ど" to "と",
    "は" to "ば", "ば" to "ぱ", "ぱ" to "は",
    "ひ" to "び", "び" to "ぴ", "ぴ" to "ひ",
    "ふ" to "ぶ", "ぶ" to "ぷ", "ぷ" to "ふ",
    "へ" to "べ", "べ" to "ぺ", "ぺ" to "へ",
    "ほ" to "ぼ", "ぼ" to "ぽ", "ぽ" to "ほ",
    "ア" to "ァ", "ァ" to "ア", "イ" to "ィ", "ィ" to "イ",
    "ウ" to "ゥ", "ゥ" to "ヴ", "ヴ" to "ウ", "エ" to "ェ", "ェ" to "エ",
    "オ" to "ォ", "ォ" to "オ", "ツ" to "ッ", "ッ" to "ヅ", "ヅ" to "ツ",
    "ヤ" to "ャ", "ャ" to "ヤ", "ユ" to "ュ", "ュ" to "ユ", "ヨ" to "ョ", "ョ" to "ヨ",
    "ワ" to "ヮ", "ヮ" to "ワ",
    "カ" to "ガ", "ガ" to "カ", "キ" to "ギ", "ギ" to "キ", "ク" to "グ", "グ" to "ク",
    "ケ" to "ゲ", "ゲ" to "ケ", "コ" to "ゴ", "ゴ" to "コ",
    "サ" to "ザ", "ザ" to "サ", "シ" to "ジ", "ジ" to "シ", "ス" to "ズ", "ズ" to "ス",
    "セ" to "ゼ", "ゼ" to "セ", "ソ" to "ゾ", "ゾ" to "ソ",
    "タ" to "ダ", "ダ" to "タ", "チ" to "ヂ", "ヂ" to "チ", "テ" to "デ", "デ" to "テ",
    "ト" to "ド", "ド" to "ト",
    "ハ" to "バ", "バ" to "パ", "パ" to "ハ",
    "ヒ" to "ビ", "ビ" to "ピ", "ピ" to "ヒ",
    "フ" to "ブ", "ブ" to "プ", "プ" to "フ",
    "ヘ" to "ベ", "ベ" to "ペ", "ペ" to "ヘ",
    "ホ" to "ボ", "ボ" to "ポ", "ポ" to "ホ",
)

/** Returns the next small, plain, voiced, or semi-voiced form for any kana layout. */
internal fun kanaCharacterFormReplacement(character: String): String? =
    kanaCharacterFormReplacements[character]

internal fun sharesKanaCharacterFormCycle(first: String, second: String): Boolean {
    val visited = mutableSetOf<String>()
    var current = first
    while (visited.add(current)) {
        current = kanaCharacterFormReplacement(current) ?: return false
        if (current == second) return true
    }
    return false
}
