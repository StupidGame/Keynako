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
