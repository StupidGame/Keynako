part of 'customization_page.dart';

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
  late String _target;
  late final Map<String, KeyActionData?> _actions;

  @override
  void initState() {
    super.initState();
    final key = widget.keyData;
    _name = TextEditingController(text: key?.name ?? '新しいキー');
    _label = TextEditingController(text: key?.label ?? '＋');
    _target = key?.target ?? 'standalone';
    _actions = {
      'タップ': key?.tap ?? const KeyActionData(type: 'input'),
      '左フリック': key?.left,
      '上フリック': key?.up,
      '右フリック': key?.right,
      '下フリック': key?.down,
      '長押し': key?.longPress,
      '長押し反復': key?.longPressRepeat,
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
          DropdownButtonFormField<String>(
            initialValue: _target,
            decoration: const InputDecoration(labelText: '配置先'),
            items:
                const {
                      'standalone': '独立キー',
                      'kogana': 'フリック「小ﾞﾟ」',
                      'kana_symbols': 'フリック「､｡?!」',
                      'hira_tab': 'フリック「あいう」',
                      'abc_tab': 'フリック「ABC」',
                      'symbols_tab': 'フリック「☆123」',
                    }.entries
                    .map(
                      (entry) => DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                    )
                    .toList(),
            onChanged: (value) =>
                setState(() => _target = value ?? 'standalone'),
          ),
          const SizedBox(height: 10),
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
      target: _target,
      tap: _actions['タップ'] ?? const KeyActionData(type: 'input'),
      left: _actions['左フリック'],
      up: _actions['上フリック'],
      right: _actions['右フリック'],
      down: _actions['下フリック'],
      longPress: _actions['長押し'],
      longPressRepeat: _actions['長押し反復'],
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
    'directInput': '文字を直接確定',
    'delete': '削除',
    'smartDeleteDefault': '直前の1単語を削除',
    'enter': '改行',
    'space': '空白',
    'replaceDefault': '小書き・濁点・大文字小文字を切替',
    'moveCursor': 'カーソル移動',
    'switchLayout': '言語・配列を変更',
    'complete': '変換を確定',
    'completeCharacterForm': '文字種を変換して確定',
    'paste': 'ペースト',
    'toggleCursorBar': 'カーソルバーを開閉',
    'toggleTabBar': 'タブバーを開閉',
    'toggleCapsLock': 'Caps Lockを切替',
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
      'directInput',
      'delete',
      'moveCursor',
      'switchLayout',
      'completeCharacterForm',
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
