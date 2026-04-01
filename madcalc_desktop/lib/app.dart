import 'package:flutter/material.dart';

import 'controllers/madcalc_controller.dart';
import 'ui/home_page.dart';

class MadCalcApp extends StatelessWidget {
  const MadCalcApp({
    required this.controller,
    super.key,
  });

  final MadCalcController controller;

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFF1F5C99);
    const background = Color(0xFFF3F0EA);
    const surface = Color(0xFFFCFBF8);

    final baseTheme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        brightness: Brightness.light,
        primary: primary,
        surface: surface,
      ),
      scaffoldBackgroundColor: background,
      fontFamily: 'SF Pro Display',
    );

    return MaterialApp(
      title: 'MadCalc',
      debugShowCheckedModeBanner: false,
      theme: baseTheme.copyWith(
        cardTheme: baseTheme.cardTheme.copyWith(
          color: surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: Color(0xFFE1DDD4)),
          ),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
            borderSide: BorderSide(color: Color(0xFFD9D6CE)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
            borderSide: BorderSide(color: Color(0xFFD9D6CE)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
            borderSide: BorderSide(color: primary, width: 1.6),
          ),
        ),
      ),
      home: HomePage(controller: controller),
    );
  }
}
