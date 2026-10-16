import 'dart:convert';
import 'dart:io';

import 'package:keynako_conversion/keynako_conversion.dart';

import 'desktop_learning.dart';

/// The mobile AppData JSON is the interchange format. Unknown mobile fields
/// stay in the sidecar so a desktop round trip does not discard them.
class PortableProfile {
  PortableProfile._(this.json, this.dictionary, this.learning, this.settings);

  final Map<String, dynamic> json;
  final List<ConversionDictionaryEntry> dictionary;
  final Map<String, int> learning;
  final Map<String, dynamic> settings;

  static PortableProfile decode(String source) {
    if (source.length > 32 * 1024 * 1024) {
      throw const FormatException('バックアップが大きすぎる');
    }
    final decoded = jsonDecode(source);
    if (decoded is! Map ||
        decoded['settings'] is! Map ||
        decoded['userDictionary'] is! List ||
        decoded['learning'] is! Map) {
      throw const FormatException('設定・辞書・学習履歴を含むJSONが必要');
    }
    final json = Map<String, dynamic>.from(decoded);
    final rawSettings = Map<String, dynamic>.from(decoded['settings'] as Map);
    final dictionary = <ConversionDictionaryEntry>[];
    for (final item in decoded['userDictionary'] as List) {
      if (item is! Map) throw const FormatException('辞書の形式が不正');
      final entry = Map<String, dynamic>.from(item);
      final reading = entry['ruby'];
      final word = entry['word'];
      if (reading is! String ||
          word is! String ||
          reading.trim().isEmpty ||
          word.trim().isEmpty) {
        throw const FormatException('辞書の読みと単語が必要');
      }
      dictionary.add(
        ConversionDictionaryEntry(
          reading: reading,
          value: word,
          importance: ((entry['importance'] as num?)?.toInt() ?? 3).clamp(1, 5),
          template: entry['isTemplateMode'] == true,
          format: entry['formatLiteral'] as String?,
        ),
      );
      if (dictionary.length > 10000) throw const FormatException('辞書が大きすぎる');
    }
    final scores = <String, int>{};
    for (final item in (decoded['learning'] as Map).entries) {
      if (item.key is! String || item.value is! num) {
        throw const FormatException('学習履歴の形式が不正');
      }
      final key = item.key as String;
      final score = (item.value as num).toInt();
      if (key.length > 256 || !key.contains('\t') || score < 0) {
        throw const FormatException('学習履歴の形式が不正');
      }
      if (score > 0) scores[key] = score.clamp(1, 32);
      if (scores.length > 4096) throw const FormatException('学習履歴が大きすぎる');
    }
    return PortableProfile._(json, dictionary, scores, rawSettings);
  }

  String export({
    required List<ConversionDictionaryEntry> dictionary,
    required Map<String, int> learning,
    required bool liveConversion,
    required bool zenzaiEnabled,
    int? automaticCompletionStrength,
  }) {
    final result = Map<String, dynamic>.of(json);
    final exportedSettings = Map<String, dynamic>.of(settings);
    exportedSettings['live_conversion'] = liveConversion;
    exportedSettings['enable_zenzai'] = zenzaiEnabled;
    if (automaticCompletionStrength != null) {
      exportedSettings['automatic_completion_strength'] =
          automaticCompletionStrength;
    }
    result['settings'] = exportedSettings;
    final original = <String, Map<String, dynamic>>{};
    for (final item in json['userDictionary'] as List) {
      if (item is! Map) continue;
      final entry = Map<String, dynamic>.from(item);
      original['${entry['ruby']}\t${entry['word']}'] = entry;
    }
    var nextId = 0;
    for (final item in original.values) {
      final id = item['id'];
      if (id is num && id.toInt() >= nextId) nextId = id.toInt() + 1;
    }
    final exportedDictionary = <Map<String, dynamic>>[];
    for (final entry in dictionary) {
      final saved = original['${entry.reading}\t${entry.value}'];
      exportedDictionary.add({
        ...?saved,
        'id': saved?['id'] ?? nextId++,
        'ruby': entry.reading,
        'word': entry.value,
        'importance': entry.importance,
        'isTemplateMode': entry.template || saved?['isTemplateMode'] == true,
        if (entry.format != null) 'formatLiteral': entry.format,
      });
    }
    result['userDictionary'] = exportedDictionary;
    result['learning'] = {
      for (final entry in learning.entries)
        if (entry.value > 0) entry.key: entry.value.clamp(1, 32),
    };
    return jsonEncode(result);
  }

  static PortableProfile empty() => decode(
    jsonEncode({
      'schemaVersion': 7,
      'settings': <String, dynamic>{},
      'userDictionary': <Object>[],
      'learning': <String, int>{},
    }),
  );
}

class DesktopPortableProfileRepository {
  DesktopPortableProfileRepository({this.file});

  final File? file;

  File get storageFile =>
      file ??
      File(
        '${DesktopLearningRepository().storageFile.parent.path}'
        '${Platform.pathSeparator}portable_profile.json',
      );

  File get imeSettingsFile => File(
    '${storageFile.parent.path}${Platform.pathSeparator}ime_settings.tsv',
  );

  Future<Map<String, dynamic>> loadImeSettings() async {
    if (!await imeSettingsFile.exists()) return {};
    final result = <String, dynamic>{};
    for (final line in const LineSplitter().convert(
      await imeSettingsFile.readAsString(),
    )) {
      final parts = line.split('\t');
      if (parts.length != 2) continue;
      if (parts[0] == 'live_conversion') result[parts[0]] = parts[1] == '1';
      if (parts[0] == 'automatic_completion_strength') {
        final strength = int.tryParse(parts[1]);
        if (strength != null) result[parts[0]] = strength.clamp(0, 4);
      }
    }
    return result;
  }

  Future<void> saveImeSettings(Map<String, dynamic> settings) async {
    final live = settings['live_conversion'] != false;
    final strength = settings['automatic_completion_strength'] is num
        ? (settings['automatic_completion_strength'] as num).toInt().clamp(0, 4)
        : 0;
    final active = imeSettingsFile;
    await active.parent.create(recursive: true);
    await active.writeAsString(
      'live_conversion\t${live ? 1 : 0}\n'
      'automatic_completion_strength\t$strength\n',
      flush: true,
    );
  }

  Future<PortableProfile> load() async {
    final active = storageFile;
    if (!await active.exists()) return PortableProfile.empty();
    if (await active.length() > 32 * 1024 * 1024) {
      throw const FormatException('バックアップが大きすぎる');
    }
    return PortableProfile.decode(await active.readAsString());
  }

  Future<void> save(String source) async {
    PortableProfile.decode(source);
    final active = storageFile;
    await active.parent.create(recursive: true);
    final temporary = File('${active.path}.tmp.$pid');
    try {
      await temporary.writeAsString(source, flush: true);
      try {
        await temporary.rename(active.path);
      } on FileSystemException {
        if (!Platform.isWindows) rethrow;
        await active.writeAsString(source, flush: true);
      }
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }
}
