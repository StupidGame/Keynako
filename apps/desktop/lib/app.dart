import 'package:flutter/material.dart';

import 'features/ime/ime_page.dart';
import 'input/desktop_input_controller.dart';

class KeynakoDesktopApp extends StatelessWidget {
  const KeynakoDesktopApp({required this.controller, super.key});

  final DesktopInputController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Keynako Desktop IME',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: ImePage(controller: controller),
    );
  }

  ThemeData _theme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xffa33d4a),
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surfaceContainerLowest,
      visualDensity: VisualDensity.standard,
      splashFactory: InkSparkle.splashFactory,
      textTheme: ThemeData(brightness: brightness).textTheme
          .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface.withValues(alpha: 0.82),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 17,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.7),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: scheme.surface.withValues(alpha: 0.88),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(26),
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.65),
          ),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          visualDensity: VisualDensity.comfortable,
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 46),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          backgroundColor: scheme.surfaceContainerHighest.withValues(
            alpha: 0.55,
          ),
        ),
      ),
    );
  }
}
