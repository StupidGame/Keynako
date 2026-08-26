import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_controller.dart';
import '../../models/app_data.dart';

part 'custom_key_editor_page.dart';
part 'custom_tab_editor_page.dart';
part 'customization_labels.dart';
part 'tab_bar_editor_page.dart';

class CustomizationPage extends StatelessWidget {
  const CustomizationPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('拡張'),
        actions: [
          IconButton(
            tooltip: 'JSONから読み込む',
            onPressed: () => _import(context),
            icon: const Icon(Icons.file_download_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _intro(
            context,
            icon: Icons.dashboard_customize_outlined,
            title: 'カスタムタブ',
            body: 'azooKey公式のCustard（1.0〜1.2）をそのまま読み込むか、端末上でタブを作成できます。',
          ),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _openTabEditor(context, kind: 'scroll'),
                  icon: const Icon(Icons.notes),
                  label: const Text('定型文タブ'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () => _openTabEditor(context, kind: 'grid'),
                  icon: const Icon(Icons.grid_view),
                  label: const Text('グリッドタブ'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (controller.data.customTabs.isEmpty &&
              controller.data.custards.isEmpty)
            const _EmptyCard(text: '作成・読み込みしたカスタムタブはここに表示されます。'),
          for (final tab in controller.data.customTabs)
            Card(
              child: ListTile(
                leading: Icon(
                  tab.kind == 'scroll' ? Icons.notes : Icons.grid_view,
                ),
                title: Text(tab.name),
                subtitle: Text('${tab.keys.length}キー・${tab.columns}列'),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => CustomTabEditorPage(tab: tab),
                  ),
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (value) async {
                    if (value == 'share') {
                      await controller.platform.shareText(
                        subject: 'Keynako Custard: ${tab.name}',
                        text: jsonEncode({'azooKeyCustomTab': tab.toJson()}),
                      );
                    } else if (value == 'delete') {
                      controller.removeCustomTab(tab.id);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'share', child: Text('共有')),
                    PopupMenuItem(value: 'delete', child: Text('削除')),
                  ],
                ),
              ),
            ),
          for (final custard in controller.data.custards)
            Card(
              child: ListTile(
                leading: const Icon(Icons.keyboard_alt_outlined),
                title: Text(custard.displayName),
                subtitle: Text(
                  'Custard ${custard.version}・${custard.keyCount}キー・${custard.layoutType}',
                ),
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text(custard.displayName),
                    content: Text(
                      '識別子: ${custard.identifier}\n'
                      '言語: ${custard.language}\n'
                      '入力方式: ${custard.inputStyle}\n\n'
                      '公式Custardの全情報を保持しており、azooKeyと同じ配置・アクションでキーボードに表示します。',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('閉じる'),
                      ),
                    ],
                  ),
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (value) async {
                    if (value == 'share') {
                      await controller.platform.shareText(
                        subject: 'Keynako Custard: ${custard.displayName}',
                        text: jsonEncode(custard.toJson()),
                      );
                    } else if (value == 'delete') {
                      controller.removeCustard(custard.identifier);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'share', child: Text('共有')),
                    PopupMenuItem(value: 'delete', child: Text('削除')),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 22),
          _intro(
            context,
            icon: Icons.view_week_outlined,
            title: 'タブバー',
            body: 'キーボード上部のタブ切り替えボタンを並べ替えます。',
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.reorder),
              title: const Text('タブバーを編集'),
              subtitle: Text('${controller.data.tabBar.length}項目'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const TabBarEditorPage(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 22),
          _intro(
            context,
            icon: Icons.keyboard_command_key,
            title: 'カスタムキー',
            body: 'タップ、上下左右フリック、長押しに入力や編集操作を割り当てます。',
          ),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const CustomKeyEditorPage(),
              ),
            ),
            icon: const Icon(Icons.add),
            label: const Text('カスタムキーを追加'),
          ),
          for (final key in controller.data.customKeys)
            Card(
              child: ListTile(
                leading: CircleAvatar(child: Text(key.label)),
                title: Text(key.name),
                subtitle: Text(
                  '${_targetLabel(key.target)}・${_actionLabel(key.tap)}',
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => CustomKeyEditorPage(keyData: key),
                  ),
                ),
                trailing: IconButton(
                  tooltip: '削除',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => controller.removeCustomKey(key.id),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _intro(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String body,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 3),
                Text(body),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openTabEditor(BuildContext context, {required String kind}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CustomTabEditorPage(initialKind: kind),
      ),
    );
  }

  Future<void> _import(BuildContext context) async {
    final text = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('URLからCustardを読み込む'),
        content: TextField(
          controller: text,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'CustardのURL',
            hintText: 'https://custard.azookey.com/tab/...',
            helperText: 'GitHub・Gist・直接の .custard / JSON URLにも対応します。',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
              text.text = clipboard?.text ?? '';
            },
            child: const Text('貼り付け'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, text.text),
            child: const Text('読み込む'),
          ),
        ],
      ),
    );
    if (result == null || !context.mounted) return;
    try {
      final trimmed = result.trim();
      final decoded = trimmed.startsWith('{') || trimmed.startsWith('[')
          ? jsonDecode(trimmed)
          : null;
      if (decoded is Map && decoded['azooKeyCustomTab'] is Map) {
        final tab = CustomTabData.fromJson(
          Map<String, dynamic>.from(decoded['azooKeyCustomTab'] as Map),
        );
        AppControllerScope.of(context).replaceCustomTab(tab);
      } else {
        final controller = AppControllerScope.of(context);
        final imported = decoded == null
            ? await controller.importCustardsFromUrl(trimmed)
            : controller.importCustards(trimmed);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${imported.length}件のCustardを読み込みました。')),
        );
      }
    } on FormatException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Custardを読み込めませんでした: ${error.message}')),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Custardを取得できませんでした: $error')));
    }
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Center(child: Text(text)),
    ),
  );
}
