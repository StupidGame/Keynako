import 'azookey_special_candidates.dart';
import 'candidate_learning.dart';
import 'conversion_candidate.dart';
import 'conversion_options.dart';

class _DictionaryMatch {
  const _DictionaryMatch(this.end, this.value, this.score, this.registered);

  final int end;
  final String value;
  final int score;
  final bool registered;
}

class _DictionaryPath {
  const _DictionaryPath(
    this.text,
    this.score,
    this.words,
    this.registeredWords,
  );

  final String text;
  final int score;
  final int words;
  final int registeredWords;
}

/// Stateless, platform-independent Japanese input transforms and candidates.
class JapaneseConverter {
  const JapaneseConverter();

  static const Map<String, String> _roman = {
    'kya': 'きゃ',
    'kyu': 'きゅ',
    'kyo': 'きょ',
    'gya': 'ぎゃ',
    'gyu': 'ぎゅ',
    'gyo': 'ぎょ',
    'sha': 'しゃ',
    'shu': 'しゅ',
    'sho': 'しょ',
    'sya': 'しゃ',
    'syu': 'しゅ',
    'syo': 'しょ',
    'ja': 'じゃ',
    'ju': 'じゅ',
    'jo': 'じょ',
    'jya': 'じゃ',
    'jyu': 'じゅ',
    'jyo': 'じょ',
    'cha': 'ちゃ',
    'chu': 'ちゅ',
    'cho': 'ちょ',
    'cya': 'ちゃ',
    'cyu': 'ちゅ',
    'cyo': 'ちょ',
    'tya': 'ちゃ',
    'tyu': 'ちゅ',
    'tyo': 'ちょ',
    'nya': 'にゃ',
    'nyu': 'にゅ',
    'nyo': 'にょ',
    'hya': 'ひゃ',
    'hyu': 'ひゅ',
    'hyo': 'ひょ',
    'bya': 'びゃ',
    'byu': 'びゅ',
    'byo': 'びょ',
    'pya': 'ぴゃ',
    'pyu': 'ぴゅ',
    'pyo': 'ぴょ',
    'mya': 'みゃ',
    'myu': 'みゅ',
    'myo': 'みょ',
    'rya': 'りゃ',
    'ryu': 'りゅ',
    'ryo': 'りょ',
    'fa': 'ふぁ',
    'fi': 'ふぃ',
    'fe': 'ふぇ',
    'fo': 'ふぉ',
    'va': 'ゔぁ',
    'vi': 'ゔぃ',
    'vu': 'ゔ',
    've': 'ゔぇ',
    'vo': 'ゔぉ',
    'tsa': 'つぁ',
    'tsi': 'つぃ',
    'tse': 'つぇ',
    'tso': 'つぉ',
    'she': 'しぇ',
    'che': 'ちぇ',
    'je': 'じぇ',
    'thi': 'てぃ',
    'dhi': 'でぃ',
    'twu': 'とぅ',
    'dwu': 'どぅ',
    'kwa': 'くぁ',
    'gwa': 'ぐぁ',
    'ye': 'いぇ',
    'wi': 'うぃ',
    'we': 'うぇ',
    'wo': 'を',
    'ka': 'か',
    'ki': 'き',
    'ku': 'く',
    'ke': 'け',
    'ko': 'こ',
    'ga': 'が',
    'gi': 'ぎ',
    'gu': 'ぐ',
    'ge': 'げ',
    'go': 'ご',
    'sa': 'さ',
    'si': 'し',
    'shi': 'し',
    'su': 'す',
    'se': 'せ',
    'so': 'そ',
    'za': 'ざ',
    'zi': 'じ',
    'ji': 'じ',
    'zu': 'ず',
    'ze': 'ぜ',
    'zo': 'ぞ',
    'ta': 'た',
    'ti': 'ち',
    'chi': 'ち',
    'tu': 'つ',
    'tsu': 'つ',
    'te': 'て',
    'to': 'と',
    'da': 'だ',
    'di': 'ぢ',
    'du': 'づ',
    'de': 'で',
    'do': 'ど',
    'na': 'な',
    'ni': 'に',
    'nu': 'ぬ',
    'ne': 'ね',
    'no': 'の',
    'ha': 'は',
    'hi': 'ひ',
    'hu': 'ふ',
    'fu': 'ふ',
    'he': 'へ',
    'ho': 'ほ',
    'ba': 'ば',
    'bi': 'び',
    'bu': 'ぶ',
    'be': 'べ',
    'bo': 'ぼ',
    'pa': 'ぱ',
    'pi': 'ぴ',
    'pu': 'ぷ',
    'pe': 'ぺ',
    'po': 'ぽ',
    'ma': 'ま',
    'mi': 'み',
    'mu': 'む',
    'me': 'め',
    'mo': 'も',
    'ya': 'や',
    'yu': 'ゆ',
    'yo': 'よ',
    'ra': 'ら',
    'ri': 'り',
    'ru': 'る',
    're': 'れ',
    'ro': 'ろ',
    'wa': 'わ',
    'nn': 'ん',
    'la': 'ぁ',
    'li': 'ぃ',
    'lu': 'ぅ',
    'le': 'ぇ',
    'lo': 'ぉ',
    'xa': 'ぁ',
    'xi': 'ぃ',
    'xu': 'ぅ',
    'xe': 'ぇ',
    'xo': 'ぉ',
    'lya': 'ゃ',
    'lyu': 'ゅ',
    'lyo': 'ょ',
    'xya': 'ゃ',
    'xyu': 'ゅ',
    'xyo': 'ょ',
    'ltu': 'っ',
    'xtu': 'っ',
    'a': 'あ',
    'i': 'い',
    'u': 'う',
    'e': 'え',
    'o': 'お',
    '-': 'ー',
    ',': '、',
    '.': '。',
    '!': '！',
    '?': '？',
  };

  static const Map<String, List<String>> _dictionary = {
    'あい': ['愛', '藍', '相'],
    'あう': ['会う', '合う', '遭う'],
    'あさ': ['朝', '麻'],
    'あした': ['明日'],
    'ありがとう': ['ありがとう', '有難う'],
    'いま': ['今', '居間'],
    'うえ': ['上'],
    'おはよう': ['おはよう', 'お早う'],
    'おねがい': ['お願い'],
    'かく': ['書く', '描く', '各'],
    'きょう': ['今日', '京'],
    'こんにちは': ['こんにちは'],
    'ことば': ['言葉'],
    'じかん': ['時間'],
    'すき': ['好き'],
    'せってい': ['設定'],
    'だいじょうぶ': ['大丈夫'],
    'つかう': ['使う'],
    'でんわ': ['電話'],
    'にほん': ['日本', '二本'],
    'にほんご': ['日本語'],
    'へんかん': ['変換'],
    'ほんじつ': ['本日'],
    'また': ['また'],
    'みる': ['見る', '観る'],
    'もじ': ['文字'],
    'よろしく': ['よろしく', '宜しく'],
    'わたし': ['私'],
  };

  static const Map<String, List<String>> _emoji = {
    'えがお': ['😊', '😄', '🙂'],
    'はーと': ['❤️', '💕', '💙'],
    'ほし': ['⭐️', '🌟', '✨'],
    'おめでとう': ['🎉', '🎊'],
    'ありがとう': ['🙏', '😊'],
    'ねこ': ['🐈', '🐱'],
    'いぬ': ['🐕', '🐶'],
  };

  static const Map<String, List<String>> _kaomoji = {
    'えがお': ['( ´ ▽ ` )', '(^_^)', '(๑˃̵ᴗ˂̵)'],
    'かなしい': ['( ; _ ; )', '(´；ω；`)'],
    'おこる': ['(｀・ω・´)', '( ` ω ´ )'],
    'よろしく': ['m(_ _)m', 'よろしく(・ω・)ノ'],
  };

  static const Map<String, String> _voicedHalfKana = {
    'ガ': 'ｶﾞ',
    'ギ': 'ｷﾞ',
    'グ': 'ｸﾞ',
    'ゲ': 'ｹﾞ',
    'ゴ': 'ｺﾞ',
    'ザ': 'ｻﾞ',
    'ジ': 'ｼﾞ',
    'ズ': 'ｽﾞ',
    'ゼ': 'ｾﾞ',
    'ゾ': 'ｿﾞ',
    'ダ': 'ﾀﾞ',
    'ヂ': 'ﾁﾞ',
    'ヅ': 'ﾂﾞ',
    'デ': 'ﾃﾞ',
    'ド': 'ﾄﾞ',
    'バ': 'ﾊﾞ',
    'ビ': 'ﾋﾞ',
    'ブ': 'ﾌﾞ',
    'ベ': 'ﾍﾞ',
    'ボ': 'ﾎﾞ',
    'パ': 'ﾊﾟ',
    'ピ': 'ﾋﾟ',
    'プ': 'ﾌﾟ',
    'ペ': 'ﾍﾟ',
    'ポ': 'ﾎﾟ',
    'ヴ': 'ｳﾞ',
    'ヷ': 'ﾜﾞ',
    'ヺ': 'ｦﾞ',
  };

  static final Map<int, String> _halfKana = () {
    const full =
        '。「」、・ヲァィゥェォャュョッーアイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワヰヱヲン';
    const half =
        '｡｢｣､･ｦｧｨｩｪｫｬｭｮｯｰｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓﾔﾕﾖﾗﾘﾙﾚﾛﾜｲｴｦﾝ';
    final sources = full.runes.toList();
    final targets = half.runes.toList();
    return {
      for (var index = 0; index < sources.length; index++)
        sources[index]: String.fromCharCode(targets[index]),
    };
  }();

  String romanToHiragana(String input) {
    final lower = input.toLowerCase();
    final result = StringBuffer();
    var index = 0;
    while (index < lower.length) {
      final current = lower[index];
      if (index + 1 < lower.length &&
          current == lower[index + 1] &&
          'bcdfghjklmpqrstvwxyz'.contains(current) &&
          current != 'n') {
        result.write('っ');
        index += 1;
        continue;
      }
      if (current == 'n' &&
          index + 1 < lower.length &&
          !'aiueoyn'.contains(lower[index + 1])) {
        result.write('ん');
        index += 1;
        continue;
      }
      String? replacement;
      var consumed = 0;
      for (final length in const [4, 3, 2, 1]) {
        if (index + length > lower.length) continue;
        final part = lower.substring(index, index + length);
        final candidate = _roman[part];
        if (candidate != null) {
          replacement = candidate;
          consumed = length;
          break;
        }
      }
      if (replacement != null) {
        result.write(replacement);
        index += consumed;
      } else {
        result.write(input[index]);
        index += 1;
      }
    }
    if (lower.endsWith('n') && !lower.endsWith('nn')) {
      final value = result.toString();
      if (value.endsWith('n')) {
        return '${value.substring(0, value.length - 1)}ん';
      }
    }
    return result.toString();
  }

  String hiraganaToKatakana(String value) {
    return String.fromCharCodes(
      value.runes.map((code) {
        if (code >= 0x3041 && code <= 0x3096) return code + 0x60;
        return code;
      }),
    );
  }

  String katakanaToHiragana(String value) {
    return String.fromCharCodes(
      value.runes.map((code) {
        if (code >= 0x30a1 && code <= 0x30f6) return code - 0x60;
        return code;
      }),
    );
  }

  String katakanaToHalfWidth(String value) {
    final output = StringBuffer();
    for (final rune in value.runes) {
      final character = String.fromCharCode(rune);
      output.write(_voicedHalfKana[character] ?? _halfKana[rune] ?? character);
    }
    return output.toString();
  }

  List<ConversionCandidate> candidates({
    required String input,
    bool romanInput = false,
    int predictionLimit = 32,
    ConversionOptions options = const ConversionOptions(),
  }) {
    if (input.isEmpty) return const [];
    final sourceReading = romanInput ? romanToHiragana(input) : input;
    final reading = katakanaToHiragana(sourceReading);
    final values = <ConversionCandidate>[
      ConversionCandidate(text: reading, reading: reading, score: 100),
    ];
    final prefixPredictions = <ConversionCandidate>[];
    final exactLearning = <String, int>{};
    final predictionLearning = <String, int>{};

    // Recover selected words even when they came from Zenzai or a dictionary
    // that is no longer loaded. A longer learned reading is only a completion.
    if (options.learningEnabled) {
      for (final entry in CandidateLearning.entries(options.learning)) {
        final ruby = entry.reading;
        final text = entry.text;
        if (text.trim().isEmpty || !ruby.startsWith(reading)) continue;
        final exact = ruby == reading;
        if (!exact && predictionLimit <= 0) continue;
        final scores = exact ? exactLearning : predictionLearning;
        if (entry.score > (scores[text] ?? 0)) scores[text] = entry.score;
        (exact ? values : prefixPredictions).add(
          ConversionCandidate(
            text: text,
            reading: ruby,
            source: exact ? 'learned' : 'learned-prediction',
            score: exact ? 250 : 180 - (ruby.length - reading.length) * 4,
          ),
        );
      }
    }

    for (final entry in options.userDictionary) {
      final ruby = katakanaToHiragana(entry.reading);
      if (ruby == reading) {
        values.add(
          ConversionCandidate(
            text: entry.template ? _renderTemplate(entry) : entry.value,
            reading: reading,
            source: 'user',
            score: 340 + entry.importance.clamp(1, 5).toInt() * 20,
          ),
        );
      } else if (predictionLimit > 0 &&
          ruby.length > reading.length &&
          ruby.startsWith(reading)) {
        prefixPredictions.add(
          ConversionCandidate(
            text: entry.template ? _renderTemplate(entry) : entry.value,
            reading: ruby,
            source: 'user-prediction',
            score:
                220 +
                entry.importance.clamp(1, 5).toInt() * 20 -
                (ruby.length - reading.length) * 4,
          ),
        );
      } else if (ruby.isNotEmpty && reading.startsWith(ruby)) {
        values.add(
          ConversionCandidate(
            text:
                (entry.template ? _renderTemplate(entry) : entry.value) +
                reading.substring(ruby.length),
            reading: reading,
            source: 'user-prefix',
            score:
                180 +
                entry.importance.clamp(1, 5).toInt() * 20 -
                (reading.length - ruby.length) * 4,
          ),
        );
      }
    }
    for (final value in _dictionary[reading] ?? const <String>[]) {
      values.add(
        ConversionCandidate(text: value, reading: reading, score: 250),
      );
    }
    for (final path in _dictionaryCombinations(
      reading,
      options.userDictionary,
    )) {
      values.add(
        ConversionCandidate(
          text: path.text,
          reading: reading,
          source: 'user-combination',
          score: 300 + (path.score ~/ 4).clamp(0, 50),
        ),
      );
    }
    for (final value in AzooKeySpecialCandidates.complete(reading)) {
      values.add(
        ConversionCandidate(
          text: value,
          reading: reading,
          source: 'special',
          score: 165,
        ),
      );
    }
    if (predictionLimit > 0) {
      for (final value in AzooKeySpecialCandidates.emailAddresses(input)) {
        prefixPredictions.add(
          ConversionCandidate(
            text: value,
            reading: value,
            source: 'special-prediction',
            score: 170,
          ),
        );
      }
    }
    if (predictionLimit > 0) {
      for (final entry in _dictionary.entries) {
        if (entry.key.length <= reading.length ||
            !entry.key.startsWith(reading)) {
          continue;
        }
        for (final value in entry.value) {
          prefixPredictions.add(
            ConversionCandidate(
              text: value,
              reading: entry.key,
              source: 'dictionary-prediction',
              score: 180 - (entry.key.length - reading.length) * 4,
            ),
          );
        }
      }
    }
    final katakana = hiraganaToKatakana(reading);
    if (katakana != reading) {
      values.add(
        ConversionCandidate(
          text: katakana,
          reading: reading,
          source: 'katakana',
          score: 80,
        ),
      );
    }
    if (options.halfWidthKanaCandidate) {
      values.add(
        ConversionCandidate(
          text: katakanaToHalfWidth(katakana),
          reading: reading,
          source: 'half-kana',
          score: 78,
        ),
      );
    }
    if (romanInput && options.fullWidthRomanCandidate) {
      values.add(
        ConversionCandidate(
          text: _asciiToFullWidth(input),
          reading: reading,
          source: 'full-width',
          score: 68,
        ),
      );
    }
    if (romanInput && options.unicodeCandidate) {
      final unicode = _unicodeCandidate(input);
      if (unicode != null) {
        values.add(
          ConversionCandidate(
            text: unicode,
            reading: reading,
            source: 'unicode',
            score: 300,
          ),
        );
      }
    }
    if (options.emojiCandidate) {
      for (final value in _emoji[reading] ?? const <String>[]) {
        values.add(
          ConversionCandidate(
            text: value,
            reading: reading,
            source: 'emoji',
            score: 120,
          ),
        );
      }
    }
    if (options.kaomojiCandidate) {
      for (final value in _kaomoji[reading] ?? const <String>[]) {
        values.add(
          ConversionCandidate(
            text: value,
            reading: reading,
            source: 'kaomoji',
            score: 110,
          ),
        );
      }
    }

    if (romanInput && options.romanEnglishCandidate) {
      values.add(
        ConversionCandidate(
          text: input,
          reading: reading,
          source: 'english',
          score: 70,
        ),
      );
    }

    final unique = <String, ConversionCandidate>{};
    for (final candidate in values) {
      if (candidate.text.trim().isEmpty) continue;
      final learned = (exactLearning[candidate.text] ?? 0).clamp(0, 1000);
      final scored = candidate.copyWith(score: candidate.score + learned * 50);
      final previous = unique[candidate.text];
      if (previous == null || scored.score > previous.score) {
        unique[candidate.text] = scored;
      }
    }
    final result = _rank(unique.values);
    final uniquePredictions = <String, ConversionCandidate>{};
    for (final candidate in prefixPredictions) {
      if (candidate.text.trim().isEmpty) continue;
      final learned = (predictionLearning[candidate.text] ?? 0).clamp(0, 1000);
      final scored = candidate.copyWith(score: candidate.score + learned * 50);
      final previous = uniquePredictions[candidate.text];
      if (previous == null || scored.score > previous.score) {
        uniquePredictions[candidate.text] = scored;
      }
    }
    final predictions = _rank(uniquePredictions.values);
    final liveCandidate =
        options.liveConversion && sourceReading == reading && result.isNotEmpty
        ? result.first
        : null;
    final pinned = <ConversionCandidate>[
      if (liveCandidate != null &&
          liveCandidate.text != reading &&
          liveCandidate.text != katakana)
        liveCandidate,
      unique[reading] ??
          ConversionCandidate(
            text: reading,
            reading: reading,
            source: 'hiragana',
            score: 100,
          ),
      if (katakana != reading)
        unique[katakana] ??
            ConversionCandidate(
              text: katakana,
              reading: reading,
              source: 'katakana',
              score: 80,
            ),
    ];
    final pinnedTexts = pinned.map((candidate) => candidate.text).toSet();
    final baseCandidates = [
      ...pinned,
      ...result.where((candidate) => !pinnedTexts.contains(candidate.text)),
    ];
    final baseTexts = baseCandidates.map((candidate) => candidate.text).toSet();
    final visiblePredictions = predictions
        .where((candidate) => !baseTexts.contains(candidate.text))
        .take(predictionLimit < 0 ? 0 : predictionLimit)
        .toList(growable: false);
    // Keep complete conversions ahead of completions, including when live
    // conversion is off. Kana shortcuts retain their established positions.
    final conversions = baseCandidates
        .where(
          (candidate) =>
              pinnedTexts.contains(candidate.text) ||
              const {
                'user',
                'user-combination',
                'system',
                'learned',
                'special',
              }.contains(candidate.source),
        )
        .toList();
    final conversionTexts = conversions
        .map((candidate) => candidate.text)
        .toSet();
    return [
      ...conversions,
      ...visiblePredictions,
      ...baseCandidates.where(
        (candidate) => !conversionTexts.contains(candidate.text),
      ),
    ];
  }

  List<ConversionCandidate> _rank(Iterable<ConversionCandidate> candidates) {
    final indexed = candidates.indexed.toList()
      ..sort((left, right) {
        final score = right.$2.score.compareTo(left.$2.score);
        return score != 0 ? score : left.$1.compareTo(right.$1);
      });
    return indexed.map((entry) => entry.$2).toList();
  }

  List<_DictionaryPath> _dictionaryCombinations(
    String reading,
    List<ConversionDictionaryEntry> entries,
  ) {
    if (reading.length < 2) return const [];
    final matches = List.generate(reading.length, (_) => <_DictionaryMatch>[]);
    var hasRegisteredMatch = false;
    void add(String ruby, String value, int importance, bool registered) {
      if (ruby.isEmpty || value.isEmpty || ruby.length > reading.length) return;
      var start = reading.indexOf(ruby);
      while (start >= 0) {
        matches[start].add(
          _DictionaryMatch(
            start + ruby.length,
            value,
            (registered ? ruby.length * 18 - 28 : ruby.length * 15 - 30) +
                importance * 4,
            registered,
          ),
        );
        if (registered) hasRegisteredMatch = true;
        start = reading.indexOf(ruby, start + 1);
      }
    }

    for (final entry in entries) {
      if (entry.template) continue;
      add(
        katakanaToHiragana(entry.reading),
        entry.value,
        entry.importance.clamp(1, 5).toInt(),
        true,
      );
    }
    if (!hasRegisteredMatch) return const [];
    for (final entry in _dictionary.entries) {
      for (final value in entry.value.take(2)) {
        add(entry.key, value, 3, false);
      }
    }

    final beams = List.generate(reading.length + 1, (_) => <_DictionaryPath>[]);
    beams[0].add(const _DictionaryPath('', 0, 0, 0));
    void push(int end, _DictionaryPath path) {
      final paths = beams[end]..add(path);
      if (paths.length > 48) {
        paths.sort((a, b) => b.score.compareTo(a.score));
        paths.removeRange(16, paths.length);
      }
    }

    for (var index = 0; index < reading.length; index++) {
      final current = beams[index]..sort((a, b) => b.score.compareTo(a.score));
      for (final path in current.take(16)) {
        push(
          index + 1,
          _DictionaryPath(
            path.text + reading.substring(index, index + 1),
            path.score - 3,
            path.words,
            path.registeredWords,
          ),
        );
        for (final match in matches[index]) {
          push(
            match.end,
            _DictionaryPath(
              path.text + match.value,
              path.score + match.score,
              path.words + 1,
              path.registeredWords + (match.registered ? 1 : 0),
            ),
          );
        }
      }
    }
    final ranked =
        beams.last
            .where((path) => path.words >= 2 && path.registeredWords >= 1)
            .toList()
          ..sort((a, b) => b.score.compareTo(a.score));
    final unique = <String, _DictionaryPath>{};
    for (final path in ranked) {
      if (path.text != reading) unique.putIfAbsent(path.text, () => path);
      if (unique.length >= 8) break;
    }
    return unique.values.toList();
  }

  String _renderTemplate(ConversionDictionaryEntry entry) {
    final now = DateTime.now();
    final literal = entry.format ?? entry.value;
    String two(int value) => value.toString().padLeft(2, '0');
    return literal
        .replaceAll('yyyy', now.year.toString().padLeft(4, '0'))
        .replaceAll('MM', two(now.month))
        .replaceAll('dd', two(now.day))
        .replaceAll('HH', two(now.hour))
        .replaceAll('mm', two(now.minute))
        .replaceAll('ss', two(now.second));
  }

  String _asciiToFullWidth(String value) => String.fromCharCodes(
    value.runes.map((rune) {
      if (rune == 0x20) return 0x3000;
      if (rune >= 0x21 && rune <= 0x7e) return rune + 0xfee0;
      return rune;
    }),
  );

  String? _unicodeCandidate(String value) {
    final match = RegExp(
      r'^u\+?([0-9a-f]{1,6})$',
      caseSensitive: false,
    ).firstMatch(value);
    if (match == null) return null;
    final codePoint = int.tryParse(match.group(1)!, radix: 16);
    if (codePoint == null ||
        codePoint > 0x10ffff ||
        codePoint >= 0xd800 && codePoint <= 0xdfff) {
      return null;
    }
    return String.fromCharCode(codePoint);
  }
}
