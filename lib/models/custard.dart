import 'dart:convert';

/// The on-disk format used by azooKey's CustardKit.
///
/// Definitions are intentionally retained as JSON instead of being reduced to
/// Keynako's editor model.  Custard supports positioned/spanning keys, ordered
/// action lists, long-press repeat actions, system keys, and two different
/// variation styles.  Keeping the source object intact lets both native
/// keyboards implement the same forward-compatible contract as azooKey.
class AzooKeyCustard {
  AzooKeyCustard._(this.definition);

  final Map<String, dynamic> definition;

  String get identifier => definition['identifier'] as String;

  String get displayName {
    final metadata = definition['metadata'] as Map<String, dynamic>;
    return metadata['display_name'] as String;
  }

  String get version {
    final metadata = definition['metadata'] as Map<String, dynamic>;
    return metadata['custard_version'] as String;
  }

  String get language => definition['language'] as String;

  String get inputStyle => definition['input_style'] as String;

  String get layoutType {
    final interface = definition['interface'] as Map<String, dynamic>;
    final layout = interface['key_layout'] as Map<String, dynamic>;
    return layout['type'] as String;
  }

  int get keyCount {
    final interface = definition['interface'] as Map<String, dynamic>;
    return (interface['keys'] as List<dynamic>).length;
  }

  factory AzooKeyCustard.fromJson(Map<String, dynamic> json) {
    final copy = _jsonMapClone(json);
    _validateCustard(copy);
    return AzooKeyCustard._(copy);
  }

  Map<String, dynamic> toJson() => _jsonMapClone(definition);

  static List<AzooKeyCustard> decodeMany(String source) {
    final decoded = jsonDecode(source);
    final definitions = decoded is List<dynamic> ? decoded : <dynamic>[decoded];
    if (definitions.isEmpty) {
      throw const FormatException('Custardが含まれていません。');
    }
    return definitions
        .map((definition) {
          if (definition is! Map) {
            throw const FormatException('CustardはJSONオブジェクトである必要があります。');
          }
          return AzooKeyCustard.fromJson(Map<String, dynamic>.from(definition));
        })
        .toList(growable: false);
  }
}

Map<String, dynamic> _jsonMapClone(Map<String, dynamic> value) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);

void _validateCustard(Map<String, dynamic> value) {
  final identifier = value['identifier'];
  if (identifier is! String || identifier.trim().isEmpty) {
    throw const FormatException('identifierがありません。');
  }
  if (!const {
    'ja_JP',
    'en_US',
    'el_GR',
    'none',
    'undefined',
  }.contains(value['language'])) {
    throw const FormatException('languageがazooKeyの仕様に適合しません。');
  }
  if (!const {'direct', 'roman2kana'}.contains(value['input_style'])) {
    throw const FormatException('input_styleがazooKeyの仕様に適合しません。');
  }

  final metadata = _requiredMap(value, 'metadata');
  if (!const {'1.0', '1.1', '1.2'}.contains(metadata['custard_version'])) {
    throw const FormatException('対応していないCustardバージョンです。');
  }
  final displayName = metadata['display_name'];
  if (displayName is! String || displayName.trim().isEmpty) {
    throw const FormatException('metadata.display_nameがありません。');
  }

  final interface = _requiredMap(value, 'interface');
  if (!const {'tenkey_style', 'pc_style'}.contains(interface['key_style'])) {
    throw const FormatException('interface.key_styleが不正です。');
  }
  final layout = _requiredMap(interface, 'key_layout');
  final layoutType = layout['type'];
  if (!const {'grid_fit', 'grid_scroll'}.contains(layoutType)) {
    throw const FormatException('interface.key_layout.typeが不正です。');
  }
  _positiveNumber(layout, 'row_count');
  _positiveNumber(layout, 'column_count');
  if (layoutType == 'grid_scroll' &&
      !const {'vertical', 'horizontal'}.contains(layout['direction'])) {
    throw const FormatException('grid_scroll.directionが不正です。');
  }

  final keys = interface['keys'];
  if (keys is! List<dynamic>) {
    throw const FormatException('interface.keysがありません。');
  }
  for (final element in keys) {
    if (element is! Map) {
      throw const FormatException('interface.keysの要素が不正です。');
    }
    final key = Map<String, dynamic>.from(element);
    final specifierType = key['specifier_type'];
    if (!const {'grid_fit', 'grid_scroll'}.contains(specifierType)) {
      throw const FormatException('specifier_typeが不正です。');
    }
    final specifier = _requiredMap(key, 'specifier');
    if (specifierType == 'grid_fit') {
      _nonNegativeNumber(specifier, 'x');
      _nonNegativeNumber(specifier, 'y');
      _positiveNumber(specifier, 'width');
      _positiveNumber(specifier, 'height');
    } else {
      _nonNegativeInteger(specifier, 'index');
    }
    final keyType = key['key_type'];
    if (!const {'custom', 'system'}.contains(keyType)) {
      throw const FormatException('key_typeが不正です。');
    }
    final keyDefinition = _requiredMap(key, 'key');
    if (keyType == 'system') {
      if (!_systemKeyTypes.contains(keyDefinition['type'])) {
        throw const FormatException('未対応のsystem keyです。');
      }
    } else {
      _validateCustomKey(keyDefinition);
    }
  }
}

const _systemKeyTypes = {
  'change_keyboard',
  'qwerty_language_switch',
  'qwerty_shift',
  'qwerty_dynamic_change',
  'qwerty_space',
  'enter',
  'upper_lower',
  'next_candidate',
  'flick_kogaki',
  'flick_kutoten',
  'flick_hira_tab',
  'flick_abc_tab',
  'flick_star123_tab',
};

void _validateCustomKey(Map<String, dynamic> key) {
  final design = _requiredMap(key, 'design');
  _requiredMap(design, 'label');
  if (!const {
    'normal',
    'special',
    'selected',
    'unimportant',
  }.contains(design['color'])) {
    throw const FormatException('key design colorが不正です。');
  }
  _validateActions(key['press_actions'], 'press_actions');
  final longPress = _requiredMap(key, 'longpress_actions');
  _validateActions(longPress['start'], 'longpress_actions.start');
  _validateActions(longPress['repeat'], 'longpress_actions.repeat');
  if (longPress.containsKey('duration') &&
      !const {'normal', 'light'}.contains(longPress['duration'])) {
    throw const FormatException('longpress durationが不正です。');
  }
  final variations = key['variations'];
  if (variations is! List<dynamic>) {
    throw const FormatException('variationsがありません。');
  }
  for (final variationValue in variations) {
    if (variationValue is! Map) {
      throw const FormatException('variationが不正です。');
    }
    final variation = Map<String, dynamic>.from(variationValue);
    final type = variation['type'];
    if (!const {'flick_variation', 'longpress_variation'}.contains(type)) {
      throw const FormatException('variation.typeが不正です。');
    }
    if (type == 'flick_variation' &&
        !const {
          'left',
          'top',
          'right',
          'bottom',
        }.contains(variation['direction'])) {
      throw const FormatException('flick variation directionが不正です。');
    }
    final variationKey = _requiredMap(variation, 'key');
    final variationDesign = _requiredMap(variationKey, 'design');
    _requiredMap(variationDesign, 'label');
    _validateActions(variationKey['press_actions'], 'variation.press_actions');
    final variationLongPress = _requiredMap(variationKey, 'longpress_actions');
    _validateActions(variationLongPress['start'], 'variation.longpress.start');
    _validateActions(
      variationLongPress['repeat'],
      'variation.longpress.repeat',
    );
  }
}

void _validateActions(Object? value, String path) {
  if (value is! List<dynamic> || value.any((action) => action is! Map)) {
    throw FormatException('$pathが不正です。');
  }
}

Map<String, dynamic> _requiredMap(Map<String, dynamic> source, String key) {
  final value = source[key];
  if (value is! Map) throw FormatException('$keyがありません。');
  return Map<String, dynamic>.from(value);
}

void _positiveNumber(Map<String, dynamic> source, String key) {
  final value = source[key];
  if (value is! num || !value.isFinite || value <= 0) {
    throw FormatException('$keyは正の数である必要があります。');
  }
}

void _nonNegativeInteger(Map<String, dynamic> source, String key) {
  final value = source[key];
  if (value is! int || value < 0) {
    throw FormatException('$keyは0以上の整数である必要があります。');
  }
}

void _nonNegativeNumber(Map<String, dynamic> source, String key) {
  final value = source[key];
  if (value is! num || !value.isFinite || value < 0) {
    throw FormatException('$keyは0以上の数である必要があります。');
  }
}
