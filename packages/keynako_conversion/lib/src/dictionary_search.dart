import 'japanese_converter.dart';

/// Matches dictionary terms as typed or by a kana or romaji reading.
class DictionarySearch {
  DictionarySearch(String query)
    : _query = _normalize(query.trim()),
      _reading = _normalize(
        _converter.romanToHiragana(query.trim().toLowerCase()),
      );

  static const _converter = JapaneseConverter();
  final String _query;
  final String _reading;

  bool get isEmpty => _query.isEmpty;

  bool matches({required String reading, required String word}) {
    if (isEmpty) return true;
    final normalizedReading = _normalize(reading);
    return normalizedReading.contains(_query) ||
        normalizedReading.contains(_reading) ||
        _normalize(word).contains(_query);
  }

  static String _normalize(String text) =>
      _converter.katakanaToHiragana(text.toLowerCase());
}
