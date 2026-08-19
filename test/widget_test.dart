import 'package:azookey_flutter/app.dart';
import 'package:azookey_flutter/core/app_controller.dart';
import 'package:azookey_flutter/core/platform_service.dart';
import 'package:flutter_test/flutter_test.dart';

class MemoryStorage implements StateStorage {
  String? value;

  @override
  Future<String?> load() async => value;

  @override
  Future<void> save(String state) async => value = state;
}

void main() {
  testWidgets('shows the four migrated application tabs', (tester) async {
    final controller = AppController(storage: MemoryStorage());
    await controller.initialize();
    controller.data.onboardingCompleted = true;

    await tester.pumpWidget(AzooKeyApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.text('使い方'), findsOneWidget);
    expect(find.text('着せ替え'), findsOneWidget);
    expect(find.text('拡張'), findsOneWidget);
    expect(find.text('設定'), findsOneWidget);
    expect(find.text('Keynako', findRichText: true), findsOneWidget);
  });
}
