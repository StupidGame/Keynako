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

  test('hides selected additional emoji without hiding a personal word', () {
    const options = ConversionOptions(
      emojiDenylist: {'🕷', '🕸'},
      userDictionary: [ConversionDictionaryEntry(reading: 'くも', value: '🕷️')],
    );
    final values = converter.candidates(input: 'くも', options: options);
    expect(values.where((value) => value.text == '🕷️').length, 1);
    expect(values.first.source, 'user');
    expect(values.map((value) => value.text), isNot(contains('🕸️')));
    final withoutPersonalWord = converter.candidates(
      input: 'くも',
      options: const ConversionOptions(emojiDenylist: {'🕷', '🕸'}),
    );
    expect(
      withoutPersonalWord.map((value) => value.text),
      isNot(contains('🕷️')),
    );
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

  test('combines two learned words across a particle', () {
    final candidates = converter.candidates(
      input: 'わたしはねこ',
      options: const ConversionOptions(learning: {'わたし\t私': 16, 'ねこ\t猫': 16}),
    );
    expect(
      candidates.where((candidate) => candidate.text == '私は猫').first.source,
      'learned-combination',
    );
  });

  test('keeps dictionary combinations before mixed learned combinations', () {
    final candidates = converter.candidates(
      input: 'まきなとれいな',
      options: const ConversionOptions(
        userDictionary: [
          ConversionDictionaryEntry(reading: 'まきな', value: 'マキナ'),
          ConversionDictionaryEntry(reading: 'れいな', value: 'レイナ'),
        ],
        learning: {'れいな\t玲奈': 16},
      ),
    );
    expect(candidates.first.text, 'マキナとレイナ');
    expect(candidates.map((candidate) => candidate.text), contains('マキナと玲奈'));
    expect(
      candidates.firstWhere((candidate) => candidate.text == 'マキナと玲奈').source,
      'learned-combination',
    );
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

  test(
    'always orders registered words before learning and other conversions',
    () {
      const options = ConversionOptions(
        userDictionary: [
          ConversionDictionaryEntry(reading: 'にほんご', value: '登録語'),
          ConversionDictionaryEntry(reading: 'にほんごか', value: '登録補完'),
        ],
        learning: {'にほんご\t学習語': 32, 'にほんごか\t学習補完': 32},
      );
      final values = converter.candidates(input: 'にほんご', options: options);
      expect(values.take(4).map((value) => value.text), [
        '登録語',
        '登録補完',
        '学習語',
        '学習補完',
      ]);
      expect(values.indexWhere((value) => value.text == '日本語'), greaterThan(3));
    },
  );

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

  test('puts registered prefix matches before other candidates', () {
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

    expect(candidates.first.text, '日本語入力');
    expect(candidates[1].text, 'にほ');
    expect(candidates[2].text, 'ニホ');
    expect(candidates.map((candidate) => candidate.text), contains('日本'));
    expect(candidates.first.source, 'user-prediction');
    expect(candidates.first.reading, 'にほんご');
  });

  test('shows a registered long word for both short reading prefixes', () {
    const options = ConversionOptions(
      userDictionary: [
        ConversionDictionaryEntry(reading: 'かめんらいだー', value: '仮面ライダー'),
        ConversionDictionaryEntry(reading: 'かめ', value: '亀壱'),
        ConversionDictionaryEntry(reading: 'かめ', value: '亀弐'),
        ConversionDictionaryEntry(reading: 'かめ', value: '亀参'),
      ],
    );
    for (final reading in ['かめ', 'かめん']) {
      final candidates = converter.candidates(input: reading, options: options);
      expect(candidates.first.source, anyOf('user', 'user-prefix'));
      final riderIndex = candidates.indexWhere(
        (candidate) => candidate.text == '仮面ライダー',
      );
      expect(riderIndex, greaterThan(0));
      expect(
        riderIndex,
        lessThan(
          candidates.indexWhere((candidate) => candidate.text == reading),
        ),
      );
      expect(
        candidates
            .firstWhere((candidate) => candidate.text == '仮面ライダー')
            .reading,
        'かめんらいだー',
      );
    }
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

  test('learned words surface beside conversions from short prefixes', () {
    for (final reading in ['かめ', 'かめん']) {
      final candidates = converter.candidates(
        input: reading,
        options: const ConversionOptions(learning: {'かめんらいだー\t仮面ライダー': 8}),
      );
      expect(candidates.first.text, '仮面ライダー', reason: reading);
      expect(candidates.first.reading, 'かめんらいだー');
      expect(candidates.first.source, 'learned-prediction');
    }
  });

  test('can disable Japanese prefix predictions', () {
    final candidates = converter.candidates(input: 'にほ', predictionLimit: 0);

    expect(
      candidates.map((candidate) => candidate.text),
      isNot(contains('日本')),
    );
  });

  test(
    'keeps the leading complete match while showing a registered completion',
    () {
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
        expect(texts.first, '挨拶');
      }
    },
  );

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
    expect(texts.first, 'テスト');
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
    expect(partial.first.text, 'Keynako');
    expect(partial[1].text, 'きー');
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

  test('puts learned kana before unlearned kana', () {
    final values = converter.candidates(
      input: 'にほんご',
      options: const ConversionOptions(learning: {'にほんご\tニホンゴ': 5}),
    );

    expect(values.take(2).map((candidate) => candidate.text), ['ニホンゴ', 'にほんご']);
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

  test('English words use dictionary, learning, then default order', () {
    const english = EnglishConverter();
    final values = english.candidates(
      input: 'hel',
      options: const ConversionOptions(
        userDictionary: [
          ConversionDictionaryEntry(reading: 'hello', value: '辞書Hello'),
        ],
        learning: {'english:hello\tLearnedHello': 32},
      ),
    );
    expect(values.take(3).map((value) => value.text), [
      '辞書Hello',
      'LearnedHello',
      'hel',
    ]);
  });
}
