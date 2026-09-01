import 'package:azookey_flutter/core/platform_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
