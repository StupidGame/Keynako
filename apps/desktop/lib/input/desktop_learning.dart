import 'dart:convert';
import 'dart:io';

abstract interface class LearningRepository {
  Future<Map<String, int>> load();
  Future<void> save(Map<String, int> scores);
}

/// Stores only bounded candidate preferences on the local desktop.
class DesktopLearningRepository implements LearningRepository {
  DesktopLearningRepository({this.file});

  final File? file;
  static int _temporaryFileId = 0;

  File get storageFile {
    if (file != null) return file!;
    final environment = Platform.environment;
    if (Platform.isWindows) {
      final root = environment['LOCALAPPDATA'];
      if (root != null && root.isNotEmpty) {
        return File('$root\\Keynako\\learning.tsv');
      }
    } else if (Platform.isMacOS) {
      final root = environment['HOME'];
      if (root != null && root.isNotEmpty) {
        return File('$root/Library/Application Support/Keynako/learning.tsv');
      }
    } else {
      final root = environment['XDG_DATA_HOME'];
      if (root != null && root.isNotEmpty) {
        return File('$root/keynako/learning.tsv');
      }
      final home = environment['HOME'];
      if (home != null && home.isNotEmpty) {
        return File('$home/.local/share/keynako/learning.tsv');
      }
    }
    return File('${Directory.systemTemp.path}/Keynako/learning.tsv');
  }

  @override
  Future<Map<String, int>> load() async {
    final active = storageFile;
    if (!await active.exists()) {
      if (file != null) return {};
      final legacy = File(
        '${active.parent.path}${Platform.pathSeparator}learning.json',
      );
      if (!await legacy.exists()) return {};
      final migrated = _decodeJson(await legacy.readAsString());
      try {
        await save(migrated);
      } on FileSystemException {
        // Leave the old file intact so it can be retried on the next launch.
      }
      return migrated;
    }
    if (await active.length() > 4 * 1024 * 1024) {
      throw const FormatException('Learning file is too large');
    }
    final source = await active.readAsString();
    return active.path.endsWith('.json')
        ? _decodeJson(source)
        : _decodeTsv(source);
  }

  static Map<String, int> _decodeJson(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map ||
        decoded['version'] != 1 ||
        decoded['scores'] is! Map) {
      throw const FormatException('Learning file is malformed');
    }
    final result = <String, int>{};
    for (final entry in (decoded['scores'] as Map).entries) {
      if (entry.key is! String ||
          entry.value is! int ||
          (entry.key as String).length > 256 ||
          entry.value <= 0) {
        continue;
      }
      result[entry.key as String] = (entry.value as int).clamp(1, 32);
      if (result.length >= 4096) break;
    }
    return result;
  }

  static Map<String, int> _decodeTsv(String source) {
    final result = <String, int>{};
    for (final line in const LineSplitter().convert(source)) {
      if (line.isEmpty) continue;
      final separator = line.lastIndexOf('\t');
      if (separator <= 0) {
        throw const FormatException('Learning file is malformed');
      }
      final key = line.substring(0, separator);
      final score = int.tryParse(line.substring(separator + 1));
      if (key.length > 256 ||
          !key.contains('\t') ||
          score == null ||
          score < 1) {
        throw const FormatException('Learning file is malformed');
      }
      result[key] = score.clamp(1, 32);
      if (result.length > 4096) {
        throw const FormatException('Learning file is too large');
      }
    }
    return result;
  }

  @override
  Future<void> save(Map<String, int> scores) async {
    final active = storageFile;
    await active.parent.create(recursive: true);
    final bounded = scores.entries.toList();
    final retained = bounded.skip(
      bounded.length > 4096 ? bounded.length - 4096 : 0,
    );
    final content = active.path.endsWith('.json')
        ? jsonEncode({
            'version': 1,
            'scores': {for (final entry in retained) entry.key: entry.value},
          })
        : retained
              .where(
                (entry) =>
                    entry.key.contains('\t') &&
                    !entry.key.contains('\n') &&
                    !entry.key.contains('\r') &&
                    entry.value > 0,
              )
              .map((entry) => '${entry.key}\t${entry.value.clamp(1, 32)}\n')
              .join();
    final temporary = File('${active.path}.tmp.$pid.${_temporaryFileId++}');
    try {
      await temporary.writeAsString(content, flush: true);
      try {
        await temporary.rename(active.path);
      } on FileSystemException {
        if (!Platform.isWindows) rethrow;
        await active.writeAsString(content, flush: true);
      }
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }
}
