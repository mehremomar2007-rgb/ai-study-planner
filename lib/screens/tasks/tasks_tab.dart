import 'package:flutter/material.dart';

import 'package:ai_study_planner/localization/app_localization.dart';
import 'package:ai_study_planner/models/models.dart';
import 'package:ai_study_planner/state/app_state.dart';
import 'package:ai_study_planner/theme/app_colors.dart';
import 'package:ai_study_planner/theme/app_theme.dart';
import 'package:ai_study_planner/widgets/common/snack.dart';
import 'package:ai_study_planner/widgets/dialogs/dialogs.dart';

class TasksTab extends StatelessWidget {
  final AppState state;
  const TasksTab({super.key, required this.state});

  Widget _taskCard(BuildContext context, TaskModel t) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: cardDecoration(t.isDone ? kGreen : null),
      child: Row(
        children: [
          Checkbox(
            value: t.isDone,
            activeColor: kGreen,
            checkColor: kBg,
            onChanged: (_) async {
              final ok = await state.toggleTask(t);
              if (!ok && context.mounted) showSnack(context, appTr('ما اتعدلتش. اتأكد من النت.'));
            },
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.title,
                  style: TextStyle(
                    fontSize: 14,
                    color: t.isDone ? kMuted : Colors.white,
                    decoration: t.isDone ? TextDecoration.lineThrough : null,
                  ),
                ),
                if (t.subjectName != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(t.subjectName!,
                        style: TextStyle(fontSize: 11, color: kGreen)),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: appTr('حذف'),
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.delete_outline, color: kMuted, size: 20),
            onPressed: () async {
              final ok = await state.deleteTask(t);
              if (!ok && context.mounted) showSnack(context, appTr('ما اتحذفتش. اتأكد من النت.'));
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final pending = state.tasks.where((t) => !t.isDone).toList();
        final done = state.tasks.where((t) => t.isDone).toList();
        final ordered = [...pending, ...done];

        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            title: Text(appTr('المهام'), style: TextStyle(fontSize: 18)),
            actions: [
              IconButton(
                tooltip: appTr('مهمة جديدة'),
                icon: Icon(Icons.add_circle, color: kGreen, size: 28),
                onPressed: () => showTaskDialog(context, state),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (ordered.isEmpty)
                Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: Center(
                    child: Text(appTr('اضغط (+) لإضافة أول مهمة.'), style: TextStyle(color: kMuted)),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                      trp('باقي {a} من {b}', {'a': pending.length, 'b': ordered.length}),
                      style: TextStyle(fontSize: 12, color: kMuted)),
                ),
              ...ordered.map((t) => _taskCard(context, t)),
            ],
          ),
        );
      },
    );
  }
}
