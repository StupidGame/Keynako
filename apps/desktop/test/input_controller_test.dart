import 'package:flutter_test/flutter_test.dart';
import 'package:keynako_conversion/keynako_conversion.dart';
import 'package:keynako_desktop/input/desktop_input_controller.dart';
import 'package:keynako_desktop/input/desktop_shared_dictionary.dart';

void main() {
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

class _FakeSharedDictionaryRepository implements SharedDictionaryRepository {
  var refreshCount = 0;

  static const snapshot = SharedDictionarySnapshot(
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
