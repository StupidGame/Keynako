import 'package:flutter/services.dart';

class KeyboardStatus {
  const KeyboardStatus({
    required this.enabled,
    required this.fullAccess,
    required this.platform,
  });

  final bool enabled;
  final bool fullAccess;
  final String platform;

  factory KeyboardStatus.fromMap(Map<Object?, Object?> map) => KeyboardStatus(
    enabled: map['enabled'] as bool? ?? false,
    fullAccess: map['fullAccess'] as bool? ?? false,
    platform: map['platform'] as String? ?? 'unknown',
  );

  static const unavailable = KeyboardStatus(
    enabled: false,
    fullAccess: false,
    platform: 'unsupported',
  );
}

abstract interface class StateStorage {
  Future<String?> load();
  Future<void> save(String state);
}

class PlatformService implements StateStorage {
  PlatformService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('net.azookey/platform');

  final MethodChannel _channel;
  String? _fallbackState;

  @override
  Future<String?> load() async {
    try {
      return await _channel.invokeMethod<String>('loadState');
    } on MissingPluginException {
      return _fallbackState;
    } on PlatformException {
      return _fallbackState;
    }
  }

  @override
  Future<void> save(String state) async {
    _fallbackState = state;
    try {
      await _channel.invokeMethod<void>('saveState', {'state': state});
    } on MissingPluginException {
      // The in-memory fallback keeps widget tests and unsupported platforms usable.
    } on PlatformException {
      // Keep the app editable even if the platform store is temporarily unavailable.
    }
  }

  Future<KeyboardStatus> keyboardStatus() async {
    try {
      final result = await _channel.invokeMapMethod<Object?, Object?>(
        'keyboardStatus',
      );
      return result == null
          ? KeyboardStatus.unavailable
          : KeyboardStatus.fromMap(result);
    } on MissingPluginException {
      return KeyboardStatus.unavailable;
    } on PlatformException {
      return KeyboardStatus.unavailable;
    }
  }

  Future<void> openKeyboardSettings() async {
    try {
      await _channel.invokeMethod<void>('openKeyboardSettings');
    } on MissingPluginException {
      return;
    }
  }

  Future<void> shareText({
    required String subject,
    required String text,
  }) async {
    try {
      await _channel.invokeMethod<void>('shareText', {
        'subject': subject,
        'text': text,
      });
    } on MissingPluginException {
      await Clipboard.setData(ClipboardData(text: text));
    }
  }

  Future<List<Map<String, String>>> importContacts() async {
    try {
      final result = await _channel.invokeListMethod<Object?>('importContacts');
      if (result == null) return [];
      return result
          .whereType<Map>()
          .map((value) {
            final map = Map<Object?, Object?>.from(value);
            return {
              'ruby': map['ruby']?.toString() ?? '',
              'word': map['word']?.toString() ?? '',
            };
          })
          .where((value) => value['word']!.isNotEmpty)
          .toList();
    } on MissingPluginException {
      return [];
    } on PlatformException {
      return [];
    }
  }

  Future<bool> submitSharedWord({
    required String word,
    required String ruby,
    required List<String> categories,
    String? note,
  }) async {
    try {
      return await _channel.invokeMethod<bool>('submitSharedWord', {
            'word': word,
            'ruby': ruby,
            'categories': categories,
            'note': note,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<String?> saveKeyboardBackgroundImage({
    required String themeId,
    required Uint8List bytes,
  }) async {
    try {
      return await _channel.invokeMethod<String>(
        'saveKeyboardBackgroundImage',
        {'themeId': themeId, 'bytes': bytes},
      );
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<void> deleteKeyboardBackgroundImage(String path) async {
    try {
      await _channel.invokeMethod<void>('deleteKeyboardBackgroundImage', {
        'path': path,
      });
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }
}
