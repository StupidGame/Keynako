import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keynako_desktop/app.dart';
import 'package:keynako_desktop/input/desktop_input_controller.dart';

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
}
