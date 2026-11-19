import 'package:flutter/material.dart';

import 'package:ai_study_planner/localization/app_localization.dart';
import 'package:ai_study_planner/localization/language_helper.dart';
import 'package:ai_study_planner/screens/auth/auth_gate.dart';
import 'package:ai_study_planner/state/app_state.dart';
import 'package:ai_study_planner/theme/app_theme.dart';

class StudyPaceApp extends StatelessWidget {
  final AppState state;
  const StudyPaceApp({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        currentLanguage = state.appLanguage;
        return MaterialApp(
          title: 'StudyPace',
          debugShowCheckedModeBanner: false,
          themeMode: ThemeMode.dark,
          darkTheme: buildDarkTheme(),
          locale: Locale(langCodes[state.appLanguage] ?? 'ar'),
          builder: (context, child) => Directionality(
            textDirection: (state.appLanguage == 'العربية') ? TextDirection.rtl : TextDirection.ltr,
            child: child!,
          ),
          home: AuthGate(state: state),
        );
      },
    );
  }
}
