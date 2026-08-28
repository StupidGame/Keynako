import 'package:azookey_flutter/app.dart';
import 'package:azookey_flutter/core/app_controller.dart';
import 'package:azookey_flutter/core/platform_service.dart';
import 'package:azookey_flutter/models/app_data.dart';
import 'package:azookey_flutter/widgets/keyboard_preview.dart';
import 'package:flutter/material.dart';
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

  testWidgets('keyboard sandbox opens a real editable input field', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: KeyboardSandboxPage()));

    final field = find.byKey(const ValueKey('keyboard-test-field'));
    expect(field, findsOneWidget);
    await tester.enterText(field, 'カスタムタブ入力');
    expect(find.text('カスタムタブ入力'), findsOneWidget);
  });

  testWidgets('candidate tabs use the regular key background color', (
    tester,
  ) async {
    const theme = KeyboardThemeConfig(
      id: 'preview-test',
      name: 'Preview test',
      backgroundColor: 0xff000000,
      keyColor: 0xff123456,
      specialKeyColor: 0xff654321,
      textColor: 0xffffffff,
      accentColor: 0xffabcdef,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: KeyboardPreview(theme: theme)),
      ),
    );

    for (final label in ['予測', '変換', '候補']) {
      final materials = find.ancestor(
        of: find.text(label),
        matching: find.byType(Material),
      );
      expect(
        materials
            .evaluate()
            .map((element) => element.widget)
            .whereType<Material>(),
        contains(
          predicate<Material>(
            (material) => material.color == const Color(0xff123456),
          ),
        ),
      );
    }
  });
}
