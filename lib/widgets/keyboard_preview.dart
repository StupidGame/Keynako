import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../input/japanese_converter.dart';
import '../models/app_data.dart';

class KeyboardPreview extends StatelessWidget {
  const KeyboardPreview({
    required this.theme,
    this.layout = 'flick',
    this.compact = true,
    this.onKey,
    super.key,
  });

  final KeyboardThemeConfig theme;
  final String layout;
  final bool compact;
  final ValueChanged<String>? onKey;

  @override
  Widget build(BuildContext context) {
    final background = Color(theme.backgroundColor);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: EdgeInsets.all(compact ? 5 : 7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _candidateBar(),
            const SizedBox(height: 4),
            if (layout == 'qwerty') _qwerty() else _flick(),
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

  Widget _flick() {
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
            return Expanded(child: _key(label, special: special));
          }).toList(),
        );
      }).toList(),
    );
  }

  Widget _qwerty() {
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
              child: _key(label, special: special),
            );
          }).toList(),
        );
      }).toList(),
    );
  }

  Widget _key(String label, {required bool special}) {
    return Padding(
      padding: EdgeInsets.all(compact ? 1.5 : 2.5),
      child: SizedBox(
        height: compact ? 25 : 42,
        child: Material(
          color: Color(special ? theme.specialKeyColor : theme.keyColor),
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

class KeyboardSandboxPage extends StatefulWidget {
  const KeyboardSandboxPage({super.key});

  @override
  State<KeyboardSandboxPage> createState() => _KeyboardSandboxPageState();
}

class _KeyboardSandboxPageState extends State<KeyboardSandboxPage> {
  final _converter = const JapaneseConverter();
  var _layout = 'flick';
  var _committed = '';
  var _composing = '';

  void _handleKey(String key) {
    setState(() {
      switch (key) {
        case '⌫':
          if (_composing.isNotEmpty) {
            _composing = _composing.substring(0, _composing.length - 1);
          } else if (_committed.isNotEmpty) {
            _committed = _committed.substring(0, _committed.length - 1);
          }
        case '空白' || 'space':
          _commitCandidate(_candidates.firstOrNull?.text ?? _composing);
          _committed += ' ';
        case '改行' || 'return':
          _commitCandidate(_candidates.firstOrNull?.text ?? _composing);
          _committed += '\n';
        case '🌐':
          _layout = _layout == 'flick' ? 'qwerty' : 'flick';
        case '☆123' || '⇧':
          break;
        default:
          _composing += key;
      }
    });
  }

  void _commitCandidate(String value) {
    if (value.isEmpty) return;
    _committed += value;
    _composing = '';
  }

  List<ConversionCandidate> get _candidates {
    if (!mounted || _composing.isEmpty) return const [];
    final controller = AppControllerScope.of(context);
    return _converter.candidates(
      input: _composing,
      data: controller.data,
      romanInput: _layout == 'qwerty',
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final theme = controller.data.themeForBrightness(dark: dark);
    final candidates = _candidates;
    final displayComposition = _layout == 'qwerty'
        ? _converter.romanToHiragana(_composing)
        : _composing;

    return Scaffold(
      appBar: AppBar(title: const Text('キーボードを試す')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).dividerColor),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SizedBox.expand(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: _committed),
                            TextSpan(
                              text: displayComposition,
                              style: const TextStyle(
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 44,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                scrollDirection: Axis.horizontal,
                itemCount: candidates.length,
                separatorBuilder: (_, _) => const VerticalDivider(),
                itemBuilder: (context, index) {
                  final candidate = candidates[index];
                  return TextButton(
                    onPressed: () => setState(() {
                      _commitCandidate(candidate.text);
                      final key = '${candidate.reading}\t${candidate.text}';
                      controller.data.learning.update(
                        key,
                        (value) => value + 1,
                        ifAbsent: () => 1,
                      );
                      controller.setSetting(
                        'last_learned_candidate',
                        candidate.text,
                      );
                    }),
                    child: Text(candidate.text),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: KeyboardPreview(
                theme: theme,
                layout: _layout,
                compact: false,
                onKey: _handleKey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
