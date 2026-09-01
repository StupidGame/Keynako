import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keynako_conversion/keynako_conversion.dart';
import 'package:keynako_desktop/app.dart';
import 'package:keynako_desktop/input/desktop_input_controller.dart';
import 'package:keynako_desktop/input/desktop_shared_dictionary.dart';

void main() {
  testWidgets('converts and commits Japanese input', (tester) async {
    final controller = DesktopInputController();
    await tester.pumpWidget(KeynakoDesktopApp(controller: controller));

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
    await tester.pump();

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
