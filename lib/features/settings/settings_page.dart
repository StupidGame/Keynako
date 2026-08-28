import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_controller.dart';
import '../../models/app_data.dart';
import '../../models/setting_descriptor.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  var _query = '';

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final visible = settingCatalog.where((item) => item.matches(_query));
    final groups = <String, List<SettingDescriptor>>{};
    for (final descriptor in visible) {
      groups.putIfAbsent(descriptor.group, () => []).add(descriptor);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            sliver: SliverToBoxAdapter(
              child: SearchBar(
                leading: const Icon(Icons.search),
                hintText: '設定を検索',
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
            sliver: SliverList.list(
              children: [
                for (final group in groups.entries) ...[
                  _SectionHeader(group.key),
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (
                          var index = 0;
                          index < group.value.length;
                          index++
                        ) ...[
                          SettingTile(descriptor: group.value[index]),
                          if (index != group.value.length - 1)
                            const Divider(height: 1, indent: 16, endIndent: 16),
                        ],
                        if (group.key == '変換') ...[
                          const Divider(height: 1, indent: 16, endIndent: 16),
                          ListTile(
                            leading: const Icon(Icons.psychology_outlined),
                            title: const Text('Zenzaiについて'),
                            subtitle: const Text('モデル、エフォート、安全性'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const ZenzaiInfoPage(),
                              ),
                            ),
                          ),
                          if (controller.setting(
                            'enable_contact_import',
                            false,
                          ))
                            ListTile(
                              leading: const Icon(Icons.contacts_outlined),
                              title: const Text('連絡先を今すぐ読み込む'),
                              onTap: () => _importContacts(context),
                            ),
                        ],
                        if (group.key == 'ユーザ辞書') ...[
                          const Divider(height: 1, indent: 16, endIndent: 16),
                          ListTile(
                            leading: const Icon(Icons.menu_book_outlined),
                            title: const Text('Keynakoユーザ辞書'),
                            subtitle: Text(
                              '${controller.data.userDictionary.length}件',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const UserDictionaryPage(),
                              ),
                            ),
                          ),
                          const Divider(height: 1, indent: 16, endIndent: 16),
                          ListTile(
                            leading: const Icon(Icons.sync),
                            title: const Text('Keynako共有変換辞書'),
                            subtitle: Text(
                              controller.azooKeyHotfixSyncing
                                  ? '最新の共有語を確認しています…'
                                  : controller.azooKeyHotfixSyncError != null
                                  ? '前回の同期に失敗しました。タップして再試行できます。'
                                  : '${controller.data.azooKeyHotfixDictionary?.entries.length ?? 0}件'
                                        '${controller.data.azooKeyHotfixLatestTag == null ? '・未同期' : '・${controller.data.azooKeyHotfixLatestTag}'}',
                            ),
                            trailing: controller.azooKeyHotfixSyncing
                                ? const SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.refresh),
                            onTap: controller.azooKeyHotfixSyncing
                                ? null
                                : () => _syncAzooKeyHotfix(context),
                          ),
                        ],
                        if (group.key == '学習機能') ...[
                          const Divider(height: 1, indent: 16, endIndent: 16),
                          ListTile(
                            leading: const Icon(Icons.delete_sweep_outlined),
                            title: const Text('学習のリセット'),
                            subtitle: const Text('候補選択の履歴をすべて消去します。'),
                            onTap: () => _confirmLearningReset(context),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                if (_query.isEmpty) ...[
                  const _SectionHeader('データ'),
                  Card(
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.ios_share),
                          title: const Text('設定データをエクスポート'),
                          subtitle: const Text('テーマ、辞書、カスタムタブをJSONで共有します。'),
                          onTap: () => controller.platform.shareText(
                            subject: 'Keynako settings backup',
                            text: controller.data.encode(),
                          ),
                        ),
                        const Divider(height: 1, indent: 16, endIndent: 16),
                        ListTile(
                          leading: const Icon(Icons.file_download_outlined),
                          title: const Text('設定データをインポート'),
                          subtitle: const Text('現在の設定をバックアップ内容で置き換えます。'),
                          onTap: () => _importBackup(context),
                        ),
                      ],
                    ),
                  ),
                  const _SectionHeader('このアプリについて'),
                  Card(
                    child: Column(
                      children: [
                        const ListTile(
                          leading: Icon(Icons.code),
                          title: Text('オープンソースソフトウェア'),
                          subtitle: Text(
                            'Keynako: Apache-2.0 / azooKey: MIT / Zenzai: Apache-2.0',
                          ),
                        ),
                        const Divider(height: 1, indent: 16, endIndent: 16),
                        const ListTile(
                          leading: Icon(Icons.link),
                          title: Text('URL Scheme'),
                          trailing: Text('keynako://'),
                        ),
                        const Divider(height: 1, indent: 16, endIndent: 16),
                        const ListTile(
                          leading: Icon(Icons.info_outline),
                          title: Text('バージョン'),
                          trailing: Text('3.0.1'),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _importContacts(BuildContext context) async {
    final count = await AppControllerScope.of(context).importContacts();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$count件の連絡先をユーザ辞書へ追加しました。')));
  }

  Future<void> _syncAzooKeyHotfix(BuildContext context) async {
    try {
      final updated = await AppControllerScope.of(context)
          .syncAzooKeyHotfixDictionary(force: true);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(updated ? 'Keynako共有変換辞書を更新しました。' : 'すでに最新の共有変換辞書です。'),
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Keynako共有変換辞書を取得できませんでした。')),
      );
    }
  }

  Future<void> _confirmLearningReset(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('学習をリセットしますか？'),
        content: const Text('候補選択の学習履歴は元に戻せません。ユーザ辞書は削除されません。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('リセット'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      AppControllerScope.of(context).resetLearning();
    }
  }

  Future<void> _importBackup(BuildContext context) async {
    final text = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('設定データをインポート'),
        content: TextField(
          controller: text,
          minLines: 6,
          maxLines: 12,
          decoration: const InputDecoration(hintText: 'バックアップJSON'),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              text.text =
                  (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
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
    if (value == null || !context.mounted) return;
    try {
      await AppControllerScope.of(context).importJson(value);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('バックアップを読み込めませんでした。')));
      }
    }
  }
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

class SettingTile extends StatelessWidget {
  const SettingTile({required this.descriptor, super.key});

  final SettingDescriptor descriptor;

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    return switch (descriptor.kind) {
      SettingKind.toggle => SwitchListTile(
        title: _title(context),
        subtitle: Text(descriptor.explanation),
        value: controller.setting(descriptor.key, false),
        onChanged: (value) => controller.setSetting(descriptor.key, value),
      ),
      SettingKind.choice => ListTile(
        title: _title(context),
        subtitle: Text(descriptor.explanation),
        trailing: DropdownButton<Object>(
          value: _optionValue(controller.data.settings[descriptor.key]),
          underline: const SizedBox.shrink(),
          items: descriptor.options
              .map(
                (option) => DropdownMenuItem<Object>(
                  value: option.value,
                  child: Text(option.label),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value != null) controller.setSetting(descriptor.key, value);
          },
        ),
      ),
      SettingKind.slider => _SliderSetting(descriptor: descriptor),
      SettingKind.text => ListTile(
        title: _title(context),
        subtitle: Text(descriptor.explanation),
        trailing: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 120),
          child: Text(
            controller.setting(descriptor.key, '').toString().isEmpty
                ? '未設定'
                : controller.setting(descriptor.key, '').toString(),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        onTap: () => _editText(context),
      ),
    };
  }

  Widget _title(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Flexible(child: Text(descriptor.title)),
      if (descriptor.requiresFullAccess) ...[
        const SizedBox(width: 6),
        Tooltip(
          message: '追加権限またはフルアクセスが必要です',
          child: Icon(
            Icons.lock_open,
            size: 16,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ],
    ],
  );

  Object _optionValue(Object? current) {
    for (final option in descriptor.options) {
      if (option.value == current) return option.value;
    }
    return descriptor.options.first.value;
  }

  Future<void> _editText(BuildContext context) async {
    final controller = AppControllerScope.of(context);
    final text = TextEditingController(
      text: controller.setting(descriptor.key, '').toString(),
    );
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(descriptor.title),
        content: TextField(controller: text, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, text.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (value != null && context.mounted) {
      controller.setSetting(descriptor.key, value);
    }
  }
}

class _SliderSetting extends StatelessWidget {
  const _SliderSetting({required this.descriptor});

  final SettingDescriptor descriptor;

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final raw = controller.data.settings[descriptor.key];
    final automatic =
        descriptor.automaticValue != null && raw == descriptor.automaticValue;
    final value = automatic
        ? (descriptor.minimum! + descriptor.maximum!) / 2
        : (raw as num?)?.toDouble().clamp(
                descriptor.minimum!,
                descriptor.maximum!,
              ) ??
              descriptor.minimum!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  descriptor.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text(
                automatic
                    ? '自動'
                    : '${value.toStringAsFixed(descriptor.decimalPlaces)}${descriptor.valueSuffix}',
              ),
            ],
          ),
          Text(
            descriptor.explanation,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          Slider(
            value: value,
            min: descriptor.minimum!,
            max: descriptor.maximum!,
            divisions: descriptor.divisions,
            onChanged: automatic
                ? null
                : (newValue) => controller.setSetting(descriptor.key, newValue),
          ),
          if (descriptor.automaticValue != null)
            Align(
              alignment: Alignment.centerRight,
              child: FilterChip(
                label: const Text('自動調整'),
                selected: automatic,
                onSelected: (selected) => controller.setSetting(
                  descriptor.key,
                  selected ? descriptor.automaticValue! : value,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class ZenzaiInfoPage extends StatelessWidget {
  const ZenzaiInfoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Zenzaiについて')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: const [
          ListTile(
            leading: Icon(Icons.psychology),
            title: Text('ニューラルかな漢字変換'),
            subtitle: Text('文脈を使って候補の自然さを評価します。'),
          ),
          ListTile(
            leading: Icon(Icons.phonelink_lock),
            title: Text('完全オフライン'),
            subtitle: Text('入力内容とモデル推論は端末内で処理され、Zenzaiの利用に通信は必要ありません。'),
          ),
          ListTile(
            leading: Icon(Icons.speed),
            title: Text('低エフォート'),
            subtitle: Text('xsmall Q5_K_M（20,970,304 bytes）を使用します。'),
          ),
          ListTile(
            leading: Icon(Icons.auto_awesome),
            title: Text('中・高エフォート'),
            subtitle: Text('small Q5_K_M（73,871,936 bytes）を使用し、高では探索回数を増やします。'),
          ),
          Padding(
            padding: EdgeInsets.all(16),
            child: Text('モデル: zenz-v3.2 / Apache License 2.0'),
          ),
        ],
      ),
    );
  }
}

class UserDictionaryPage extends StatefulWidget {
  const UserDictionaryPage({super.key});

  @override
  State<UserDictionaryPage> createState() => _UserDictionaryPageState();
}

class _UserDictionaryPageState extends State<UserDictionaryPage> {
  var _query = '';

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final entries = controller.data.userDictionary.where((entry) {
      final query = _query.toLowerCase();
      return entry.ruby.toLowerCase().contains(query) ||
          entry.word.toLowerCase().contains(query);
    }).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('ユーザ辞書'),
        actions: [
          IconButton(
            tooltip: '追加',
            icon: const Icon(Icons.add),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const UserDictionaryEditorPage(),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: SearchBar(
              leading: const Icon(Icons.search),
              hintText: '読み・単語を検索',
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final entry = entries[index];
                return Dismissible(
                  key: ValueKey(entry.id),
                  background: Container(
                    color: Theme.of(context).colorScheme.errorContainer,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 24),
                    child: const Icon(Icons.delete),
                  ),
                  direction: DismissDirection.endToStart,
                  onDismissed: (_) =>
                      controller.removeDictionaryEntry(entry.id),
                  child: ListTile(
                    title: Text(
                      entry.isTemplateMode
                          ? (entry.formatLiteral ?? entry.word)
                          : entry.word,
                    ),
                    subtitle: Text('${entry.ruby} ・ 重要度 ${entry.importance}'),
                    leading: Icon(
                      entry.isTemplateMode
                          ? Icons.schedule
                          : entry.isPersonName
                          ? Icons.person_outline
                          : entry.isPlaceName
                          ? Icons.place_outlined
                          : Icons.text_fields,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => UserDictionaryEditorPage(entry: entry),
                      ),
                    ),
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

class UserDictionaryEditorPage extends StatefulWidget {
  const UserDictionaryEditorPage({this.entry, super.key});
  final UserDictionaryEntry? entry;

  @override
  State<UserDictionaryEditorPage> createState() =>
      _UserDictionaryEditorPageState();
}

class _UserDictionaryEditorPageState extends State<UserDictionaryEditorPage> {
  late final TextEditingController _word;
  late final TextEditingController _ruby;
  late final TextEditingController _format;
  late bool _verb;
  late bool _person;
  late bool _place;
  late bool _template;
  late bool _shared;
  late int _importance;

  @override
  void initState() {
    super.initState();
    final entry = widget.entry;
    _word = TextEditingController(text: entry?.word ?? '');
    _ruby = TextEditingController(text: entry?.ruby ?? '');
    _format = TextEditingController(text: entry?.formatLiteral ?? 'yyyy/MM/dd');
    _verb = entry?.isVerb ?? false;
    _person = entry?.isPersonName ?? false;
    _place = entry?.isPlaceName ?? false;
    _template = entry?.isTemplateMode ?? false;
    _shared = entry?.shared ?? false;
    _importance = entry?.importance ?? 3;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ユーザ辞書を編集'),
        actions: [TextButton(onPressed: _save, child: const Text('保存'))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _ruby,
            decoration: const InputDecoration(
              labelText: '読み',
              helperText: 'ひらがな、英字、数字で入力します。',
            ),
          ),
          const SizedBox(height: 12),
          if (_template)
            TextField(
              controller: _format,
              decoration: const InputDecoration(
                labelText: '日時の書式',
                helperText: '例: yyyy年MM月dd日 HH:mm',
              ),
            )
          else
            TextField(
              controller: _word,
              decoration: const InputDecoration(labelText: '単語'),
            ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('時刻・ランダム変換'),
            value: _template,
            onChanged: (value) => setState(() => _template = value),
          ),
          if (!_template) ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('「〜らない」と活用できる動詞'),
              value: _verb,
              onChanged: (value) => setState(() => _verb = value),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('人・動物・会社などの名前'),
              value: _person,
              onChanged: (value) => setState(() => _person = value),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('場所・建物などの名前'),
              value: _place,
              onChanged: (value) => setState(() => _place = value),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('変換の重要度 $_importance'),
              subtitle: const Text('1は低く、5は高く候補へ表示します。共有時にも同じ重要度を送ります。'),
            ),
            Slider(
              value: _importance.toDouble(),
              min: 1,
              max: 5,
              divisions: 4,
              label: '$_importance',
              onChanged: (value) => setState(() => _importance = value.round()),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('この変換をKeynakoと共有'),
              subtitle: const Text(
                'オンで保存すると、読み・単語・品詞・重要度をKeynakoの共有辞書へ自動送信します。',
              ),
              value: _shared,
              onChanged: (value) => setState(() => _shared = value),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _save() async {
    final ruby = _ruby.text.trim();
    final word = _word.text.trim();
    if (ruby.isEmpty ||
        (!_template && word.isEmpty) ||
        (_template && _format.text.isEmpty)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('読みと単語（または書式）を入力してください。')));
      return;
    }
    final controller = AppControllerScope.of(context);
    final wantsShare = _shared && !_template;
    final payloadAlreadyShared =
        widget.entry?.hasSameSharedPayload(
          ruby: ruby,
          word: word,
          isVerb: _verb,
          isPersonName: _person,
          isPlaceName: _place,
          importance: _importance,
        ) ??
        false;
    var shared = wantsShare && payloadAlreadyShared;
    if (wantsShare && !payloadAlreadyShared) {
      final categories = <String>[
        if (_person) '人・動物・会社などの名前',
        if (_place) '場所・建物などの名前',
        if (_verb) '五段活用',
      ];
      shared = await controller.platform.submitSharedWord(
        word: word,
        ruby: ruby,
        importance: _importance,
        categories: categories,
      );
      if (!mounted) return;
      if (!shared) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('共有先への送信に失敗しました。単語は端末内へ保存します。')),
        );
      }
    }
    controller.addOrUpdateDictionaryEntry(
      UserDictionaryEntry(
        id: widget.entry?.id ?? controller.nextDictionaryId(),
        ruby: ruby,
        word: word,
        isVerb: _verb,
        isPersonName: _person,
        isPlaceName: _place,
        importance: _importance,
        shared: shared,
        isTemplateMode: _template,
        formatLiteral: _template ? _format.text : null,
      ),
    );
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _word.dispose();
    _ruby.dispose();
    _format.dispose();
    super.dispose();
  }
}
