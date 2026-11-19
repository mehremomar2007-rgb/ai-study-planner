import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ai_study_planner/app/studypace_app.dart';
import 'package:ai_study_planner/config/supabase_config.dart';
import 'package:ai_study_planner/state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final configured = !kSupabaseUrl.contains('YOUR_PROJECT_ID') &&
      !kSupabaseAnonKey.contains('YOUR_ANON');
  if (configured) {
    try {
      await Supabase.initialize(url: kSupabaseUrl, anonKey: kSupabaseAnonKey);
      supabaseReady = true;
    } catch (e) {
      debugPrint('Supabase.initialize failed: $e');
    }
  }

  final state = AppState();
  await state.loadLocal();
  runApp(StudyPaceApp(state: state));
  if (isSignedIn) unawaited(state.migrateGuestDataAndRefresh());
}
