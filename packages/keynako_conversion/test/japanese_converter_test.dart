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

  test('keeps exact dictionary entries after standard conversions', () {
    final values = converter.candidates(
      input: 'nihongo',
      romanInput: true,
      options: const ConversionOptions(
        userDictionary: [
          ConversionDictionaryEntry(reading: 'にほんご', value: '日本語入力'),
        ],
      ),
    );

    expect(values.first.text, '日本語');
    expect(values.map((value) => value.text), contains('日本語入力'));
    expect(values.map((value) => value.text), contains('日本語'));
    expect(values.map((value) => value.text), contains('ニホンゴ'));
  });

  test('keeps a single kana literal first unless it was registered', () {
    expect(converter.candidates(input: 'te', romanInput: true).first.text, 'て');
    final registered = converter.candidates(
      input: 'te',
      romanInput: true,
      options: const ConversionOptions(
        userDictionary: [ConversionDictionaryEntry(reading: 'て', value: '登録語')],
      ),
    );
    expect(registered.first.text, '登録語');
  });

  test('weak automatic learning cannot replace short grammatical kana', () {
    final automatic = converter.candidates(
      input: 'shite',
      romanInput: true,
      options: const ConversionOptions(learning: {'して\t仕手': 1}),
    );
    expect(automatic.first.text, 'して');
    expect(automatic.map((candidate) => candidate.text), contains('仕手'));

    final deliberate = converter.candidates(
      input: 'shite',
      romanInput: true,
      options: const ConversionOptions(learning: {'して\t仕手': 4}),
    );
    expect(deliberate.first.text, '仕手');
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

  test(
    'puts a complete conversion before a partial dictionary replacement',
    () {
      final values = converter.candidates(
        input: 'にほんご',
        options: const ConversionOptions(
          userDictionary: [
            ConversionDictionaryEntry(reading: 'にほん', value: '登録'),
          ],
        ),
      );
      expect(values.first.text, '日本語');
      expect(
        values.firstWhere((candidate) => candidate.text == '登録ご').source,
        'user-prefix',
      );
    },
  );

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

  test('allows particle endings but not unmatched words in combinations', () {
    const options = ConversionOptions(
      userDictionary: [
        ConversionDictionaryEntry(reading: 'まきな', value: 'マキナ'),
        ConversionDictionaryEntry(reading: 'れいな', value: 'レイナ'),
      ],
    );
    expect(
      converter
          .candidates(input: 'まきなとれいなも', options: options)
          .where((candidate) => candidate.source == 'user-combination')
          .map((candidate) => candidate.text),
      contains('マキナとレイナも'),
    );
    for (final reading in ['あまきなとれいな', 'まきなぴょれいな', 'まきなとれいなぴょ']) {
      expect(
        converter
            .candidates(input: reading, options: options)
            .where((candidate) => candidate.source == 'user-combination'),
        isEmpty,
      );
    }
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

  test('prefers ordinary spellings and combines built-in words', () {
    final rain = converter.candidates(input: 'あめ');
    expect(rain.first.text, '雨');
    expect(rain.map((candidate) => candidate.text), contains('飴'));
    expect(rain.indexWhere((candidate) => candidate.text == 'あめ'), lessThan(4));

    final phrase = converter.candidates(input: 'きょうはあめ');
    expect(phrase.first.text, '今日は雨');
    expect(phrase.first.source, 'system-combination');
    expect(phrase.map((candidate) => candidate.text), isNot(contains('今日は飴')));

    final longer = converter.candidates(input: 'にほんごをつかう');
    expect(longer.first.text, '日本語を使う');
    expect(longer.first.source, 'system-combination');
  });

  test('attaches 付き to preceding dictionary and learned word groups', () {
    expect(converter.candidates(input: 'ぼいすつき').first.text, 'ボイス付き');
    expect(converter.candidates(input: 'わたしのぼいすつき').first.text, '私のボイス付き');
    expect(converter.candidates(input: 'ほしょうつき').first.text, '保証付き');
    final learned = converter.candidates(
      input: 'きゃらつき',
      options: const ConversionOptions(learning: {'きゃら\tキャラ': 8}),
    );
    expect(learned.map((candidate) => candidate.text), contains('キャラ付き'));
    final registered = converter.candidates(
      input: 'とうろくごつき',
      options: const ConversionOptions(
        userDictionary: [
          ConversionDictionaryEntry(reading: 'とうろくご', value: '登録語'),
        ],
      ),
    );
    expect(registered.first.text, '登録語付き');
  });

  test('does not join built-in words through unmatched kana', () {
    final candidates = converter.candidates(input: 'きょうぴょあめ');
    expect(
      candidates.map((candidate) => candidate.text),
      isNot(contains('今日ぴょ雨')),
    );
  });

  test('combines learned words with ordinary words', () {
    final candidates = converter.candidates(
      input: 'まきなとねこ',
      options: const ConversionOptions(learning: {'まきな\tマキナ': 8}),
    );
    expect(candidates.first.text, 'マキナと猫');
    expect(candidates.first.source, 'learned-combination');
  });

  test('uses the preceding text to disambiguate an ordinary word', () {
    final learning = <String, int>{'あめ\t雨': 8};
    CandidateLearning.recordContext(
      learning,
      leftContext: '今日は',
      reading: 'あめ',
      text: '飴',
    );
    expect(
      converter
          .candidates(
            input: 'あめ',
            options: ConversionOptions(learning: learning, leftContext: '今日は'),
          )
          .first
          .text,
      '飴',
    );
    expect(
      converter
          .candidates(
            input: 'あめ',
            options: ConversionOptions(learning: learning, leftContext: '明日は'),
          )
          .first
          .text,
      '雨',
    );
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
    final withParticle = converter.candidates(
      input: 'わたしはねこも',
      options: const ConversionOptions(learning: {'わたし\t私': 16, 'ねこ\t猫': 16}),
    );
    expect(
      withParticle
          .where((candidate) => candidate.source == 'learned-combination')
          .map((candidate) => candidate.text),
      contains('私は猫も'),
    );
  });

  test('keeps learned and registered paths through a long sentence', () {
    final candidates = converter.candidates(
      input: 'わたしはねこときょうのにほんご',
      options: const ConversionOptions(
        userDictionary: [ConversionDictionaryEntry(reading: 'ねこ', value: '猫')],
        learning: {'わたし\t私': 8},
      ),
    );
    expect(
      candidates.map((candidate) => candidate.text),
      contains('私は猫と今日の日本語'),
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
    'orders complete matches before dictionary and learning completions',
    () {
      const options = ConversionOptions(
        userDictionary: [
          ConversionDictionaryEntry(reading: 'にほんご', value: '登録語'),
          ConversionDictionaryEntry(reading: 'にほんごか', value: '登録補完'),
        ],
        learning: {'にほんご\t学習語': 32, 'にほんごか\t学習補完': 32},
      );
      final values = converter.candidates(input: 'にほんご', options: options);
      expect(values.take(3).map((value) => value.text), ['日本語', '登録語', '学習語']);
      expect(
        values.indexWhere((value) => value.text == '登録補完'),
        greaterThan(values.indexWhere((value) => value.text == '日本語')),
      );
      expect(
        values.indexWhere((value) => value.text == '学習補完'),
        greaterThan(values.indexWhere((value) => value.text == '登録補完')),
      );
    },
  );

  test('puts complete conversions ahead of raw kana', () {
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

    expect(candidates.take(2).map((candidate) => candidate.text), [
      '日本語',
      '日本語入力',
    ]);
    expect(
      candidates.indexWhere((candidate) => candidate.text == 'にほんご'),
      greaterThan(1),
    );
  });

  test('normalizes katakana before looking up candidates', () {
    final candidates = converter.candidates(input: 'キョウ');

    expect(candidates.take(2).map((candidate) => candidate.text), [
      'きょう',
      'キョウ',
    ]);
    expect(candidates.map((candidate) => candidate.text), contains('今日'));
  });

  test(
    'keeps both kana spellings among the first candidates with many matches',
    () {
      final candidates = converter.candidates(
        input: 'にほんご',
        options: ConversionOptions(
          userDictionary: List.generate(
            20,
            (index) =>
                ConversionDictionaryEntry(reading: 'にほんご', value: '登録$index'),
          ),
        ),
      );
      final texts = candidates.map((candidate) => candidate.text).toList();
      expect(texts.indexOf('にほんご'), inInclusiveRange(0, 3));
      expect(texts.indexOf('ニホンゴ'), inInclusiveRange(0, 4));
    },
  );

  test('puts complete standard matches before registered completions', () {
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

    expect(candidates.first.text, '日本');
    expect(
      candidates.indexWhere((candidate) => candidate.text == 'にほ'),
      greaterThan(0),
    );
    expect(candidates.map((candidate) => candidate.text), contains('日本'));
    expect(
      candidates.firstWhere((candidate) => candidate.text == '日本語入力').source,
      'user-prediction',
    );
    expect(
      candidates.firstWhere((candidate) => candidate.text == '日本語入力').reading,
      'にほんご',
    );
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
      expect(riderIndex, lessThan(9));
      expect(
        candidates.indexWhere((candidate) => candidate.text == reading),
        lessThan(9),
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
        expect(texts.first, live ? '愛' : 'あい');
        expect(texts.indexOf('挨拶'), greaterThan(texts.indexOf('藍')));
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

  test('keeps learned kana after standard conversions', () {
    final values = converter.candidates(
      input: 'にほんご',
      options: const ConversionOptions(learning: {'にほんご\tニホンゴ': 5}),
    );

    expect(values.take(2).map((candidate) => candidate.text), ['日本語', 'ニホンゴ']);
    expect(
      values.indexWhere((candidate) => candidate.text == 'にほんご'),
      greaterThan(1),
    );
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
