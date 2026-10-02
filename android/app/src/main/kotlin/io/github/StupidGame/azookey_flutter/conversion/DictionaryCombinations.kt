package io.github.StupidGame.azookey_flutter.conversion

internal data class DictionaryCombinationEntry(
    val reading: String,
    val value: String,
    val importance: Int = 3,
)

/** Compose complete candidates from registered words, preserving intervening kana. */
internal fun dictionaryCombinationCandidates(
    reading: String,
    entries: List<DictionaryCombinationEntry>,
    limit: Int = 8,
): List<String> {
    if (reading.length < 2 || entries.isEmpty() || limit <= 0) return emptyList()
    data class Match(val end: Int, val value: String, val score: Int)
    data class Path(val text: String, val score: Int, val words: Int)

    val matches = List(reading.length) { mutableListOf<Match>() }
    for (entry in entries) {
        val ruby = katakanaToHiragana(entry.reading)
        if (ruby.isEmpty() || entry.value.isEmpty() || ruby.length > reading.length) continue
        var start = reading.indexOf(ruby)
        while (start >= 0) {
            matches[start].add(Match(
                start + ruby.length,
                entry.value,
                ruby.length * 18 - 28 + entry.importance.coerceIn(1, 5) * 4,
            ))
            start = reading.indexOf(ruby, start + 1)
        }
    }
    if (matches.count { it.isNotEmpty() } < 2) return emptyList()

    val beams = List(reading.length + 1) { mutableListOf<Path>() }
    beams[0].add(Path("", 0, 0))
    fun push(end: Int, path: Path) {
        val paths = beams[end]
        paths.add(path)
        if (paths.size > 48) {
            paths.sortByDescending { it.score }
            paths.subList(16, paths.size).clear()
        }
    }
    for (index in reading.indices) {
        for (path in beams[index].sortedByDescending { it.score }.take(16)) {
            push(index + 1, Path(path.text + reading[index], path.score - 3, path.words))
            for (match in matches[index]) {
                push(match.end, Path(
                    path.text + match.value,
                    path.score + match.score,
                    path.words + 1,
                ))
            }
        }
    }
    return beams.last().asSequence()
        .filter { it.words >= 2 && it.text != reading }
        .sortedByDescending { it.score }
        .map { it.text }
        .distinct()
        .take(limit)
        .toList()
}
