import 'package:flutter/material.dart';

import '../../core/app_controller.dart';
import '../../models/app_data.dart';

class KeyboardSettingsPage extends StatelessWidget {
  const KeyboardSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final automatic = controller.setting('automatic_keyboard_switching', true);
    final wordDeleteInterval = controller
        .setting<num>('quick_word_delete_interval_ms', 350)
        .toInt()
        .clamp(100, 1000)
        .toInt();
    final customOptions = _customLayoutOptions(controller.data);
    final layouts = [
      for (final layout in _keyboardLayouts)
        (
          spec: layout,
          options: [...layout.options, ...customOptions],
          value: controller.setting(
            layout.key,
            defaultKeyboardLayoutSettings[layout.key]!,
          ),
        ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('キーボード設定')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        children: [
          const _SectionHeader('自動切り替え'),
          Card(
            clipBehavior: Clip.antiAlias,
            child: SwitchListTile(
              secondary: const Icon(Icons.auto_awesome_motion_outlined),
              title: const Text('入力欄に合わせる'),
              subtitle: const Text(
                '数字、電話番号、メールアドレスなど、入力欄が要求する種類に合わせて最初の配列を切り替えます。',
              ),
              value: automatic,
              onChanged: (value) =>
                  controller.setSetting('automatic_keyboard_switching', value),
            ),
          ),
          const _SectionHeader('削除'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.backspace_outlined),
                  title: const Text('削除ボタンを2回押す間隔'),
                  subtitle: const Text('2回目をこの時間内に押すと、カーソル直前の単語を削除する。'),
                  trailing: Text('$wordDeleteInterval ms'),
                ),
                Slider.adaptive(
                  key: const ValueKey('quick-word-delete-interval'),
                  min: 100,
                  max: 1000,
                  divisions: 18,
                  value: wordDeleteInterval.toDouble(),
                  label: '$wordDeleteInterval ms',
                  onChanged: (value) => controller.setSetting(
                    'quick_word_delete_interval_ms',
                    value.round(),
                  ),
                ),
              ],
            ),
          ),
          const _SectionHeader('配列'),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final (index, layout) in layouts.indexed) ...[
                  if (index > 0)
                    const Divider(height: 1, indent: 16, endIndent: 16),
                  _LayoutTile(
                    key: ValueKey('keyboard-layout-${layout.spec.key}'),
                    icon: layout.spec.icon,
                    title: layout.spec.title,
                    subtitle: layout.spec.description,
                    value: layout.value,
                    options: layout.options,
                    onChanged: (value) =>
                        controller.setSetting(layout.spec.key, value),
                  ),
                ],
              ],
            ),
          ),
          if (customOptions.isEmpty)
            const Card(
              child: ListTile(
                leading: Icon(Icons.dashboard_customize_outlined),
                title: Text('カスタム配列を追加'),
                subtitle: Text('「拡張」でカスタムタブを作るか、Custard配列を読み込むと選択肢に追加されます。'),
              ),
            ),
          const _SectionHeader('切り替えの対応'),
          Card(
            child: Column(
              children: [
                for (final (index, layout) in layouts.indexed) ...[
                  if (index > 0)
                    const Divider(height: 1, indent: 16, endIndent: 16),
                  _MappingTile(
                    icon: layout.spec.mappingIcon,
                    title: layout.spec.inputFields,
                    destination: _selectedLayout(
                      layout.options,
                      layout.value,
                    ).label,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LayoutTile extends StatelessWidget {
  const _LayoutTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.options,
    required this.onChanged,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String value;
  final List<_LayoutOption> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = _selectedLayout(options, value);
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 132),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                selected.label,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
      onTap: () async {
        final result = await showModalBottomSheet<String>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (context) => FractionallySizedBox(
            heightFactor: 0.72,
            child: SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 2, 20, 12),
                    child: Row(
                      children: [
                        Icon(icon),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '$titleで使う配列',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.only(bottom: 20),
                      children: _layoutChoices(
                        context,
                        options,
                        selected.value,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        if (result != null && result != value) onChanged(result);
      },
    );
  }
}

class _KeyboardLayout {
  const _KeyboardLayout({
    required this.key,
    required this.title,
    required this.description,
    required this.inputFields,
    required this.icon,
    required this.mappingIcon,
    required this.options,
  });

  final String key;
  final String title;
  final String description;
  final String inputFields;
  final IconData icon;
  final IconData mappingIcon;
  final List<_LayoutOption> options;
}

const _keyboardLayouts = [
  _KeyboardLayout(
    key: 'keyboard_type',
    title: '日本語',
    description: '通常の文章入力欄で使う配列',
    inputFields: '通常の文章',
    icon: Icons.translate,
    mappingIcon: Icons.notes,
    options: [
      _LayoutOption('flick', 'フリック入力', '標準配列'),
      _LayoutOption('qwerty', 'ローマ字入力', '標準配列'),
    ],
  ),
  _KeyboardLayout(
    key: 'keyboard_type_en',
    title: '英語',
    description: '英語、メールアドレス、URLなどで使う配列',
    inputFields: '英語・メール・URL・パスワード',
    icon: Icons.abc,
    mappingIcon: Icons.alternate_email,
    options: [
      _LayoutOption('flick', 'フリック入力', '標準配列'),
      _LayoutOption('qwerty', 'QWERTY入力', '標準配列'),
    ],
  ),
  _KeyboardLayout(
    key: 'keyboard_type_number',
    title: '数字',
    description: '数値入力欄で使う配列',
    inputFields: '整数・小数',
    icon: Icons.pin_outlined,
    mappingIcon: Icons.pin,
    options: [
      _LayoutOption('tenkey', 'テンキー', '標準配列'),
      _LayoutOption('symbols', '数字・記号', '標準配列'),
    ],
  ),
  _KeyboardLayout(
    key: 'keyboard_type_phone',
    title: '電話',
    description: '電話番号入力欄で使う配列',
    inputFields: '電話番号',
    icon: Icons.phone_outlined,
    mappingIcon: Icons.phone_outlined,
    options: [_LayoutOption('phone', '電話テンキー', '標準配列')],
  ),
  _KeyboardLayout(
    key: 'keyboard_type_datetime',
    title: '日時',
    description: '日付・時刻入力欄で使う配列',
    inputFields: '日付・時刻',
    icon: Icons.calendar_month_outlined,
    mappingIcon: Icons.calendar_month_outlined,
    options: [_LayoutOption('datetime', '日時テンキー', '標準配列')],
  ),
];

class _LayoutOption {
  const _LayoutOption(this.value, this.label, this.group, [this.detail]);

  final String value;
  final String label;
  final String group;
  final String? detail;
}

List<_LayoutOption> _customLayoutOptions(AppData data) => [
  for (final tab in data.customTabs)
    _LayoutOption(
      'custom:${tab.id}',
      tab.name,
      'カスタムタブ',
      '${tab.kind == 'scroll' ? '定型文' : 'グリッド'}・${tab.keys.length}キー',
    ),
  for (final custard in data.custards)
    _LayoutOption(
      'custom:${custard.identifier}',
      custard.displayName,
      'カスタム配列',
      'Custard ${custard.version}・${custard.keyCount}キー',
    ),
];

_LayoutOption _selectedLayout(List<_LayoutOption> options, String value) =>
    options.firstWhere(
      (option) => option.value == value,
      orElse: () => options.first,
    );

List<Widget> _layoutChoices(
  BuildContext context,
  List<_LayoutOption> options,
  String selected,
) {
  final result = <Widget>[];
  String? group;
  for (final option in options) {
    if (option.group != group) {
      group = option.group;
      result.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
          child: Text(group, style: Theme.of(context).textTheme.labelLarge),
        ),
      );
    }
    final checked = option.value == selected;
    result.add(
      ListTile(
        leading: Icon(checked ? Icons.check_circle : Icons.circle_outlined),
        title: Text(option.label),
        subtitle: option.detail == null ? null : Text(option.detail!),
        selected: checked,
        onTap: () => Navigator.pop(context, option.value),
      ),
    );
  }
  return result;
}

class _MappingTile extends StatelessWidget {
  const _MappingTile({
    required this.icon,
    required this.title,
    required this.destination,
  });

  final IconData icon;
  final String title;
  final String destination;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon),
    title: Text(title),
    trailing: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 132),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.arrow_forward, size: 18),
          const SizedBox(width: 8),
          Flexible(
            child: Tooltip(
              message: destination,
              child: Text(destination, overflow: TextOverflow.ellipsis),
            ),
          ),
        ],
      ),
    ),
  );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 18, 12, 5),
    child: Text(title, style: Theme.of(context).textTheme.titleSmall),
  );
}
