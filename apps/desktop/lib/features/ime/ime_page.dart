import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../input/desktop_input_controller.dart';

class ImePage extends StatefulWidget {
  const ImePage({required this.controller, super.key});

  final DesktopInputController controller;

  @override
  State<ImePage> createState() => _ImePageState();
}

class _ImePageState extends State<ImePage> {
  late final TextEditingController _compositionController;
  late final TextEditingController _outputController;
  final FocusNode _compositionFocus = FocusNode();

  DesktopInputController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _compositionController = TextEditingController(text: controller.rawInput);
    _outputController = TextEditingController(text: controller.committedText);
    controller.addListener(_syncControllers);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _compositionFocus.requestFocus(),
    );
  }

  @override
  void dispose() {
    controller.removeListener(_syncControllers);
    _compositionController.dispose();
    _outputController.dispose();
    _compositionFocus.dispose();
    super.dispose();
  }

  void _syncControllers() {
    if (!mounted) return;
    if (_compositionController.text != controller.rawInput) {
      _compositionController.value = TextEditingValue(
        text: controller.rawInput,
        selection: TextSelection.collapsed(offset: controller.rawInput.length),
      );
    }
    if (_outputController.text != controller.committedText) {
      _outputController.value = TextEditingValue(
        text: controller.committedText,
        selection: TextSelection.collapsed(
          offset: controller.committedSelectionOffset,
        ),
      );
    }
    setState(() {});
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || controller.rawInput.isEmpty) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.space ||
        event.logicalKey == LogicalKeyboardKey.arrowDown) {
      controller.beginOrCycleCandidate(1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      controller.beginOrCycleCandidate(-1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _commitSelected();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (!controller.cancelConversion()) controller.cancelComposition();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _commitSelected() {
    final selection = _outputController.selection;
    controller.commitSelected(
      replaceStart: selection.isValid ? selection.start : null,
      replaceEnd: selection.isValid ? selection.end : null,
    );
  }

  void _updateRawInput(String value) {
    if (value.isNotEmpty && value.trim().isEmpty) {
      final selection = _outputController.selection;
      controller.commitDirectText(
        value,
        replaceStart: selection.isValid ? selection.start : null,
        replaceEnd: selection.isValid ? selection.end : null,
      );
      return;
    }
    controller.updateRawInput(value);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colors.primaryContainer.withValues(alpha: 0.28),
              colors.surfaceContainerLowest,
              colors.tertiaryContainer.withValues(alpha: 0.18),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Header(controller: controller),
                    const SizedBox(height: 18),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            flex: 4,
                            child: _InputCard(
                              controller: controller,
                              compositionController: _compositionController,
                              compositionFocus: _compositionFocus,
                              onKeyEvent: _handleKey,
                              onCommit: _commitSelected,
                              onRawInputChanged: _updateRawInput,
                            ),
                          ),
                          const SizedBox(width: 18),
                          Expanded(
                            flex: 5,
                            child: Card(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _SectionHeading(
                                      icon: Icons.edit_note_rounded,
                                      title: '確定した文章',
                                      subtitle: '入力結果をそのまま編集・コピー',
                                      trailing: IconButton(
                                        tooltip: 'コピー',
                                        onPressed:
                                            controller.committedText.isEmpty
                                            ? null
                                            : () => Clipboard.setData(
                                                ClipboardData(
                                                  text:
                                                      controller.committedText,
                                                ),
                                              ),
                                        icon: const Icon(
                                          Icons.copy_all_rounded,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 18),
                                    Expanded(
                                      child: TextField(
                                        key: const Key('committed-editor'),
                                        controller: _outputController,
                                        onChanged:
                                            controller.replaceCommittedText,
                                        maxLines: null,
                                        expands: true,
                                        textAlignVertical:
                                            TextAlignVertical.top,
                                        decoration: const InputDecoration(
                                          hintText: '確定した文字がここに入る',
                                          alignLabelWithHint: true,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.controller});

  final DesktopInputController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [colors.primary, colors.tertiary],
                ),
                borderRadius: BorderRadius.circular(17),
                boxShadow: [
                  BoxShadow(
                    color: colors.primary.withValues(alpha: 0.22),
                    blurRadius: 18,
                    offset: const Offset(0, 7),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Text(
                controller.mode == InputMode.japanese ? 'あ' : 'A',
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: colors.onPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Keynako',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '日本語・英語入力エンジン',
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              flex: 3,
              child: Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 10,
                runSpacing: 8,
                children: [
                  Tooltip(
                    message:
                        '今すぐ読み込む。アプリ起動中は5分ごとに自動更新。'
                        '現在: ${controller.sharedDictionaryStatus}',
                    child: ActionChip(
                      key: const Key('shared-dictionary-import'),
                      avatar: controller.sharedDictionarySyncing
                          ? const SizedBox.square(
                              dimension: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.cloud_done_rounded, size: 18),
                      onPressed: controller.sharedDictionarySyncing
                          ? null
                          : () async {
                              final imported = await controller
                                  .importSharedDictionary();
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    imported
                                        ? '共有辞書を読み込みました。'
                                        : '共有辞書を読み込めませんでした。',
                                  ),
                                ),
                              );
                            },
                      label: Text(
                        controller.sharedDictionarySyncing
                            ? '共有辞書 読込中'
                            : '共有辞書を読込',
                      ),
                    ),
                  ),
                  SegmentedButton<InputMode>(
                    segments: const [
                      ButtonSegment(
                        value: InputMode.japanese,
                        label: Text('日本語'),
                        icon: Icon(Icons.translate_rounded),
                      ),
                      ButtonSegment(
                        value: InputMode.english,
                        label: Text('English'),
                        icon: Icon(Icons.abc_rounded),
                      ),
                    ],
                    selected: {controller.mode},
                    showSelectedIcon: false,
                    onSelectionChanged: (selection) {
                      controller.setMode(selection.single);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InputCard extends StatelessWidget {
  const _InputCard({
    required this.controller,
    required this.compositionController,
    required this.compositionFocus,
    required this.onKeyEvent,
    required this.onCommit,
    required this.onRawInputChanged,
  });

  final DesktopInputController controller;
  final TextEditingController compositionController;
  final FocusNode compositionFocus;
  final FocusOnKeyEventCallback onKeyEvent;
  final VoidCallback onCommit;
  final ValueChanged<String> onRawInputChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final compact = MediaQuery.sizeOf(context).height < 680;
    return Card(
      child: Padding(
        padding: EdgeInsets.all(compact ? 16 : 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SectionHeading(
              icon: Icons.keyboard_rounded,
              title: '入力と変換',
              subtitle: 'Space・変換キーで候補を開く',
            ),
            if (controller.mode == InputMode.japanese) ...[
              SizedBox(height: compact ? 6 : 12),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: [
                  FilterChip(
                    selected: controller.liveConversionEnabled,
                    avatar: const Icon(Icons.bolt_rounded, size: 17),
                    label: const Text('ライブ変換'),
                    onSelected: controller.setLiveConversionEnabled,
                  ),
                  if (controller.zenzaiWorking)
                    const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Icon(
                      controller.zenzaiStatus == 'モデル未検出' ||
                              controller.zenzaiStatus == '利用不可'
                          ? Icons.warning_amber_rounded
                          : Icons.auto_awesome_rounded,
                      size: 18,
                      color: colors.primary,
                    ),
                  DropdownButton<ZenzaiModel>(
                    value: controller.zenzaiModel,
                    underline: const SizedBox.shrink(),
                    borderRadius: BorderRadius.circular(16),
                    items: const [
                      DropdownMenuItem(
                        value: ZenzaiModel.off,
                        child: Text('Zenzai 無効'),
                      ),
                      DropdownMenuItem(
                        value: ZenzaiModel.xsmall,
                        child: Text('Zenzai 軽量'),
                      ),
                      DropdownMenuItem(
                        value: ZenzaiModel.small,
                        child: Text('Zenzai 標準'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) controller.setZenzaiModel(value);
                    },
                  ),
                ],
              ),
            ],
            SizedBox(height: compact ? 8 : 14),
            Focus(
              onKeyEvent: onKeyEvent,
              child: TextField(
                key: const Key('composition-field'),
                controller: compositionController,
                focusNode: compositionFocus,
                onChanged: onRawInputChanged,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: controller.mode == InputMode.japanese
                      ? 'ローマ字を入力'
                      : 'Type in English',
                  suffixIcon: controller.rawInput.isEmpty
                      ? null
                      : IconButton(
                          tooltip: '取り消す',
                          onPressed: controller.cancelComposition,
                          icon: const Icon(Icons.close),
                        ),
                ),
              ),
            ),
            SizedBox(height: compact ? 8 : 16),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: EdgeInsets.symmetric(
                horizontal: 18,
                vertical: compact ? 10 : 16,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: controller.rawInput.isEmpty
                      ? [
                          colors.surfaceContainerHighest,
                          colors.surfaceContainerHigh,
                        ]
                      : [
                          colors.primaryContainer.withValues(alpha: 0.9),
                          colors.tertiaryContainer.withValues(alpha: 0.55),
                        ],
                ),
                borderRadius: BorderRadius.circular(19),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      controller.displayedComposition.isEmpty
                          ? '編集中の文字'
                          : controller.displayedComposition,
                      key: const Key('composing-text'),
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: controller.displayedComposition.isEmpty
                                ? colors.onSurfaceVariant
                                : colors.onPrimaryContainer,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                  if (controller.rawInput.isNotEmpty)
                    _StatusPill(
                      label: controller.converting ? '変換中' : 'ライブ',
                      color: colors.primary,
                    ),
                ],
              ),
            ),
            if (controller.mode == InputMode.japanese &&
                controller.liveConversionEnabled &&
                controller.rawInput.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                '読み: ${controller.composingText}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            SizedBox(height: compact ? 9 : 18),
            Row(
              children: [
                Icon(Icons.view_list_rounded, size: 18, color: colors.primary),
                const SizedBox(width: 8),
                Text('変換候補', style: Theme.of(context).textTheme.labelLarge),
                const Spacer(),
                if (controller.candidates.isNotEmpty)
                  Text(
                    '${controller.selectedIndex + 1} / ${controller.candidates.length}',
                    style: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(color: colors.onSurfaceVariant),
                  ),
              ],
            ),
            SizedBox(height: compact ? 6 : 10),
            Expanded(
              child: controller.candidates.isEmpty
                  ? Center(
                      child: Text(
                        '文字を入力すると候補が表示される',
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                    )
                  : ListView.separated(
                      itemCount: controller.candidates.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 7),
                      itemBuilder: (context, index) {
                        final candidate = controller.candidates[index];
                        final selected = index == controller.selectedIndex;
                        final sourceLabel = switch (candidate.source) {
                          'zenzai' => 'Zenzai',
                          'user' || 'shared' => '共有',
                          _ => null,
                        };
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 140),
                          decoration: BoxDecoration(
                            color: selected
                                ? colors.secondaryContainer
                                : colors.surfaceContainerHighest.withValues(
                                    alpha: 0.7,
                                  ),
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(
                              color: selected
                                  ? colors.secondary.withValues(alpha: 0.48)
                                  : colors.outlineVariant.withValues(
                                      alpha: 0.48,
                                    ),
                            ),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(15),
                            onTap: () => controller.selectCandidate(index),
                            onDoubleTap: () {
                              controller.selectCandidate(index);
                              onCommit();
                            },
                            onSecondaryTap: () async {
                              final sent = await controller.shareCandidate(
                                index,
                              );
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    sent
                                        ? '候補を共有ストレージへ送信しました。'
                                        : '候補を共有ストレージへ送信できませんでした。',
                                  ),
                                ),
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 11,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 28,
                                    height: 28,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: selected
                                          ? colors.secondary
                                          : colors.surface,
                                      borderRadius: BorderRadius.circular(9),
                                    ),
                                    child: Text(
                                      '${index + 1}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium
                                          ?.copyWith(
                                            color: selected
                                                ? colors.onSecondary
                                                : colors.onSurfaceVariant,
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      candidate.text,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    ),
                                  ),
                                  if (sourceLabel != null)
                                    _StatusPill(
                                      label: sourceLabel,
                                      color: candidate.source == 'zenzai'
                                          ? colors.tertiary
                                          : colors.primary,
                                    ),
                                  if (selected) ...[
                                    const SizedBox(width: 8),
                                    Icon(
                                      Icons.check_circle_rounded,
                                      size: 18,
                                      color: colors.secondary,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            SizedBox(height: compact ? 8 : 14),
            Row(
              children: [
                if (!compact)
                  const Expanded(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _Shortcut(keys: 'Space', action: '次候補'),
                        _Shortcut(keys: 'Enter', action: '確定'),
                        _Shortcut(keys: 'Esc', action: '戻る'),
                      ],
                    ),
                  ),
                if (compact) const Spacer(),
                FilledButton.icon(
                  onPressed: controller.rawInput.isEmpty ? null : onCommit,
                  icon: const Icon(Icons.keyboard_return),
                  label: const Text('確定'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: colors.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: colors.onPrimaryContainer, size: 20),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _Shortcut extends StatelessWidget {
  const _Shortcut({required this.keys, required this.action});

  final String keys;
  final String action;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: keys,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(text: '  $action'),
          ],
        ),
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}
