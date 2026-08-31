import 'package:keynako_conversion/keynako_conversion.dart';
import 'package:test/test.dart';

void main() {
  const converter = JapaneseConverter();

  group('romanToHiragana', () {
    test('converts basic and contracted sounds', () {
      expect(converter.romanToHiragana('nihongo'), 'にほんご');
      expect(converter.romanToHiragana('kyou'), 'きょう');
      expect(converter.romanToHiragana('gakkou'), 'がっこう');
    });

    test('handles a final n', () {
      expect(converter.romanToHiragana('hon'), 'ほん');
    });
  });

  test('prioritizes matching user dictionary entries', () {
    final values = converter.candidates(
      input: 'nihongo',
      romanInput: true,
      options: const ConversionOptions(
        userDictionary: [
          ConversionDictionaryEntry(reading: 'にほんご', value: '日本語入力'),
        ],
      ),
    );

    expect(values.first.text, '日本語入力');
    expect(values.map((value) => value.text), contains('日本語'));
    expect(values.map((value) => value.text), contains('ニホンゴ'));
  });

  test('orders user dictionary entries by importance', () {
    final candidates = converter.candidates(
      input: 'きーなこ',
      options: const ConversionOptions(
        userDictionary: [
          ConversionDictionaryEntry(
            reading: 'きーなこ',
            value: '低い候補',
            importance: 1,
          ),
          ConversionDictionaryEntry(
            reading: 'きーなこ',
            value: '高い候補',
            importance: 5,
          ),
        ],
      ),
    );

    expect(candidates.first.text, '高い候補');
  });

  test('pins live conversion, hiragana, and katakana in that order', () {
    final candidates = converter.candidates(
      input: 'nihongo',
      romanInput: true,
      options: const ConversionOptions(
        userDictionary: [
          ConversionDictionaryEntry(
            reading: 'にほんご',
            value: '日本語入力',
            importance: 5,
          ),
        ],
      ),
    );

    expect(candidates.take(3).map((candidate) => candidate.text), [
      '日本語入力',
      'にほんご',
      'ニホンゴ',
    ]);
  });

  test('normalizes katakana before looking up candidates', () {
    final candidates = converter.candidates(input: 'キョウ');

    expect(candidates.take(2).map((candidate) => candidate.text), [
      'きょう',
      'キョウ',
    ]);
    expect(candidates.map((candidate) => candidate.text), contains('今日'));
  });

  test('applies learning while preserving pinned kana order', () {
    final values = converter.candidates(
      input: 'にほんご',
      options: const ConversionOptions(learning: {'にほんご\tニホンゴ': 5}),
    );

    expect(values.take(2).map((candidate) => candidate.text), ['にほんご', 'ニホンゴ']);
  });

  test('provides optional half-width, full-width and Unicode candidates', () {
    final kana = converter.candidates(input: 'がくせい');
    final roman = converter.candidates(input: 'abc123', romanInput: true);
    final unicode = converter.candidates(input: 'u3042', romanInput: true);

    expect(kana.map((value) => value.text), contains('ｶﾞｸｾｲ'));
    expect(roman.map((value) => value.text), contains('ａｂｃ１２３'));
    expect(unicode.map((value) => value.text), contains('あ'));
  });

  test('provides direct English input and prefix predictions', () {
    const english = EnglishConverter();
    final values = english.candidates(input: 'hel');

    expect(values.first.text, 'hel');
    expect(values.map((value) => value.text), contains('hello'));
  });
}
