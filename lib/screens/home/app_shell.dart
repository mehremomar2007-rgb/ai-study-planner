import 'package:flutter/material.dart';

import 'package:ai_study_planner/localization/app_localization.dart';
import 'package:ai_study_planner/screens/dashboard/dashboard_tab.dart';
import 'package:ai_study_planner/screens/focus/focus_tab.dart';
import 'package:ai_study_planner/screens/plan/plan_tab.dart';
import 'package:ai_study_planner/screens/subjects/subjects_tab.dart';
import 'package:ai_study_planner/screens/tasks/tasks_tab.dart';
import 'package:ai_study_planner/state/app_state.dart';
import 'package:ai_study_planner/theme/app_colors.dart';

class AppShell extends StatefulWidget {
  final AppState state;
  const AppShell({super.key, required this.state});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: _currentIndex,
          children: [
            DashboardTab(state: widget.state),
            PlanTab(state: widget.state),
            SubjectsTab(state: widget.state),
            FocusTab(state: widget.state),
            TasksTab(state: widget.state),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        decoration: BoxDecoration(
          color: kDeep.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kBorder.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _navItem(0, Icons.dashboard_rounded, 'الرئيسية'),
            _navItem(1, Icons.calendar_today_rounded, 'الخطة'),
            _navItem(2, Icons.menu_book_rounded, 'المواد'),
            _navItem(3, Icons.spa_rounded, 'التركيز'),
            _navItem(4, Icons.checklist_rounded, 'المهام'),
          ],
        ),
      ),
    );
  }

  Widget _navItem(int index, IconData icon, String label) {
    final selected = _currentIndex == index;
    final color = selected ? kGreen : kMuted;
    return InkWell(
      onTap: () => setState(() => _currentIndex = index),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 22),
            SizedBox(height: 4),
            Text(appTr(label),
                style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.bold : FontWeight.w500)),
            if (selected) ...[
              SizedBox(height: 3),
              Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(color: kGreen, shape: BoxShape.circle),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
