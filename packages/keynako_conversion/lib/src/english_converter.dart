import 'candidate_learning.dart';
import 'conversion_candidate.dart';
import 'conversion_options.dart';

/// Direct English input with lightweight offline word prediction.
class EnglishConverter {
  const EnglishConverter();

  static const _words = <String>[
    'about',
    'after',
    'again',
    'also',
    'because',
    'before',
    'can',
    'come',
    'could',
    'day',
    'first',
    'from',
    'good',
    'have',
    'hello',
    'help',
    'here',
    'how',
    'input',
    'Japanese',
    'keyboard',
    'know',
    'like',
    'make',
    'more',
    'need',
    'people',
    'please',
    'really',
    'right',
    'should',
    'some',
    'text',
    'thank',
    'thanks',
    'that',
    'their',
    'then',
    'there',
    'these',
    'they',
    'thing',
    'think',
    'this',
    'time',
    'want',
    'what',
    'when',
    'where',
    'which',
    'will',
    'with',
    'work',
    'would',
    'write',
    'you',
    'your',
  ];

  List<ConversionCandidate> candidates({
    required String input,
    ConversionOptions options = const ConversionOptions(),
    int predictionLimit = 8,
  }) {
    if (input.isEmpty || predictionLimit <= 0) return const [];
    final normalized = input.toLowerCase();
    final values = <ConversionCandidate>[
      ConversionCandidate(
        text: input,
        reading: input,
        source: 'english',
        score: 250,
      ),
    ];

    for (final entry in options.userDictionary) {
      if (entry.reading.toLowerCase() == normalized) {
        values.add(
          ConversionCandidate(
            text: entry.value,
            reading: input,
            source: 'user',
            score: 400,
          ),
        );
      }
    }
    for (final word in _words.where(
      (word) => word.toLowerCase().startsWith(normalized),
    )) {
      final matchedCase = _matchCase(input, word);
      values.add(
        ConversionCandidate(
          text: matchedCase,
          reading: input,
          source: 'english-prediction',
          score: 180 - (word.length - input.length),
        ),
      );
    }

    final learnedScores = <String, int>{};
    if (options.learningEnabled) {
      for (final entry in CandidateLearning.entries(
        options.learning,
        english: true,
      )) {
        if (!entry.reading.startsWith(normalized) &&
            !entry.text.toLowerCase().startsWith(normalized)) {
          continue;
        }
        final text = _matchCase(input, entry.text);
        if (entry.score > (learnedScores[text] ?? 0)) {
          learnedScores[text] = entry.score;
        }
        values.add(
          ConversionCandidate(
            text: text,
            reading: input,
            source: 'english-learned',
            score: 180,
          ),
        );
      }
    }

    final unique = <String, ConversionCandidate>{};
    for (final candidate in values) {
      final learned = learnedScores[candidate.text] ?? 0;
      final scored = candidate.copyWith(score: candidate.score + learned * 50);
      final previous = unique[candidate.text];
      if (previous == null || scored.score > previous.score) {
        unique[candidate.text] = scored;
      }
    }
    final ranked = unique.values.indexed.toList()
      ..sort((left, right) {
        final learned = (learnedScores[right.$2.text] ?? 0).compareTo(
          learnedScores[left.$2.text] ?? 0,
        );
        if (learned != 0) return learned;
        final score = right.$2.score.compareTo(left.$2.score);
        return score != 0 ? score : left.$1.compareTo(right.$1);
      });
    // English composition remains literal until a completion is selected.
    return [
      unique[input]!,
      ...ranked.map((entry) => entry.$2).where((value) => value.text != input),
    ].take(predictionLimit).toList(growable: false);
  }

  String _matchCase(String input, String word) {
    if (input == input.toUpperCase()) return word.toUpperCase();
    if (input.length > 1 &&
        input[0] == input[0].toUpperCase() &&
        input.substring(1) == input.substring(1).toLowerCase()) {
      return '${word[0].toUpperCase()}${word.substring(1)}';
    }
    return word;
  }
}
