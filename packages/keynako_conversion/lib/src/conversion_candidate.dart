/// A displayable result produced for a Japanese reading.
class ConversionCandidate {
  const ConversionCandidate({
    required this.text,
    required this.reading,
    this.source = 'system',
    this.score = 0,
  });

  final String text;
  final String reading;
  final String source;
  final int score;

  ConversionCandidate copyWith({int? score}) => ConversionCandidate(
    text: text,
    reading: reading,
    source: source,
    score: score ?? this.score,
  );
}
