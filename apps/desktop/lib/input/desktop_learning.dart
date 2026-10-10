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

  File get _learningFile {
    if (file != null) return file!;
    final environment = Platform.environment;
    if (Platform.isWindows) {
      final root = environment['LOCALAPPDATA'];
      if (root != null && root.isNotEmpty) {
        return File('$root\\Keynako\\learning.json');
      }
    } else if (Platform.isMacOS) {
      final root = environment['HOME'];
      if (root != null && root.isNotEmpty) {
        return File('$root/Library/Application Support/Keynako/learning.json');
      }
    } else {
      final root = environment['XDG_DATA_HOME'];
      if (root != null && root.isNotEmpty) {
        return File('$root/keynako/learning.json');
      }
      final home = environment['HOME'];
      if (home != null && home.isNotEmpty) {
        return File('$home/.local/share/keynako/learning.json');
      }
    }
    return File('${Directory.systemTemp.path}/Keynako/learning.json');
  }

  @override
  Future<Map<String, int>> load() async {
    final active = _learningFile;
    if (!await active.exists()) return {};
    if (await active.length() > 1024 * 1024) {
      throw const FormatException('Learning file is too large');
    }
    final decoded = jsonDecode(await active.readAsString());
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

  @override
  Future<void> save(Map<String, int> scores) async {
    final active = _learningFile;
    await active.parent.create(recursive: true);
    final bounded = scores.entries.toList();
    final retained = bounded.skip(
      bounded.length > 4096 ? bounded.length - 4096 : 0,
    );
    final content = jsonEncode({
      'version': 1,
      'scores': {for (final entry in retained) entry.key: entry.value},
    });
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
