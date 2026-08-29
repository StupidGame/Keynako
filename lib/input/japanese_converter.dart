import 'package:keynako_conversion/keynako_conversion.dart' as conversion;

import '../models/app_data.dart';

export 'package:keynako_conversion/keynako_conversion.dart'
    show ConversionCandidate;

/// Adapts persisted application settings to the shared conversion core.
class JapaneseConverter {
  const JapaneseConverter();

  static const conversion.JapaneseConverter _converter =
      conversion.JapaneseConverter();

  String romanToHiragana(String input) => _converter.romanToHiragana(input);

  String hiraganaToKatakana(String value) =>
      _converter.hiraganaToKatakana(value);

  String katakanaToHalfWidth(String value) =>
      _converter.katakanaToHalfWidth(value);

  List<conversion.ConversionCandidate> candidates({
    required String input,
    required AppData data,
    bool romanInput = false,
  }) {
    return _converter.candidates(
      input: input,
      romanInput: romanInput,
      options: conversion.ConversionOptions(
        userDictionary: data.userDictionary
            .map(
              (entry) => conversion.ConversionDictionaryEntry(
                reading: entry.ruby,
                value: entry.word,
                template: entry.isTemplateMode,
                format: entry.formatLiteral,
              ),
            )
            .toList(growable: false),
        learning: data.learning,
        learningEnabled: data.settings['memory_learining_styple_setting'] != 2,
        halfWidthKanaCandidate: data.settings['half_kana_candidate'] == true,
        fullWidthRomanCandidate: data.settings['full_roman_candidate'] == true,
        unicodeCandidate: data.settings['unicode_candidate'] == true,
        emojiCandidate: data.settings['emoji_dictionary_enabled'] == true,
        kaomojiCandidate: data.settings['kaomoji_dictionary_enabled'] == true,
        romanEnglishCandidate: data.settings['roman_english_candidate'] == true,
      ),
    );
  }
}
