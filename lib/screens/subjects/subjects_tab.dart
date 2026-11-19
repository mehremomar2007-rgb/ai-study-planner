import 'package:flutter/material.dart';

import 'package:ai_study_planner/localization/app_localization.dart';
import 'package:ai_study_planner/models/models.dart';
import 'package:ai_study_planner/state/app_state.dart';
import 'package:ai_study_planner/theme/app_colors.dart';
import 'package:ai_study_planner/theme/app_theme.dart';
import 'package:ai_study_planner/utils/formatters.dart';
import 'package:ai_study_planner/widgets/common/snack.dart';
import 'package:ai_study_planner/widgets/dialogs/dialogs.dart';

class SubjectsTab extends StatelessWidget {
  final AppState state;
  const SubjectsTab({super.key, required this.state});

  Future<void> _confirmDelete(BuildContext context, SubjectModel s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard,
        title: Text(appTr('حذف المادة؟'), style: TextStyle(color: Colors.white)),
        content: Text(trp('هتتحذف "{name}" من القائمة. الجلسات القديمة هتفضل في السجل.', {'name': s.name}),
            style: TextStyle(color: kMuted)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(appTr('إلغاء'))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(appTr('حذف'), style: TextStyle(color: kRed))),
        ],
      ),
    );
    if (ok != true) return;
    final deleted = await state.deleteSubject(s);
    if (!deleted && context.mounted) {
      showSnack(context, appTr('ما اتحذفتش. اتأكد من النت.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) => Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: Text(appTr('المواد'), style: TextStyle(fontSize: 18)),
          actions: [
            IconButton(
              tooltip: appTr('مزامنة'),
              onPressed: state.syncing ? null : () => state.refresh(),
              icon: state.syncing
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: kMuted),
                    )
                  : Icon(Icons.sync_rounded, color: kMuted),
            ),
            IconButton(
              tooltip: appTr('إضافة مادة'),
              icon: Icon(Icons.add_circle, color: kGreen, size: 28),
              onPressed: () => showSubjectDialog(context, state),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (state.subjects.isEmpty)
              Padding(
                padding: EdgeInsets.only(top: 40),
                child: Center(
                  child: Text(appTr('اضغط (+) لإضافة أول مادة.'), style: TextStyle(color: kMuted)),
                ),
              ),
            ...state.subjects.map((s) {
              final done = state.todayHoursFor(s.name);
              final p = s.targetHours <= 0 ? 0.0 : (done / s.targetHours).clamp(0.0, 1.0);
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: cardDecoration(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(s.name,
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white)),
                        ),
                        IconButton(
                          tooltip: appTr('تعديل'),
                          visualDensity: VisualDensity.compact,
                          icon: Icon(Icons.edit_outlined, color: kMuted, size: 20),
                          onPressed: () => showSubjectDialog(context, state, existing: s),
                        ),
                        IconButton(
                          tooltip: appTr('حذف'),
                          visualDensity: VisualDensity.compact,
                          icon: Icon(Icons.delete_outline, color: kMuted, size: 20),
                          onPressed: () => _confirmDelete(context, s),
                        ),
                      ],
                    ),
                    SizedBox(height: 4),
                    Text('${diffLabel(s.difficulty)} • ${appTr('الهدف')} ${fmtHours(s.targetHours)} • ${appTr('النهاردة')} ${fmtHours(done)}',
                      style: TextStyle(fontSize: 12, color: kMuted),
                    ),
                    SizedBox(height: 8),
                    LinearProgressIndicator(value: p, backgroundColor: kDeep, color: kGreen),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
