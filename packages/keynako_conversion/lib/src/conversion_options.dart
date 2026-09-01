/// A dictionary item understood by the platform-independent converter.
class ConversionDictionaryEntry {
  const ConversionDictionaryEntry({
    required this.reading,
    required this.value,
    this.template = false,
    this.format,
    this.importance = 3,
    this.wordWeight,
    this.leftContextId,
    this.rightContextId,
  });

  final String reading;
  final String value;
  final bool template;
  final String? format;
  final int importance;
  final double? wordWeight;
  final int? leftContextId;
  final int? rightContextId;
}

/// Per-request candidate switches and personalization data.
class ConversionOptions {
  const ConversionOptions({
    this.userDictionary = const [],
    this.learning = const {},
    this.learningEnabled = true,
    this.halfWidthKanaCandidate = true,
    this.fullWidthRomanCandidate = true,
    this.unicodeCandidate = true,
    this.emojiCandidate = true,
    this.kaomojiCandidate = true,
    this.romanEnglishCandidate = true,
    this.liveConversion = true,
  });

  final List<ConversionDictionaryEntry> userDictionary;
  final Map<String, int> learning;
  final bool learningEnabled;
  final bool halfWidthKanaCandidate;
  final bool fullWidthRomanCandidate;
  final bool unicodeCandidate;
  final bool emojiCandidate;
  final bool kaomojiCandidate;
  final bool romanEnglishCandidate;
  final bool liveConversion;
}
