import 'package:azookey_flutter/core/app_controller.dart';
import 'package:azookey_flutter/core/platform_service.dart';
import 'package:azookey_flutter/models/app_data.dart';
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
}
