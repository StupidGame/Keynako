import 'package:azookey_flutter/input/japanese_converter.dart';
import 'package:azookey_flutter/models/app_data.dart';
import 'package:flutter_test/flutter_test.dart';

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

  test('puts a matching user dictionary entry before system candidates', () {
    final data = AppData.defaults();
    data.userDictionary.add(
      const UserDictionaryEntry(id: 10, ruby: 'にほんご', word: '日本語入力'),
    );

    final values = converter.candidates(
      input: 'nihongo',
      data: data,
      romanInput: true,
    );

    expect(values.first.text, '日本語入力');
    expect(values.map((value) => value.text), contains('日本語'));
    expect(values.map((value) => value.text), contains('ニホンゴ'));
  });

  test('renders date templates locally', () {
    final data = AppData.defaults();
    data.userDictionary.add(
      const UserDictionaryEntry(
        id: 11,
        ruby: 'ひづけ',
        word: '',
        isTemplateMode: true,
        formatLiteral: 'yyyy/MM/dd',
      ),
    );
    final value = converter.candidates(input: 'ひづけ', data: data).first.text;
    expect(value, matches(RegExp(r'^\d{4}/\d{2}/\d{2}$')));
  });

  test('provides half-width kana and full-width roman candidates', () {
    final data = AppData.defaults();
    final kana = converter.candidates(input: 'がくせい', data: data);
    final roman = converter.candidates(
      input: 'abc123',
      data: data,
      romanInput: true,
    );

    expect(kana.map((value) => value.text), contains('ｶﾞｸｾｲ'));
    expect(roman.map((value) => value.text), contains('ａｂｃ１２３'));
  });

  test('converts a Unicode code point candidate', () {
    final values = converter.candidates(
      input: 'u3042',
      data: AppData.defaults(),
      romanInput: true,
    );

    expect(values.map((value) => value.text), contains('あ'));
  });
}
