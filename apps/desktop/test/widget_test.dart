import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keynako_conversion/keynako_conversion.dart';
import 'package:keynako_desktop/app.dart';
import 'package:keynako_desktop/input/desktop_input_controller.dart';
import 'package:keynako_desktop/input/desktop_shared_dictionary.dart';

void main() {
  testWidgets(
    'long press resets only the chosen candidate without committing',
    (tester) async {
      final controller = DesktopInputController();
      addTearDown(controller.dispose);
      controller.updateRawInput('ame');
      controller.selectCandidate(
        controller.candidates.indexWhere((value) => value.text == '飴'),
      );
      controller.commitSelected();
      controller.replaceCommittedText('');
      controller.updateRawInput('ame');
      expect(controller.candidates.first.text, '飴');
      await tester.pumpWidget(KeynakoDesktopApp(controller: controller));
      await tester.longPress(find.byKey(const Key('candidate-0')));
      await tester.pumpAndSettle();
      expect(find.text('この単語の学習をリセット'), findsOneWidget);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(controller.candidates.first.text, '飴');
      await tester.longPress(find.byKey(const Key('candidate-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('この単語の学習をリセット'));
      await tester.pumpAndSettle();
      expect(controller.candidates.first.text, '雨');
      expect(controller.rawInput, 'ame');
      expect(controller.committedText, isEmpty);
      expect(find.text('「飴」の学習をリセットしたよ'), findsOneWidget);
    },
  );

  testWidgets('converts and commits Japanese input', (tester) async {
    final controller = DesktopInputController();
    await tester.pumpWidget(KeynakoDesktopApp(controller: controller));

    expect(
      Localizations.localeOf(
        tester.element(find.byKey(const Key('composition-field'))),
      ),
      const Locale('ja', 'JP'),
    );

    await tester.enterText(
      find.byKey(const Key('composition-field')),
      'nihongo',
    );
    await tester.pump();

    expect(find.textContaining('にほんご'), findsWidgets);
    expect(find.text('日本語'), findsWidgets);

    controller.selectCandidate(
      controller.candidates.indexWhere((candidate) => candidate.text == '日本語'),
    );
    controller.commitSelected();
    await tester.pump();

    expect(controller.committedText, '日本語');
    expect(controller.rawInput, isEmpty);
  });

  testWidgets('switches to English predictions', (tester) async {
    final controller = DesktopInputController();
    await tester.pumpWidget(KeynakoDesktopApp(controller: controller));

    controller.setMode(InputMode.english);
    await tester.pump();
    await tester.enterText(find.byKey(const Key('composition-field')), 'hel');
    await tester.pump();

    expect(find.text('hello'), findsOneWidget);
  });

  testWidgets('committing input replaces the selected output text', (
    tester,
  ) async {
    final controller = DesktopInputController();
    await tester.pumpWidget(KeynakoDesktopApp(controller: controller));
    controller.replaceCommittedText('前の文章後');
    await tester.pump();

    final editor = tester.widget<TextField>(
      find.byKey(const Key('committed-editor')),
    );
    editor.controller!.selection = const TextSelection(
      baseOffset: 1,
      extentOffset: 4,
    );
    await tester.enterText(
      find.byKey(const Key('composition-field')),
      'nihongo',
    );
    controller.selectCandidate(
      controller.candidates.indexWhere((candidate) => candidate.text == '日本語'),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(controller.committedText, '前日本語後');
    expect(
      editor.controller!.selection,
      const TextSelection.collapsed(offset: 4),
    );
  });

  testWidgets('commits whitespace without showing conversion candidates', (
    tester,
  ) async {
    final controller = DesktopInputController();
    await tester.pumpWidget(KeynakoDesktopApp(controller: controller));

    await tester.enterText(find.byKey(const Key('composition-field')), '　');
    await tester.pump();

    expect(controller.committedText, '　');
    expect(controller.rawInput, isEmpty);
    expect(controller.candidates, isEmpty);
  });

  testWidgets('auto-closes an opening delimiter and selects its inside', (
    tester,
  ) async {
    final controller = DesktopInputController();
    await tester.pumpWidget(KeynakoDesktopApp(controller: controller));

    await tester.enterText(
      find.byKey(const Key('composition-field')),
      'nihongo(',
    );
    await tester.pump();

    final editor = tester.widget<TextField>(
      find.byKey(const Key('committed-editor')),
    );
    expect(controller.committedText, '日本語()');
    expect(
      editor.controller!.selection,
      const TextSelection.collapsed(offset: 4),
    );
    expect(controller.rawInput, isEmpty);
  });

  testWidgets('sends a candidate with a secondary click', (tester) async {
    final submitter = _FakeDictionarySubmitter();
    final controller = DesktopInputController(
      sharedDictionarySubmitter: submitter,
    );
    await tester.pumpWidget(KeynakoDesktopApp(controller: controller));

    await tester.enterText(
      find.byKey(const Key('composition-field')),
      'nihongo',
    );
    await tester.pump();
    await tester.tap(
      find.text('日本語').last,
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('共通辞書に送る'));
    await tester.pumpAndSettle();

    expect(submitter.word, '日本語');
    expect(submitter.ruby, 'にほんご');
  });

  testWidgets('manually imports the shared dictionary from the header', (
    tester,
  ) async {
    final repository = _FakeSharedDictionaryRepository();
    final controller = DesktopInputController(
      sharedDictionaryRepository: repository,
    );
    await tester.pumpWidget(KeynakoDesktopApp(controller: controller));

    await tester.tap(find.byKey(const Key('shared-dictionary-import')));
    await tester.pumpAndSettle();

    expect(repository.refreshCount, 1);
    expect(find.text('共有辞書を読込'), findsOneWidget);
    expect(find.text('共有辞書を読み込みました。'), findsOneWidget);
  });
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

class _FakeSharedDictionaryRepository implements SharedDictionaryRepository {
  var refreshCount = 0;

  @override
  Future<bool> isRefreshDue() async => false;

  @override
  Future<SharedDictionarySnapshot?> load() async => null;

  @override
  Future<SharedDictionarySnapshot> refresh() async {
    refreshCount += 1;
    return const SharedDictionarySnapshot(
      revision: 'widget-test',
      version: '1',
      lastUpdate: 'today',
      entries: [],
    );
  }
}
