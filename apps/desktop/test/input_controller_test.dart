import 'package:flutter_test/flutter_test.dart';
import 'package:keynako_conversion/keynako_conversion.dart';
import 'package:keynako_desktop/input/desktop_input_controller.dart';

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

  test('previews the selected candidate during live conversion', () {
    final controller = DesktopInputController();
    controller.updateRawInput('nihongo');

    expect(controller.composingText, 'にほんご');
    expect(controller.displayedComposition, '日本語');

    controller.setLiveConversionEnabled(false);
    expect(controller.displayedComposition, 'にほんご');
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
