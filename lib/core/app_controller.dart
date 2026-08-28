import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';

import '../input/azookey_hotfix_sync.dart';
import '../models/app_data.dart';
import '../models/custard.dart';
import 'platform_service.dart';

class AppController extends ChangeNotifier {
  AppController({
    StateStorage? storage,
    PlatformService? platform,
    AzooKeyHotfixSynchronizer? azooKeyHotfixSynchronizer,
    DateTime Function()? now,
  }) {
    final resolvedPlatform = platform ?? PlatformService();
    this.platform = resolvedPlatform;
    _storage = storage ?? resolvedPlatform;
    _azooKeyHotfixSynchronizer =
        azooKeyHotfixSynchronizer ??
        (storage == null && platform == null
            ? AzooKeyHotfixSyncClient()
            : null);
    _now = now ?? DateTime.now;
  }

  late final StateStorage _storage;
  late final PlatformService platform;
  late final AzooKeyHotfixSynchronizer? _azooKeyHotfixSynchronizer;
  late final DateTime Function() _now;
  AppData data = AppData.defaults();
  bool initialized = false;
  Object? loadError;
  bool azooKeyHotfixSyncing = false;
  Object? azooKeyHotfixSyncError;
  Timer? _saveTimer;
  Future<bool>? _azooKeyHotfixSyncTask;

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
    if (_azooKeyHotfixSynchronizer != null) {
      unawaited(_runAutomaticAzooKeyHotfixSync());
    }
  }

  Future<void> _runAutomaticAzooKeyHotfixSync() async {
    try {
      await syncAzooKeyHotfixDictionary();
    } catch (_) {
      // A maintenance failure must not interrupt app launch. The error remains
      // available to the settings UI and a later launch can retry it.
    }
  }

  Future<bool> syncAzooKeyHotfixDictionary({bool force = false}) {
    final running = _azooKeyHotfixSyncTask;
    if (running != null) return running;
    final task = _performAzooKeyHotfixSync(force: force);
    _azooKeyHotfixSyncTask = task;
    return task.whenComplete(() {
      _azooKeyHotfixSyncTask = null;
    });
  }

  Future<bool> _performAzooKeyHotfixSync({required bool force}) async {
    final synchronizer = _azooKeyHotfixSynchronizer;
    if (synchronizer == null ||
        (!force &&
            !isAzooKeyHotfixCheckDue(
              data.azooKeyHotfixLastCheckDate,
              _now(),
            ))) {
      return false;
    }

    azooKeyHotfixSyncing = true;
    azooKeyHotfixSyncError = null;
    notifyListeners();
    try {
      final result = await synchronizer.checkAndUpdate(
        cachedTag: data.azooKeyHotfixLatestTag,
      );
      if (result.dictionaryChanged) {
        data.azooKeyHotfixDictionary = result.dictionary;
        data.azooKeyHotfixLatestTag = result.latestTag;
      }
      data.azooKeyHotfixLastCheckDate = _now();
      notifyListeners();
      await flush();
      return result.dictionaryChanged;
    } catch (error) {
      azooKeyHotfixSyncError = error;
      rethrow;
    } finally {
      azooKeyHotfixSyncing = false;
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
    data.userDictionary.sort(
      (a, b) => a.ruby == b.ruby
          ? b.importance.compareTo(a.importance)
          : a.ruby.compareTo(b.ruby),
    );
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
    data.custards.removeWhere((item) => item.identifier == tab.id);
    final index = data.customTabs.indexWhere((item) => item.id == tab.id);
    if (index < 0) {
      data.customTabs.add(tab);
    } else {
      data.customTabs[index] = tab;
    }
    final tabBarItem = 'custom:${tab.id}';
    if (tab.addToTabBar) {
      if (!data.tabBar.contains(tabBarItem)) data.tabBar.add(tabBarItem);
    } else {
      data.tabBar.removeWhere((item) => item == tabBarItem);
    }
    _changed();
  }

  void removeCustomTab(String id) {
    data.customTabs.removeWhere((item) => item.id == id);
    data.tabBar.removeWhere((item) => item == 'custom:$id');
    _changed();
  }

  List<AzooKeyCustard> importCustards(String source) {
    final imported = AzooKeyCustard.decodeMany(source);
    for (final custard in imported) {
      data.customTabs.removeWhere((item) => item.id == custard.identifier);
      final index = data.custards.indexWhere(
        (item) => item.identifier == custard.identifier,
      );
      if (index < 0) {
        data.custards.add(custard);
      } else {
        data.custards[index] = custard;
      }
      final tab = 'custom:${custard.identifier}';
      if (!data.tabBar.contains(tab)) data.tabBar.add(tab);
    }
    _changed(immediate: true);
    return imported;
  }

  Future<List<AzooKeyCustard>> importCustardsFromUrl(String source) async {
    final requested = Uri.tryParse(source.trim());
    if (requested == null ||
        !requested.hasAuthority ||
        !const {'http', 'https'}.contains(requested.scheme)) {
      throw const FormatException('httpまたはhttpsのURLを入力してください。');
    }
    final uri = resolveCustardUrl(requested);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(uri);
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/json, text/plain',
      );
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'Keynako Custard Import',
      );
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('HTTP ${response.statusCode}で取得に失敗しました。', uri: uri);
      }
      const maximumBytes = 10 * 1024 * 1024;
      if (response.contentLength > maximumBytes) {
        throw const FormatException('Custardファイルが10MBを超えています。');
      }
      final bytes = <int>[];
      await for (final chunk in response) {
        bytes.addAll(chunk);
        if (bytes.length > maximumBytes) {
          throw const FormatException('Custardファイルが10MBを超えています。');
        }
      }
      return importCustards(utf8.decode(bytes));
    } on TimeoutException {
      throw const HttpException('Custardの取得がタイムアウトしました。');
    } finally {
      client.close(force: true);
    }
  }

  void removeCustard(String identifier) {
    data.custards.removeWhere((item) => item.identifier == identifier);
    data.tabBar.removeWhere((item) => item == 'custom:$identifier');
    _changed();
  }

  void replaceCustomKey(CustomKeyData key) {
    if (key.target != 'standalone') {
      data.customKeys.removeWhere(
        (item) => item.target == key.target && item.id != key.id,
      );
    }
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

@visibleForTesting
Uri resolveCustardUrl(Uri uri) {
  if (uri.host == 'custard.azookey.com' && uri.path.startsWith('/tab/')) {
    return uri.replace(path: uri.path.replaceFirst('/tab/', '/api/tab/'));
  }
  if (uri.host == 'github.com') {
    final segments = uri.pathSegments;
    if (segments.length >= 5 && segments[2] == 'blob') {
      return Uri.https(
        'raw.githubusercontent.com',
        <String>[
          segments[0],
          segments[1],
          segments[3],
          ...segments.skip(4),
        ].join('/'),
      );
    }
  }
  if (uri.host == 'gist.github.com' &&
      uri.pathSegments.length >= 2 &&
      uri.pathSegments.last != 'raw') {
    return uri.replace(path: '${uri.path}/raw');
  }
  return uri;
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
