package io.github.StupidGame.azookey_flutter.conversion

import java.text.Normalizer

internal fun katakanaToHalfWidth(value: String): String = buildString {
    val decomposed = Normalizer.normalize(value, Normalizer.Form.NFD)
    for (character in decomposed) append(halfWidthKanaMap[character] ?: character.toString())
}

internal fun asciiToFullWidth(value: String): String = buildString {
    for (character in value) {
        append(
            when (character) {
                ' ' -> '　'
                in '!'..'~' -> (character.code + 0xfee0).toChar()
                else -> character
            },
        )
    }
}

internal fun unicodeCandidate(value: String): String? {
    val hex = Regex("(?i)^u\\+?([0-9a-f]{1,6})$").matchEntire(value)?.groupValues?.get(1) ?: return null
    val codePoint = hex.toIntOrNull(16) ?: return null
    if (!Character.isValidCodePoint(codePoint) || codePoint in 0xd800..0xdfff) return null
    return String(Character.toChars(codePoint))
}

/** Symbols and spacing controls are committed verbatim instead of sent to conversion. */
internal fun shouldDirectCommitJapaneseInput(value: String): Boolean {
    if (value.isEmpty()) return false
    var index = 0
    while (index < value.length) {
        val codePoint = Character.codePointAt(value, index)
        if (Character.getType(codePoint) !in nonConvertibleCharacterTypes) return false
        index += Character.charCount(codePoint)
    }
    return true
}

internal fun toMathematicalBold(value: String): String = buildString {
    for (character in value) {
        val codePoint = when (character) {
            in 'A'..'Z' -> 0x1d400 + (character - 'A')
            in 'a'..'z' -> 0x1d41a + (character - 'a')
            in '0'..'9' -> 0x1d7ce + (character - '0')
            else -> character.code
        }
        append(String(Character.toChars(codePoint)))
    }
}

internal fun romanToHiragana(input: String): String {
    val result = StringBuilder()
    var index = 0
    val lower = input.lowercase()
    while (index < lower.length) {
        val current = lower[index]
        if (index + 1 < lower.length && current == lower[index + 1] && current in "bcdfghjklmpqrstvwxyz" && current != 'n') {
            result.append('っ')
            index += 1
            continue
        }
        if (current == 'n' && index + 1 < lower.length && lower[index + 1] !in "aiueoyn") {
            result.append('ん')
            index += 1
            continue
        }
        var found: String? = null
        var consumed = 0
        for (length in listOf(4, 3, 2, 1)) {
            if (index + length > lower.length) continue
            val replacement = romanMap[lower.substring(index, index + length)] ?: continue
            found = replacement
            consumed = length
            break
        }
        if (found == null) {
            result.append(lower[index])
            index += 1
        } else {
            result.append(found)
            index += consumed
        }
    }
    if (result.endsWith("n")) result.replace(result.length - 1, result.length, "ん")
    return result.toString()
}

internal fun hiraganaToKatakana(value: String): String = buildString {
    for (character in value) {
        append(if (character.code in 0x3041..0x3096) (character.code + 0x60).toChar() else character)
    }
}

internal fun katakanaToHiragana(value: String): String = buildString {
    for (character in value) {
        append(if (character.code in 0x30a1..0x30f6) (character.code - 0x60).toChar() else character)
    }
}

internal val defaultScanTargets = listOf("、", "。", "！", "？", ".", ",", "．", "，", "\n")

private val halfWidthKanaMap: Map<Char, String> = run {
    val full = "。「」、・ヲァィゥェォャュョッーアイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワヰヱヲン゙゚"
    val half = "｡｢｣､･ｦｧｨｩｪｫｬｭｮｯｰｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓﾔﾕﾖﾗﾘﾙﾚﾛﾜｲｴｦﾝﾞﾟ"
    full.zip(half).associate { (source, target) -> source to target.toString() } + mapOf(
        'ヮ' to "ﾜ",
        'ヵ' to "ｶ",
        'ヶ' to "ｹ",
    )
}

private val nonConvertibleCharacterTypes = setOf(
    Character.CONNECTOR_PUNCTUATION.toInt(),
    Character.DASH_PUNCTUATION.toInt(),
    Character.START_PUNCTUATION.toInt(),
    Character.END_PUNCTUATION.toInt(),
    Character.INITIAL_QUOTE_PUNCTUATION.toInt(),
    Character.FINAL_QUOTE_PUNCTUATION.toInt(),
    Character.OTHER_PUNCTUATION.toInt(),
    Character.MATH_SYMBOL.toInt(),
    Character.CURRENCY_SYMBOL.toInt(),
    Character.MODIFIER_SYMBOL.toInt(),
    Character.OTHER_SYMBOL.toInt(),
    Character.SPACE_SEPARATOR.toInt(),
    Character.LINE_SEPARATOR.toInt(),
    Character.PARAGRAPH_SEPARATOR.toInt(),
    Character.CONTROL.toInt(),
    Character.FORMAT.toInt(),
)

private val romanMap = mapOf(
    "kya" to "きゃ", "kyu" to "きゅ", "kyo" to "きょ", "gya" to "ぎゃ", "gyu" to "ぎゅ", "gyo" to "ぎょ",
    "sha" to "しゃ", "shu" to "しゅ", "sho" to "しょ", "sya" to "しゃ", "syu" to "しゅ", "syo" to "しょ",
    "jya" to "じゃ", "jyu" to "じゅ", "jyo" to "じょ", "cha" to "ちゃ", "chu" to "ちゅ", "cho" to "ちょ",
    "nya" to "にゃ", "nyu" to "にゅ", "nyo" to "にょ", "hya" to "ひゃ", "hyu" to "ひゅ", "hyo" to "ひょ",
    "mya" to "みゃ", "myu" to "みゅ", "myo" to "みょ", "rya" to "りゃ", "ryu" to "りゅ", "ryo" to "りょ",
    "fa" to "ふぁ", "fi" to "ふぃ", "fe" to "ふぇ", "fo" to "ふぉ", "she" to "しぇ", "che" to "ちぇ", "je" to "じぇ",
    "ka" to "か", "ki" to "き", "ku" to "く", "ke" to "け", "ko" to "こ", "ga" to "が", "gi" to "ぎ", "gu" to "ぐ", "ge" to "げ", "go" to "ご",
    "sa" to "さ", "si" to "し", "shi" to "し", "su" to "す", "se" to "せ", "so" to "そ", "za" to "ざ", "zi" to "じ", "ji" to "じ", "zu" to "ず", "ze" to "ぜ", "zo" to "ぞ",
    "ta" to "た", "ti" to "ち", "chi" to "ち", "tu" to "つ", "tsu" to "つ", "te" to "て", "to" to "と", "da" to "だ", "di" to "ぢ", "du" to "づ", "de" to "で", "do" to "ど",
    "na" to "な", "ni" to "に", "nu" to "ぬ", "ne" to "ね", "no" to "の", "ha" to "は", "hi" to "ひ", "hu" to "ふ", "fu" to "ふ", "he" to "へ", "ho" to "ほ",
    "ba" to "ば", "bi" to "び", "bu" to "ぶ", "be" to "べ", "bo" to "ぼ", "pa" to "ぱ", "pi" to "ぴ", "pu" to "ぷ", "pe" to "ぺ", "po" to "ぽ",
    "ma" to "ま", "mi" to "み", "mu" to "む", "me" to "め", "mo" to "も", "ya" to "や", "yu" to "ゆ", "yo" to "よ",
    "ra" to "ら", "ri" to "り", "ru" to "る", "re" to "れ", "ro" to "ろ", "wa" to "わ", "wo" to "を", "nn" to "ん",
    "la" to "ぁ", "li" to "ぃ", "lu" to "ぅ", "le" to "ぇ", "lo" to "ぉ", "ltu" to "っ", "xtu" to "っ",
    "a" to "あ", "i" to "い", "u" to "う", "e" to "え", "o" to "お", "-" to "ー", "," to "、", "." to "。",
)
