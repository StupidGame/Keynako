part of 'customization_page.dart';

String _actionLabel(KeyActionData action) {
  final label =
      const {
        'input': '入力',
        'directInput': '直接入力',
        'direct_input': '直接入力',
        'delete': '削除',
        'smartDeleteDefault': '単語削除',
        'smart_delete_default': '単語削除',
        'smart_delete': 'スマート削除（後方は単語削除）',
        'enter': '改行',
        'space': '空白',
        'replaceDefault': '文字種切替',
        'replace_default': '文字種切替',
        'replace_last_characters': '末尾文字置換',
        'moveCursor': 'カーソル移動',
        'move_cursor': 'カーソル移動',
        'smart_move_cursor': '指定位置へ移動',
        'switchLayout': '配列変更',
        'move_tab': 'タブ移動',
        'select_candidate': '候補選択',
        'complete': '確定',
        'completeCharacterForm': '文字種確定',
        'complete_character_form': '文字種確定',
        'paste': 'ペースト',
        '__paste': 'ペースト',
        'toggleCursorBar': 'カーソルバー',
        'toggle_cursor_bar': 'カーソルバー',
        'toggleTabBar': 'タブバー',
        'toggle_tab_bar': 'タブバー',
        'toggleCapsLock': 'Caps Lock',
        'toggle_caps_lock_state': 'Caps Lock',
        'dismiss': '閉じる',
        'dismiss_keyboard': '閉じる',
        'enable_resizing_mode': 'サイズ変更',
        'launch_application': 'アプリ起動',
      }[action.type] ??
      '未対応の操作';
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
