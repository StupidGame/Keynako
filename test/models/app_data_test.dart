import 'package:azookey_flutter/models/app_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('round trips all portable state', () {
    final data = AppData.defaults();
    data.settings['live_conversion'] = false;
    data.customTabs.add(
      const CustomTabData(
        id: 'phrases',
        name: '定型文',
        kind: 'scroll',
        columns: 2,
        rows: 5,
        keys: [
          CustomKeyData(
            id: 'hello',
            name: '挨拶',
            label: '挨拶',
            tap: KeyActionData(type: 'input', value: 'こんにちは'),
          ),
        ],
      ),
    );
    data.learning['にほん\t日本'] = 3;

    final decoded = AppData.decode(data.encode());

    expect(decoded.settings['live_conversion'], isFalse);
    expect(decoded.customTabs.single.keys.single.tap.value, 'こんにちは');
    expect(decoded.learning['にほん\t日本'], 3);
    expect(decoded.themes, hasLength(3));
  });

  test('fills new defaults when loading an older state', () {
    final data = AppData.fromJson({
      'schemaVersion': 0,
      'settings': {'live_conversion': false},
    });

    expect(data.schemaVersion, currentSchemaVersion);
    expect(data.settings['live_conversion'], isFalse);
    expect(data.settings['keyboard_type'], 'flick');
    expect(data.settings['half_kana_candidate'], isTrue);
    expect(data.settings['unicode_candidate'], isTrue);
    expect(data.themes, isNotEmpty);
  });
}
