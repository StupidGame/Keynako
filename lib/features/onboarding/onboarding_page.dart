import 'package:flutter/material.dart';

import '../../core/app_controller.dart';
import '../../core/platform_service.dart';
import '../shell/app_shell.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _pageController = PageController();
  var _index = 0;
  var _status = KeyboardStatus.unavailable;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    final value = await AppControllerScope.of(context).platform
        .keyboardStatus();
    if (mounted) setState(() => _status = value);
  }

  void _finish() {
    AppControllerScope.of(context).completeOnboarding();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const AppShell()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    return Scaffold(
      appBar: AppBar(
        actions: [TextButton(onPressed: _finish, child: const Text('あとで'))],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (value) => setState(() => _index = value),
                children: [
                  const _OnboardingStep(
                    icon: Icons.keyboard_alt_outlined,
                    title: 'Keynakoへようこそ',
                    body: 'フリック入力、ローマ字入力、ライブ変換、テーマやカスタムタブを利用できる日本語キーボードです。',
                  ),
                  _OnboardingStep(
                    icon: Icons.settings_suggest_outlined,
                    title: 'キーボードを有効化',
                    body: _status.enabled
                        ? 'Keynakoキーボードは有効です。'
                        : '端末のキーボード設定を開き、Keynakoを有効にしてください。',
                    action: FilledButton.icon(
                      onPressed: () async {
                        await controller.platform.openKeyboardSettings();
                        await _refresh();
                      },
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('キーボード設定を開く'),
                    ),
                  ),
                  _OnboardingStep(
                    icon: Icons.lock_open_outlined,
                    title: '追加機能について',
                    body: 'クリップボード履歴、連絡先変換、誤変換レポートなどは、OS側の追加権限またはフルアクセスが必要です。必要な機能だけを設定から有効にできます。',
                    action: FilledButton.icon(
                      onPressed: _finish,
                      icon: const Icon(Icons.check),
                      label: const Text('はじめる'),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: Row(
                children: [
                  for (var index = 0; index < 3; index++)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: CircleAvatar(
                        radius: 4,
                        backgroundColor: index == _index
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                  const Spacer(),
                  if (_index < 2)
                    FilledButton(
                      onPressed: () => _pageController.nextPage(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOut,
                      ),
                      child: const Text('次へ'),
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

class _OnboardingStep extends StatelessWidget {
  const _OnboardingStep({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 88, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 28),
          Text(title, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 14),
          Text(
            body,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          if (action != null) ...[const SizedBox(height: 28), action!],
        ],
      ),
    );
  }
}
