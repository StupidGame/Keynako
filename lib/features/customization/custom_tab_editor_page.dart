part of 'customization_page.dart';

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
