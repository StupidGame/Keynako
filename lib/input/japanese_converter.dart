import '../models/app_data.dart';

class ConversionCandidate {
  const ConversionCandidate({
    required this.text,
    required this.reading,
    this.source = 'system',
    this.score = 0,
  });

  final String text;
  final String reading;
  final String source;
  final int score;

  ConversionCandidate copyWith({int? score}) => ConversionCandidate(
    text: text,
    reading: reading,
    source: source,
    score: score ?? this.score,
  );
}

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
    required AppData data,
    bool romanInput = false,
  }) {
    if (input.isEmpty) return const [];
    final reading = romanInput ? romanToHiragana(input) : input;
    final values = <ConversionCandidate>[
      ConversionCandidate(text: reading, reading: reading, score: 100),
    ];

    for (final entry in data.userDictionary) {
      if (entry.ruby == reading) {
        values.add(
          ConversionCandidate(
            text: entry.isTemplateMode ? _renderTemplate(entry) : entry.word,
            reading: reading,
            source: 'user',
            score: 340 + entry.importance * 20,
          ),
        );
      }
    }
    for (final value in _dictionary[reading] ?? const <String>[]) {
      values.add(
        ConversionCandidate(text: value, reading: reading, score: 250),
      );
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
    if (data.settings['half_kana_candidate'] == true) {
      values.add(
        ConversionCandidate(
          text: katakanaToHalfWidth(katakana),
          reading: reading,
          source: 'half-kana',
          score: 78,
        ),
      );
    }
    if (romanInput && data.settings['full_roman_candidate'] == true) {
      values.add(
        ConversionCandidate(
          text: _asciiToFullWidth(input),
          reading: reading,
          source: 'full-width',
          score: 68,
        ),
      );
    }
    if (romanInput && data.settings['unicode_candidate'] == true) {
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
    if (data.settings['emoji_dictionary_enabled'] == true) {
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
    if (data.settings['kaomoji_dictionary_enabled'] == true) {
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

    if (romanInput && data.settings['roman_english_candidate'] == true) {
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
      final learned = data.settings['memory_learining_styple_setting'] == 2
          ? 0
          : data.learning['$reading\t${candidate.text}'] ?? 0;
      final scored = candidate.copyWith(score: candidate.score + learned * 50);
      final previous = unique[candidate.text];
      if (previous == null || scored.score > previous.score) {
        unique[candidate.text] = scored;
      }
    }
    final result = unique.values.toList()
      ..sort((left, right) => right.score.compareTo(left.score));
    return result;
  }

  String _renderTemplate(UserDictionaryEntry entry) {
    final now = DateTime.now();
    final literal = entry.formatLiteral ?? entry.word;
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
