import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../input/desktop_input_controller.dart';

class PortableProfilePage extends StatefulWidget {
  const PortableProfilePage({required this.controller, super.key});

  final DesktopInputController controller;

  @override
  State<PortableProfilePage> createState() => _PortableProfilePageState();
}

class _PortableProfilePageState extends State<PortableProfilePage> {
  final _json = TextEditingController();
  late final TextEditingController _path;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final home =
        Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        Directory.current.path;
    _path = TextEditingController(
      text:
          '$home${Platform.pathSeparator}Downloads'
          '${Platform.pathSeparator}keynako-backup.json',
    );
  }

  @override
  void dispose() {
    _json.dispose();
    _path.dispose();
    super.dispose();
  }

  Future<void> _run(Future<String> Function() task) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final message = await task();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('バックアップを処理できない: $error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export({required bool toFile}) => _run(() async {
    final source = await widget.controller.exportPortableProfile();
    _json.text = source;
    if (toFile) {
      final path = _path.text.trim();
      if (path.isEmpty) throw const FormatException('保存先を入力してね');
      final file = File(path);
      await file.parent.create(recursive: true);
      await file.writeAsString(source, flush: true);
      return 'JSONファイルに保存したよ';
    }
    await Clipboard.setData(ClipboardData(text: source));
    return 'JSONをコピーしたよ';
  });

  Future<void> _import({required bool fromFile}) => _run(() async {
    final source = fromFile
        ? await File(_path.text.trim()).readAsString()
        : _json.text.trim();
    await widget.controller.importPortableProfile(source);
    return '設定・個人辞書・学習履歴を読み込んだよ';
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('バックアップと復元')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'Android・iOSと共通のJSON形式。設定、個人辞書、学習履歴をまとめて移せるよ。'
          '読み込みは現在のデータを置き換えるよ。',
        ),
        const SizedBox(height: 20),
        TextField(
          key: const Key('portable-profile-path'),
          controller: _path,
          decoration: const InputDecoration(labelText: 'JSONファイルの保存先・読み込み元'),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _export(toFile: true),
              icon: const Icon(Icons.save_alt),
              label: const Text('ファイルに保存'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _import(fromFile: true),
              icon: const Icon(Icons.file_open),
              label: const Text('ファイルから読み込む'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        TextField(
          key: const Key('portable-profile-json'),
          controller: _json,
          minLines: 8,
          maxLines: 16,
          decoration: const InputDecoration(labelText: 'バックアップJSON'),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _export(toFile: false),
              icon: const Icon(Icons.copy),
              label: const Text('JSONをコピー'),
            ),
            TextButton.icon(
              onPressed: _busy
                  ? null
                  : () async {
                      _json.text =
                          (await Clipboard.getData(Clipboard.kTextPlain))
                              ?.text ??
                          '';
                    },
              icon: const Icon(Icons.paste),
              label: const Text('貼り付け'),
            ),
            FilledButton.icon(
              onPressed: _busy ? null : () => _import(fromFile: false),
              icon: const Icon(Icons.file_download),
              label: const Text('JSONを読み込む'),
            ),
          ],
        ),
      ],
    ),
  );
}
