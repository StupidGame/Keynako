import 'package:azookey_flutter/core/app_controller.dart';
import 'package:azookey_flutter/core/platform_service.dart';
import 'package:azookey_flutter/input/azookey_hotfix_sync.dart';
import 'package:azookey_flutter/models/app_data.dart';
import 'package:azookey_flutter/models/azookey_hotfix_dictionary.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryStorage implements StateStorage {
  String? value;

  @override
  Future<String?> load() async => value;

  @override
  Future<void> save(String state) async {
    value = state;
  }
}

class _HotfixSynchronizer implements AzooKeyHotfixSynchronizer {
  _HotfixSynchronizer(this.result);

  final AzooKeyHotfixSyncResult result;
  var calls = 0;
  String? receivedCachedTag;

  @override
  Future<AzooKeyHotfixSyncResult> checkAndUpdate({String? cachedTag}) async {
    calls += 1;
    receivedCachedTag = cachedTag;
    return result;
  }
}

const _hotfixDictionary = AzooKeyHotfixDictionary(
  metadata: AzooKeyHotfixMetadata(
    status: 'active',
    name: 'data_v1.json',
    description: 'test',
    version: '1.0',
    lastUpdate: '2025-05-04T16:30:00.00',
  ),
  entries: [
    AzooKeyHotfixEntry(
      word: 'azooKey',
      ruby: 'あずーきー',
      wordWeight: -15,
      lcid: 1288,
      rcid: 1288,
      mid: 501,
      date: '2025-05-04',
      author: '@ensan-hcl',
    ),
  ],
);

void main() {
  test('resolves azooKey share URLs to the Custard API', () {
    expect(
      resolveCustardUrl(Uri.parse('https://custard.azookey.com/tab/example-id'))
          .toString(),
      'https://custard.azookey.com/api/tab/example-id',
    );
  });

  test('resolves GitHub and Gist page URLs to raw content', () {
    expect(
      resolveCustardUrl(
        Uri.parse('https://github.com/owner/repo/blob/main/layout.custard'),
      ).toString(),
      'https://raw.githubusercontent.com/owner/repo/main/layout.custard',
    );
    expect(
      resolveCustardUrl(
        Uri.parse('https://gist.github.com/owner/0123456789abcdef'),
      ).toString(),
      'https://gist.github.com/owner/0123456789abcdef/raw',
    );
  });

  test('keeps edited custom tabs in sync with the keyboard tab bar', () {
    final controller = AppController(storage: _MemoryStorage());
    const hidden = CustomTabData(
      id: 'phrases',
      name: '定型文',
      kind: 'scroll',
      columns: 2,
      rows: 5,
      keys: [],
      addToTabBar: false,
    );

    controller.replaceCustomTab(hidden);
    expect(controller.data.tabBar, isNot(contains('custom:phrases')));

    controller.replaceCustomTab(hidden.copyWith(addToTabBar: true));
    expect(controller.data.tabBar, contains('custom:phrases'));

    controller.replaceCustomTab(hidden);
    expect(controller.data.tabBar, isNot(contains('custom:phrases')));
    controller.dispose();
  });

  test('imports a custom array and exposes it as a selectable tab', () {
    final controller = AppController(storage: _MemoryStorage());
    const source = '''
{
  "identifier": "numbers",
  "language": "none",
  "input_style": "direct",
  "metadata": {"custard_version": "1.2", "display_name": "数字"},
  "interface": {
    "key_style": "pc_style",
    "key_layout": {"type": "grid_fit", "row_count": 1, "column_count": 2},
    "keys": [
      {"specifier_type":"grid_fit","specifier":{"x":0,"y":0,"width":1,"height":1},"key_type":"custom","key":{"design":{"color":"normal","label":{"text":"1"}},"press_actions":[{"type":"input","text":"1"}],"longpress_actions":{"start":[],"repeat":[]},"variations":[]}},
      {"specifier_type":"grid_fit","specifier":{"x":1,"y":0,"width":1,"height":1},"key_type":"custom","key":{"design":{"color":"normal","label":{"text":"2"}},"press_actions":[{"type":"input","text":"2"}],"longpress_actions":{"start":[],"repeat":[]},"variations":[]}}
    ]
  }
}
''';

    final imported = controller.importCustards(source);

    expect(imported.single.identifier, 'numbers');
    expect(controller.data.custards.single.displayName, '数字');
    expect(controller.data.tabBar, contains('custom:numbers'));
    expect(controller.data.customTabs, isEmpty);
    controller.dispose();
  });

  test('syncs and persists the Keynako hotfix dictionary', () async {
    final storage = _MemoryStorage();
    final synchronizer = _HotfixSynchronizer(
      const AzooKeyHotfixSyncResult(
        latestTag: 'v2',
        dictionaryChanged: true,
        dictionary: _hotfixDictionary,
      ),
    );
    final now = DateTime.utc(2026, 8, 27, 12);
    final controller = AppController(
      storage: storage,
      azooKeyHotfixSynchronizer: synchronizer,
      now: () => now,
    );
    controller.data.azooKeyHotfixLatestTag = 'v1';

    final updated = await controller.syncAzooKeyHotfixDictionary(force: true);

    expect(updated, isTrue);
    expect(synchronizer.receivedCachedTag, 'v1');
    expect(controller.data.azooKeyHotfixLatestTag, 'v2');
    expect(
      controller.data.azooKeyHotfixDictionary?.entries.single.word,
      'azooKey',
    );
    expect(controller.data.azooKeyHotfixLastCheckDate, now);
    final persisted = AppData.decode(storage.value!);
    expect(persisted.azooKeyHotfixLatestTag, 'v2');
    expect(persisted.azooKeyHotfixDictionary?.entries, hasLength(1));
    controller.dispose();
  });

  test('skips automatic hotfix checks made within five minutes', () async {
    final now = DateTime.utc(2026, 8, 27, 12);
    final synchronizer = _HotfixSynchronizer(
      const AzooKeyHotfixSyncResult(latestTag: 'v1', dictionaryChanged: false),
    );
    final controller = AppController(
      storage: _MemoryStorage(),
      azooKeyHotfixSynchronizer: synchronizer,
      now: () => now,
    );
    controller.data.azooKeyHotfixLastCheckDate = now.subtract(
      const Duration(minutes: 4),
    );

    final updated = await controller.syncAzooKeyHotfixDictionary();

    expect(updated, isFalse);
    expect(synchronizer.calls, 0);
    controller.dispose();
  });
}
