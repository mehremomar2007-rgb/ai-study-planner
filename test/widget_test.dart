import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_study_planner/app/studypace_app.dart';
import 'package:ai_study_planner/state/app_state.dart';

void main() {
  testWidgets('StudyPace app works correctly', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final state = AppState();

    await tester.pumpWidget(
      StudyPaceApp(state: state),
    );

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}