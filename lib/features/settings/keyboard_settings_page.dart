import 'package:flutter/material.dart';

import '../../core/app_controller.dart';

class KeyboardSettingsPage extends StatelessWidget {
  const KeyboardSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final automatic = controller.setting('automatic_keyboard_switching', true);

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
                  icon: Icons.translate,
                  title: '日本語',
                  subtitle: '通常の文章入力欄で使う配列',
                  value: controller.setting('keyboard_type', 'flick'),
                  options: const {'flick': 'フリック入力', 'qwerty': 'ローマ字入力'},
                  onChanged: (value) =>
                      controller.setSetting('keyboard_type', value),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                _LayoutTile(
                  icon: Icons.abc,
                  title: '英語',
                  subtitle: '英語、メールアドレス、URLなどで使う配列',
                  value: controller.setting('keyboard_type_en', 'flick'),
                  options: const {'flick': 'フリック入力', 'qwerty': 'QWERTY入力'},
                  onChanged: (value) =>
                      controller.setSetting('keyboard_type_en', value),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                _LayoutTile(
                  icon: Icons.pin_outlined,
                  title: '数字',
                  subtitle: '数値入力欄で使う配列',
                  value: controller.setting('keyboard_type_number', 'tenkey'),
                  options: const {'tenkey': 'テンキー', 'symbols': '数字・記号'},
                  onChanged: (value) =>
                      controller.setSetting('keyboard_type_number', value),
                ),
              ],
            ),
          ),
          const _SectionHeader('切り替えの対応'),
          const Card(
            child: Column(
              children: [
                _MappingTile(
                  icon: Icons.notes,
                  title: '通常の文章',
                  destination: '日本語',
                ),
                Divider(height: 1, indent: 16, endIndent: 16),
                _MappingTile(
                  icon: Icons.alternate_email,
                  title: '英語・メール・URL・パスワード',
                  destination: '英語',
                ),
                Divider(height: 1, indent: 16, endIndent: 16),
                _MappingTile(
                  icon: Icons.pin,
                  title: '整数・小数',
                  destination: '数字',
                ),
                Divider(height: 1, indent: 16, endIndent: 16),
                _MappingTile(
                  icon: Icons.phone_outlined,
                  title: '電話番号',
                  destination: '電話',
                ),
                Divider(height: 1, indent: 16, endIndent: 16),
                _MappingTile(
                  icon: Icons.calendar_month_outlined,
                  title: '日付・時刻',
                  destination: '日時',
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
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String value;
  final Map<String, String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon),
    title: Text(title),
    subtitle: Text(subtitle),
    trailing: DropdownButton<String>(
      value: options.containsKey(value) ? value : options.keys.first,
      underline: const SizedBox.shrink(),
      items: [
        for (final option in options.entries)
          DropdownMenuItem(value: option.key, child: Text(option.value)),
      ],
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
    ),
  );
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
