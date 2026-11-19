import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ai_study_planner/config/supabase_config.dart';
import 'package:ai_study_planner/localization/app_localization.dart';
import 'package:ai_study_planner/screens/auth/login_screen.dart';
import 'package:ai_study_planner/screens/home/app_shell.dart';
import 'package:ai_study_planner/state/app_state.dart';
import 'package:ai_study_planner/theme/app_colors.dart';

class AuthGate extends StatefulWidget {
  final AppState state;
  const AuthGate({super.key, required this.state});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  StreamSubscription<AuthState>? _sub;
  Session? _session;
  bool _reminderShowing = false;

  @override
  void initState() {
    super.initState();
    if (supabaseReady) {
      _session = supabase.auth.currentSession;
      if (_session != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => widget.state.migrateGuestDataAndRefresh());
      }
      _sub = supabase.auth.onAuthStateChange.listen((data) async {
        if (!mounted) return;
        final wasIn = _session != null;
        final now = data.session;
        setState(() => _session = now);
        if (!wasIn && now != null) {
          await widget.state.migrateGuestDataAndRefresh();
          if (mounted) Navigator.of(context).maybePop();
        } else if (wasIn && now == null) {
          await widget.state.clearData();
        }
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowGuestReminder());
  }

  Future<void> _maybeShowGuestReminder() async {
    if (!mounted || _reminderShowing || isSignedIn) return;
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getInt('guest_account_reminder_at') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    const intervalMs = 3 * 24 * 60 * 60 * 1000;
    if (now - last < intervalMs) return;
    _reminderShowing = true;
    await prefs.setInt('guest_account_reminder_at', now);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: kCard,
        title: Text(appTr('احفظ تقدمك في StudyPace')),
        content: Text(appTr('تقدر تكمل كضيف عادي، لكن إنشاء حساب هيساعدك تحتفظ بموادك وجلساتك ومهامك لو غيّرت جهازك.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(appTr('ذكرني لاحقًا'))),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LoginScreen()));
            },
            child: Text(appTr('إنشاء حساب / تسجيل الدخول')),
          ),
        ],
      ),
    );
    _reminderShowing = false;
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppShell(state: widget.state);
}
