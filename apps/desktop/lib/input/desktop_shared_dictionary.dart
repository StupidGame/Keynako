import 'dart:io';

import 'package:keynako_conversion/keynako_conversion.dart';

const Duration desktopSharedDictionaryInterval = Duration(minutes: 5);

abstract interface class SharedDictionaryRepository {
  Future<SharedDictionarySnapshot?> load();
  Future<bool> isRefreshDue();
  Future<SharedDictionarySnapshot> refresh();
}

class DesktopSharedDictionaryRepository implements SharedDictionaryRepository {
  DesktopSharedDictionaryRepository({KeynakoSharedDictionaryClient? client})
    : _client = client ?? KeynakoSharedDictionaryClient();

  final KeynakoSharedDictionaryClient _client;
  File? _activeFile;

  @override
  Future<SharedDictionarySnapshot?> load() async {
    for (final file in _candidateFiles()) {
      if (!await file.exists()) continue;
      try {
        final snapshot = NativeSharedDictionaryCodec.decode(
          await file.readAsString(),
        );
        _activeFile = file;
        return snapshot;
      } on FormatException {
        continue;
      }
    }
    return null;
  }

  @override
  Future<bool> isRefreshDue() async {
    final file = _activeFile ?? await _firstExistingFile();
    if (file == null) return true;
    final modified = await file.lastModified();
    return !modified
        .add(desktopSharedDictionaryInterval)
        .isAfter(DateTime.now());
  }

  @override
  Future<SharedDictionarySnapshot> refresh() async {
    final snapshot = await _client.fetch();
    final content = NativeSharedDictionaryCodec.encode(snapshot);
    Object? lastError;
    for (final file in _candidateFiles()) {
      try {
        await file.parent.create(recursive: true);
        await file.writeAsString(content, flush: true);
        _activeFile = file;
        return snapshot;
      } on FileSystemException catch (error) {
        lastError = error;
      }
    }
    throw FileSystemException(
      '共有辞書を保存できませんでした。',
      null,
      lastError is FileSystemException ? lastError.osError : null,
    );
  }

  Future<File?> _firstExistingFile() async {
    for (final file in _candidateFiles()) {
      if (await file.exists()) return file;
    }
    return null;
  }

  List<File> _candidateFiles() {
    final paths = <String>[];
    if (Platform.isWindows) {
      final programData = Platform.environment['ProgramData'];
      final localAppData = Platform.environment['LOCALAPPDATA'];
      if (programData != null && programData.isNotEmpty) {
        paths.add('$programData\\Keynako\\shared_dictionary.tsv');
      }
      if (localAppData != null && localAppData.isNotEmpty) {
        paths.add('$localAppData\\Keynako\\shared_dictionary.tsv');
      }
    } else if (Platform.isMacOS) {
      final home = Platform.environment['HOME'];
      if (home != null && home.isNotEmpty) {
        paths.add(
          '$home/Library/Application Support/Keynako/shared_dictionary.tsv',
        );
      }
    } else {
      final home = Platform.environment['HOME'];
      final xdg = Platform.environment['XDG_DATA_HOME'];
      if (xdg != null && xdg.isNotEmpty) {
        paths.add('$xdg/keynako/shared_dictionary.tsv');
      }
      if (home != null && home.isNotEmpty) {
        paths.add('$home/.local/share/keynako/shared_dictionary.tsv');
      }
    }
    if (paths.isEmpty) {
      paths.add('${Directory.systemTemp.path}/Keynako/shared_dictionary.tsv');
    }
    return paths.map(File.new).toList(growable: false);
  }
}
