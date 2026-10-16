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
    if (ruby.startsWith('context:')) return null;
    final text = key.substring(separator + 1);
    if (text.trim().isEmpty) return null;
    if (ruby.startsWith('english:')) {
      if (!english) return null;
      ruby = ruby.substring('english:'.length);
    } else {
      final legacyEnglish = _legacyEnglishReading.hasMatch(ruby);
      // Older mobile versions stored English readings without a namespace.
      if (english != legacyEnglish) return null;
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

  static List<String> _contextPrefixes(String leftContext, String reading) {
    final preceding = leftContext.trimRight().runes.toList();
    if (preceding.isEmpty || reading.trim().isEmpty) return const [];
    final prefixes = <String>{};
    for (final length in [8, 4]) {
      final suffix = String.fromCharCodes(
        preceding.sublist(
          preceding.length > length ? preceding.length - length : 0,
        ),
      );
      final portable = suffix.runes
          .map((code) => code.toRadixString(16))
          .join('.');
      prefixes.add('context:$portable\t${normalizeReading(reading)}\t');
      // Backups made before the portable key format used URI escaping.
      prefixes.add(
        'context:${Uri.encodeComponent(suffix)}\t'
        '${normalizeReading(reading)}\t',
      );
    }
    return prefixes.toList();
  }

  /// Recalls deliberate choices only when the same preceding text reappears.
  static Map<String, int> contextScores(
    Map<String, int> learning, {
    required String leftContext,
    required String reading,
  }) {
    for (final prefix in _contextPrefixes(leftContext, reading)) {
      final result = <String, int>{};
      for (final entry in learning.entries) {
        if (!entry.key.startsWith(prefix) || entry.value <= 0) continue;
        final text = entry.key.substring(prefix.length);
        if (text.trim().isNotEmpty) {
          result[text] = entry.value.clamp(1, maxScore);
        }
      }
      if (result.isNotEmpty) return result;
    }
    return const {};
  }

  static void recordContext(
    Map<String, int> learning, {
    required String leftContext,
    required String reading,
    required String text,
  }) {
    if (reading.contains('\t') || text.trim().isEmpty) return;
    final prefixes = _contextPrefixes(leftContext, reading);
    if (prefixes.isEmpty) return;
    for (final prefix in prefixes.where((value) => !value.contains('%'))) {
      final choices = learning.keys
          .where((key) => key.startsWith(prefix))
          .toList();
      final strongest = choices.fold<int>(
        0,
        (score, key) => learning[key]! > score ? learning[key]! : score,
      );
      for (final key in choices) {
        if (key != '$prefix$text') learning[key] = learning[key]! ~/ 2;
      }
      final key = '$prefix$text';
      // A deliberate correction must outrank the former favorite immediately.
      learning[key] = (strongest + 4).clamp(1, maxScore);
    }
    final contextKeys = learning.keys
        .where((key) => key.startsWith('context:'))
        .toList();
    for (final stale in contextKeys.take(
      contextKeys.length > 512 ? contextKeys.length - 512 : 0,
    )) {
      learning.remove(stale);
    }
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
      // Automatic acceptance stays weaker than one deliberate correction.
      final existing = scores[text] ?? 0;
      scores[text] = existing >= 4 ? existing : (existing + 1).clamp(1, 3);
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
