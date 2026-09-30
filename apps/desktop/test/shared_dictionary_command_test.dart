import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keynako_conversion/keynako_conversion.dart';
import 'package:keynako_desktop/input/desktop_shared_dictionary.dart';

void main() {
  test('manual command refreshes even when the cache is current', () async {
    final repository = _CommandRepository(refreshDue: false);

    expect(
      await runSharedDictionaryCommand(const [
        refreshSharedDictionaryCommand,
      ], repository: repository),
      0,
    );
    expect(repository.refreshCount, 1);
  });

  test('periodic command skips a current cache', () async {
    final repository = _CommandRepository(refreshDue: false);

    expect(
      await runSharedDictionaryCommand(const [
        refreshSharedDictionaryIfDueCommand,
      ], repository: repository),
      0,
    );
    expect(repository.refreshCount, 0);
  });

  test(
    'refresh replaces an existing cache and leaves no temporary file',
    () async {
      final directory = await Directory.systemTemp.createTemp('keynako_cache_');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/shared_dictionary.tsv');
      await file.writeAsString(
        NativeSharedDictionaryCodec.encode(
          const SharedDictionarySnapshot(
            revision: 'old',
            version: '1',
            lastUpdate: 'yesterday',
            entries: [],
          ),
        ),
      );
      const updated = SharedDictionarySnapshot(
        revision: 'new',
        version: '2',
        lastUpdate: 'today',
        entries: [],
      );
      final repository = DesktopSharedDictionaryRepository(
        client: _SnapshotClient(updated),
        cacheFile: file,
      );

      await repository.refresh();

      expect(
        NativeSharedDictionaryCodec.decode(await file.readAsString()).revision,
        'new',
      );
      expect(await directory.list().length, 1);
    },
  );

  test('a malformed cache is due for refresh', () async {
    final directory = await Directory.systemTemp.createTemp('keynako_cache_');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/shared_dictionary.tsv');
    await file.writeAsString('# keynako-shared-dictionary-v1\tpartial\n');
    final repository = DesktopSharedDictionaryRepository(cacheFile: file);

    expect(await repository.isRefreshDue(), isTrue);
  });
}

class _SnapshotClient extends KeynakoSharedDictionaryClient {
  _SnapshotClient(this.snapshot);

  final SharedDictionarySnapshot snapshot;

  @override
  Future<SharedDictionarySnapshot> fetch() async => snapshot;
}

class _CommandRepository implements SharedDictionaryRepository {
  _CommandRepository({required this.refreshDue});

  final bool refreshDue;
  var refreshCount = 0;

  @override
  Future<bool> isRefreshDue() async => refreshDue;

  @override
  Future<SharedDictionarySnapshot?> load() async => null;

  @override
  Future<SharedDictionarySnapshot> refresh() async {
    refreshCount += 1;
    return const SharedDictionarySnapshot(
      revision: 'test',
      version: '1',
      lastUpdate: 'today',
      entries: [],
    );
  }
}
