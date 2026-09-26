/// A learned reading/value pair, using the existing persisted score map.
class LearnedCandidate {
  const LearnedCandidate(this.reading, this.text, this.score);

  final String reading;
  final String text;
  final int score;
}

/// Bounded learning that can adapt when a user corrects an established choice.
class CandidateLearning {
  static const maxScore = 32;
  static final _legacyEnglishReading = RegExp(r"^[a-zA-Z']+$");

  static String normalizeReading(String reading, {bool english = false}) =>
      english
      ? reading.toLowerCase()
      : String.fromCharCodes(
          reading.runes.map(
            (code) => code >= 0x30a1 && code <= 0x30f6 ? code - 0x60 : code,
          ),
        );

  static Iterable<LearnedCandidate> entries(
    Map<String, int> learning, {
    bool english = false,
  }) sync* {
    for (final entry in learning.entries) {
      final decoded = _decode(entry.key, entry.value, english);
      if (decoded != null) yield decoded;
    }
  }

  static LearnedCandidate? _decode(String key, int count, bool english) {
    final separator = key.indexOf('\t');
    if (separator <= 0 || count <= 0) return null;
    var ruby = key.substring(0, separator);
    final text = key.substring(separator + 1);
    if (text.trim().isEmpty) return null;
    if (ruby.startsWith('english:')) {
      if (!english) return null;
      ruby = ruby.substring('english:'.length);
    } else if (english && !_legacyEnglishReading.hasMatch(ruby)) {
      // Older mobile versions stored English readings without a namespace.
      return null;
    }
    if (ruby.isEmpty) return null;
    return LearnedCandidate(
      normalizeReading(ruby, english: english),
      text,
      count.clamp(1, maxScore),
    );
  }

  static Map<String, int> exactScores(
    Map<String, int> learning,
    String reading, {
    bool english = false,
  }) {
    final normalized = normalizeReading(reading, english: english);
    final result = <String, int>{};
    for (final entry in entries(learning, english: english)) {
      if (entry.reading != normalized) continue;
      final text = english ? entry.text.toLowerCase() : entry.text;
      if (entry.score > (result[text] ?? 0)) result[text] = entry.score;
    }
    return result;
  }

  static void record(
    Map<String, int> learning, {
    required String reading,
    required String text,
    bool english = false,
    bool explicitSelection = false,
  }) {
    if (reading.trim().isEmpty ||
        reading.contains('\t') ||
        text.trim().isEmpty) {
      return;
    }
    final normalized = normalizeReading(reading, english: english);
    final scores = <String, int>{};
    final oldKeys = <String>[];
    for (final entry in learning.entries) {
      final match = _decode(entry.key, entry.value, english);
      if (match == null || match.reading != normalized) continue;
      final word = match.text;
      oldKeys.add(entry.key);
      if (match.score > (scores[word] ?? 0)) {
        scores[word] = match.score;
      }
    }
    if (english) {
      for (final word in scores.keys.toList()) {
        if (word != text && word.toLowerCase() == text.toLowerCase()) {
          final score = scores.remove(word)!;
          if (score > (scores[text] ?? 0)) scores[text] = score;
        }
      }
    }
    if (explicitSelection) {
      // Repeated automatic acceptance must not make a correction ineffective.
      for (final word in scores.keys.toList()) {
        if (word != text) scores[word] = scores[word]! ~/ 2;
      }
      final highest = scores.values.fold(0, (a, b) => a > b ? a : b);
      scores[text] = (highest + 4).clamp(1, maxScore);
    } else {
      scores[text] = ((scores[text] ?? 0) + 1).clamp(1, maxScore);
    }
    for (final key in oldKeys) {
      learning.remove(key);
    }
    final prefix = english ? 'english:$normalized' : normalized;
    for (final entry in scores.entries) {
      if (entry.value > 0) learning['$prefix\t${entry.key}'] = entry.value;
    }
  }
}
