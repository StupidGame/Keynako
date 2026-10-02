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

    test('uses full-width punctuation for Japanese input', () {
      expect(converter.romanToHiragana('nani!?'), 'なに！？');
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

  test('applies a personal word to the start of a longer reading', () {
    final values = converter.candidates(
      input: 'てすとかな',
      options: const ConversionOptions(
        userDictionary: [
          ConversionDictionaryEntry(reading: 'てすと', value: '登録語'),
        ],
      ),
    );

    expect(values.map((candidate) => candidate.text), contains('登録語かな'));
    expect(values.first.source, 'user-prefix');
  });

  test('combines personal and shared dictionary words across a particle', () {
    final candidates = converter.candidates(
      input: 'まきなとれいな',
      options: const ConversionOptions(
        userDictionary: [
          ConversionDictionaryEntry(reading: 'まきな', value: 'マキナ'),
          ConversionDictionaryEntry(
            reading: 'れいな',
            value: 'レイナ',
            wordWeight: -7,
          ),
        ],
      ),
    );

    expect(candidates.first.text, 'マキナとレイナ');
    expect(candidates.first.source, 'user-combination');
  });

  test('combines a registered word with a built-in word', () {
    final candidates = converter.candidates(
      input: 'わたしはねこ',
      options: const ConversionOptions(
        userDictionary: [ConversionDictionaryEntry(reading: 'ねこ', value: '猫')],
      ),
    );

    expect(candidates.map((candidate) => candidate.text), contains('私は猫'));
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

  test('places prefix matches near the front without live autocompletion', () {
    final candidates = converter.candidates(
      input: 'にほ',
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

    expect(candidates.first.text, 'にほ');
    expect(candidates[1].text, 'ニホ');
    expect(candidates[2].text, '日本語入力');
    expect(candidates.map((candidate) => candidate.text), contains('日本'));
    expect(candidates[2].source, 'user-prediction');
    expect(candidates[2].reading, 'にほんご');
  });

  test('prediction candidates retain their complete readings', () {
    final values = converter.candidates(
      input: 'にほ',
      options: const ConversionOptions(learning: {'にほんご\t日本語入力': 4}),
    );
    expect(
      values
          .firstWhere((value) => value.source == 'learned-prediction')
          .reading,
      'にほんご',
    );
    expect(values.firstWhere((value) => value.text == '日本').reading, 'にほん');
  });

  test('can disable Japanese prefix predictions', () {
    final candidates = converter.candidates(input: 'にほ', predictionLimit: 0);

    expect(
      candidates.map((candidate) => candidate.text),
      isNot(contains('日本')),
    );
  });

  test('keeps complete matches ahead of longer, high importance words', () {
    for (final live in [true, false]) {
      final texts = converter
          .candidates(
            input: 'あい',
            options: ConversionOptions(
              liveConversion: live,
              userDictionary: const [
                ConversionDictionaryEntry(
                  reading: 'あいさつ',
                  value: '挨拶',
                  importance: 5,
                ),
              ],
            ),
          )
          .map((value) => value.text)
          .toList();
      expect(texts.indexOf('藍'), lessThan(texts.indexOf('挨拶')));
      expect(texts.indexOf('相'), lessThan(texts.indexOf('挨拶')));
    }
  });

  test('ranks equally weighted predictions by remaining reading length', () {
    final texts = converter
        .candidates(
          input: 'てす',
          options: const ConversionOptions(
            userDictionary: [
              ConversionDictionaryEntry(reading: 'テストケース', value: 'テストケース'),
              ConversionDictionaryEntry(reading: 'テスト', value: 'テスト'),
            ],
          ),
        )
        .map((value) => value.text)
        .toList();
    expect(texts.indexOf('テスト'), lessThan(texts.indexOf('テストケース')));
    expect(texts.first, 'てす');
  });

  test('recalls learned words and predicts them from a shorter reading', () {
    const options = ConversionOptions(learning: {'キーナコ\tKeynako': 4});
    expect(
      converter.candidates(input: 'きーなこ', options: options).first.text,
      'Keynako',
    );
    final partial = converter.candidates(
      input: 'きー',
      predictionLimit: 1,
      options: options,
    );
    expect(partial.first.text, 'きー');
    expect(partial[2].text, 'Keynako');
    expect(
      converter
          .candidates(input: 'きー', predictionLimit: 0, options: options)
          .map((value) => value.text),
      isNot(contains('Keynako')),
    );
  });

  test('does not recall disabled, invalid or unrelated learning', () {
    const learning = {'きーなこ\tKeynako': 4, 'きーなこ\t': 99, 'missing separator': 9};
    for (final input in ['きーなこ', 'きー']) {
      final texts = converter
          .candidates(
            input: input,
            options: const ConversionOptions(
              learning: learning,
              learningEnabled: false,
            ),
          )
          .map((value) => value.text);
      expect(texts, isNot(contains('Keynako')));
      expect(texts, isNot(contains('')));
    }
    expect(
      converter
          .candidates(
            input: 'ほか',
            options: const ConversionOptions(learning: learning),
          )
          .map((value) => value.text),
      isNot(contains('Keynako')),
    );
  });

  test(
    'ranks and deduplicates learned predictions before applying the limit',
    () {
      final predictions = converter
          .candidates(
            input: 'てす',
            predictionLimit: 1,
            options: const ConversionOptions(
              userDictionary: [
                ConversionDictionaryEntry(reading: 'てすと', value: 'テスト'),
                ConversionDictionaryEntry(reading: 'てすと', value: 'テスト'),
                ConversionDictionaryEntry(reading: 'てすとけーす', value: 'テストケース'),
              ],
              learning: {'てすとけーす\tテストケース': 5},
            ),
          )
          .where((value) => value.source.endsWith('prediction'))
          .toList();
      expect(predictions.map((value) => value.text), ['テストケース']);
    },
  );

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
