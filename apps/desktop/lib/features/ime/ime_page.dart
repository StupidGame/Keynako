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
          offset: controller.committedText.length,
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
      controller.cycleCandidate(1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      controller.cycleCandidate(-1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      controller.commitSelected();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      controller.cancelComposition();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(controller: controller),
                  const SizedBox(height: 24),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: 3,
                          child: _InputCard(
                            controller: controller,
                            compositionController: _compositionController,
                            compositionFocus: _compositionFocus,
                            onKeyEvent: _handleKey,
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          flex: 4,
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(22),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.edit_note,
                                        color: colors.primary,
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        '確定した文章',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium,
                                      ),
                                      const Spacer(),
                                      IconButton(
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
                                        icon: const Icon(Icons.copy_outlined),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 14),
                                  Expanded(
                                    child: TextField(
                                      key: const Key('committed-editor'),
                                      controller: _outputController,
                                      onChanged:
                                          controller.replaceCommittedText,
                                      maxLines: null,
                                      expands: true,
                                      textAlignVertical: TextAlignVertical.top,
                                      decoration: const InputDecoration(
                                        hintText: '確定した文字がここに入る',
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
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.controller});

  final DesktopInputController controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(15),
          ),
          child: const Icon(Icons.keyboard_alt_outlined),
        ),
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Keynako', style: Theme.of(context).textTheme.headlineSmall),
            Text('日本語・英語入力エンジン', style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
        const Spacer(),
        SegmentedButton<InputMode>(
          segments: const [
            ButtonSegment(
              value: InputMode.japanese,
              label: Text('日本語'),
              icon: Icon(Icons.translate),
            ),
            ButtonSegment(
              value: InputMode.english,
              label: Text('English'),
              icon: Icon(Icons.abc),
            ),
          ],
          selected: {controller.mode},
          onSelectionChanged: (selection) {
            controller.setMode(selection.single);
          },
        ),
      ],
    );
  }
}

class _InputCard extends StatelessWidget {
  const _InputCard({
    required this.controller,
    required this.compositionController,
    required this.compositionFocus,
    required this.onKeyEvent,
  });

  final DesktopInputController controller;
  final TextEditingController compositionController;
  final FocusNode compositionFocus;
  final FocusOnKeyEventCallback onKeyEvent;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                Text('入力', style: Theme.of(context).textTheme.titleMedium),
                if (controller.mode == InputMode.japanese)
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('ライブ変換'),
                          Switch(
                            value: controller.liveConversionEnabled,
                            onChanged: controller.setLiveConversionEnabled,
                          ),
                        ],
                      ),
                      if (controller.zenzaiWorking)
                        const SizedBox.square(
                          dimension: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        Tooltip(
                          message: controller.zenzaiStatus,
                          child: Icon(
                            controller.zenzaiStatus == 'モデル未検出' ||
                                    controller.zenzaiStatus == '利用不可'
                                ? Icons.warning_amber_rounded
                                : Icons.auto_awesome,
                            size: 17,
                          ),
                        ),
                      DropdownButton<ZenzaiModel>(
                        value: controller.zenzaiModel,
                        underline: const SizedBox.shrink(),
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
            ),
            const SizedBox(height: 16),
            Focus(
              onKeyEvent: onKeyEvent,
              child: TextField(
                key: const Key('composition-field'),
                controller: compositionController,
                focusNode: compositionFocus,
                onChanged: controller.updateRawInput,
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
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: colors.primaryContainer.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                controller.displayedComposition.isEmpty
                    ? '編集中の文字'
                    : controller.displayedComposition,
                key: const Key('composing-text'),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: controller.displayedComposition.isEmpty
                      ? colors.onSurfaceVariant
                      : colors.onPrimaryContainer,
                ),
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
            const SizedBox(height: 18),
            Text('候補', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 10),
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
                        return Material(
                          color: selected
                              ? colors.secondaryContainer
                              : colors.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(13),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(13),
                            onTap: () => controller.selectCandidate(index),
                            onDoubleTap: () {
                              controller.selectCandidate(index);
                              controller.commitSelected();
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 11,
                              ),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 24,
                                    child: Text('${index + 1}'),
                                  ),
                                  Expanded(
                                    child: Text(
                                      candidate.text,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    ),
                                  ),
                                  if (candidate.source == 'zenzai')
                                    const Icon(Icons.auto_awesome, size: 18),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Space 候補選択  ·  Enter 確定  ·  Esc 取消',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                FilledButton.icon(
                  onPressed: controller.rawInput.isEmpty
                      ? null
                      : controller.commitSelected,
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
