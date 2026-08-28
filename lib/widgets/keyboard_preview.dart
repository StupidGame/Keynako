import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/app_data.dart';

class KeyboardPreview extends StatelessWidget {
  const KeyboardPreview({
    required this.theme,
    this.layout = 'flick',
    this.compact = true,
    this.backgroundImageBytes,
    this.onKey,
    super.key,
  });

  final KeyboardThemeConfig theme;
  final String layout;
  final bool compact;
  final Uint8List? backgroundImageBytes;
  final ValueChanged<String>? onKey;

  @override
  Widget build(BuildContext context) {
    final background = Color(theme.backgroundColor);
    final image = backgroundImageBytes != null
        ? Image.memory(
            backgroundImageBytes!,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          )
        : theme.backgroundImage != null
        ? Image.file(
            File(theme.backgroundImage!),
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          )
        : null;
    final hasImage = image != null;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: ColoredBox(
        color: background,
        child: Stack(
          children: [
            if (image != null)
              Positioned.fill(child: Opacity(opacity: 0.85, child: image)),
            Padding(
              padding: EdgeInsets.all(compact ? 5 : 7),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _candidateBar(),
                  const SizedBox(height: 4),
                  if (layout == 'qwerty')
                    _qwerty(hasImage: hasImage)
                  else
                    _flick(hasImage: hasImage),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _candidateBar() {
    return SizedBox(
      height: compact ? 25 : 38,
      child: Row(
        children: ['予測', '変換', '候補']
            .map(
              (label) => Expanded(
                child: Center(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: Color(theme.textColor),
                      fontSize: compact ? 9 : 14,
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _flick({required bool hasImage}) {
    const rows = [
      ['あ', 'か', 'さ', '⌫'],
      ['た', 'な', 'は', '空白'],
      ['ま', 'や', 'ら', '改行'],
      ['☆123', '小ﾞﾟ', 'わ', '🌐'],
    ];
    return Column(
      children: rows.map((row) {
        return Row(
          children: row.map((label) {
            final special = const {
              '⌫',
              '空白',
              '改行',
              '☆123',
              '🌐',
            }.contains(label);
            return Expanded(
              child: _key(label, special: special, hasImage: hasImage),
            );
          }).toList(),
        );
      }).toList(),
    );
  }

  Widget _qwerty({required bool hasImage}) {
    const rows = [
      ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'],
      ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l'],
      ['⇧', 'z', 'x', 'c', 'v', 'b', 'n', 'm', '⌫'],
      ['☆123', '🌐', 'space', 'return'],
    ];
    return Column(
      children: rows.map((row) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: row.map((label) {
            final special = const {
              '⇧',
              '⌫',
              '☆123',
              '🌐',
              'return',
            }.contains(label);
            final flex = label == 'space' ? 4 : (row.length == 4 ? 2 : 1);
            return Expanded(
              flex: flex,
              child: _key(label, special: special, hasImage: hasImage),
            );
          }).toList(),
        );
      }).toList(),
    );
  }

  Widget _key(String label, {required bool special, required bool hasImage}) {
    return Padding(
      padding: EdgeInsets.all(compact ? 1.5 : 2.5),
      child: SizedBox(
        height: compact ? 25 : 42,
        child: Material(
          color: Color(special ? theme.specialKeyColor : theme.keyColor)
              .withValues(alpha: hasImage ? theme.keyOpacity : 1),
          borderRadius: BorderRadius.circular(compact ? 4 : 6),
          elevation: compact ? 0.5 : 1,
          child: InkWell(
            borderRadius: BorderRadius.circular(compact ? 4 : 6),
            onTap: onKey == null ? null : () => onKey!(label),
            child: Center(
              child: Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  color: Color(theme.textColor),
                  fontSize: compact ? 8 : 14,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class KeyboardSandboxPage extends StatelessWidget {
  const KeyboardSandboxPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('キーボードを試す')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '端末で選択中のキーボードをそのまま開きます。'
                'Keynakoを選択すると、変換・フリック・カスタムタブを実際のIMEで確認できます。',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              const Expanded(
                child: TextField(
                  key: ValueKey('keyboard-test-field'),
                  autofocus: true,
                  expands: true,
                  maxLines: null,
                  minLines: null,
                  textAlignVertical: TextAlignVertical.top,
                  keyboardType: TextInputType.multiline,
                  decoration: InputDecoration(
                    labelText: '入力テスト',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
