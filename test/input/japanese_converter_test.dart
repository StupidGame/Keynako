import 'package:azookey_flutter/input/japanese_converter.dart';
import 'package:azookey_flutter/models/app_data.dart';
import 'package:azookey_flutter/models/azookey_hotfix_dictionary.dart';
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

  test(
    'puts a live conversion before hiragana, katakana, and dictionaries',
    () {
      final data = AppData.defaults();
      data.userDictionary.add(
        const UserDictionaryEntry(id: 10, ruby: 'にほんご', word: '日本語入力'),
      );

      final values = converter.candidates(
        input: 'nihongo',
        data: data,
        romanInput: true,
      );

      expect(values.take(3).map((value) => value.text), [
        '日本語入力',
        'にほんご',
        'ニホンゴ',
      ]);
      expect(values.map((value) => value.text), contains('日本語'));
      expect(
        values.indexWhere((value) => value.text == '日本語入力'),
        lessThan(values.indexWhere((value) => value.text == '日本語')),
      );
    },
  );

  test('orders matching user words by conversion importance', () {
    final data = AppData.defaults();
    data.userDictionary.addAll(const [
      UserDictionaryEntry(id: 20, ruby: 'きーなこ', word: '低い候補', importance: 1),
      UserDictionaryEntry(id: 21, ruby: 'きーなこ', word: '高い候補', importance: 5),
    ]);

    final values = converter.candidates(input: 'きーなこ', data: data);

    expect(values.first.text, '高い候補');
    expect(
      values.indexWhere((value) => value.text == '高い候補'),
      lessThan(values.indexWhere((value) => value.text == '低い候補')),
    );
    expect(values.skip(1).take(2).map((value) => value.text), ['きーなこ', 'キーナコ']);
  });

  test('pins hiragana and katakana first when live conversion is disabled', () {
    final data = AppData.defaults();
    data.settings['live_conversion'] = false;

    final values = converter.candidates(input: 'にほんご', data: data);

    expect(values.take(2).map((value) => value.text), ['にほんご', 'ニホンゴ']);
    expect(values.map((value) => value.text), contains('日本語'));
  });

  test(
    'normalizes katakana input without treating raw text as a live conversion',
    () {
      final values = converter.candidates(
        input: 'キョウ',
        data: AppData.defaults(),
      );

      expect(values.take(2).map((value) => value.text), ['きょう', 'キョウ']);
    },
  );

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

  test(
    'uses active shared dictionary entries for conversion and prediction',
    () {
      final data = AppData.defaults();
      for (final status in ['active', 'disabled']) {
        data.azooKeyHotfixDictionary = AzooKeyHotfixDictionary.fromJson({
          'metadata': {
            'status': status,
            'name': 'test',
            'description': 'test',
            'version': '1',
            'last_update': '2026-09-22',
          },
          'data': [
            {
              'word': 'Keynako共有',
              'ruby': 'キーナコキョウユウ',
              'word_weight': -5,
              'lcid': 1285,
              'rcid': 1285,
              'mid': 501,
              'date': '2026-09-22',
              'author': 'test',
              'importance': 5,
            },
          ],
        });
        for (final reading in ['きーなこきょうゆう', 'きーなこ']) {
          final texts = converter
              .candidates(input: reading, data: data)
              .map((value) => value.text);
          expect(
            texts,
            status == 'active'
                ? contains('Keynako共有')
                : isNot(contains('Keynako共有')),
          );
        }
      }
    },
  );

  test('combines personal and active shared words in one sentence', () {
    final data = AppData.defaults();
    data.userDictionary.add(
      const UserDictionaryEntry(id: 30, ruby: 'わたし', word: '私'),
    );
    data.azooKeyHotfixDictionary = AzooKeyHotfixDictionary.fromJson({
      'metadata': {
        'status': 'active',
        'name': 'test',
        'description': 'test',
        'version': '1',
        'last_update': '2026-09-22',
      },
      'data': [
        {
          'word': '猫',
          'ruby': 'ネコ',
          'word_weight': -5,
          'lcid': 1285,
          'rcid': 1285,
          'mid': 501,
          'date': '2026-09-22',
          'author': 'test',
          'importance': 5,
        },
      ],
    });

    final candidates = converter.candidates(input: 'わたしはねこ', data: data);
    expect(candidates.map((candidate) => candidate.text), contains('私は猫'));
    expect(
      candidates.firstWhere((candidate) => candidate.text == '私は猫').source,
      'user-combination',
    );
  });

  test('shows personal and shared long words from short reading prefixes', () {
    final data = AppData.defaults();
    data.userDictionary.add(
      const UserDictionaryEntry(id: 31, ruby: 'かめんらいだー', word: '仮面ライダー'),
    );
    data.azooKeyHotfixDictionary = AzooKeyHotfixDictionary.fromJson({
      'metadata': {
        'status': 'active',
        'name': 'test',
        'description': 'test',
        'version': '1',
        'last_update': '2026-09-22',
      },
      'data': [
        {
          'word': '仮面の共有語',
          'ruby': 'カメンノキョウユウゴ',
          'word_weight': -5,
          'lcid': 1285,
          'rcid': 1285,
          'mid': 501,
          'date': '2026-09-22',
          'author': 'test',
          'importance': 5,
        },
      ],
    });

    for (final reading in ['かめ', 'かめん']) {
      final candidates = converter.candidates(input: reading, data: data);
      final texts = candidates.map((candidate) => candidate.text).toList();
      expect(texts.first, isNot('仮面ライダー'));
      expect(texts.take(5), containsAll(['仮面ライダー', '仮面の共有語']));
      expect(
        candidates
            .firstWhere((candidate) => candidate.text == '仮面ライダー')
            .reading,
        'かめんらいだー',
      );
    }
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
