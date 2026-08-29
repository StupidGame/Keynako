import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Input context passed to the bundled Zenzai v3.2 runtime.
class ZenzaiRequest {
  const ZenzaiRequest({
    required this.reading,
    this.leftContext = '',
    this.rightContext = '',
    this.maxTokens = 24,
  });

  final String reading;
  final String leftContext;
  final String rightContext;
  final int maxTokens;
}

abstract interface class ZenzaiEngine {
  Future<void> initialize();

  Future<String?> generate(ZenzaiRequest request);

  Future<void> close();
}

/// Keeps the bundled llama.cpp helper alive so the model is loaded only once.
class ZenzaiProcessEngine implements ZenzaiEngine {
  ZenzaiProcessEngine({
    required this.executablePath,
    required this.modelPath,
    this.requestTimeout = const Duration(seconds: 30),
  });

  final String executablePath;
  final String modelPath;
  final Duration requestTimeout;

  Process? _process;
  StreamIterator<String>? _lines;
  StreamSubscription<String>? _stderr;
  Future<void> _queue = Future.value();
  bool _closing = false;

  @override
  Future<void> initialize() async {
    if (_process != null) return;
    if (!File(executablePath).existsSync()) {
      throw StateError('Zenzai helper was not found: $executablePath');
    }
    if (!File(modelPath).existsSync()) {
      throw StateError('Zenzai model was not found: $modelPath');
    }

    final process = await Process.start(executablePath, [modelPath]);
    final lines = StreamIterator(
      process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
    );
    _stderr = process.stderr
        .transform(utf8.decoder)
        .listen((_) {}, cancelOnError: false);

    if (!await lines.moveNext().timeout(requestTimeout) ||
        lines.current != 'READY') {
      process.kill();
      throw StateError('Zenzai helper did not become ready');
    }
    _process = process;
    _lines = lines;
  }

  @override
  Future<String?> generate(ZenzaiRequest request) {
    final result = Completer<String?>();
    _queue = _queue.then((_) async {
      try {
        await initialize();
        if (_closing) {
          result.complete(null);
          return;
        }
        final prompt = _buildPrompt(request);
        _process!.stdin.writeln(
          '${request.maxTokens.clamp(1, 128)}\t${_hexEncode(prompt)}',
        );
        await _process!.stdin.flush();
        final lines = _lines!;
        if (!await lines.moveNext().timeout(requestTimeout)) {
          throw StateError('Zenzai helper stopped unexpectedly');
        }
        final response = lines.current;
        if (response.startsWith('ERROR')) {
          throw StateError(response);
        }
        final value = _sanitize(_hexDecode(response));
        result.complete(value.isEmpty ? null : value);
      } catch (error, stackTrace) {
        if (!result.isCompleted) result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }

  @override
  Future<void> close() async {
    _closing = true;
    await _queue;
    final process = _process;
    if (process != null) {
      process.stdin.writeln('QUIT');
      await process.stdin.flush();
      await process.exitCode.timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          process.kill();
          return -1;
        },
      );
    }
    await _stderr?.cancel();
    _process = null;
    _lines = null;
  }

  String _buildPrompt(ZenzaiRequest request) {
    final output = StringBuffer();
    if (request.leftContext.isNotEmpty) {
      output
        ..write('\uEE02')
        ..write(_preprocess(request.leftContext));
    }
    if (request.rightContext.isNotEmpty) {
      output
        ..write('\uEE07')
        ..write(_preprocess(request.rightContext));
    }
    output
      ..write('\uEE00')
      ..write(_preprocess(request.reading))
      ..write('\uEE01');
    return output.toString();
  }

  String _preprocess(String value) =>
      value.replaceAll(' ', '　').replaceAll('\r', '').replaceAll('\n', '');

  String _sanitize(String value) {
    final marker = value.indexOf(RegExp(r'[\uEE00-\uEE07]'));
    final result = marker < 0 ? value : value.substring(0, marker);
    return result
        .replaceAll(RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F]'), '')
        .trim();
  }

  String _hexEncode(String value) => utf8
      .encode(value)
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();

  String _hexDecode(String value) {
    if (value.length.isOdd) throw const FormatException('Invalid hex response');
    return utf8.decode([
      for (var index = 0; index < value.length; index += 2)
        int.parse(value.substring(index, index + 2), radix: 16),
    ], allowMalformed: true);
  }
}
