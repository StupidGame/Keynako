import 'package:flutter/material.dart';

import '../../input/desktop_input_controller.dart';

class CandidateDictionaryChoicePage extends StatefulWidget {
  const CandidateDictionaryChoicePage({
    required this.controller,
    required this.word,
    required this.reading,
    super.key,
  });

  final DesktopInputController controller;
  final String word;
  final String reading;

  @override
  State<CandidateDictionaryChoicePage> createState() =>
      _CandidateDictionaryChoicePageState();
}

class _CandidateDictionaryChoicePageState
    extends State<CandidateDictionaryChoicePage> {
  bool _busy = false;
  String? _status;

  Future<void> _register({required bool shared}) async {
    if (_busy) return;
    setState(() => _busy = true);
    final success = shared
        ? await widget.controller.shareCandidateText(
            widget.word,
            widget.reading,
          )
        : await widget.controller.saveCandidateTextToPersonalDictionary(
            widget.word,
            widget.reading,
          );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = widget.controller.candidateShareStatus.isNotEmpty
          ? widget.controller.candidateShareStatus
          : success
          ? '登録したよ'
          : '登録できなかった';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('候補を辞書に登録')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.word,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text('読み: ${widget.reading}'),
                const SizedBox(height: 24),
                FilledButton(
                  key: const Key('candidate-register-shared'),
                  onPressed: _busy ? null : () => _register(shared: true),
                  child: const Text('共通辞書に送る'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  key: const Key('candidate-register-personal'),
                  onPressed: _busy ? null : () => _register(shared: false),
                  child: const Text('個人辞書に登録'),
                ),
                if (_status != null) ...[
                  const SizedBox(height: 16),
                  Text(_status!, key: const Key('candidate-register-status')),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
