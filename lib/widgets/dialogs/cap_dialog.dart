import 'package:flutter/material.dart';

import 'package:ai_study_planner/localization/app_localization.dart';
import 'package:ai_study_planner/state/app_state.dart';
import 'package:ai_study_planner/theme/app_colors.dart';
import 'package:ai_study_planner/utils/formatters.dart';
import 'package:ai_study_planner/widgets/common/snack.dart';

Future<void> showCapDialog(BuildContext context, AppState state) {
  final controller = TextEditingController(text: state.dailySafeCap.toString());
  return showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: kCard,
      title: Text(appTr('الحد اليومي الآمن'), style: TextStyle(color: Colors.white)),
      content: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: appTr('عدد الساعات (من 0.5 إلى 16)'),
          labelStyle: TextStyle(color: kMuted),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(appTr('إلغاء'))),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: kGreen),
          onPressed: () {
            final v = parseNumber(controller.text);
            if (v == null || v < 0.5 || v > 16) {
              showSnack(ctx, appTr('اكتب رقم بين 0.5 و 16'));
              return;
            }
            state.setDailyCap(v);
            Navigator.pop(ctx);
          },
          child: Text(appTr('حفظ'), style: TextStyle(color: kBg)),
        ),
      ],
    ),
  );
}
