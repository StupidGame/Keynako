import 'package:azookey_flutter/core/platform_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a native save failure is reported to the caller', () async {
    const channel = MethodChannel('net.azookey/state-failure-test');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'saveState') {
        throw PlatformException(code: 'write_failed');
      }
      return 'saved state';
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final service = PlatformService(channel: channel);
    await expectLater(
      service.save('new state'),
      throwsA(isA<PlatformException>()),
    );
    expect(await service.load(), 'saved state');
  });

  test(
    'shares the configured dictionary endpoint with the native IME',
    () async {
      const channel = MethodChannel('net.azookey/platform-test');
      MethodCall? received;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            received = call;
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      final service = PlatformService(channel: channel);
      await service.configureDictionarySubmissionEndpoint(
        '  https://example.com/submissions  ',
      );

      expect(received?.method, 'configureDictionarySubmission');
      expect(received?.arguments, {
        'endpoint': 'https://example.com/submissions',
      });
    },
  );
}
