import 'package:flutter/material.dart';

import '../../core/app_controller.dart';
import '../../models/app_data.dart';

class KeyboardSettingsPage extends StatelessWidget {
  const KeyboardSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final automatic = controller.setting('automatic_keyboard_switching', true);
    final customOptions = _customLayoutOptions(controller.data);
    final japaneseOptions = [
      const _LayoutOption('flick', 'フリック入力', '標準配列'),
      const _LayoutOption('qwerty', 'ローマ字入力', '標準配列'),
      ...customOptions,
    ];
    final englishOptions = [
      const _LayoutOption('flick', 'フリック入力', '標準配列'),
      const _LayoutOption('qwerty', 'QWERTY入力', '標準配列'),
      ...customOptions,
    ];
    final numberOptions = [
      const _LayoutOption('tenkey', 'テンキー', '標準配列'),
      const _LayoutOption('symbols', '数字・記号', '標準配列'),
      ...customOptions,
    ];
    final phoneOptions = [
      const _LayoutOption('phone', '電話テンキー', '標準配列'),
      ...customOptions,
    ];
    final dateTimeOptions = [
      const _LayoutOption('datetime', '日時テンキー', '標準配列'),
      ...customOptions,
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
          const _SectionHeader('配列'),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _LayoutTile(
                  key: const ValueKey('keyboard-layout-keyboard_type'),
                  icon: Icons.translate,
                  title: '日本語',
                  subtitle: '通常の文章入力欄で使う配列',
                  value: controller.setting('keyboard_type', 'flick'),
                  options: japaneseOptions,
                  onChanged: (value) =>
                      controller.setSetting('keyboard_type', value),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                _LayoutTile(
                  key: const ValueKey('keyboard-layout-keyboard_type_en'),
                  icon: Icons.abc,
                  title: '英語',
                  subtitle: '英語、メールアドレス、URLなどで使う配列',
                  value: controller.setting('keyboard_type_en', 'flick'),
                  options: englishOptions,
                  onChanged: (value) =>
                      controller.setSetting('keyboard_type_en', value),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                _LayoutTile(
                  key: const ValueKey('keyboard-layout-keyboard_type_number'),
                  icon: Icons.pin_outlined,
                  title: '数字',
                  subtitle: '数値入力欄で使う配列',
                  value: controller.setting('keyboard_type_number', 'tenkey'),
                  options: numberOptions,
                  onChanged: (value) =>
                      controller.setSetting('keyboard_type_number', value),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                _LayoutTile(
                  key: const ValueKey('keyboard-layout-keyboard_type_phone'),
                  icon: Icons.phone_outlined,
                  title: '電話',
                  subtitle: '電話番号入力欄で使う配列',
                  value: controller.setting('keyboard_type_phone', 'phone'),
                  options: phoneOptions,
                  onChanged: (value) =>
                      controller.setSetting('keyboard_type_phone', value),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                _LayoutTile(
                  key: const ValueKey('keyboard-layout-keyboard_type_datetime'),
                  icon: Icons.calendar_month_outlined,
                  title: '日時',
                  subtitle: '日付・時刻入力欄で使う配列',
                  value: controller.setting(
                    'keyboard_type_datetime',
                    'datetime',
                  ),
                  options: dateTimeOptions,
                  onChanged: (value) =>
                      controller.setSetting('keyboard_type_datetime', value),
                ),
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
                _MappingTile(
                  icon: Icons.notes,
                  title: '通常の文章',
                  destination: _selectedLabel(
                    japaneseOptions,
                    controller.setting('keyboard_type', 'flick'),
                  ),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                _MappingTile(
                  icon: Icons.alternate_email,
                  title: '英語・メール・URL・パスワード',
                  destination: _selectedLabel(
                    englishOptions,
                    controller.setting('keyboard_type_en', 'flick'),
                  ),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                _MappingTile(
                  icon: Icons.pin,
                  title: '整数・小数',
                  destination: _selectedLabel(
                    numberOptions,
                    controller.setting('keyboard_type_number', 'tenkey'),
                  ),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                _MappingTile(
                  icon: Icons.phone_outlined,
                  title: '電話番号',
                  destination: _selectedLabel(
                    phoneOptions,
                    controller.setting('keyboard_type_phone', 'phone'),
                  ),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                _MappingTile(
                  icon: Icons.calendar_month_outlined,
                  title: '日付・時刻',
                  destination: _selectedLabel(
                    dateTimeOptions,
                    controller.setting('keyboard_type_datetime', 'datetime'),
                  ),
                ),
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
    final selected = options.firstWhere(
      (option) => option.value == value,
      orElse: () => options.first,
    );
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

String _selectedLabel(List<_LayoutOption> options, String value) => options
    .firstWhere((option) => option.value == value, orElse: () => options.first)
    .label;

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
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.arrow_forward, size: 18),
        const SizedBox(width: 8),
        Text(destination),
      ],
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
