import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ai_study_planner/config/supabase_config.dart';
import 'package:ai_study_planner/localization/app_localization.dart';
import 'package:ai_study_planner/theme/app_colors.dart';
import 'package:ai_study_planner/widgets/dialogs/dialogs.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final nameController = TextEditingController();
  bool isSignUp = false;
  bool loading = false;
  String? message;
  Color messageColor = kRed;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = emailController.text.trim();
    final password = passwordController.text;
    if (email.isEmpty || !email.contains('@')) {
      setState(() {
        message = appTr('اكتب إيميل صحيح');
        messageColor = kRed;
      });
      return;
    }
    if (password.length < 6) {
      setState(() {
        message = appTr('كلمة السر لازم تكون 6 حروف على الأقل');
        messageColor = kRed;
      });
      return;
    }

    setState(() {
      loading = true;
      message = null;
    });
    try {
      if (isSignUp) {
        final name = nameController.text.trim();
        final res = await supabase.auth.signUp(
          email: email,
          password: password,
          data: name.isEmpty ? null : {'name': name},
        );
        if (res.session == null && mounted) {
          setState(() {
            message = appTr('اتبعتلك إيميل تأكيد. افتحه وبعدين سجّل دخول.');
            messageColor = kGreen;
            isSignUp = false;
          });
        }
      } else {
        await supabase.auth.signInWithPassword(email: email, password: password);
      }
    } on AuthException catch (e) {
      if (mounted) {
        setState(() {
          message = e.message;
          messageColor = kRed;
        });
      }
    } catch (e) {
      debugPrint('auth failed: $e');
      if (mounted) {
        setState(() {
          message = appTr('حصلت مشكلة في الاتصال. اتأكد من النت وحاول تاني.');
          messageColor = kRed;
        });
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.spa_rounded, color: kGreen, size: 48),
                  SizedBox(height: 12),
                  Text(tr('StudyPace'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white)),
                  SizedBox(height: 4),
                  Text(appTr(isSignUp ? 'أنشئ حساب جديد' : 'سجّل دخول'),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: kMuted)),
                  SizedBox(height: 28),
                  if (isSignUp) ...[
                    TextField(
                      controller: nameController,
                      style: TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: appTr('اسمك'),
                        labelStyle: TextStyle(color: kMuted),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    SizedBox(height: 14),
                  ],
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    textDirection: TextDirection.ltr,
                    style: TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: appTr('الإيميل'),
                      labelStyle: TextStyle(color: kMuted),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  SizedBox(height: 14),
                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    textDirection: TextDirection.ltr,
                    style: TextStyle(color: Colors.white),
                    onSubmitted: (_) => loading ? null : _submit(),
                    decoration: InputDecoration(
                      labelText: appTr('كلمة السر'),
                      labelStyle: TextStyle(color: kMuted),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (!isSignUp)
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton(
                        onPressed: loading
                            ? null
                            : () => showResetPasswordDialog(
                                context, emailController.text.trim()),
                        child: Text(appTr('نسيت كلمة السر؟'),
                            style: TextStyle(color: kMuted, fontSize: 12)),
                      ),
                    ),
                  if (message != null) ...[
                    SizedBox(height: 12),
                    Text(message!,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: messageColor, height: 1.4)),
                  ],
                  SizedBox(height: 20),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kGreen,
                      foregroundColor: kBg,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape:
                          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: loading ? null : _submit,
                    child: loading
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: kBg),
                          )
                        : Text(appTr(isSignUp ? 'إنشاء حساب' : 'دخول'),
                            style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  SizedBox(height: 8),
                  TextButton(
                    onPressed: loading
                        ? null
                        : () => setState(() {
                              isSignUp = !isSignUp;
                              message = null;
                            }),
                    child: Text(
                      appTr(isSignUp ? 'عندي حساب بالفعل' : 'مفيش حساب؟ أنشئ واحد'),
                      style: TextStyle(color: kMuted, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
