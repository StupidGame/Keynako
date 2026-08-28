import 'package:azookey_flutter/models/app_data.dart';
import 'package:azookey_flutter/models/azookey_hotfix_dictionary.dart';
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
    data.themes[0] = data.themes.first.copyWith(
      backgroundImage: '/app/theme_backgrounds/classic.image',
      keyOpacity: 0.45,
    );
    data.azooKeyHotfixDictionary = const AzooKeyHotfixDictionary(
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
    data.azooKeyHotfixLatestTag = 'v1';
    data.azooKeyHotfixLastCheckDate = DateTime.utc(2026, 8, 1, 12);

    final decoded = AppData.decode(data.encode());

    expect(decoded.settings['live_conversion'], isFalse);
    expect(decoded.customTabs.single.keys.single.tap.value, 'こんにちは');
    expect(decoded.learning['にほん\t日本'], 3);
    expect(decoded.themes, hasLength(3));
    expect(
      decoded.themes.first.backgroundImage,
      '/app/theme_backgrounds/classic.image',
    );
    expect(decoded.themes.first.keyOpacity, 0.45);
    expect(decoded.azooKeyHotfixDictionary?.entries.single.word, 'azooKey');
    expect(decoded.azooKeyHotfixLatestTag, 'v1');
    expect(decoded.azooKeyHotfixLastCheckDate, DateTime.utc(2026, 8, 1, 12));
  });

  test('detects edits that need to be re-sent to Keynako', () {
    const entry = UserDictionaryEntry(
      id: 1,
      ruby: 'あずーきー',
      word: 'azooKey',
      isPersonName: true,
      shared: true,
      importance: 4,
    );

    expect(
      entry.hasSameSharedPayload(
        ruby: 'あずーきー',
        word: 'azooKey',
        isVerb: false,
        isPersonName: true,
        isPlaceName: false,
        importance: 4,
      ),
      isTrue,
    );
    expect(
      entry.hasSameSharedPayload(
        ruby: 'あずーきー',
        word: 'AzooKey',
        isVerb: false,
        isPersonName: true,
        isPlaceName: false,
        importance: 4,
      ),
      isFalse,
    );
    expect(
      entry.hasSameSharedPayload(
        ruby: 'あずーきー',
        word: 'azooKey',
        isVerb: false,
        isPersonName: true,
        isPlaceName: false,
        importance: 5,
      ),
      isFalse,
    );
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
    expect(data.themes.first.keyOpacity, 0.72);
  });

  test('uses a transparent key default for an older image theme', () {
    final theme = KeyboardThemeConfig.fromJson({
      'id': 'image',
      'name': '画像',
      'backgroundColor': 0xffffffff,
      'keyColor': 0xffffffff,
      'specialKeyColor': 0xffeeeeee,
      'textColor': 0xff000000,
      'accentColor': 0xff0000ff,
      'backgroundImage': '/tmp/image.png',
    });

    expect(theme.keyOpacity, 0.72);
  });

  test('restores selectable phrase tabs while decoding older state', () {
    final data = AppData.defaults()
      ..customTabs.add(
        const CustomTabData(
          id: 'phrases',
          name: '定型文',
          kind: 'scroll',
          columns: 2,
          rows: 5,
          keys: [],
        ),
      );

    final json = data.toJson()..['tabBar'] = <String>['japanese'];
    final decoded = AppData.fromJson(json);

    expect(decoded.tabBar, ['japanese', 'custom:phrases']);
  });
}
