import 'package:flutter/material.dart';

import 'package:ai_study_planner/localization/app_localization.dart';
import 'package:ai_study_planner/state/app_state.dart';
import 'package:ai_study_planner/theme/app_colors.dart';
import 'package:ai_study_planner/widgets/common/snack.dart';

Future<void> showTaskDialog(BuildContext context, AppState state) {
  final titleController = TextEditingController();
  String? subject;
  var saving = false;
  return showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        backgroundColor: kCard,
        title: Text(appTr('مهمة جديدة'), style: TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: titleController,
                autofocus: true,
                style: TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: appTr('المهمة (مثال: حل شيت 3)'),
                  labelStyle: TextStyle(color: kMuted),
                ),
              ),
              SizedBox(height: 16),
              Text(appTr('المادة (اختياري)'), style: TextStyle(fontSize: 12, color: kMuted)),
              DropdownButton<String?>(
                isExpanded: true,
                dropdownColor: kCard,
                value: subject,
                items: [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text(appTr('بدون مادة'), style: TextStyle(color: Colors.white)),
                  ),
                  ...state.subjects.map((s) => DropdownMenuItem<String?>(
                        value: s.name,
                        child: Text(s.name, style: TextStyle(color: Colors.white)),
                      )),
                ],
                onChanged: (v) => setLocal(() => subject = v),
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
                    final title = titleController.text.trim();
                    if (title.isEmpty) {
                      showSnack(ctx, appTr('اكتب المهمة'));
                      return;
                    }
                    setLocal(() => saving = true);
                    final ok = await state.addTask(title, subject);
                    if (!ctx.mounted) return;
                    if (ok) {
                      Navigator.pop(ctx);
                    } else {
                      setLocal(() => saving = false);
                      showSnack(ctx, appTr('ما اتحفظتش. اتأكد من النت.'));
                    }
                  },
            child: Text(appTr('إضافة'), style: TextStyle(color: kBg)),
          ),
        ],
      ),
    ),
  );
}
