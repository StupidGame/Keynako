import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_controller.dart';
import '../../models/app_data.dart';

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
            body: '好きな文字、文章、操作を並べたオリジナルのタブを作成できます。',
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
          if (controller.data.customTabs.isEmpty)
            const _EmptyCard(text: '作成したカスタムタブはここに表示されます。')
          else
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
                subtitle: Text(_actionLabel(key.tap)),
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
        title: const Text('カスタムタブを読み込む'),
        content: TextField(
          controller: text,
          minLines: 5,
          maxLines: 10,
          decoration: const InputDecoration(hintText: '共有されたJSONを貼り付けます'),
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
      final decoded = jsonDecode(result);
      final envelope = Map<String, dynamic>.from(decoded as Map);
      final tab = CustomTabData.fromJson(
        Map<String, dynamic>.from(envelope['azooKeyCustomTab'] as Map),
      );
      AppControllerScope.of(context).replaceCustomTab(tab);
    } catch (_) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('カスタムタブJSONを読み込めませんでした。')));
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

class CustomTabEditorPage extends StatefulWidget {
  const CustomTabEditorPage({this.tab, this.initialKind = 'grid', super.key});

  final CustomTabData? tab;
  final String initialKind;

  @override
  State<CustomTabEditorPage> createState() => _CustomTabEditorPageState();
}

class _CustomTabEditorPageState extends State<CustomTabEditorPage> {
  late final TextEditingController _name;
  late String _kind;
  late int _columns;
  late int _rows;
  late bool _addToTabBar;
  late List<CustomKeyData> _keys;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.tab?.name ?? '新規タブ');
    _kind = widget.tab?.kind ?? widget.initialKind;
    _columns = widget.tab?.columns ?? (_kind == 'scroll' ? 2 : 4);
    _rows = widget.tab?.rows ?? 5;
    _addToTabBar = widget.tab?.addToTabBar ?? true;
    _keys = [...?widget.tab?.keys];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.tab == null ? 'カスタムタブを作る' : 'カスタムタブを編集'),
        actions: [TextButton(onPressed: _save, child: const Text('保存'))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'タブ名'),
          ),
          const SizedBox(height: 14),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'grid', label: Text('グリッド')),
              ButtonSegment(value: 'scroll', label: Text('定型文')),
            ],
            selected: {_kind},
            onSelectionChanged: (value) => setState(() => _kind = value.first),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _columns,
                  decoration: const InputDecoration(labelText: '列数'),
                  items: [1, 2, 3, 4, 5, 6]
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text('$value'),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _columns = value ?? 4),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _rows,
                  decoration: const InputDecoration(labelText: '行数'),
                  items: [2, 3, 4, 5, 6, 7, 8]
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text('$value'),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _rows = value ?? 5),
                ),
              ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('タブバーへ自動追加'),
            value: _addToTabBar,
            onChanged: (value) => setState(() => _addToTabBar = value),
          ),
          const Divider(height: 28),
          Row(
            children: [
              Text('キー', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              TextButton.icon(
                onPressed: () async {
                  final key = await Navigator.of(context).push<CustomKeyData>(
                    MaterialPageRoute<CustomKeyData>(
                      builder: (_) =>
                          const CustomKeyEditorPage(returnValue: true),
                    ),
                  );
                  if (key != null) setState(() => _keys.add(key));
                },
                icon: const Icon(Icons.add),
                label: const Text('追加'),
              ),
            ],
          ),
          if (_keys.isEmpty) const _EmptyCard(text: '文字や操作を割り当てたキーを追加してください。'),
          for (var index = 0; index < _keys.length; index++)
            Card(
              child: ListTile(
                leading: CircleAvatar(child: Text(_keys[index].label)),
                title: Text(_keys[index].name),
                subtitle: Text(_actionLabel(_keys[index].tap)),
                onTap: () async {
                  final key = await Navigator.of(context).push<CustomKeyData>(
                    MaterialPageRoute<CustomKeyData>(
                      builder: (_) => CustomKeyEditorPage(
                        keyData: _keys[index],
                        returnValue: true,
                      ),
                    ),
                  );
                  if (key != null) setState(() => _keys[index] = key);
                },
                trailing: IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: () => setState(() => _keys.removeAt(index)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _save() {
    final id = widget.tab?.id ?? 'tab-${DateTime.now().millisecondsSinceEpoch}';
    final tab = CustomTabData(
      id: id,
      name: _name.text.trim().isEmpty ? '名称未設定' : _name.text.trim(),
      kind: _kind,
      columns: _columns,
      rows: _rows,
      keys: _keys,
      addToTabBar: _addToTabBar,
    );
    AppControllerScope.of(context).replaceCustomTab(tab);
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }
}

class CustomKeyEditorPage extends StatefulWidget {
  const CustomKeyEditorPage({
    this.keyData,
    this.returnValue = false,
    super.key,
  });

  final CustomKeyData? keyData;
  final bool returnValue;

  @override
  State<CustomKeyEditorPage> createState() => _CustomKeyEditorPageState();
}

class _CustomKeyEditorPageState extends State<CustomKeyEditorPage> {
  late final TextEditingController _name;
  late final TextEditingController _label;
  late final Map<String, KeyActionData?> _actions;

  @override
  void initState() {
    super.initState();
    final key = widget.keyData;
    _name = TextEditingController(text: key?.name ?? '新しいキー');
    _label = TextEditingController(text: key?.label ?? '＋');
    _actions = {
      'タップ': key?.tap ?? const KeyActionData(type: 'input'),
      '左フリック': key?.left,
      '上フリック': key?.up,
      '右フリック': key?.right,
      '下フリック': key?.down,
      '長押し': key?.longPress,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('カスタムキーを編集'),
        actions: [TextButton(onPressed: _save, child: const Text('保存'))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'キー名'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _label,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(labelText: '表示'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          for (final entry in _actions.entries)
            Card(
              child: ListTile(
                title: Text(entry.key),
                subtitle: Text(
                  entry.value == null ? '割り当てなし' : _actionLabel(entry.value!),
                ),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () async {
                  final value = await showDialog<KeyActionData?>(
                    context: context,
                    builder: (_) => _ActionEditor(action: entry.value),
                  );
                  if (value != null) {
                    setState(() => _actions[entry.key] = value);
                  }
                },
                onLongPress: entry.key == 'タップ'
                    ? null
                    : () => setState(() => _actions[entry.key] = null),
              ),
            ),
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text('長押しすると、その方向の割り当てを解除できます。'),
          ),
        ],
      ),
    );
  }

  void _save() {
    final value = CustomKeyData(
      id: widget.keyData?.id ?? 'key-${DateTime.now().microsecondsSinceEpoch}',
      name: _name.text.trim().isEmpty ? '名称未設定' : _name.text.trim(),
      label: _label.text.isEmpty ? ' ' : _label.text,
      tap: _actions['タップ'] ?? const KeyActionData(type: 'input'),
      left: _actions['左フリック'],
      up: _actions['上フリック'],
      right: _actions['右フリック'],
      down: _actions['下フリック'],
      longPress: _actions['長押し'],
    );
    if (widget.returnValue) {
      Navigator.of(context).pop(value);
    } else {
      AppControllerScope.of(context).replaceCustomKey(value);
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _label.dispose();
    super.dispose();
  }
}

class _ActionEditor extends StatefulWidget {
  const _ActionEditor({this.action});
  final KeyActionData? action;

  @override
  State<_ActionEditor> createState() => _ActionEditorState();
}

class _ActionEditorState extends State<_ActionEditor> {
  late String _type;
  late final TextEditingController _value;

  static const _types = {
    'input': '文字を入力',
    'delete': '削除',
    'enter': '改行',
    'space': '空白',
    'moveCursor': 'カーソル移動',
    'switchLayout': '言語・配列を変更',
    'paste': 'ペースト',
    'toggleTabBar': 'タブバーを開閉',
    'dismiss': 'キーボードを閉じる',
  };

  @override
  void initState() {
    super.initState();
    _type = widget.action?.type ?? 'input';
    _value = TextEditingController(text: widget.action?.value ?? '');
  }

  @override
  Widget build(BuildContext context) {
    final needsValue = const {
      'input',
      'delete',
      'moveCursor',
      'switchLayout',
    }.contains(_type);
    return AlertDialog(
      title: const Text('アクション'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: '種類'),
              items: _types.entries
                  .map(
                    (entry) => DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _type = value ?? 'input'),
            ),
            if (needsValue) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _value,
                decoration: InputDecoration(
                  labelText: _type == 'input'
                      ? '入力する文字列'
                      : _type == 'moveCursor'
                      ? '移動量（例: -1）'
                      : '値',
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            KeyActionData(type: _type, value: _value.text),
          ),
          child: const Text('決定'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }
}

class TabBarEditorPage extends StatelessWidget {
  const TabBarEditorPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('タブバーを編集')),
      body: ReorderableListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: controller.data.tabBar.length,
        onReorderItem: controller.reorderTabBar,
        itemBuilder: (context, index) {
          final item = controller.data.tabBar[index];
          return Card(
            key: ValueKey(item),
            child: ListTile(
              leading: const Icon(Icons.drag_handle),
              title: Text(_tabLabel(controller.data, item)),
              trailing: const Icon(Icons.reorder),
            ),
          );
        },
      ),
    );
  }

  String _tabLabel(AppData data, String value) {
    if (value.startsWith('custom:')) {
      final id = value.substring('custom:'.length);
      for (final tab in data.customTabs) {
        if (tab.id == id) return tab.name;
      }
      return '不明なカスタムタブ';
    }
    return const {
          'dismiss': 'キーボードを閉じる',
          'resize': '片手モード',
          'emoji': '絵文字',
          'japanese': 'あいう',
          'english': 'ABC',
          'clipboard': 'コピー履歴',
        }[value] ??
        value;
  }
}

String _actionLabel(KeyActionData action) {
  final label =
      const {
        'input': '入力',
        'delete': '削除',
        'enter': '改行',
        'space': '空白',
        'moveCursor': 'カーソル移動',
        'switchLayout': '配列変更',
        'paste': 'ペースト',
        'toggleTabBar': 'タブバー',
        'dismiss': '閉じる',
      }[action.type] ??
      action.type;
  return action.value.isEmpty ? label : '$label: ${action.value}';
}
