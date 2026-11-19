import 'package:flutter/material.dart';

import 'package:ai_study_planner/theme/app_colors.dart';

ThemeData buildDarkTheme() => ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: kBg,
      primaryColor: kGreen,
      colorScheme: const ColorScheme.dark(
        surface: kCard,
        primary: kGreen,
        secondary: kIndigo,
        error: Color(0xFFffb4ab),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: kCard,
        contentTextStyle: TextStyle(color: Colors.white, fontSize: 13),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: kBorder.withValues(alpha: 0.6)),
        ),
      ),
    );

BoxDecoration cardDecoration([Color? borderColor]) => BoxDecoration(
      color: kCard,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: (borderColor ?? kBorder).withValues(alpha: 0.5)),
    );
