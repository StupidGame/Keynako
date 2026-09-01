import 'dart:io';

import 'package:keynako_conversion/keynako_conversion.dart';

const Duration desktopSharedDictionaryInterval = Duration(minutes: 5);
const String refreshSharedDictionaryCommand = '--refresh-shared-dictionary';
const String refreshSharedDictionaryIfDueCommand =
    '--refresh-shared-dictionary-if-due';

abstract interface class SharedDictionaryRepository {
  Future<SharedDictionarySnapshot?> load();
  Future<bool> isRefreshDue();
  Future<SharedDictionarySnapshot> refresh();
}

Future<int?> runSharedDictionaryCommand(
  List<String> arguments, {
  SharedDictionaryRepository? repository,
}) async {
  final force = arguments.contains(refreshSharedDictionaryCommand);
  final ifDue = arguments.contains(refreshSharedDictionaryIfDueCommand);
  if (!force && !ifDue) return null;
  final activeRepository = repository ?? DesktopSharedDictionaryRepository();
  try {
    if (force || await activeRepository.isRefreshDue()) {
      await activeRepository.refresh();
    }
    return 0;
  } on Object {
    return 1;
  }
}

class DesktopSharedDictionaryRepository implements SharedDictionaryRepository {
  DesktopSharedDictionaryRepository({KeynakoSharedDictionaryClient? client})
    : _client = client ?? KeynakoSharedDictionaryClient();

  final KeynakoSharedDictionaryClient _client;
  File? _activeFile;

  @override
  Future<SharedDictionarySnapshot?> load() async {
    for (final file in [..._writableFiles(), ..._bundledFiles()]) {
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
    for (final file in _writableFiles()) {
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
    for (final file in _writableFiles()) {
      if (await file.exists()) return file;
    }
    return null;
  }

  List<File> _writableFiles() {
    final paths = <String>[];
    if (Platform.isWindows) {
      final programData = Platform.environment['ProgramData'];
      final localAppData = Platform.environment['LOCALAPPDATA'];
      if (localAppData != null && localAppData.isNotEmpty) {
        paths.add('$localAppData\\Keynako\\shared_dictionary.tsv');
      }
      if (programData != null && programData.isNotEmpty) {
        paths.add('$programData\\Keynako\\shared_dictionary.tsv');
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

  List<File> _bundledFiles() {
    final executable = File(Platform.resolvedExecutable);
    final directory = executable.parent;
    if (Platform.isWindows) {
      return [File('${directory.path}\\ime\\bundled_shared_dictionary.tsv')];
    }
    if (Platform.isMacOS) {
      return [
        File(
          '${directory.parent.path}/Resources/bundled_shared_dictionary.tsv',
        ),
      ];
    }
    return [File('${directory.path}/bundled_shared_dictionary.tsv')];
  }
}
