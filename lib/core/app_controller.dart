import 'dart:async';

import 'package:flutter/widgets.dart';

import '../models/app_data.dart';
import 'platform_service.dart';

class AppController extends ChangeNotifier {
  AppController({StateStorage? storage, PlatformService? platform})
    : platform = platform ?? PlatformService(),
      _storage = storage ?? platform ?? PlatformService();

  final StateStorage _storage;
  final PlatformService platform;
  AppData data = AppData.defaults();
  bool initialized = false;
  Object? loadError;
  Timer? _saveTimer;

  Future<void> initialize() async {
    try {
      final value = await _storage.load();
      if (value != null && value.trim().isNotEmpty) {
        data = AppData.decode(value);
      }
    } catch (error) {
      loadError = error;
      data = AppData.defaults();
    } finally {
      initialized = true;
      notifyListeners();
    }
  }

  T setting<T>(String key, T fallback) {
    final value = data.settings[key];
    return value is T ? value : fallback;
  }

  void setSetting(String key, Object value) {
    data.settings[key] = value;
    _changed();
  }

  void completeOnboarding() {
    data.onboardingCompleted = true;
    _changed(immediate: true);
  }

  void addOrUpdateDictionaryEntry(UserDictionaryEntry entry) {
    final index = data.userDictionary.indexWhere((item) => item.id == entry.id);
    if (index < 0) {
      data.userDictionary.add(entry);
    } else {
      data.userDictionary[index] = entry;
    }
    data.userDictionary.sort((a, b) => a.ruby.compareTo(b.ruby));
    _changed();
  }

  void removeDictionaryEntry(int id) {
    data.userDictionary.removeWhere((item) => item.id == id);
    _changed();
  }

  int nextDictionaryId() {
    if (data.userDictionary.isEmpty) return 0;
    return data.userDictionary
            .map((entry) => entry.id)
            .reduce((left, right) => left > right ? left : right) +
        1;
  }

  void replaceTheme(KeyboardThemeConfig theme) {
    final index = data.themes.indexWhere((item) => item.id == theme.id);
    if (index < 0) {
      data.themes.add(theme);
    } else {
      data.themes[index] = theme;
    }
    _changed();
  }

  void removeTheme(String id) {
    if (const {'classic', 'midnight', 'azuki'}.contains(id)) return;
    data.themes.removeWhere((item) => item.id == id);
    if (data.lightThemeId == id) data.lightThemeId = 'classic';
    if (data.darkThemeId == id) data.darkThemeId = 'midnight';
    _changed();
  }

  void selectTheme(String id, {required bool dark}) {
    if (dark) {
      data.darkThemeId = id;
    } else {
      data.lightThemeId = id;
    }
    _changed();
  }

  void replaceCustomTab(CustomTabData tab) {
    final index = data.customTabs.indexWhere((item) => item.id == tab.id);
    if (index < 0) {
      data.customTabs.add(tab);
      if (tab.addToTabBar && !data.tabBar.contains('custom:${tab.id}')) {
        data.tabBar.add('custom:${tab.id}');
      }
    } else {
      data.customTabs[index] = tab;
    }
    _changed();
  }

  void removeCustomTab(String id) {
    data.customTabs.removeWhere((item) => item.id == id);
    data.tabBar.removeWhere((item) => item == 'custom:$id');
    _changed();
  }

  void replaceCustomKey(CustomKeyData key) {
    final index = data.customKeys.indexWhere((item) => item.id == key.id);
    if (index < 0) {
      data.customKeys.add(key);
    } else {
      data.customKeys[index] = key;
    }
    _changed();
  }

  void removeCustomKey(String id) {
    data.customKeys.removeWhere((item) => item.id == id);
    _changed();
  }

  void reorderTabBar(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    final item = data.tabBar.removeAt(oldIndex);
    data.tabBar.insert(newIndex, item);
    _changed();
  }

  void resetLearning() {
    data.learning.clear();
    data.settings['memory_reset_setting'] =
        'need${DateTime.now().microsecondsSinceEpoch}';
    _changed(immediate: true);
  }

  Future<int> importContacts() async {
    final contacts = await platform.importContacts();
    var id = nextDictionaryId();
    var added = 0;
    for (final contact in contacts) {
      final word = contact['word'] ?? '';
      if (word.isEmpty ||
          data.userDictionary.any((entry) => entry.word == word)) {
        continue;
      }
      data.userDictionary.add(
        UserDictionaryEntry(
          id: id++,
          ruby: contact['ruby'] ?? word,
          word: word,
          isPersonName: true,
        ),
      );
      added += 1;
    }
    if (added > 0) _changed(immediate: true);
    return added;
  }

  Future<void> importJson(String value) async {
    data = AppData.decode(value);
    notifyListeners();
    await flush();
  }

  void _changed({bool immediate = false}) {
    notifyListeners();
    _saveTimer?.cancel();
    if (immediate) {
      unawaited(flush());
    } else {
      _saveTimer = Timer(const Duration(milliseconds: 180), flush);
    }
  }

  Future<void> flush() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    await _storage.save(data.encode());
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }
}

class AppControllerScope extends InheritedNotifier<AppController> {
  const AppControllerScope({
    required AppController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static AppController of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<AppControllerScope>();
    assert(
      scope != null,
      'AppControllerScope was not found in the widget tree',
    );
    return scope!.notifier!;
  }
}
