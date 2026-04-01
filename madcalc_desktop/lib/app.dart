import 'package:flutter/material.dart';

import 'controllers/madcalc_controller.dart';
import 'ui/home_page.dart';

class MadCalcApp extends StatelessWidget {
  const MadCalcApp({required this.controller, super.key});

  final MadCalcController controller;

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFF1F5C99);
    const lightBackground = Color(0xFFF3F0EA);
    const lightSurface = Color(0xFFFCFBF8);
    const darkBackground = Color(0xFF0F141B);
    const darkSurface = Color(0xFF18212C);

    ThemeData buildTheme({
      required Brightness brightness,
      required Color background,
      required Color surface,
    }) {
      final colorScheme = ColorScheme.fromSeed(
        seedColor: primary,
        brightness: brightness,
        primary: primary,
        surface: surface,
      );

      final baseTheme = ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: background,
        fontFamily: 'SF Pro Display',
      );

      return baseTheme.copyWith(
        cardTheme: baseTheme.cardTheme.copyWith(
          color: surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: colorScheme.outlineVariant),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: brightness == Brightness.dark
              ? colorScheme.surfaceContainerHighest
              : Colors.white,
          border: OutlineInputBorder(
            borderRadius: const BorderRadius.all(Radius.circular(16)),
            borderSide: BorderSide(color: colorScheme.outlineVariant),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: const BorderRadius.all(Radius.circular(16)),
            borderSide: BorderSide(color: colorScheme.outlineVariant),
          ),
          focusedBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
            borderSide: BorderSide(color: primary, width: 1.6),
          ),
        ),
      );
    }

    return MaterialApp(
      title: 'MadCalc',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: buildTheme(
        brightness: Brightness.light,
        background: lightBackground,
        surface: lightSurface,
      ),
      darkTheme: buildTheme(
        brightness: Brightness.dark,
        background: darkBackground,
        surface: darkSurface,
      ),
      home: HomePage(controller: controller),
    );
  }
}
