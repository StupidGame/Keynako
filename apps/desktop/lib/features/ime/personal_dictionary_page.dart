import 'package:flutter/material.dart';
import 'package:keynako_conversion/keynako_conversion.dart';

import '../../input/desktop_input_controller.dart';

class PersonalDictionaryPage extends StatefulWidget {
  const PersonalDictionaryPage({required this.controller, super.key});

  final DesktopInputController controller;

  @override
  State<PersonalDictionaryPage> createState() => _PersonalDictionaryPageState();
}

class _PersonalDictionaryPageState extends State<PersonalDictionaryPage> {
  bool _saving = false;
  final _searchController = TextEditingController();
  var _search = DictionarySearch('');

  void _updateSearch(String query) =>
      setState(() => _search = DictionarySearch(query));

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _edit({ConversionDictionaryEntry? existing}) async {
    final current = widget.controller.personalDictionary;
    final index = existing == null ? null : current.indexOf(existing);
    if (index == -1) return;
    final result = await showDialog<ConversionDictionaryEntry>(
      context: context,
      builder: (_) => _DictionaryEditDialog(
        existing: existing,
        entries: current,
        editingIndex: index,
        englishMode: widget.controller.mode == InputMode.english,
      ),
    );
    if (result == null || !mounted) return;
    final updated = [...widget.controller.personalDictionary];
    if (existing == null) {
      updated.add(result);
    } else {
      final currentIndex = updated.indexOf(existing);
      if (currentIndex < 0) return;
      updated[currentIndex] = result;
    }
    await _save(updated);
  }

  Future<void> _save(List<ConversionDictionaryEntry> entries) async {
    setState(() => _saving = true);
    try {
      await widget.controller.savePersonalDictionary(entries);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('個人辞書を保存できなかった')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete(ConversionDictionaryEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('単語を削除'),
        content: Text('「${entry.value}」を削除する？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final updated = [...widget.controller.personalDictionary];
    if (!updated.remove(entry)) return;
    await _save(updated);
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.controller.personalDictionary;
    final visible = entries
        .asMap()
        .entries
        .where(
          (item) => _search.matches(
            reading: item.value.reading,
            word: item.value.value,
          ),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('個人辞書')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('dictionary-add'),
        onPressed: _saving ? null : () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('単語を登録'),
      ),
      body: widget.controller.personalDictionaryLoadFailed
          ? const Center(child: Text('保存済みの個人辞書を読み込めなかった。ファイルを確認してね'))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: SearchBar(
                    controller: _searchController,
                    leading: const Icon(Icons.search),
                    hintText: '読み・単語・ローマ字で検索',
                    onChanged: _updateSearch,
                    trailing: [
                      if (!_search.isEmpty)
                        IconButton(
                          tooltip: '検索をクリア',
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            _updateSearch('');
                          },
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: visible.isEmpty
                      ? Center(
                          child: Text(
                            entries.isEmpty
                                ? '登録した単語はまだないよ'
                                : '一致する単語が見つからなかったよ',
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 88),
                          itemCount: visible.length,
                          itemBuilder: (context, position) {
                            final MapEntry(key: index, value: entry) =
                                visible[position];
                            return ListTile(
                              key: Key('dictionary-entry-$index'),
                              title: Text(entry.value),
                              subtitle: Text(
                                '${entry.reading} · 重要度 ${entry.importance}',
                              ),
                              onTap: _saving
                                  ? null
                                  : () => _edit(existing: entry),
                              trailing: IconButton(
                                tooltip: '削除',
                                onPressed: _saving
                                    ? null
                                    : () => _delete(entry),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

class _DictionaryEditDialog extends StatefulWidget {
  const _DictionaryEditDialog({
    required this.existing,
    required this.entries,
    required this.editingIndex,
    required this.englishMode,
  });

  final ConversionDictionaryEntry? existing;
  final List<ConversionDictionaryEntry> entries;
  final int? editingIndex;
  final bool englishMode;

  @override
  State<_DictionaryEditDialog> createState() => _DictionaryEditDialogState();
}

class _DictionaryEditDialogState extends State<_DictionaryEditDialog> {
  late final TextEditingController _reading;
  late final TextEditingController _word;
  late int _importance;
  late bool _englishReading;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reading = TextEditingController(text: widget.existing?.reading ?? '');
    _word = TextEditingController(text: widget.existing?.value ?? '');
    _importance = widget.existing?.importance ?? 3;
    _englishReading = widget.existing == null
        ? widget.englishMode
        : RegExp(r'^[\x00-\x7F]+$').hasMatch(widget.existing!.reading);
  }

  @override
  void dispose() {
    _reading.dispose();
    _word.dispose();
    super.dispose();
  }

  void _save() {
    final rawReading = _reading.text.trim();
    final value = _word.text.trim();
    final converter = const JapaneseConverter();
    final normalized = _englishReading
        ? rawReading.toLowerCase()
        : converter.katakanaToHiragana(
            converter.romanToHiragana(rawReading.toLowerCase()),
          );
    if (normalized.isEmpty ||
        value.isEmpty ||
        normalized.length > 128 ||
        value.length > 128 ||
        normalized.contains(RegExp(r'[\t\r\n]')) ||
        value.contains(RegExp(r'[\t\r\n]'))) {
      setState(() => _error = '読みと単語を確認してね（各128文字まで）');
      return;
    }
    if (widget.entries.asMap().entries.any(
      (entry) =>
          entry.key != widget.editingIndex &&
          entry.value.reading == normalized &&
          entry.value.value == value,
    )) {
      setState(() => _error = '同じ読みと単語が登録済みだよ');
      return;
    }
    Navigator.pop(
      context,
      ConversionDictionaryEntry(
        reading: normalized,
        value: value,
        importance: _importance,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.existing == null ? '単語を登録' : '単語を編集'),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('dictionary-reading'),
            controller: _reading,
            autofocus: true,
            decoration: const InputDecoration(labelText: '読み（ローマ字も可）'),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('dictionary-word'),
            controller: _word,
            decoration: const InputDecoration(labelText: '単語'),
          ),
          SwitchListTile(
            key: const Key('dictionary-english-reading'),
            title: const Text('英語の読み'),
            value: _englishReading,
            onChanged: (value) => setState(() => _englishReading = value),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            key: const Key('dictionary-importance'),
            initialValue: _importance,
            decoration: const InputDecoration(labelText: '重要度'),
            items: [
              for (var value = 1; value <= 5; value++)
                DropdownMenuItem(value: value, child: Text('$value')),
            ],
            onChanged: (value) => _importance = value ?? _importance,
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
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
        key: const Key('dictionary-save'),
        onPressed: _save,
        child: const Text('保存'),
      ),
    ],
  );
}
