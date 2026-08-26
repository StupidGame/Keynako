part of 'customization_page.dart';

String _actionLabel(KeyActionData action) {
  final label =
      const {
        'input': '入力',
        'directInput': '直接入力',
        'delete': '削除',
        'smartDeleteDefault': '文節削除',
        'enter': '改行',
        'space': '空白',
        'replaceDefault': '文字種切替',
        'moveCursor': 'カーソル移動',
        'switchLayout': '配列変更',
        'complete': '確定',
        'completeCharacterForm': '文字種確定',
        'paste': 'ペースト',
        'toggleCursorBar': 'カーソルバー',
        'toggleTabBar': 'タブバー',
        'toggleCapsLock': 'Caps Lock',
        'dismiss': '閉じる',
      }[action.type] ??
      action.type;
  return action.value.isEmpty ? label : '$label: ${action.value}';
}

String _targetLabel(String target) =>
    const {
      'standalone': '独立キー',
      'kogana': '小ﾞﾟキー',
      'kana_symbols': '､｡?!キー',
      'hira_tab': 'あいうキー',
      'abc_tab': 'ABCキー',
      'symbols_tab': '☆123キー',
    }[target] ??
    target;
