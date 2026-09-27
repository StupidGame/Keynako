import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:keynako_conversion/keynako_conversion.dart';
import 'package:keynako_desktop/input/desktop_input_controller.dart';
import 'package:keynako_desktop/input/desktop_shared_dictionary.dart';

void main() {
  test('a correction overtakes many automatic confirmations', () {
    final controller = DesktopInputController();
    for (var i = 0; i < 100; i++) {
      controller.updateRawInput('ai');
      controller.commitSelected();
    }
    controller.updateRawInput('ai');
    controller.selectCandidate(
      controller.candidates.indexWhere((value) => value.text == '藍'),
    );
    controller.commitSelected();
    controller.updateRawInput('ai');
    expect(controller.displayedComposition, '藍');
    controller.dispose();
  });

  test('Zenzai cannot override a learned correction', () async {
    final controller = DesktopInputController(
      zenzaiEngineFactory: (_) async => _FakeZenzaiEngine(),
    );
    controller.updateRawInput('nihongo');
    controller.selectCandidate(
      controller.candidates.indexWhere((value) => value.text == '日本語'),
    );
    controller.commitSelected();
    await controller.setZenzaiModel(ZenzaiModel.xsmall);
    controller.updateRawInput('nihongo');
    await Future<void>.delayed(const Duration(milliseconds: 180));
    expect(controller.candidates.first.text, '日本語');
    controller.dispose();
  });

  test(
    'a pending Zenzai result preserves the manual selection and commit',
    () async {
      final engine = _DelayedZenzaiEngine();
      final controller = DesktopInputController(
        zenzaiEngineFactory: (_) async => engine,
      );
      await controller.setZenzaiModel(ZenzaiModel.xsmall);
      controller.updateRawInput('nihongo');
      controller.selectCandidate(
        controller.candidates.indexWhere((value) => value.text == 'ニホンゴ'),
      );
      await engine.started.future;
      engine.result.complete('日本語入力');
      await Future<void>.delayed(Duration.zero);
      expect(controller.displayedComposition, 'ニホンゴ');
      controller.commitSelected();
      expect(controller.committedText, 'ニホンゴ');
      controller.dispose();
    },
  );

  test('places a Zenzai result before base Japanese candidates', () async {
    final engine = _FakeZenzaiEngine();
    final controller = DesktopInputController(
      zenzaiEngineFactory: (_) async => engine,
    );
    await controller.setZenzaiModel(ZenzaiModel.xsmall);

    controller.updateRawInput('nihongo');
    await Future<void>.delayed(const Duration(milliseconds: 180));

    expect(engine.lastRequest?.reading, 'にほんご');
    expect(controller.candidates.first.text, '日本語入力');
    expect(controller.candidates.first.source, 'zenzai');
    controller.dispose();
  });

  test('commits English predictions with a trailing space', () {
    final controller = DesktopInputController();
    controller.setMode(InputMode.english);
    controller.updateRawInput('hel');
    controller.selectCandidate(
      controller.candidates.indexWhere(
        (candidate) => candidate.text == 'hello',
      ),
    );

    controller.commitSelected();

    expect(controller.committedText, 'hello ');
    controller.dispose();
  });

  test('recalls a committed Zenzai word after the model is disabled', () async {
    final controller = DesktopInputController(
      zenzaiEngineFactory: (_) async => _FakeZenzaiEngine(),
    );
    await controller.setZenzaiModel(ZenzaiModel.xsmall);
    controller.updateRawInput('nihongo');
    await Future<void>.delayed(const Duration(milliseconds: 180));
    controller.commitSelected();
    await controller.setZenzaiModel(ZenzaiModel.off);
    controller.updateRawInput('nihongo');
    expect(controller.candidates.first.text, '日本語入力');
    controller.updateRawInput('niho');
    expect(controller.displayedComposition, 'にほ');
    expect(
      controller.candidates.map((candidate) => candidate.text),
      contains('日本語入力'),
    );
    controller.dispose();
  });

  test('keeps composition and candidates when switching input mode', () {
    final controller = DesktopInputController();
    controller.updateRawInput('nihongo');
    controller.beginOrCycleCandidate(1);

    controller.setMode(InputMode.english);

    expect(controller.rawInput, 'nihongo');
    expect(controller.composingText, 'nihongo');
    expect(controller.candidates, isNotEmpty);
    expect(controller.converting, isTrue);

    controller.setMode(InputMode.japanese);

    expect(controller.rawInput, 'nihongo');
    expect(controller.composingText, 'にほんご');
    expect(controller.displayedComposition, '日本語');
    expect(
      controller.candidates.any((candidate) => candidate.text == '日本語'),
      isTrue,
    );
    expect(controller.converting, isTrue);
    controller.dispose();
  });

  test('replaces the selected committed text and keeps the new caret', () {
    final controller = DesktopInputController();
    controller.replaceCommittedText('前の文章後');
    controller.updateRawInput('nihongo');
    controller.selectCandidate(
      controller.candidates.indexWhere((candidate) => candidate.text == '日本語'),
    );

    controller.commitSelected(replaceStart: 1, replaceEnd: 4);

    expect(controller.committedText, '前日本語後');
    expect(controller.committedSelectionOffset, 4);
    controller.dispose();
  });

  test('direct whitespace input does not create conversion candidates', () {
    final controller = DesktopInputController();

    controller.commitDirectText('　');

    expect(controller.committedText, '　');
    expect(controller.rawInput, isEmpty);
    expect(controller.candidates, isEmpty);
    controller.dispose();
  });

  test('inserts paired delimiters and leaves the caret between them', () {
    final controller = DesktopInputController();
    controller.replaceCommittedText('前後');

    controller.commitDirectText('「', replaceStart: 1, replaceEnd: 1);

    expect(controller.committedText, '前「」後');
    expect(controller.committedSelectionOffset, 2);

    controller.commitDirectText('(', replaceStart: 2, replaceEnd: 2);

    expect(controller.committedText, '前「()」後');
    expect(controller.committedSelectionOffset, 3);
    controller.dispose();
  });

  test('previews the selected candidate during live conversion', () {
    final controller = DesktopInputController();
    controller.updateRawInput('nihongo');

    expect(controller.composingText, 'にほんご');
    expect(controller.displayedComposition, '日本語');

    controller.setLiveConversionEnabled(false);
    expect(controller.displayedComposition, 'にほんご');
    controller.dispose();
  });

  test('uses full-width punctuation only in Japanese mode', () {
    final controller = DesktopInputController();
    controller.updateRawInput('!?');
    expect(controller.composingText, '！？');

    controller.setMode(InputMode.english);
    controller.updateRawInput('!?');
    expect(controller.composingText, '!?');
    controller.dispose();
  });

  test('uses a two-stage explicit conversion and cancellation', () {
    final controller = DesktopInputController();
    controller.setLiveConversionEnabled(false);
    controller.updateRawInput('nihongo');

    expect(controller.displayedComposition, 'にほんご');
    controller.beginOrCycleCandidate(1);
    expect(controller.converting, isTrue);
    expect(controller.displayedComposition, '日本語');

    controller.beginOrCycleCandidate(1);
    expect(controller.selectedIndex, 1);
    expect(controller.cancelConversion(), isTrue);
    expect(controller.displayedComposition, 'にほんご');
    expect(controller.rawInput, 'nihongo');
    controller.dispose();
  });

  test('periodically imports the shared dictionary', () async {
    final repository = _FakeSharedDictionaryRepository();
    final controller = DesktopInputController(
      sharedDictionaryRepository: repository,
      sharedDictionaryInterval: const Duration(milliseconds: 10),
    );

    await controller.initializeSharedDictionary();
    await Future<void>.delayed(const Duration(milliseconds: 35));
    controller.updateRawInput('ki-nako');

    expect(repository.refreshCount, greaterThanOrEqualTo(2));
    expect(controller.sharedDictionaryEntryCount, 1);
    expect(controller.candidates.first.text, 'Keynako共有');
    controller.dispose();
  });

  test(
    'shares the right-clicked candidate through the common gateway',
    () async {
      final submitter = _FakeDictionarySubmitter();
      final controller = DesktopInputController(
        sharedDictionarySubmitter: submitter,
      );
      controller.updateRawInput('nihongo');
      final index = controller.candidates.indexWhere(
        (candidate) => candidate.text == '日本語',
      );

      expect(await controller.shareCandidate(index), isTrue);
      expect(submitter.word, '日本語');
      expect(submitter.ruby, 'にほんご');
      expect(controller.candidateShareStatus, '共有ストレージへ送信しました');
      controller.dispose();
    },
  );

  test('learns and shares a prediction with its completed reading', () async {
    final submitter = _FakeDictionarySubmitter();
    final repository = _FakeSharedDictionaryRepository();
    final controller = DesktopInputController(
      sharedDictionaryRepository: repository,
      sharedDictionarySubmitter: submitter,
    );
    await controller.importSharedDictionary();
    controller.updateRawInput('ki-');
    final index = controller.candidates.indexWhere(
      (candidate) => candidate.text == 'Keynako共有',
    );
    expect(index, greaterThanOrEqualTo(0));
    expect(controller.candidates[index].reading, 'きーなこ');
    expect(await controller.shareCandidate(index), isTrue);
    expect(submitter.ruby, 'きーなこ');

    controller.selectCandidate(index);
    controller.commitSelected();
    repository.snapshot = const SharedDictionarySnapshot(
      revision: 'empty',
      version: '1.1',
      lastUpdate: 'today',
      entries: [],
    );
    await controller.importSharedDictionary();
    controller.updateRawInput('ki-nako');
    expect(controller.candidates.first.text, 'Keynako共有');
    expect(controller.candidates.first.source, 'learned');
    controller.dispose();
  });
}

class _FakeZenzaiEngine implements ZenzaiEngine {
  ZenzaiRequest? lastRequest;

  @override
  Future<void> initialize() async {}

  @override
  Future<String?> generate(ZenzaiRequest request) async {
    lastRequest = request;
    return '日本語入力';
  }

  @override
  Future<void> close() async {}
}

class _DelayedZenzaiEngine implements ZenzaiEngine {
  final started = Completer<void>();
  final result = Completer<String?>();

  @override
  Future<void> initialize() async {}

  @override
  Future<String?> generate(ZenzaiRequest request) {
    started.complete();
    return result.future;
  }

  @override
  Future<void> close() async {}
}

class _FakeSharedDictionaryRepository implements SharedDictionaryRepository {
  var refreshCount = 0;

  SharedDictionarySnapshot snapshot = const SharedDictionarySnapshot(
    revision: 'test',
    version: '1.1',
    lastUpdate: 'today',
    entries: [
      ConversionDictionaryEntry(
        reading: 'きーなこ',
        value: 'Keynako共有',
        importance: 5,
      ),
    ],
  );

  @override
  Future<bool> isRefreshDue() async => true;

  @override
  Future<SharedDictionarySnapshot?> load() async => null;

  @override
  Future<SharedDictionarySnapshot> refresh() async {
    refreshCount += 1;
    return snapshot;
  }
}

class _FakeDictionarySubmitter implements KeynakoDictionarySubmitter {
  String? word;
  String? ruby;

  @override
  Future<bool> submit({
    required String word,
    required String ruby,
    required int importance,
    required List<String> categories,
    String? note,
  }) async {
    this.word = word;
    this.ruby = ruby;
    return true;
  }
}
