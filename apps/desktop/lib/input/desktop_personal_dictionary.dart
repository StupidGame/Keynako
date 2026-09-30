import 'dart:io';

import 'package:keynako_conversion/keynako_conversion.dart';

abstract interface class PersonalDictionaryRepository {
  Future<List<ConversionDictionaryEntry>> load();
  Future<void> save(List<ConversionDictionaryEntry> entries);
}

class DesktopPersonalDictionaryRepository
    implements PersonalDictionaryRepository {
  DesktopPersonalDictionaryRepository({this.file});

  final File? file;
  static int _temporaryFileId = 0;

  File get _dictionaryFile {
    if (file != null) return file!;
    final environment = Platform.environment;
    if (Platform.isWindows) {
      final root = environment['LOCALAPPDATA'];
      if (root != null && root.isNotEmpty) {
        return File('$root\\Keynako\\user_dictionary.tsv');
      }
    } else if (Platform.isMacOS) {
      final root = environment['HOME'];
      if (root != null && root.isNotEmpty) {
        return File(
          '$root/Library/Application Support/Keynako/user_dictionary.tsv',
        );
      }
    } else {
      final root = environment['XDG_DATA_HOME'];
      if (root != null && root.isNotEmpty) {
        return File('$root/keynako/user_dictionary.tsv');
      }
      final home = environment['HOME'];
      if (home != null && home.isNotEmpty) {
        return File('$home/.local/share/keynako/user_dictionary.tsv');
      }
    }
    return File('${Directory.systemTemp.path}/Keynako/user_dictionary.tsv');
  }

  @override
  Future<List<ConversionDictionaryEntry>> load() async {
    final active = _dictionaryFile;
    if (!await active.exists()) return const [];
    return NativeSharedDictionaryCodec.decode(await active.readAsString())
        .entries;
  }

  @override
  Future<void> save(List<ConversionDictionaryEntry> entries) async {
    final active = _dictionaryFile;
    await active.parent.create(recursive: true);
    final content = NativeSharedDictionaryCodec.encode(
      SharedDictionarySnapshot(
        revision: 'local',
        version: '1',
        lastUpdate: DateTime.now().toUtc().toIso8601String(),
        entries: entries,
      ),
    );
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
