import 'package:flutter/material.dart';

import 'package:ai_study_planner/config/supabase_config.dart';
import 'package:ai_study_planner/localization/app_localization.dart';
import 'package:ai_study_planner/localization/language_helper.dart';
import 'package:ai_study_planner/screens/auth/login_screen.dart';
import 'package:ai_study_planner/state/app_state.dart';
import 'package:ai_study_planner/theme/app_colors.dart';

class ProfileScreen extends StatefulWidget {
  final AppState state;
  const ProfileScreen({super.key, required this.state});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final TextEditingController nameController;
  late final TextEditingController customMajorController;
  String level = '';
  String year = '';
  String major = '';
  String language = 'العربية';

  final Map<String, List<String>> levels = const {
    'ابتدائي': ['الصف الأول', 'الصف الثاني', 'الصف الثالث', 'الصف الرابع', 'الصف الخامس', 'الصف السادس'],
    'إعدادي': ['الصف الأول', 'الصف الثاني', 'الصف الثالث'],
    'ثانوي': ['الصف الأول', 'الصف الثاني', 'الصف الثالث'],
    'جامعة': ['السنة الأولى', 'السنة الثانية', 'السنة الثالثة', 'السنة الرابعة', 'السنة الخامسة', 'السنة السادسة', 'السنة السابعة'],
  };
  final majors = const ['حاسبات ومعلومات', 'ذكاء اصطناعي', 'نظم معلومات', 'تكنولوجيا المعلومات', 'هندسة برمجيات', 'طب بشري', 'طب أسنان', 'صيدلة', 'هندسة', 'تجارة وإدارة أعمال', 'حقوق', 'إعلام', 'علوم', 'تخصص آخر'];

  final supportedLanguages = const [
    'العربية',
    'English',
    'الإسبانية',
    'الفرنسية',
    'الألمانية',
    'الروسية',
    'الصينية',
    'البرتغالية',
    'اليابانية',
    'الإيطالية'
  ];

  @override
  void initState() {
    super.initState();
    final s = widget.state;
    nameController = TextEditingController(text: s.profileName.isEmpty ? s.userNameOrNull ?? '' : s.profileName);
    customMajorController = TextEditingController(text: s.major);
    level = s.educationLevel;
    year = s.educationYear;
    major = s.major;
    language = s.appLanguage;
  }
  @override
  void dispose() { nameController.dispose(); customMajorController.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final isUniversity = level == 'جامعة';
    return Scaffold(
      appBar: AppBar(title: Text(appTr('الملف الشخصي'))),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Center(child: CircleAvatar(radius: 38, backgroundColor: kGreen.withValues(alpha: .18), child: Icon(Icons.person, size: 42, color: kGreen))),
        SizedBox(height: 20),
        TextField(controller: nameController, decoration: InputDecoration(labelText: appTr('الاسم الكامل'), border: OutlineInputBorder())),
        SizedBox(height: 14),
        if (supabaseReady && supabase.auth.currentUser != null) ...[
          ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.email_outlined), title: Text(appTr('البريد الإلكتروني')), subtitle: Text(supabase.auth.currentUser?.email ?? '')),
          ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.verified_user_outlined), title: Text(appTr('الحساب')), subtitle: Text(appTr('حساب مسجل'))),
        ] else ...[
          ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.person_outline), title: Text(appTr('وضع الاستخدام')), subtitle: Text(appTr('ضيف — بياناتك محفوظة على هذا الجهاز'))),
          OutlinedButton.icon(onPressed: !supabaseReady ? null : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LoginScreen())), icon: Icon(Icons.person_add_alt_1), label: Text(appTr('إنشاء حساب أو تسجيل الدخول'))),
        ],
        SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: levels.containsKey(level) ? level : null,
          decoration: InputDecoration(labelText: appTr('المرحلة التعليمية'), border: OutlineInputBorder()),
          items: levels.keys.map((x) => DropdownMenuItem(value: x, child: Text(appTr(x)))).toList(),
          onChanged: (v) => setState(() { level = v ?? ''; year = ''; })
        ),
        if (level.isNotEmpty) ...[
          SizedBox(height: 14),
          DropdownButtonFormField<String>(
            value: levels[level]!.contains(year) ? year : null,
            decoration: InputDecoration(labelText: appTr('الصف / السنة الدراسية'), border: OutlineInputBorder()),
            items: levels[level]!.map((x) => DropdownMenuItem(value: x, child: Text(appTr(x)))).toList(),
            onChanged: (v) => setState(() => year = v ?? '')
          ),
        ],
        if (isUniversity) ...[
          SizedBox(height: 14),
          DropdownButtonFormField<String>(
            value: majors.contains(major) ? major : (major.isEmpty ? null : 'تخصص آخر'),
            decoration: InputDecoration(labelText: appTr('الكلية / التخصص'), border: OutlineInputBorder()),
            items: majors.map((x) => DropdownMenuItem(value: x, child: Text(appTr(x)))).toList(),
            onChanged: (v) => setState(() => major = v ?? '')
          ),
          if (major == 'تخصص آخر') ...[
            SizedBox(height: 12),
            TextField(controller: customMajorController, decoration: InputDecoration(labelText: appTr('اكتب تخصصك'), border: OutlineInputBorder()), onChanged: (v) => major = v),
          ],
        ],
        SizedBox(height: 14),
        DropdownButtonFormField<String>(
          value: supportedLanguages.contains(language) ? language : 'العربية',
          decoration: InputDecoration(labelText: appTr('لغة التطبيق'), border: OutlineInputBorder()),
          items: supportedLanguages.map((x) => DropdownMenuItem(value: x, child: Text(nativeLangNames[x] ?? x))).toList(),
          onChanged: (v) => setState(() => language = v ?? 'العربية')
        ),
        SizedBox(height: 20),
        ElevatedButton.icon(
          onPressed: () async {
            final chosenMajor = isUniversity ? (major == 'تخصص آخر' ? customMajorController.text.trim() : major) : '';
            await widget.state.saveProfile(name: nameController.text, level: level, year: year, selectedMajor: chosenMajor, language: language);
            if (mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(appTr('تم حفظ بيانات الملف الشخصي')))); Navigator.pop(context); }
          },
          icon: Icon(Icons.save),
          label: Text(appTr('حفظ التغييرات'))
        ),
        if (supabaseReady && supabase.auth.currentSession != null) ...[
          SizedBox(height: 12),
          TextButton.icon(
            onPressed: () async { await supabase.auth.signOut(); if (mounted) Navigator.pop(context); },
            icon: Icon(Icons.logout),
            label: Text(appTr('تسجيل الخروج والعودة كضيف'))
          ),
        ],
      ]),
    );
  }
}
