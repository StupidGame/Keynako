package io.github.StupidGame.azookey_flutter.conversion

/** Returns dictionary values whose reading extends the text currently being composed. */
internal fun prefixPredictionValues(
    reading: String,
    entries: Iterable<Pair<String, List<String>>>,
    limit: Int,
): List<String> {
    if (reading.isEmpty() || limit <= 0) return emptyList()
    return entries.asSequence()
        .filter { (ruby, _) -> ruby.length > reading.length && ruby.startsWith(reading) }
        .flatMap { (_, values) -> values.asSequence() }
        .filter(String::isNotBlank)
        .distinct()
        .take(limit)
        .toList()
}

/** Keeps live conversion first while moving prefix predictions into the visible candidates. */
internal fun prioritizePrefixPredictions(
    conversions: List<String>,
    predictions: List<String>,
    insertIndex: Int = 2,
): List<String> {
    val insertion = insertIndex.coerceIn(0, conversions.size)
    return buildList {
        addAll(conversions.take(insertion))
        addAll(predictions)
        addAll(conversions.drop(insertion))
    }.distinct()
}
