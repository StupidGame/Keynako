import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/app_controller.dart';
import '../../models/app_data.dart';
import '../../widgets/keyboard_preview.dart';

class ThemePage extends StatelessWidget {
  const ThemePage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final data = controller.data;
    return Scaffold(
      appBar: AppBar(title: const Text('着せ替え')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          FilledButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ThemeEditorPage()),
            ),
            icon: const Icon(Icons.add),
            label: const Text('着せ替えを作成'),
          ),
          const SizedBox(height: 18),
          Text('選ぶ', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          for (final theme in data.themes)
            _ThemeCard(
              theme: theme,
              lightSelected: data.lightThemeId == theme.id,
              darkSelected: data.darkThemeId == theme.id,
            ),
        ],
      ),
    );
  }
}

class _ThemeCard extends StatelessWidget {
  const _ThemeCard({
    required this.theme,
    required this.lightSelected,
    required this.darkSelected,
  });

  final KeyboardThemeConfig theme;
  final bool lightSelected;
  final bool darkSelected;

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final builtIn = const {'classic', 'midnight', 'azuki'}.contains(theme.id);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 7),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(10),
            child: KeyboardPreview(theme: theme),
          ),
          ListTile(
            title: Text(theme.name),
            subtitle: Wrap(
              spacing: 6,
              children: [
                if (lightSelected)
                  const Chip(
                    avatar: Icon(Icons.light_mode, size: 16),
                    label: Text('ライト'),
                    visualDensity: VisualDensity.compact,
                  ),
                if (darkSelected)
                  const Chip(
                    avatar: Icon(Icons.dark_mode, size: 16),
                    label: Text('ダーク'),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            trailing: PopupMenuButton<String>(
              onSelected: (value) async {
                switch (value) {
                  case 'light':
                    await controller.selectTheme(theme.id, dark: false);
                  case 'dark':
                    await controller.selectTheme(theme.id, dark: true);
                  case 'edit':
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ThemeEditorPage(theme: theme),
                      ),
                    );
                  case 'share':
                    await controller.platform.shareText(
                      subject: 'Keynako theme: ${theme.name}',
                      text: jsonEncode({
                        'azooKeyTheme': theme
                            .copyWith(clearBackgroundImage: true)
                            .toJson(),
                      }),
                    );
                  case 'delete':
                    final backgroundImage = theme.backgroundImage;
                    controller.removeTheme(theme.id);
                    await controller.flush();
                    if (backgroundImage != null) {
                      await controller.platform.deleteKeyboardBackgroundImage(
                        backgroundImage,
                      );
                    }
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'light', child: Text('ライトモードで使用')),
                const PopupMenuItem(value: 'dark', child: Text('ダークモードで使用')),
                const PopupMenuDivider(),
                if (!builtIn)
                  const PopupMenuItem(value: 'edit', child: Text('編集')),
                const PopupMenuItem(value: 'share', child: Text('共有')),
                if (!builtIn)
                  const PopupMenuItem(value: 'delete', child: Text('削除')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ThemeEditorPage extends StatefulWidget {
  const ThemeEditorPage({this.theme, super.key});

  final KeyboardThemeConfig? theme;

  @override
  State<ThemeEditorPage> createState() => _ThemeEditorPageState();
}

class _ThemeEditorPageState extends State<ThemeEditorPage> {
  late final TextEditingController _name;
  late final String _id;
  late int _background;
  late int _key;
  late int _special;
  late int _text;
  late int _accent;
  late double _keyOpacity;
  String? _backgroundImage;
  late int _backgroundImageRevision;
  Uint8List? _pickedBackgroundImage;
  var _removeBackgroundImage = false;
  var _saving = false;

  static const _colors = [
    0xffffffff,
    0xfff8fafc,
    0xffd1d5db,
    0xff94a3b8,
    0xff334155,
    0xff111827,
    0xfffee2e2,
    0xfffca5a5,
    0xff9f3a48,
    0xffffedd5,
    0xfffde68a,
    0xffbbf7d0,
    0xff86efac,
    0xffdbeafe,
    0xff60a5fa,
    0xff2563eb,
    0xffe9d5ff,
    0xffc084fc,
  ];

  @override
  void initState() {
    super.initState();
    final source = widget.theme ?? AppData.defaults().themes.first;
    _id = widget.theme?.id ?? 'theme-${DateTime.now().millisecondsSinceEpoch}';
    _name = TextEditingController(
      text: widget.theme == null ? '新しい着せ替え' : source.name,
    );
    _background = source.backgroundColor;
    _key = source.keyColor;
    _special = source.specialKeyColor;
    _text = source.textColor;
    _accent = source.accentColor;
    _backgroundImage = source.backgroundImage;
    _backgroundImageRevision = source.backgroundImageRevision;
    _keyOpacity = source.keyOpacity;
  }

  KeyboardThemeConfig get _value => KeyboardThemeConfig(
    id: _id,
    name: _name.text.trim().isEmpty ? '名称未設定' : _name.text.trim(),
    backgroundColor: _background,
    keyColor: _key,
    specialKeyColor: _special,
    textColor: _text,
    accentColor: _accent,
    backgroundImage: _removeBackgroundImage ? null : _backgroundImage,
    backgroundImageRevision: _backgroundImageRevision,
    keyOpacity: _keyOpacity,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.theme == null ? '着せ替えを作成' : '着せ替えを編集'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('保存'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          KeyboardPreview(
            theme: _value,
            compact: false,
            backgroundImageBytes: _pickedBackgroundImage,
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: '着せ替え名'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 18),
          _ColorSetting(
            title: '背景',
            value: _background,
            colors: _colors,
            onChanged: (value) => setState(() => _background = value),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('背景画像', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  const Text(
                    '端末内の画像を最大2048pxに調整し、キーボードの比率に合わせて中央を切り抜きます。'
                    '画像自体はテーマ共有に含まれません。',
                  ),
                  const SizedBox(height: 10),
                  FilledButton.tonalIcon(
                    onPressed: _pickBackgroundImage,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: Text(
                      _pickedBackgroundImage != null ||
                              (_backgroundImage != null &&
                                  !_removeBackgroundImage)
                          ? '別の画像を選ぶ'
                          : '画像を選ぶ',
                    ),
                  ),
                  if (_pickedBackgroundImage != null ||
                      (_backgroundImage != null && !_removeBackgroundImage))
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 10),
                        Text(
                          'キー背景の透過度 '
                          '${((1 - _keyOpacity) * 100).round()}%',
                        ),
                        Slider(
                          value: 1 - _keyOpacity,
                          min: 0,
                          max: 0.85,
                          divisions: 17,
                          label: '${((1 - _keyOpacity) * 100).round()}%',
                          onChanged: (value) =>
                              setState(() => _keyOpacity = 1 - value),
                        ),
                        TextButton.icon(
                          onPressed: () => setState(() {
                            _pickedBackgroundImage = null;
                            _removeBackgroundImage = true;
                          }),
                          icon: const Icon(Icons.hide_image_outlined),
                          label: const Text('背景画像を外す'),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _ColorSetting(
            title: '通常キー',
            value: _key,
            colors: _colors,
            onChanged: (value) => setState(() => _key = value),
          ),
          _ColorSetting(
            title: '特殊キー',
            value: _special,
            colors: _colors,
            onChanged: (value) => setState(() => _special = value),
          ),
          _ColorSetting(
            title: '文字',
            value: _text,
            colors: _colors,
            onChanged: (value) => setState(() => _text = value),
          ),
          _ColorSetting(
            title: 'アクセント',
            value: _accent,
            colors: _colors,
            onChanged: (value) => setState(() => _accent = value),
          ),
        ],
      ),
    );
  }

  Future<void> _pickBackgroundImage() async {
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 85,
        requestFullMetadata: false,
      );
      if (image == null) return;
      final bytes = await image.readAsBytes();
      if (!mounted) return;
      if (bytes.length > 8 * 1024 * 1024) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('画像を8MB以下にしてください。')));
        return;
      }
      setState(() {
        if (_backgroundImage == null && _pickedBackgroundImage == null) {
          _keyOpacity = 0.72;
        }
        _pickedBackgroundImage = bytes;
        _removeBackgroundImage = false;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('画像を読み込めませんでした。')));
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final controller = AppControllerScope.of(context);
    var backgroundImage = _removeBackgroundImage ? null : _backgroundImage;
    var backgroundImageRevision = _backgroundImageRevision;
    final bytes = _pickedBackgroundImage;
    if (bytes != null) {
      backgroundImage = await controller.platform.saveKeyboardBackgroundImage(
        themeId: _id,
        bytes: bytes,
      );
      if (!mounted) return;
      if (backgroundImage == null) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('背景画像を保存できませんでした。')));
        return;
      }
      backgroundImageRevision = DateTime.now().microsecondsSinceEpoch;
    } else if (backgroundImage == null) {
      backgroundImageRevision = 0;
    }

    final oldBackgroundImage = widget.theme?.backgroundImage;
    controller.replaceTheme(
      _value.copyWith(
        backgroundImage: backgroundImage,
        backgroundImageRevision: backgroundImageRevision,
        clearBackgroundImage: backgroundImage == null,
      ),
    );
    await controller.flush();
    if (oldBackgroundImage != null && oldBackgroundImage != backgroundImage) {
      await controller.platform.deleteKeyboardBackgroundImage(
        oldBackgroundImage,
      );
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }
}

class _ColorSetting extends StatelessWidget {
  const _ColorSetting({
    required this.title,
    required this.value,
    required this.colors,
    required this.onChanged,
  });

  final String title;
  final int value;
  final List<int> colors;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: colors.map((color) {
              final selected = value == color;
              return InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => onChanged(color),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Color(color),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outlineVariant,
                      width: selected ? 3 : 1,
                    ),
                  ),
                  child: selected
                      ? Icon(
                          Icons.check,
                          size: 18,
                          color:
                              ThemeData.estimateBrightnessForColor(
                                    Color(color),
                                  ) ==
                                  Brightness.dark
                              ? Colors.white
                              : Colors.black,
                        )
                      : null,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
