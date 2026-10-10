import 'package:keynako_conversion/keynako_conversion.dart';
import 'package:test/test.dart';

void main() {
  test('automatic acceptance stays below a deliberate correction', () {
    final learning = <String, int>{};
    for (var i = 0; i < 20; i++) {
      CandidateLearning.record(learning, reading: 'して', text: '仕手');
    }
    expect(learning['して\t仕手'], 3);
    CandidateLearning.record(
      learning,
      reading: 'して',
      text: 'して',
      explicitSelection: true,
    );
    expect(learning['して\tして'], greaterThan(learning['して\t仕手']!));
  });

  test('a correction overtakes an old repeatedly accepted choice', () {
    final learning = {'あい\t愛': 1000000, 'べつ\t別': 7};
    CandidateLearning.record(
      learning,
      reading: 'あい',
      text: '藍',
      explicitSelection: true,
    );
    expect(learning['あい\t藍'], greaterThan(learning['あい\t愛']!));
    expect(learning['べつ\t別'], 7);
    expect(
      const JapaneseConverter()
          .candidates(
            input: 'あい',
            options: ConversionOptions(learning: learning),
          )
          .first
          .text,
      '藍',
    );
  });

  test(
    'repeated selections strengthen the choice without unbounded scores',
    () {
      final learning = <String, int>{};
      for (var i = 0; i < 100; i++) {
        final before = learning['あい\t藍'] ?? 0;
        CandidateLearning.record(
          learning,
          reading: 'あい',
          text: '藍',
          explicitSelection: true,
        );
        expect(learning['あい\t藍'], greaterThanOrEqualTo(before));
        expect(
          learning['あい\t藍'],
          lessThanOrEqualTo(CandidateLearning.maxScore),
        );
      }
      CandidateLearning.record(
        learning,
        reading: 'あい',
        text: '愛',
        explicitSelection: true,
      );
      expect(learning['あい\t愛'], greaterThan(learning['あい\t藍']!));
    },
  );

  test('merges kana variants while preserving other language histories', () {
    final learning = {'アイ\t愛': 9, 'あい\t愛': 5, 'english:ai\tAI': 6};
    CandidateLearning.record(
      learning,
      reading: 'アイ',
      text: '藍',
      explicitSelection: true,
    );
    expect(learning.containsKey('アイ\t愛'), isFalse);
    expect(learning['あい\t愛'], 4);
    expect(learning['english:ai\tAI'], 6);
    expect(learning['あい\t藍'], greaterThan(4));
  });

  test(
    'migrates legacy English scores and matches case without Japanese leakage',
    () {
      final learning = {
        'Hel\tHello': 10,
        'english:hel\thello': 7,
        'はろー\thelloworld': 30,
      };
      CandidateLearning.record(
        learning,
        reading: 'HEL',
        text: 'HELLO',
        english: true,
        explicitSelection: true,
      );
      expect(learning['english:hel\tHELLO'], 14);
      expect(learning.containsKey('Hel\tHello'), isFalse);
      expect(learning.containsKey('english:hel\thello'), isFalse);
      final texts = const EnglishConverter()
          .candidates(
            input: 'Hel',
            options: ConversionOptions(learning: learning),
          )
          .map((candidate) => candidate.text)
          .toList();
      expect(texts.first, 'HELLO');
      expect(texts[1], 'Hel');
      expect(texts, isNot(contains('Helloworld')));
    },
  );

  test('English learning follows the word as more letters are typed', () {
    const learning = {'english:he\thelium': 8};
    const english = EnglishConverter();
    final texts = english
        .candidates(
          input: 'heli',
          options: const ConversionOptions(learning: learning),
        )
        .map((candidate) => candidate.text);
    expect(texts, ['helium', 'heli']);
    expect(
      english
          .candidates(
            input: 'heli',
            options: const ConversionOptions(
              learning: learning,
              learningEnabled: false,
            ),
          )
          .map((candidate) => candidate.text),
      ['heli'],
    );
  });

  test('legacy English learning does not enter Japanese candidates', () {
    const learning = {'hello\tHello': 10, 'へろー\t日本語': 4};

    expect(
      CandidateLearning.entries(learning).map((candidate) => candidate.text),
      ['日本語'],
    );
    expect(
      CandidateLearning.entries(
        learning,
        english: true,
      ).map((candidate) => candidate.text),
      ['Hello'],
    );
  });

  test('invalid learning does not affect valid candidates', () {
    final learning = <String, int>{};
    CandidateLearning.record(learning, reading: '', text: '語');
    CandidateLearning.record(learning, reading: 'よみ\t別', text: '語');
    CandidateLearning.record(learning, reading: 'よみ', text: ' ');
    expect(learning, isEmpty);
    expect(
      CandidateLearning.entries({'broken': 8, 'よみ\t': 1, 'よみ\t語': -1}),
      isEmpty,
    );
  });

  test('context choices stay local and separate from general learning', () {
    final learning = <String, int>{};
    CandidateLearning.recordContext(
      learning,
      leftContext: '今日は',
      reading: 'あめ',
      text: '飴',
    );
    expect(CandidateLearning.entries(learning), isEmpty);
    expect(
      CandidateLearning.contextScores(
        learning,
        leftContext: '今日は',
        reading: 'あめ',
      ),
      {'飴': 4},
    );
    expect(
      CandidateLearning.contextScores(
        learning,
        leftContext: '明日は',
        reading: 'あめ',
      ),
      isEmpty,
    );
  });
}
