import 'package:flutter/material.dart';

import 'package:ai_study_planner/localization/app_localization.dart';
import 'package:ai_study_planner/state/app_state.dart';
import 'package:ai_study_planner/theme/app_colors.dart';
import 'package:ai_study_planner/widgets/common/snack.dart';

Future<void> showNameDialog(BuildContext context, AppState state) {
  final controller = TextEditingController(text: state.userNameOrNull ?? '');
  var saving = false;
  return showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        backgroundColor: kCard,
        title: Text(appTr('اسمك'), style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 30,
          style: TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: appTr('اكتب اسمك'),
            labelStyle: TextStyle(color: kMuted),
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
                    final name = controller.text.trim();
                    if (name.isEmpty) {
                      showSnack(ctx, appTr('اكتب اسمك'));
                      return;
                    }
                    setLocal(() => saving = true);
                    final ok = await state.setUserName(name);
                    if (!ctx.mounted) return;
                    if (ok) {
                      Navigator.pop(ctx);
                    } else {
                      setLocal(() => saving = false);
                      showSnack(ctx, appTr('ما اتحفظتش. اتأكد من النت.'));
                    }
                  },
            child: Text(appTr('حفظ'), style: TextStyle(color: kBg)),
          ),
        ],
      ),
    ),
  );
}
