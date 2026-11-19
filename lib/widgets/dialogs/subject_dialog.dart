import 'package:flutter/material.dart';

import 'package:ai_study_planner/localization/app_localization.dart';
import 'package:ai_study_planner/models/models.dart';
import 'package:ai_study_planner/state/app_state.dart';
import 'package:ai_study_planner/theme/app_colors.dart';
import 'package:ai_study_planner/utils/formatters.dart';
import 'package:ai_study_planner/widgets/common/snack.dart';

Future<void> showSubjectDialog(
  BuildContext context,
  AppState state, {
  SubjectModel? existing,
}) {
  final nameController = TextEditingController(text: existing?.name ?? '');
  final targetController =
      TextEditingController(text: (existing?.targetHours ?? 2.0).toString());
  var difficulty = existing?.difficulty ?? 'Medium';
  var saving = false;

  return showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        backgroundColor: kCard,
        title: Text(tr(existing != null ? 'تعديل المادة' : 'إضافة مادة جديدة'),
            style: TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameController,
                style: TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: appTr('اسم المادة (مثال: Databases)'),
                  labelStyle: TextStyle(color: kMuted),
                ),
              ),
              SizedBox(height: 16),
              Text(appTr('مستوى الصعوبة'), style: TextStyle(fontSize: 12, color: kMuted)),
              SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: ['Easy', 'Medium', 'Hard']
                    .map((d) => ChoiceChip(
                          label: Text(diffLabel(d)),
                          selected: difficulty == d,
                          onSelected: (_) => setLocal(() => difficulty = d),
                        ))
                    .toList(),
              ),
              SizedBox(height: 12),
              TextField(
                controller: targetController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: appTr('الهدف اليومي بالساعات'),
                  labelStyle: TextStyle(color: kMuted),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx),
              child: Text(appTr('إلغاء'))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kGreen),
            onPressed: saving
                ? null
                : () async {
                    final name = nameController.text.trim();
                    final target = parseNumber(targetController.text);
                    if (name.isEmpty) {
                      showSnack(ctx, appTr('اكتب اسم المادة'));
                      return;
                    }
                    final clash = state.subjects.any((s) =>
                        s.name.toLowerCase() == name.toLowerCase() &&
                        s.name != existing?.name);
                    if (clash) {
                      showSnack(ctx, appTr('المادة دي موجودة بالفعل'));
                      return;
                    }
                    if (target == null || target <= 0 || target > 12) {
                      showSnack(ctx, appTr('الهدف لازم يكون أكبر من 0 وأقل من 12 ساعة'));
                      return;
                    }

                    setLocal(() => saving = true);
                    final ok = existing != null
                        ? await state.updateSubject(
                            existing.name,
                            existing.copyWith(
                                name: name, difficulty: difficulty, targetHours: target),
                          )
                        : await state.addSubject(name, difficulty, target);
                    if (!ctx.mounted) return;
                    if (ok) {
                      Navigator.pop(ctx);
                    } else {
                      setLocal(() => saving = false);
                      showSnack(ctx, appTr('ما اتحفظتش. اتأكد من النت ومن إعدادات Supabase.'));
                    }
                  },
            child: saving
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: kBg),
                  )
                : Text(appTr('حفظ'), style: TextStyle(color: kBg)),
          ),
        ],
      ),
    ),
  );
}
