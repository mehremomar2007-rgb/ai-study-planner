import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ai_study_planner/config/supabase_config.dart';
import 'package:ai_study_planner/localization/app_localization.dart';
import 'package:ai_study_planner/theme/app_colors.dart';

Future<void> showResetPasswordDialog(BuildContext context, String initialEmail) {
  final emailController = TextEditingController(text: initialEmail);
  final codeController = TextEditingController();
  final passwordController = TextEditingController();
  var codeSent = false;
  var loading = false;
  String? error;

  return showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        Future<void> run(Future<void> Function() job) async {
          setLocal(() {
            loading = true;
            error = null;
          });
          try {
            await job();
          } on AuthException catch (e) {
            if (ctx.mounted) setLocal(() => error = e.message);
          } catch (e) {
            debugPrint('reset failed: $e');
            if (ctx.mounted) setLocal(() => error = appTr('حصلت مشكلة في الاتصال. حاول تاني.'));
          }
          if (ctx.mounted) setLocal(() => loading = false);
        }

        Future<void> sendCode() async {
          final email = emailController.text.trim();
          if (!email.contains('@')) {
            setLocal(() => error = appTr('اكتب إيميل صحيح'));
            return;
          }
          await run(() async {
            await supabase.auth.resetPasswordForEmail(email);
            if (ctx.mounted) setLocal(() => codeSent = true);
          });
        }

        Future<void> confirm() async {
          final code = codeController.text.trim();
          final pass = passwordController.text;
          if (code.isEmpty) {
            setLocal(() => error = appTr('اكتب الكود اللي وصلك على الإيميل'));
            return;
          }
          if (pass.length < 6) {
            setLocal(() => error = appTr('كلمة السر لازم تكون 6 حروف على الأقل'));
            return;
          }
          await run(() async {
            await supabase.auth.verifyOTP(
              type: OtpType.recovery,
              email: emailController.text.trim(),
              token: code,
            );
            await supabase.auth.updateUser(UserAttributes(password: pass));
            if (ctx.mounted) Navigator.pop(ctx);
          });
        }

        return AlertDialog(
          backgroundColor: kCard,
          title: Text(appTr('نسيت كلمة السر'), style: TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: emailController,
                  enabled: !codeSent,
                  keyboardType: TextInputType.emailAddress,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: appTr('الإيميل'),
                    labelStyle: TextStyle(color: kMuted),
                  ),
                ),
                if (codeSent) ...[
                  SizedBox(height: 12),
                  Text(appTr('بعتنالك كود على الإيميل. اكتبه هنا مع كلمة السر الجديدة.'),
                      style: TextStyle(fontSize: 12, color: kMuted, height: 1.4)),
                  TextField(
                    controller: codeController,
                    keyboardType: TextInputType.number,
                    textDirection: TextDirection.ltr,
                    style: TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: appTr('الكود'),
                      labelStyle: TextStyle(color: kMuted),
                    ),
                  ),
                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    textDirection: TextDirection.ltr,
                    style: TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: appTr('كلمة السر الجديدة'),
                      labelStyle: TextStyle(color: kMuted),
                    ),
                  ),
                ],
                if (error != null) ...[
                  SizedBox(height: 12),
                  Text(error!, style: TextStyle(fontSize: 12, color: kRed)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: loading ? null : () => Navigator.pop(ctx),
                child: Text(appTr('إلغاء'))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: kGreen),
              onPressed: loading ? null : (codeSent ? confirm : sendCode),
              child: loading
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: kBg),
                    )
                  : Text(tr(codeSent ? 'تأكيد' : 'ابعت الكود'),
                      style: TextStyle(color: kBg)),
            ),
          ],
        );
      },
    ),
  );
}
