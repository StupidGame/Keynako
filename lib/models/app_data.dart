import 'dart:convert';

import 'custard.dart';

const int currentSchemaVersion = 2;

const Map<String, dynamic> defaultKeyboardSettings = {
  'keyboard_type': 'flick',
  'keyboard_type_en': 'flick',
  'live_conversion': true,
  'automatic_completion_strength': 1,
  'enable_zenzai': false,
  'zenzai_effort': 1,
  'typography_roman_candidate': true,
  'roman_english_candidate': true,
  'sound_enable_setting': false,
  'enable_key_haptics': false,
  'use_OS_user_dict': true,
  'use_move_cursor_bar_beta': true,
  'display_cursor_bar_automatically': false,
  'use_shift_key': false,
  'keep_deprecated_shift_key_behavior': true,
  'use_next_candidate_key': false,
  'hide_reset_button_in_one_handed_mode': false,
  'stop_learning_when_search': false,
  'enable_paste_button_on_flick_cursorbar_key': false,
  'enable_contact_import': false,
  'enable_clipboard_history_manager_tab': false,
  'enable_wrong_conversion_report': false,
  'wrong_conversion_report_frequency': 10,
  'wrong_conversion_include_context': false,
  'wrong_conversion_report_user_nickname': '',
  'result_view_font_size': -1.0,
  'key_view_font_size': -1.0,
  'flick_sensitivity_setting': 1.0,
  'keyboard_height_scale': 1.0,
  'memory_learining_styple_setting': 0,
  'marked_text_setting_beta': 'disabled',
  'half_kana_candidate': true,
  'full_roman_candidate': true,
  'unicode_candidate': true,
  'display_tab_bar_button': true,
  'emoji_dictionary_enabled': true,
  'kaomoji_dictionary_enabled': false,
};

class UserDictionaryEntry {
  const UserDictionaryEntry({
    required this.id,
    required this.ruby,
    required this.word,
    this.isVerb = false,
    this.isPersonName = false,
    this.isPlaceName = false,
    this.shared = false,
    this.isTemplateMode = false,
    this.formatLiteral,
  });

  final int id;
  final String ruby;
  final String word;
  final bool isVerb;
  final bool isPersonName;
  final bool isPlaceName;
  final bool shared;
  final bool isTemplateMode;
  final String? formatLiteral;

  UserDictionaryEntry copyWith({
    int? id,
    String? ruby,
    String? word,
    bool? isVerb,
    bool? isPersonName,
    bool? isPlaceName,
    bool? shared,
    bool? isTemplateMode,
    String? formatLiteral,
    bool clearFormatLiteral = false,
  }) {
    return UserDictionaryEntry(
      id: id ?? this.id,
      ruby: ruby ?? this.ruby,
      word: word ?? this.word,
      isVerb: isVerb ?? this.isVerb,
      isPersonName: isPersonName ?? this.isPersonName,
      isPlaceName: isPlaceName ?? this.isPlaceName,
      shared: shared ?? this.shared,
      isTemplateMode: isTemplateMode ?? this.isTemplateMode,
      formatLiteral: clearFormatLiteral
          ? null
          : (formatLiteral ?? this.formatLiteral),
    );
  }

  factory UserDictionaryEntry.fromJson(Map<String, dynamic> json) {
    return UserDictionaryEntry(
      id: (json['id'] as num?)?.toInt() ?? 0,
      ruby: json['ruby'] as String? ?? '',
      word: json['word'] as String? ?? '',
      isVerb: json['isVerb'] as bool? ?? false,
      isPersonName: json['isPersonName'] as bool? ?? false,
      isPlaceName: json['isPlaceName'] as bool? ?? false,
      shared: json['shared'] as bool? ?? false,
      isTemplateMode: json['isTemplateMode'] as bool? ?? false,
      formatLiteral: json['formatLiteral'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'ruby': ruby,
    'word': word,
    'isVerb': isVerb,
    'isPersonName': isPersonName,
    'isPlaceName': isPlaceName,
    'shared': shared,
    'isTemplateMode': isTemplateMode,
    'formatLiteral': formatLiteral,
  };
}

class KeyboardThemeConfig {
  const KeyboardThemeConfig({
    required this.id,
    required this.name,
    required this.backgroundColor,
    required this.keyColor,
    required this.specialKeyColor,
    required this.textColor,
    required this.accentColor,
    this.backgroundImage,
  });

  final String id;
  final String name;
  final int backgroundColor;
  final int keyColor;
  final int specialKeyColor;
  final int textColor;
  final int accentColor;
  final String? backgroundImage;

  KeyboardThemeConfig copyWith({
    String? id,
    String? name,
    int? backgroundColor,
    int? keyColor,
    int? specialKeyColor,
    int? textColor,
    int? accentColor,
    String? backgroundImage,
    bool clearBackgroundImage = false,
  }) {
    return KeyboardThemeConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      keyColor: keyColor ?? this.keyColor,
      specialKeyColor: specialKeyColor ?? this.specialKeyColor,
      textColor: textColor ?? this.textColor,
      accentColor: accentColor ?? this.accentColor,
      backgroundImage: clearBackgroundImage
          ? null
          : (backgroundImage ?? this.backgroundImage),
    );
  }

  factory KeyboardThemeConfig.fromJson(Map<String, dynamic> json) {
    return KeyboardThemeConfig(
      id: json['id'] as String? ?? 'theme',
      name: json['name'] as String? ?? 'テーマ',
      backgroundColor: (json['backgroundColor'] as num?)?.toInt() ?? 0xffd1d5db,
      keyColor: (json['keyColor'] as num?)?.toInt() ?? 0xffffffff,
      specialKeyColor: (json['specialKeyColor'] as num?)?.toInt() ?? 0xffaeb4bd,
      textColor: (json['textColor'] as num?)?.toInt() ?? 0xff111827,
      accentColor: (json['accentColor'] as num?)?.toInt() ?? 0xff2563eb,
      backgroundImage: json['backgroundImage'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'backgroundColor': backgroundColor,
    'keyColor': keyColor,
    'specialKeyColor': specialKeyColor,
    'textColor': textColor,
    'accentColor': accentColor,
    'backgroundImage': backgroundImage,
  };
}

class KeyActionData {
  const KeyActionData({required this.type, this.value = ''});

  final String type;
  final String value;

  factory KeyActionData.fromJson(Map<String, dynamic> json) => KeyActionData(
    type: json['type'] as String? ?? 'input',
    value: json['value'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {'type': type, 'value': value};
}

class CustomKeyData {
  const CustomKeyData({
    required this.id,
    required this.name,
    required this.label,
    required this.tap,
    this.target = 'standalone',
    this.left,
    this.up,
    this.right,
    this.down,
    this.longPress,
    this.longPressRepeat,
  });

  final String id;
  final String name;
  final String label;
  final String target;
  final KeyActionData tap;
  final KeyActionData? left;
  final KeyActionData? up;
  final KeyActionData? right;
  final KeyActionData? down;
  final KeyActionData? longPress;
  final KeyActionData? longPressRepeat;

  factory CustomKeyData.fromJson(Map<String, dynamic> json) {
    KeyActionData? action(String key) {
      final value = json[key];
      return value is Map
          ? KeyActionData.fromJson(Map<String, dynamic>.from(value))
          : null;
    }

    return CustomKeyData(
      id: json['id'] as String? ?? 'key',
      name: json['name'] as String? ?? 'カスタムキー',
      label: json['label'] as String? ?? '',
      target: json['target'] as String? ?? 'standalone',
      tap: action('tap') ?? const KeyActionData(type: 'input'),
      left: action('left'),
      up: action('up'),
      right: action('right'),
      down: action('down'),
      longPress: action('longPress'),
      longPressRepeat: action('longPressRepeat'),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'label': label,
    'target': target,
    'tap': tap.toJson(),
    'left': left?.toJson(),
    'up': up?.toJson(),
    'right': right?.toJson(),
    'down': down?.toJson(),
    'longPress': longPress?.toJson(),
    'longPressRepeat': longPressRepeat?.toJson(),
  };
}

class CustomTabData {
  const CustomTabData({
    required this.id,
    required this.name,
    required this.kind,
    required this.columns,
    required this.rows,
    required this.keys,
    this.inputStyle = 'direct',
    this.language = 'ja_JP',
    this.addToTabBar = true,
  });

  final String id;
  final String name;
  final String kind;
  final int columns;
  final int rows;
  final List<CustomKeyData> keys;
  final String inputStyle;
  final String language;
  final bool addToTabBar;

  CustomTabData copyWith({
    String? id,
    String? name,
    String? kind,
    int? columns,
    int? rows,
    List<CustomKeyData>? keys,
    String? inputStyle,
    String? language,
    bool? addToTabBar,
  }) {
    return CustomTabData(
      id: id ?? this.id,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      columns: columns ?? this.columns,
      rows: rows ?? this.rows,
      keys: keys ?? this.keys,
      inputStyle: inputStyle ?? this.inputStyle,
      language: language ?? this.language,
      addToTabBar: addToTabBar ?? this.addToTabBar,
    );
  }

  factory CustomTabData.fromJson(Map<String, dynamic> json) => CustomTabData(
    id: json['id'] as String? ?? 'tab',
    name: json['name'] as String? ?? 'カスタムタブ',
    kind: json['kind'] as String? ?? 'grid',
    columns: (json['columns'] as num?)?.toInt() ?? 4,
    rows: (json['rows'] as num?)?.toInt() ?? 5,
    keys: (json['keys'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (value) => CustomKeyData.fromJson(Map<String, dynamic>.from(value)),
        )
        .toList(),
    inputStyle: json['inputStyle'] as String? ?? 'direct',
    language: json['language'] as String? ?? 'ja_JP',
    addToTabBar: json['addToTabBar'] as bool? ?? true,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'kind': kind,
    'columns': columns,
    'rows': rows,
    'keys': keys.map((value) => value.toJson()).toList(),
    'inputStyle': inputStyle,
    'language': language,
    'addToTabBar': addToTabBar,
  };
}

class AppData {
  AppData({
    required this.schemaVersion,
    required this.settings,
    required this.userDictionary,
    required this.themes,
    required this.lightThemeId,
    required this.darkThemeId,
    required this.customTabs,
    required this.custards,
    required this.customKeys,
    required this.tabBar,
    required this.clipboardHistory,
    required this.learning,
    required this.onboardingCompleted,
  });

  int schemaVersion;
  final Map<String, dynamic> settings;
  final List<UserDictionaryEntry> userDictionary;
  final List<KeyboardThemeConfig> themes;
  String lightThemeId;
  String darkThemeId;
  final List<CustomTabData> customTabs;
  final List<AzooKeyCustard> custards;
  final List<CustomKeyData> customKeys;
  final List<String> tabBar;
  final List<String> clipboardHistory;
  final Map<String, int> learning;
  bool onboardingCompleted;

  factory AppData.defaults() {
    const themes = [
      KeyboardThemeConfig(
        id: 'classic',
        name: 'クラシック',
        backgroundColor: 0xffd1d5db,
        keyColor: 0xffffffff,
        specialKeyColor: 0xffadb5bd,
        textColor: 0xff111827,
        accentColor: 0xff2563eb,
      ),
      KeyboardThemeConfig(
        id: 'midnight',
        name: 'ミッドナイト',
        backgroundColor: 0xff111827,
        keyColor: 0xff374151,
        specialKeyColor: 0xff1f2937,
        textColor: 0xfff9fafb,
        accentColor: 0xff60a5fa,
      ),
      KeyboardThemeConfig(
        id: 'azuki',
        name: 'あずき',
        backgroundColor: 0xffead7d7,
        keyColor: 0xfffff8f6,
        specialKeyColor: 0xffc99393,
        textColor: 0xff4c1d1d,
        accentColor: 0xff9f3a48,
      ),
    ];
    return AppData(
      schemaVersion: currentSchemaVersion,
      settings: Map<String, dynamic>.from(defaultKeyboardSettings),
      userDictionary: const [
        UserDictionaryEntry(
          id: 0,
          ruby: 'きーなこ',
          word: 'Keynako',
          isPersonName: true,
        ),
      ].toList(),
      themes: themes.toList(),
      lightThemeId: 'classic',
      darkThemeId: 'midnight',
      customTabs: [],
      custards: [],
      customKeys: [],
      tabBar: ['dismiss', 'resize', 'emoji', 'japanese', 'english'],
      clipboardHistory: [],
      learning: {},
      onboardingCompleted: false,
    );
  }

  factory AppData.fromJson(Map<String, dynamic> json) {
    final defaults = AppData.defaults();
    final rawSettings = json['settings'];
    if (rawSettings is Map) {
      defaults.settings.addAll(Map<String, dynamic>.from(rawSettings));
    }

    List<T> decodeList<T>(String key, T Function(Map<String, dynamic>) decode) {
      final value = json[key];
      if (value is! List) return <T>[];
      return value
          .whereType<Map>()
          .map((item) => decode(Map<String, dynamic>.from(item)))
          .toList();
    }

    final decodedThemes = decodeList('themes', KeyboardThemeConfig.fromJson);
    final decodedDictionary = decodeList(
      'userDictionary',
      UserDictionaryEntry.fromJson,
    );
    final rawLearning = json['learning'];
    final rawTabBar = json['tabBar'];
    final rawClipboard = json['clipboardHistory'];

    final data = AppData(
      schemaVersion:
          (json['schemaVersion'] as num?)?.toInt() ?? currentSchemaVersion,
      settings: defaults.settings,
      userDictionary: decodedDictionary.isEmpty
          ? defaults.userDictionary
          : decodedDictionary,
      themes: decodedThemes.isEmpty ? defaults.themes : decodedThemes,
      lightThemeId: json['lightThemeId'] as String? ?? defaults.lightThemeId,
      darkThemeId: json['darkThemeId'] as String? ?? defaults.darkThemeId,
      customTabs: decodeList('customTabs', CustomTabData.fromJson),
      custards: decodeList('custards', AzooKeyCustard.fromJson),
      customKeys: decodeList('customKeys', CustomKeyData.fromJson),
      tabBar: rawTabBar is List
          ? rawTabBar.whereType<String>().toList()
          : defaults.tabBar,
      clipboardHistory: rawClipboard is List
          ? rawClipboard.whereType<String>().take(50).toList()
          : <String>[],
      learning: rawLearning is Map
          ? rawLearning.map(
              (key, value) =>
                  MapEntry(key.toString(), value is num ? value.toInt() : 0),
            )
          : <String, int>{},
      onboardingCompleted: json['onboardingCompleted'] as bool? ?? false,
    )..schemaVersion = currentSchemaVersion;

    // Older versions only synchronized the tab bar when a custom tab was
    // first created. Repair that saved state so existing tabs are selectable.
    for (final tab in data.customTabs) {
      final item = 'custom:${tab.id}';
      if (tab.addToTabBar) {
        if (!data.tabBar.contains(item)) data.tabBar.add(item);
      } else {
        data.tabBar.removeWhere((value) => value == item);
      }
    }
    for (final custard in data.custards) {
      final item = 'custom:${custard.identifier}';
      if (!data.tabBar.contains(item)) data.tabBar.add(item);
    }
    return data;
  }

  factory AppData.decode(String value) {
    final decoded = jsonDecode(value);
    if (decoded is! Map) return AppData.defaults();
    return AppData.fromJson(Map<String, dynamic>.from(decoded));
  }

  KeyboardThemeConfig themeForBrightness({required bool dark}) {
    final target = dark ? darkThemeId : lightThemeId;
    return themes.firstWhere(
      (theme) => theme.id == target,
      orElse: () => themes.first,
    );
  }

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'settings': settings,
    'userDictionary': userDictionary.map((value) => value.toJson()).toList(),
    'themes': themes.map((value) => value.toJson()).toList(),
    'lightThemeId': lightThemeId,
    'darkThemeId': darkThemeId,
    'customTabs': customTabs.map((value) => value.toJson()).toList(),
    'custards': custards.map((value) => value.toJson()).toList(),
    'customKeys': customKeys.map((value) => value.toJson()).toList(),
    'tabBar': tabBar,
    'clipboardHistory': clipboardHistory,
    'learning': learning,
    'onboardingCompleted': onboardingCompleted,
  };

  String encode() => jsonEncode(toJson());
}
