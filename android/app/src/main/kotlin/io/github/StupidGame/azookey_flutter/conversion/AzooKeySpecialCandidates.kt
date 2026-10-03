package io.github.StupidGame.azookey_flutter.conversion

/** azooKey's special conversion forms, kept separate from predictive dictionary entries. */
internal object AzooKeySpecialCandidates {
    private val emailDomains = listOf(
        "@gmail.com", "@icloud.com", "@yahoo.co.jp", "@au.com",
        "@docomo.ne.jp", "@excite.co.jp", "@ezweb.ne.jp", "@googlemail.com",
        "@hotmail.co.jp", "@hotmail.com", "@i.softbank.jp", "@live.jp",
        "@me.com", "@mineo.jp", "@nifty.com", "@outlook.com", "@outlook.jp",
        "@softbank.ne.jp", "@yahoo.ne.jp", "@ybb.ne.jp", "@ymobile.ne.jp",
    )
    private val numeric = Regex("-?[0-9]+(\\.[0-9]+)?")
    private val westernYear = Regex("([0-9]{4})ねん")
    private val japaneseYear = Regex("(めいじ|たいしょう|しょうわ|へいせい|れいわ)(がん|[0-9]{1,2})ねん")
    private val emailLocal = Regex("[A-Za-z0-9._+\\-]*")

    fun emails(input: String): List<String> {
        val at = input.lastIndexOf('@')
        if (at < 0 || !emailLocal.matches(input.substring(0, at))) return emptyList()
        val id = input.substring(0, at)
        val prefix = input.substring(at).lowercase()
        return emailDomains.filter { it.startsWith(prefix) }.map { id + it }
    }

    fun canContinueEmail(current: String, input: String): Boolean {
        if (input == "@") return '@' !in current && emailLocal.matches(current)
        return '@' in current && input.isNotEmpty() &&
            input.all { it in 'a'..'z' || it in 'A'..'Z' || it in '0'..'9' || it == '.' || it == '-' }
    }

    fun complete(reading: String): List<String> = buildList {
        if (numeric.matches(reading)) {
            val negative = reading.startsWith('-')
            val parts = reading.removePrefix("-").split('.')
            if (parts[0].length > 3) {
                val grouped = parts[0].reversed().chunked(3).joinToString(",").reversed()
                add((if (negative) "-" else "") + grouped +
                    (if (parts.size == 2) ".${parts[1]}" else ""))
            }
            if (!negative && parts.size == 1 && reading.length in 3..4) {
                val hours = reading.dropLast(2).toInt()
                val minutes = reading.takeLast(2).toInt()
                if (hours <= 24 && minutes <= 59) {
                    add((if (reading.length == 4) hours.toString().padStart(2, '0') else "$hours") +
                        ":" + minutes.toString().padStart(2, '0'))
                }
            }
        }
        westernYear.matchEntire(reading)?.groupValues?.get(1)?.toInt()?.let { year ->
            val eras = listOf(
                Triple(2019, 2018, "令和"), Triple(1989, 1988, "平成"),
                Triple(1926, 1925, "昭和"), Triple(1912, 1911, "大正"),
                Triple(1868, 1867, "明治"),
            )
            for ((start, offset, name) in eras) {
                if (year >= start) {
                    add("$name${if (year == start) "元" else "${year - offset}"}年")
                    break
                }
            }
            when (year) {
                2019 -> add("平成31年")
                1989 -> add("昭和64年")
                1926 -> add("大正15年")
                1912 -> add("明治45年")
                1868 -> add("慶應4年")
            }
        }
        japaneseYear.matchEntire(reading)?.groupValues?.let { values ->
            val offset = when (values[1]) {
                "めいじ" -> 1867
                "たいしょう" -> 1911
                "しょうわ" -> 1925
                "へいせい" -> 1988
                else -> 2018
            }
            val year = if (values[2] == "がん") 1 else values[2].toInt()
            add("${offset + year}年")
        }
    }
}
