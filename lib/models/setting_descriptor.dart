enum SettingKind { toggle, slider, choice, text }

class SettingOption {
  const SettingOption(this.value, this.label);

  final Object value;
  final String label;
}

class SettingDescriptor {
  const SettingDescriptor({
    required this.group,
    required this.key,
    required this.title,
    required this.explanation,
    required this.kind,
    this.options = const [],
    this.minimum,
    this.maximum,
    this.divisions,
    this.automaticValue,
    this.requiresFullAccess = false,
  });

  final String group;
  final String key;
  final String title;
  final String explanation;
  final SettingKind kind;
  final List<SettingOption> options;
  final double? minimum;
  final double? maximum;
  final int? divisions;
  final double? automaticValue;
  final bool requiresFullAccess;

  bool matches(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return true;
    return '$group $title $explanation $key'.toLowerCase().contains(normalized);
  }
}

const List<SettingDescriptor> settingCatalog = [
  SettingDescriptor(
    group: 'キーボードの種類',
    key: 'keyboard_type',
    title: '日本語キーボード',
    explanation: '日本語の入力方法をフリック入力とローマ字入力から選択できます。',
    kind: SettingKind.choice,
    options: [
      SettingOption('flick', 'フリック入力'),
      SettingOption('qwerty', 'ローマ字入力'),
    ],
  ),
  SettingDescriptor(
    group: 'キーボードの種類',
    key: 'keyboard_type_en',
    title: '英語キーボード',
    explanation: '英語の入力方法をフリック入力とQWERTY入力から選択できます。',
    kind: SettingKind.choice,
    options: [
      SettingOption('flick', 'フリック入力'),
      SettingOption('qwerty', 'QWERTY入力'),
    ],
  ),
  SettingDescriptor(
    group: 'ライブ変換',
    key: 'live_conversion',
    title: 'ライブ変換',
    explanation: '入力中の文字列を自動的に変換します。',
    kind: SettingKind.toggle,
  ),
  SettingDescriptor(
    group: 'ライブ変換',
    key: 'automatic_completion_strength',
    title: '自動確定の速さ',
    explanation: '長い文章を入力したときに先頭側を自動確定する強さです。',
    kind: SettingKind.choice,
    options: [
      SettingOption(0, '無効'),
      SettingOption(1, '弱い'),
      SettingOption(2, '普通'),
      SettingOption(3, '強い'),
      SettingOption(4, '非常に強い'),
    ],
  ),
  SettingDescriptor(
    group: 'カスタムキー',
    key: 'use_next_candidate_key',
    title: '次候補キーを使う',
    explanation: '入力中、空白キーに次候補機能を表示します。',
    kind: SettingKind.toggle,
  ),
  SettingDescriptor(
    group: 'カスタムキー',
    key: 'use_shift_key',
    title: 'シフトキーを使う',
    explanation: 'QWERTYキーボードでAaキーの代わりにシフトキーを利用します。',
    kind: SettingKind.toggle,
  ),
  SettingDescriptor(
    group: 'カスタムキー',
    key: 'keep_deprecated_shift_key_behavior',
    title: 'シフトキーの従来動作',
    explanation: '連続タップでCaps Lockへ切り替える従来の操作を利用します。',
    kind: SettingKind.toggle,
  ),
  SettingDescriptor(
    group: 'カスタムキー',
    key: 'enable_paste_button_on_flick_cursorbar_key',
    title: 'ペーストボタン',
    explanation: 'カーソル移動キーの上フリックにペーストを追加します。',
    kind: SettingKind.toggle,
    requiresFullAccess: true,
  ),
  SettingDescriptor(
    group: 'バー',
    key: 'use_move_cursor_bar_beta',
    title: '新しいカーソルバーを使う',
    explanation: '指の移動を反映するカーソルバーを有効化します。',
    kind: SettingKind.toggle,
  ),
  SettingDescriptor(
    group: 'バー',
    key: 'display_cursor_bar_automatically',
    title: 'カーソルバーを自動表示',
    explanation: 'カーソル移動の際にカーソルバーを自動表示します。',
    kind: SettingKind.toggle,
  ),
  SettingDescriptor(
    group: 'バー',
    key: 'enable_clipboard_history_manager_tab',
    title: 'クリップボードの履歴を保存',
    explanation: 'コピーした文字列を保存し、専用タブから入力できるようにします。',
    kind: SettingKind.toggle,
    requiresFullAccess: true,
  ),
  SettingDescriptor(
    group: 'バー',
    key: 'display_tab_bar_button',
    title: 'タブバーボタン',
    explanation: '変換候補欄が空のときにタブバーを表示します。',
    kind: SettingKind.toggle,
  ),
  SettingDescriptor(
    group: 'サウンドと振動',
    key: 'sound_enable_setting',
    title: 'キーの音',
    explanation: 'キーを押した際にクリック音を鳴らします。',
    kind: SettingKind.toggle,
  ),
  SettingDescriptor(
    group: 'サウンドと振動',
    key: 'enable_key_haptics',
    title: '振動フィードバック',
    explanation: 'キーを押した際に端末を振動させます。',
    kind: SettingKind.toggle,
    requiresFullAccess: true,
  ),
  SettingDescriptor(
    group: '表示',
    key: 'key_view_font_size',
    title: 'キーの表示サイズ',
    explanation: 'キーの文字サイズを指定します。自動を選ぶとキーサイズに追従します。',
    kind: SettingKind.slider,
    minimum: 14,
    maximum: 30,
    divisions: 16,
    automaticValue: -1,
  ),
  SettingDescriptor(
    group: '表示',
    key: 'result_view_font_size',
    title: '変換候補の表示サイズ',
    explanation: '変換候補の文字サイズを指定します。',
    kind: SettingKind.slider,
    minimum: 12,
    maximum: 24,
    divisions: 12,
    automaticValue: -1,
  ),
  SettingDescriptor(
    group: '表示',
    key: 'keyboard_height_scale',
    title: 'キーボードの高さ',
    explanation: '端末に対するキーボードの高さを倍率で調整します。',
    kind: SettingKind.slider,
    minimum: 0.7,
    maximum: 1.4,
    divisions: 14,
  ),
  SettingDescriptor(
    group: '操作性',
    key: 'hide_reset_button_in_one_handed_mode',
    title: '片手モードで解除ボタンを表示しない',
    explanation: '片手モードの解除・調整ボタンを非表示にします。',
    kind: SettingKind.toggle,
  ),
  SettingDescriptor(
    group: '操作性',
    key: 'flick_sensitivity_setting',
    title: 'フリックの感度',
    explanation: '値が小さいほど短い指の移動をフリックとして判定します。',
    kind: SettingKind.slider,
    minimum: 0.5,
    maximum: 2,
    divisions: 15,
  ),
  SettingDescriptor(
    group: '変換',
    key: 'enable_zenzai',
    title: 'Zenzaiを有効化',
    explanation: '高度な変換アルゴリズムZenzaiを利用します。',
    kind: SettingKind.toggle,
  ),
  SettingDescriptor(
    group: '変換',
    key: 'zenzai_effort',
    title: 'Zenzaiのエフォート',
    explanation: '高いほど候補探索を強めますが処理が重くなります。',
    kind: SettingKind.choice,
    options: [
      SettingOption(0, '低'),
      SettingOption(1, '中'),
      SettingOption(2, '高'),
    ],
  ),
  SettingDescriptor(
    group: '変換',
    key: 'roman_english_candidate',
    title: '日本語入力中の英単語変換',
    explanation: 'ローマ字日本語入力中も英語候補を表示します。',
    kind: SettingKind.toggle,
  ),
  SettingDescriptor(
    group: '変換',
    key: 'typography_roman_candidate',
    title: '装飾英字変換',
    explanation: '太字や筆記体などの装飾英字を候補に表示します。',
    kind: SettingKind.toggle,
  ),
  SettingDescriptor(
    group: '変換',
    key: 'half_kana_candidate',
    title: '半角カナ変換',
    explanation: '半角カタカナへの変換を候補に表示します。',
    kind: SettingKind.toggle,
  ),
  SettingDescriptor(
    group: '変換',
    key: 'full_roman_candidate',
    title: '全角英数字変換',
    explanation: '全角英数字への変換を候補に表示します。',
    kind: SettingKind.toggle,
  ),
  SettingDescriptor(
    group: '変換',
    key: 'unicode_candidate',
    title: 'Unicode変換',
    explanation: 'u3042やU+1F600のような入力を対応する文字へ変換します。',
    kind: SettingKind.toggle,
  ),
  SettingDescriptor(
    group: '変換',
    key: 'marked_text_setting_beta',
    title: '入力中のテキストを保護',
    explanation: 'Webアプリなどで入力中テキストの挙動を安定させます。',
    kind: SettingKind.choice,
    options: [
      SettingOption('disabled', '無効'),
      SettingOption('enabled', '有効'),
      SettingOption('auto', '自動'),
    ],
  ),
  SettingDescriptor(
    group: '変換',
    key: 'enable_contact_import',
    title: '変換に連絡先データを利用',
    explanation: '連絡先に登録された氏名を変換候補へ追加します。',
    kind: SettingKind.toggle,
    requiresFullAccess: true,
  ),
  SettingDescriptor(
    group: '絵文字と顔文字',
    key: 'emoji_dictionary_enabled',
    title: '絵文字変換',
    explanation: '読みから絵文字を変換候補に表示します。',
    kind: SettingKind.toggle,
  ),
  SettingDescriptor(
    group: '絵文字と顔文字',
    key: 'kaomoji_dictionary_enabled',
    title: '顔文字変換',
    explanation: '読みから顔文字を変換候補に表示します。',
    kind: SettingKind.toggle,
  ),
  SettingDescriptor(
    group: 'ユーザ辞書',
    key: 'use_OS_user_dict',
    title: 'OSのユーザ辞書の利用',
    explanation: 'OS標準のユーザ辞書も候補生成に利用します。',
    kind: SettingKind.toggle,
  ),
  SettingDescriptor(
    group: '学習機能',
    key: 'memory_learining_styple_setting',
    title: '学習の使用',
    explanation: '候補選択の学習と反映方法を選択します。',
    kind: SettingKind.choice,
    options: [
      SettingOption(0, '学習する'),
      SettingOption(1, '新たな学習を停止'),
      SettingOption(2, '学習結果を反映しない'),
    ],
  ),
  SettingDescriptor(
    group: '協力',
    key: 'enable_wrong_conversion_report',
    title: '誤変換レポートを送信',
    explanation: '候補選択後に内容を確認してレポートを送信できます。',
    kind: SettingKind.toggle,
    requiresFullAccess: true,
  ),
  SettingDescriptor(
    group: '協力',
    key: 'wrong_conversion_report_frequency',
    title: '送信を提案する頻度',
    explanation: '誤変換レポートの提案頻度を調整します。',
    kind: SettingKind.choice,
    options: [
      SettingOption(1, 'とても頻繁'),
      SettingOption(3, '頻繁'),
      SettingOption(10, 'たまに'),
      SettingOption(50, 'まれに'),
    ],
  ),
  SettingDescriptor(
    group: '協力',
    key: 'wrong_conversion_include_context',
    title: '文脈をデフォルトで含める',
    explanation: 'レポートに前後それぞれ約10文字までの文脈を含めます。',
    kind: SettingKind.toggle,
  ),
  SettingDescriptor(
    group: '協力',
    key: 'wrong_conversion_report_user_nickname',
    title: 'ユーザニックネーム',
    explanation: 'レポートに含める任意の名前です。',
    kind: SettingKind.text,
  ),
];
