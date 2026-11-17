import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ═══════════ supabase_config.dart ═══════════

// حط هنا بيانات مشروعك (Settings ← API). استخدم anon key بس، مش service_role أبداً.
const kSupabaseUrl = 'https://mgssvmfhcepybwcvafxz.supabase.co';
const kSupabaseAnonKey = 'sb_publishable_yFxYm5-zCet2HIfq_rU_yA_IkCMdZM9';

/// بيبقى true لما Supabase.initialize تنجح.
/// لو false التطبيق بيشتغل بالبيانات المحفوظة على الجهاز بس.
bool supabaseReady = false;

SupabaseClient get supabase => Supabase.instance.client;

/// أي طلب للسيرفر بيتقطع بعد 10 ثواني بدل ما يفضل معلّق
Future<T> _net<T>(Future<T> f) => f.timeout(const Duration(seconds: 10));

// ═══════════ utils/dates.dart ═══════════

// أدوات التواريخ. بنبني التاريخ بـ DateTime(y, m, d + n) بدل Duration
// عشان تغيير التوقيت الصيفي في مصر ما يبوّظش حساب الأيام.

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

DateTime addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

/// بداية الأسبوع = السبت
DateTime weekStart(DateTime d) {
  final offset = (d.weekday - DateTime.saturday) % 7;
  return DateTime(d.year, d.month, d.day - offset);
}

// الفهرس = weekday - 1  (الإثنين = 0 ... الأحد = 6)
const kDayNames = [
  'الإثنين',
  'الثلاثاء',
  'الأربعاء',
  'الخميس',
  'الجمعة',
  'السبت',
  'الأحد',
];

const kDayShort = ['إثن', 'ثلا', 'أرب', 'خمي', 'جمع', 'سبت', 'أحد'];

String dayName(DateTime d) => kDayNames[d.weekday - 1];

String shortDate(DateTime d) => '${d.day}/${d.month}';

// ═══════════ models/guard_level.dart ═══════════

enum GuardLevel { safe, warning, over }

// ═══════════ models/subject.dart ═══════════

class SubjectModel {
  final int? id; // رقم الصف في Supabase (null = مادة قديمة لسه ما اترفعتش)
  final String name;
  final String difficulty; // Easy, Medium, Hard
  final double targetHours; // هدف المادة اليومي (بيتخزن في عمود max_hours)
  final DateTime createdAt; // عشان الخطة ما تحسبش أيام قبل إضافة المادة

  const SubjectModel({
    this.id,
    required this.name,
    required this.difficulty,
    required this.targetHours,
    required this.createdAt,
  });

  /// ترتيب الصعوبة: الصعبة أولاً
  int get rank => switch (difficulty) {
        'Hard' => 0,
        'Medium' => 1,
        _ => 2,
      };

  SubjectModel copyWith({String? name, String? difficulty, double? targetHours}) =>
      SubjectModel(
        id: id,
        name: name ?? this.name,
        difficulty: difficulty ?? this.difficulty,
        targetHours: targetHours ?? this.targetHours,
        createdAt: createdAt,
      );

  // ───── التخزين المحلي (كاش على الجهاز) ─────
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'difficulty': difficulty,
        'targetHours': targetHours,
        'createdAt': createdAt.toIso8601String(),
      };

  factory SubjectModel.fromJson(Map<String, dynamic> j) => SubjectModel(
        id: (j['id'] as num?)?.toInt(),
        name: j['name'] as String,
        difficulty: j['difficulty'] as String,
        targetHours: (j['targetHours'] as num).toDouble(),
        // البيانات القديمة ماكانش فيها تاريخ إنشاء، فبنعتبرها اتضافت النهاردة
        createdAt: j['createdAt'] is String
            ? DateTime.parse(j['createdAt'] as String)
            : dateOnly(DateTime.now()),
      );

  // ───── Supabase (جدول subject) ─────
  factory SubjectModel.fromRemote(Map<String, dynamic> r) => SubjectModel(
        id: (r['id'] as num).toInt(),
        name: r['name'] as String,
        difficulty: (r['difficulty'] as String?) ?? 'Medium',
        targetHours: ((r['max_hours'] as num?) ?? 2).toDouble(),
        createdAt: dateOnly(DateTime.parse(r['created_at'] as String).toLocal()),
      );
}

// ═══════════ models/study_session.dart ═══════════

class StudySession {
  final int? id; // null = لسه ما اترفعتش للسيرفر
  final String subject;
  final DateTime date;
  final double hours;

  const StudySession({
    this.id,
    required this.subject,
    required this.date,
    required this.hours,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'subject': subject,
        'date': date.toIso8601String(),
        'hours': hours,
      };

  factory StudySession.fromJson(Map<String, dynamic> j) => StudySession(
        id: (j['id'] as num?)?.toInt(),
        subject: j['subject'] as String,
        date: DateTime.parse(j['date'] as String),
        hours: (j['hours'] as num).toDouble(),
      );

  // ───── Supabase (جدول sessions) ─────
  Map<String, dynamic> toRemote() => {
        'subject': subject,
        'hours': hours,
        'session_date': date.toUtc().toIso8601String(),
      };

  factory StudySession.fromRemote(Map<String, dynamic> r) => StudySession(
        id: (r['id'] as num).toInt(),
        subject: r['subject'] as String,
        date: DateTime.parse(r['session_date'] as String).toLocal(),
        hours: (r['hours'] as num).toDouble(),
      );
}

// ═══════════ models/task.dart ═══════════

class TaskModel {
  final int id;
  final String title;
  final bool isDone;
  final String? subjectName;

  const TaskModel({
    required this.id,
    required this.title,
    required this.isDone,
    this.subjectName,
  });

  TaskModel copyWith({bool? isDone}) => TaskModel(
        id: id,
        title: title,
        isDone: isDone ?? this.isDone,
        subjectName: subjectName,
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'title': title, 'isDone': isDone, 'subjectName': subjectName};

  factory TaskModel.fromJson(Map<String, dynamic> j) => TaskModel(
        id: (j['id'] as num).toInt(),
        title: j['title'] as String,
        isDone: (j['isDone'] as bool?) ?? false,
        subjectName: j['subjectName'] as String?,
      );

  factory TaskModel.fromRemote(Map<String, dynamic> r) => TaskModel(
        id: (r['id'] as num).toInt(),
        title: (r['title'] as String?) ?? '',
        isDone: (r['is_done'] as bool?) ?? false,
        subjectName: r['subject_name'] as String?,
      );
}

// ═══════════ services/planner.dart ═══════════

/// خطة يوم واحد
class DayPlan {
  final DateTime date;
  final bool isRest;

  /// الساعات الأساسية لكل مادة
  final Map<String, double> base = {};

  /// الساعات اللي اتنقلت من أيام فاتت (Auto-Reschedule)
  final Map<String, double> carried = {};

  DayPlan(this.date, this.isRest);

  Set<String> get subjects => {...base.keys, ...carried.keys};

  double hoursFor(String subject) => (base[subject] ?? 0) + (carried[subject] ?? 0);

  double get total =>
      base.values.fold(0.0, (a, b) => a + b) +
      carried.values.fold(0.0, (a, b) => a + b);
}

/// خطة الأسبوع (من السبت للجمعة)
class WeekPlan {
  final List<DayPlan> days;

  /// ساعات ماقدرناش نلاقيلها مكان تحت الحد الآمن
  final Map<String, double> unplaced;

  /// إجمالي الساعات اللي اتنقلت من أيام فاتت
  final double carriedTotal;

  const WeekPlan({
    required this.days,
    required this.unplaced,
    required this.carriedTotal,
  });
}

class Planner {
  /// قواعد الخطة:
  /// 1. كل يوم مذاكرة فيه كل مادة بهدفها اليومي.
  /// 2. لو مجموع الأهداف أكبر من الحد الآمن، الأهداف بتتصغّر بنفس النسبة.
  /// 3. يوم الراحة فاضي.
  /// 4. (Auto-Reschedule) اللي فاتك في الأيام اللي فاتت بيتوزع بالتساوي على
  ///    الأيام الجاية (من النهاردة)، المواد الصعبة الأول، من غير ما أي يوم يعدّي الحد.
  static WeekPlan build({
    required List<SubjectModel> subjects,
    required double cap,
    required int restDay, // 0 = مفيش يوم راحة
    required bool autoReschedule,
    required DateTime today,
    required double Function(String subject, DateTime day) hoursFor,
  }) {
    final todayDate = dateOnly(today);
    final start = weekStart(todayDate);

    final sumTargets = subjects.fold(0.0, (a, s) => a + s.targetHours);
    final scale = (sumTargets > cap && sumTargets > 0) ? cap / sumTargets : 1.0;

    final days = List.generate(7, (i) {
      final date = addDays(start, i);
      final rest = restDay != 0 && date.weekday == restDay;
      final plan = DayPlan(date, rest);
      if (!rest) {
        for (final s in subjects) {
          if (!date.isBefore(dateOnly(s.createdAt))) {
            plan.base[s.name] = s.targetHours * scale;
          }
        }
      }
      return plan;
    });

    final unplaced = <String, double>{};
    var carriedTotal = 0.0;

    if (autoReschedule) {
      final sorted = [...subjects]..sort((a, b) => a.rank.compareTo(b.rank));
      final future =
          days.where((d) => !d.isRest && !d.date.isBefore(todayDate)).toList();

      for (final s in sorted) {
        // النقص = مجموع (المخطط - المذاكَر) في الأيام اللي فاتت
        var deficit = 0.0;
        for (final d in days) {
          if (d.isRest || !d.date.isBefore(todayDate)) continue;
          final planned = d.base[s.name] ?? 0;
          if (planned <= 0) continue;
          deficit += math.max(0.0, planned - hoursFor(s.name, d.date));
        }
        if (deficit < 0.05) continue; // أقل من 3 دقايق مش مهم

        var remaining = deficit;
        for (var pass = 0; pass < 6 && remaining > 0.01; pass++) {
          final open = future.where((d) => cap - d.total > 0.01).toList();
          if (open.isEmpty) break;
          final share = remaining / open.length;
          for (final d in open) {
            final give = math.min(share, cap - d.total);
            d.carried[s.name] = (d.carried[s.name] ?? 0) + give;
            remaining -= give;
            carriedTotal += give;
          }
        }
        if (remaining > 0.05) unplaced[s.name] = remaining;
      }
    }

    return WeekPlan(days: days, unplaced: unplaced, carriedTotal: carriedTotal);
  }
}

// ═══════════ state/app_state.dart ═══════════

class Suggestion {
  final String subject;
  final double remaining;
  const Suggestion(this.subject, this.remaining);
}

/// حالة التطبيق كلها.
/// - الإعدادات (الحد اليومي، يوم الراحة، إعادة الجدولة) محفوظة على الجهاز.
/// - المواد والجلسات في Supabase، ومعاهم كاش على الجهاز عشان التطبيق يفتح بسرعة وأوفلاين.
class AppState extends ChangeNotifier {
  List<SubjectModel> subjects = [];
  List<StudySession> sessions = [];
  List<TaskModel> tasks = [];
  double dailySafeCap = 4.5;
  int restDay = DateTime.friday; // 0 = مفيش يوم راحة
  bool autoReschedule = true;

  bool syncing = false;
  String? syncError;
  bool _again = false;

  // ───────────── التحميل والحفظ المحلي ─────────────
  Future<void> loadLocal() async {
    final prefs = await SharedPreferences.getInstance();
    dailySafeCap = prefs.getDouble('dailySafeCap') ?? 4.5;
    restDay = prefs.getInt('restDay') ?? DateTime.friday;
    autoReschedule = prefs.getBool('autoReschedule') ?? true;
    final subjectsRaw = prefs.getString('subjects');
    final sessionsRaw = prefs.getString('sessions');
    final tasksRaw = prefs.getString('tasks');
    try {
      subjects = subjectsRaw == null
          ? []
          : (jsonDecode(subjectsRaw) as List)
              .map((e) => SubjectModel.fromJson(e as Map<String, dynamic>))
              .toList();
      sessions = sessionsRaw == null
          ? []
          : (jsonDecode(sessionsRaw) as List)
              .map((e) => StudySession.fromJson(e as Map<String, dynamic>))
              .toList();
      // نحتفظ بآخر 180 يوم بس عشان البيانات ما تكبرش
      final cutoff = DateTime.now().subtract(const Duration(days: 180));
      sessions = sessions.where((s) => s.date.isAfter(cutoff)).toList();
      tasks = tasksRaw == null
          ? []
          : (jsonDecode(tasksRaw) as List)
              .map((e) => TaskModel.fromJson(e as Map<String, dynamic>))
              .toList();
    } catch (_) {
      // لو البيانات المحفوظة بايظة نبدأ من جديد بدل ما التطبيق يقع
      subjects = [];
      sessions = [];
      tasks = [];
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('dailySafeCap', dailySafeCap);
    await prefs.setInt('restDay', restDay);
    await prefs.setBool('autoReschedule', autoReschedule);
    await prefs.setString(
        'subjects', jsonEncode(subjects.map((s) => s.toJson()).toList()));
    await prefs.setString(
        'sessions', jsonEncode(sessions.map((s) => s.toJson()).toList()));
    await prefs.setString(
        'tasks', jsonEncode(tasks.map((t) => t.toJson()).toList()));
  }

  void _changed() {
    notifyListeners();
    _save();
  }

  // ───────────── المزامنة مع Supabase ─────────────

  /// بترفع أي حاجة لسه ما اترفعتش، وبعدين بتسحب آخر نسخة من السيرفر.
  /// لو اتندهت وهي شغالة، بتعيد المزامنة مرة كمان بعد ما تخلص.
  Future<void> refresh() async {
    if (!supabaseReady) {
      syncError = 'Supabase مش متضبط. البيانات محفوظة على الجهاز بس.';
      notifyListeners();
      return;
    }
    if (syncing) {
      _again = true;
      return;
    }
    syncing = true;
    notifyListeners();
    do {
      _again = false;
      await _syncOnce();
    } while (_again);
    syncing = false;
    _changed();
  }

  Future<void> _syncOnce() async {
    try {
      await _pushLocalOnly();

      final cutoff = DateTime.now().subtract(const Duration(days: 180));
      final subjectRows =
          await _net(supabase.from('subject').select().order('created_at'));
      final sessionRows = await _net(supabase
          .from('sessions')
          .select()
          .gte('session_date', cutoff.toUtc().toIso8601String())
          .order('session_date'));
      final taskRows =
          await _net(supabase.from('tasks').select().order('created_at'));

      tasks = taskRows.map(TaskModel.fromRemote).toList();
      subjects = subjectRows.map(SubjectModel.fromRemote).toList();
      // الجلسات اللي اتضافت أثناء المزامنة (لسه من غير id) بنحتفظ بيها
      final inFlight = sessions.where((s) => s.id == null).toList();
      sessions = [...sessionRows.map(StudySession.fromRemote), ...inFlight];
      syncError = null;
    } catch (e) {
      debugPrint('Supabase sync failed: $e');
      syncError = 'تعذّر الاتصال بالسيرفر. بنعرض آخر بيانات محفوظة.';
    }
  }

  /// بترفع: (1) المواد القديمة اللي كانت محلية بس، (2) الجلسات اللي اتسجلت أوفلاين.
  Future<void> _pushLocalOnly() async {
    final legacy = subjects.where((s) => s.id == null).toList();
    if (legacy.isNotEmpty) {
      final rows = await _net(supabase.from('subject').select('name'));
      final existing = {
        for (final r in rows) (r['name'] as String).toLowerCase(),
      };
      for (final s in legacy) {
        if (existing.contains(s.name.toLowerCase())) continue;
        await _net(supabase.from('subject').insert({
          'name': s.name,
          'difficulty': s.difficulty,
          'max_hours': s.targetHours,
          'created_at': s.createdAt.toUtc().toIso8601String(),
        }));
      }
    }

    final pending = sessions.where((s) => s.id == null).toList();
    for (final s in pending) {
      final row =
          await _net(supabase.from('sessions').insert(s.toRemote()).select().single());
      final saved = StudySession.fromRemote(row);
      sessions = sessions.map((x) => identical(x, s) ? saved : x).toList();
    }
  }

  // ───────────── حسابات ─────────────
  double hoursOn(DateTime day) => sessions
      .where((s) => sameDay(s.date, day))
      .fold(0.0, (a, s) => a + s.hours);

  double hoursForOn(String subject, DateTime day) => sessions
      .where((s) => s.subject == subject && sameDay(s.date, day))
      .fold(0.0, (a, s) => a + s.hours);

  double get todayHours => hoursOn(DateTime.now());

  double todayHoursFor(String subject) => hoursForOn(subject, DateTime.now());

  double get ratio => dailySafeCap <= 0 ? 0 : todayHours / dailySafeCap;

  GuardLevel get level {
    if (ratio >= 1.0) return GuardLevel.over;
    if (ratio >= 0.7) return GuardLevel.warning;
    return GuardLevel.safe;
  }

  bool isRestDay(DateTime d) => restDay != 0 && d.weekday == restDay;

  /// أيام متتالية فيها مذاكرة. يوم الراحة الفاضي ما بيكسرش السلسلة،
  /// واليوم الحالي لو لسه فاضي ما بيكسرهاش.
  int get streak {
    final today = dateOnly(DateTime.now());
    var count = 0;
    for (var i = 0; i < 400; i++) {
      final d = addDays(today, -i);
      if (hoursOn(d) > 0) {
        count++;
      } else if (i == 0 || isRestDay(d)) {
        continue;
      } else {
        break;
      }
    }
    return count;
  }

  WeekPlan get weekPlan => Planner.build(
        subjects: subjects,
        cap: dailySafeCap,
        restDay: restDay,
        autoReschedule: autoReschedule,
        today: DateTime.now(),
        hoursFor: hoursForOn,
      );

  /// المادة المقترحة النهاردة: الأصعب اللي لسه عليها ساعات في خطة اليوم
  Suggestion? get todaySuggestion {
    final today = dateOnly(DateTime.now());
    final day = weekPlan.days.firstWhere((d) => sameDay(d.date, today));
    if (day.isRest) return null;

    Suggestion? best;
    var bestRank = 99;
    for (final s in subjects) {
      final rem = day.hoursFor(s.name) - hoursForOn(s.name, today);
      if (rem <= 0.02) continue;
      if (best == null || s.rank < bestRank || (s.rank == bestRank && rem > best.remaining)) {
        best = Suggestion(s.name, rem);
        bestRank = s.rank;
      }
    }
    return best;
  }

  // ───────────── العمليات ─────────────
  void setDailyCap(double hours) {
    dailySafeCap = hours;
    _changed();
  }

  void setRestDay(int weekday) {
    restDay = weekday;
    _changed();
  }

  void setAutoReschedule(bool value) {
    autoReschedule = value;
    _changed();
  }

  /// بترجع true لو اتحفظت في Supabase. محتاجة نت عشان ناخد الـ id من السيرفر.
  Future<bool> addSubject(String name, String difficulty, double target) async {
    if (!supabaseReady) return false;
    try {
      final row = await _net(supabase
          .from('subject')
          .insert({'name': name, 'difficulty': difficulty, 'max_hours': target})
          .select()
          .single());
      subjects = [...subjects, SubjectModel.fromRemote(row)];
      _changed();
      return true;
    } catch (e) {
      debugPrint('addSubject failed: $e');
      return false;
    }
  }

  /// تعديل مادة. لو الاسم اتغيّر، الجلسات القديمة بتتنقل للاسم الجديد.
  Future<bool> updateSubject(String oldName, SubjectModel updated) async {
    if (!supabaseReady) return false;
    try {
      if (updated.id != null) {
        await _net(supabase.from('subject').update({
          'name': updated.name,
          'difficulty': updated.difficulty,
          'max_hours': updated.targetHours,
        }).eq('id', updated.id!));
        if (oldName != updated.name) {
          await _net(supabase
              .from('sessions')
              .update({'subject': updated.name}).eq('subject', oldName));
        }
      }
      subjects = subjects.map((s) => s.name == oldName ? updated : s).toList();
      if (oldName != updated.name) {
        sessions = sessions
            .map((s) => s.subject == oldName
                ? StudySession(
                    id: s.id, subject: updated.name, date: s.date, hours: s.hours)
                : s)
            .toList();
      }
      _changed();
      return true;
    } catch (e) {
      debugPrint('updateSubject failed: $e');
      return false;
    }
  }

  Future<bool> deleteSubject(SubjectModel subject) async {
    if (!supabaseReady) return false;
    try {
      if (subject.id != null) {
        await _net(supabase.from('subject').delete().eq('id', subject.id!));
      }
      subjects = subjects.where((s) => s.name != subject.name).toList();
      _changed();
      return true;
    } catch (e) {
      debugPrint('deleteSubject failed: $e');
      return false;
    }
  }

  /// الجلسة بتظهر فوراً على الشاشة، وبعدين بتترفع للسيرفر في الخلفية.
  /// لو النت واقع بتفضل محفوظة محلياً وبتترفع في أول مزامنة ناجحة.
  void addSession(String subject, double hours) {
    sessions = [
      ...sessions,
      StudySession(subject: subject, date: DateTime.now(), hours: hours),
    ];
    _changed();
    unawaited(refresh());
  }

  // ───────────── المهام ─────────────
  Future<bool> addTask(String title, String? subjectName) async {
    if (!supabaseReady) return false;
    try {
      final row = await _net(supabase
          .from('tasks')
          .insert({'title': title, 'is_done': false, 'subject_name': subjectName})
          .select()
          .single());
      tasks = [...tasks, TaskModel.fromRemote(row)];
      _changed();
      return true;
    } catch (e) {
      debugPrint('addTask failed: $e');
      return false;
    }
  }

  Future<bool> toggleTask(TaskModel t) async {
    if (!supabaseReady) return false;
    try {
      await _net(supabase.from('tasks').update({'is_done': !t.isDone}).eq('id', t.id));
      tasks = tasks.map((x) => x.id == t.id ? x.copyWith(isDone: !t.isDone) : x).toList();
      _changed();
      return true;
    } catch (e) {
      debugPrint('toggleTask failed: $e');
      return false;
    }
  }

  Future<bool> deleteTask(TaskModel t) async {
    if (!supabaseReady) return false;
    try {
      await _net(supabase.from('tasks').delete().eq('id', t.id));
      tasks = tasks.where((x) => x.id != t.id).toList();
      _changed();
      return true;
    } catch (e) {
      debugPrint('deleteTask failed: $e');
      return false;
    }
  }

  // ───────────── اسم المستخدم (متخزن في حسابه على Supabase) ─────────────
  String? get userNameOrNull {
    if (!supabaseReady) return null;
    final n = supabase.auth.currentUser?.userMetadata?['name'];
    return (n is String && n.trim().isNotEmpty) ? n.trim() : null;
  }

  String get userName => userNameOrNull ?? 'صديقي';

  Future<bool> setUserName(String name) async {
    if (!supabaseReady) return false;
    try {
      await _net(supabase.auth.updateUser(UserAttributes(data: {'name': name})));
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('setUserName failed: $e');
      return false;
    }
  }

  /// بتتندّه لما المستخدم يسجّل خروج، عشان بياناته ما تفضلش ظاهرة على الجهاز
  Future<void> clearData() async {
    subjects = [];
    sessions = [];
    tasks = [];
    syncError = null;
    _changed();
  }
}

// ═══════════ theme.dart ═══════════

const kBg = Color(0xFF0b1326);
const kCard = Color(0xFF171f33);
const kDeep = Color(0xFF060e20);
const kGreen = Color(0xFF10B981);
const kIndigo = Color(0xFF6366F1);
const kMuted = Color(0xFFbbcabf);
const kBorder = Color(0xFF3c4a42);
const kOrange = Color(0xFFFFB020);
const kRed = Color(0xFFEF4444);

ThemeData buildDarkTheme() => ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: kBg,
      primaryColor: kGreen,
      colorScheme: const ColorScheme.dark(
        surface: kCard,
        primary: kGreen,
        secondary: kIndigo,
        error: Color(0xFFffb4ab),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: kCard,
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: kBorder.withValues(alpha: 0.6)),
        ),
      ),
    );

// ───────────── نصوص وألوان مشتركة ─────────────
String fmtHours(double hours) {
  final totalMin = (hours * 60).round();
  final h = totalMin ~/ 60;
  final m = totalMin % 60;
  if (h == 0) return '${m}د';
  if (m == 0) return '${h}س';
  return '${h}س ${m}د';
}

String diffLabel(String d) => switch (d) {
      'Easy' => 'سهلة',
      'Hard' => 'صعبة',
      _ => 'متوسطة',
    };

Color levelColor(GuardLevel l) => switch (l) {
      GuardLevel.safe => kGreen,
      GuardLevel.warning => kOrange,
      GuardLevel.over => kRed,
    };

String levelMessage(GuardLevel l) => switch (l) {
      GuardLevel.safe => 'ماشي تمام، كمّل بنفس الإيقاع.',
      GuardLevel.warning => 'قربت من الحد الآمن، خد استراحة قريب.',
      GuardLevel.over => 'عديت الحد الآمن النهاردة. وقّف وارتاح.',
    };

double? parseNumber(String text) =>
    double.tryParse(text.trim().replaceAll(',', '.'));

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

BoxDecoration cardDecoration([Color? borderColor]) => BoxDecoration(
      color: kCard,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: (borderColor ?? kBorder).withValues(alpha: 0.5)),
    );

// ═══════════ widgets/dialogs.dart ═══════════

Future<void> showCapDialog(BuildContext context, AppState state) {
  final controller = TextEditingController(text: state.dailySafeCap.toString());
  return showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: kCard,
      title: const Text('الحد اليومي الآمن', style: TextStyle(color: Colors.white)),
      content: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: const TextStyle(color: Colors.white),
        decoration: const InputDecoration(
          labelText: 'عدد الساعات (من 0.5 إلى 16)',
          labelStyle: TextStyle(color: kMuted),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: kGreen),
          onPressed: () {
            final v = parseNumber(controller.text);
            if (v == null || v < 0.5 || v > 16) {
              showSnack(ctx, 'اكتب رقم بين 0.5 و 16');
              return;
            }
            state.setDailyCap(v);
            Navigator.pop(ctx);
          },
          child: const Text('حفظ', style: TextStyle(color: kBg)),
        ),
      ],
    ),
  );
}

/// نافذة إضافة أو تعديل مادة (لو existing فيها قيمة يبقى تعديل)
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
        title: Text(existing != null ? 'تعديل المادة' : 'إضافة مادة جديدة',
            style: const TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'اسم المادة (مثال: Databases)',
                  labelStyle: TextStyle(color: kMuted),
                ),
              ),
              const SizedBox(height: 16),
              const Text('مستوى الصعوبة', style: TextStyle(fontSize: 12, color: kMuted)),
              const SizedBox(height: 8),
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
              const SizedBox(height: 12),
              TextField(
                controller: targetController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'الهدف اليومي بالساعات',
                  labelStyle: TextStyle(color: kMuted),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx),
              child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kGreen),
            onPressed: saving
                ? null
                : () async {
                    final name = nameController.text.trim();
                    final target = parseNumber(targetController.text);
                    if (name.isEmpty) {
                      showSnack(ctx, 'اكتب اسم المادة');
                      return;
                    }
                    final clash = state.subjects.any((s) =>
                        s.name.toLowerCase() == name.toLowerCase() &&
                        s.name != existing?.name);
                    if (clash) {
                      showSnack(ctx, 'المادة دي موجودة بالفعل');
                      return;
                    }
                    if (target == null || target <= 0 || target > 12) {
                      showSnack(ctx, 'الهدف لازم يكون أكبر من 0 وأقل من 12 ساعة');
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
                      showSnack(ctx, 'ما اتحفظتش. اتأكد من النت ومن إعدادات Supabase.');
                    }
                  },
            child: saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: kBg),
                  )
                : const Text('حفظ', style: TextStyle(color: kBg)),
          ),
        ],
      ),
    ),
  );
}

/// نافذة تغيير الاسم (بيتخزن في حساب المستخدم)
Future<void> showNameDialog(BuildContext context, AppState state) {
  final controller = TextEditingController(text: state.userNameOrNull ?? '');
  var saving = false;
  return showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        backgroundColor: kCard,
        title: const Text('اسمك', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 30,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'اكتب اسمك',
            labelStyle: TextStyle(color: kMuted),
          ),
        ),
        actions: [
          TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx),
              child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kGreen),
            onPressed: saving
                ? null
                : () async {
                    final name = controller.text.trim();
                    if (name.isEmpty) {
                      showSnack(ctx, 'اكتب اسمك');
                      return;
                    }
                    setLocal(() => saving = true);
                    final ok = await state.setUserName(name);
                    if (!ctx.mounted) return;
                    if (ok) {
                      Navigator.pop(ctx);
                    } else {
                      setLocal(() => saving = false);
                      showSnack(ctx, 'ما اتحفظش. اتأكد من النت.');
                    }
                  },
            child: const Text('حفظ', style: TextStyle(color: kBg)),
          ),
        ],
      ),
    ),
  );
}

/// نافذة إضافة مهمة جديدة
Future<void> showTaskDialog(BuildContext context, AppState state) {
  final titleController = TextEditingController();
  String? subject;
  var saving = false;
  return showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        backgroundColor: kCard,
        title: const Text('مهمة جديدة', style: TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: titleController,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'المهمة (مثال: حل شيت 3)',
                  labelStyle: TextStyle(color: kMuted),
                ),
              ),
              const SizedBox(height: 16),
              const Text('المادة (اختياري)', style: TextStyle(fontSize: 12, color: kMuted)),
              DropdownButton<String?>(
                isExpanded: true,
                dropdownColor: kCard,
                value: subject,
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('بدون مادة', style: TextStyle(color: Colors.white)),
                  ),
                  ...state.subjects.map((s) => DropdownMenuItem<String?>(
                        value: s.name,
                        child: Text(s.name, style: const TextStyle(color: Colors.white)),
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
              child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kGreen),
            onPressed: saving
                ? null
                : () async {
                    final title = titleController.text.trim();
                    if (title.isEmpty) {
                      showSnack(ctx, 'اكتب المهمة');
                      return;
                    }
                    setLocal(() => saving = true);
                    final ok = await state.addTask(title, subject);
                    if (!ctx.mounted) return;
                    if (ok) {
                      Navigator.pop(ctx);
                    } else {
                      setLocal(() => saving = false);
                      showSnack(ctx, 'ما اتحفظتش. اتأكد من النت.');
                    }
                  },
            child: const Text('إضافة', style: TextStyle(color: kBg)),
          ),
        ],
      ),
    ),
  );
}

/// نسيت كلمة السر: بنبعت كود على الإيميل، وبعدين المستخدم يكتب الكود وكلمة سر جديدة
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
            if (ctx.mounted) setLocal(() => error = 'حصلت مشكلة في الاتصال. حاول تاني.');
          }
          if (ctx.mounted) setLocal(() => loading = false);
        }

        Future<void> sendCode() async {
          final email = emailController.text.trim();
          if (!email.contains('@')) {
            setLocal(() => error = 'اكتب إيميل صحيح');
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
            setLocal(() => error = 'اكتب الكود اللي وصلك على الإيميل');
            return;
          }
          if (pass.length < 6) {
            setLocal(() => error = 'كلمة السر لازم تكون 6 حروف على الأقل');
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
          title: const Text('نسيت كلمة السر', style: TextStyle(color: Colors.white)),
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
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'الإيميل',
                    labelStyle: TextStyle(color: kMuted),
                  ),
                ),
                if (codeSent) ...[
                  const SizedBox(height: 12),
                  const Text('بعتنالك كود على الإيميل. اكتبه هنا مع كلمة السر الجديدة.',
                      style: TextStyle(fontSize: 12, color: kMuted, height: 1.4)),
                  TextField(
                    controller: codeController,
                    keyboardType: TextInputType.number,
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'الكود',
                      labelStyle: TextStyle(color: kMuted),
                    ),
                  ),
                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'كلمة السر الجديدة',
                      labelStyle: TextStyle(color: kMuted),
                    ),
                  ),
                ],
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(error!, style: const TextStyle(fontSize: 12, color: kRed)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: loading ? null : () => Navigator.pop(ctx),
                child: const Text('إلغاء')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: kGreen),
              onPressed: loading ? null : (codeSent ? confirm : sendCode),
              child: loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: kBg),
                    )
                  : Text(codeSent ? 'تأكيد' : 'ابعت الكود',
                      style: const TextStyle(color: kBg)),
            ),
          ],
        );
      },
    ),
  );
}

// ═══════════ widgets/week_chart.dart ═══════════

/// رسم بياني بسيط لآخر 7 أيام (من غير أي حزمة خارجية).
/// الخط الأحمر = الحد الآمن اليومي.
class WeekChart extends StatelessWidget {
  final List<DateTime> days;
  final List<double> hours;
  final double cap;

  const WeekChart({
    super.key,
    required this.days,
    required this.hours,
    required this.cap,
  });

  @override
  Widget build(BuildContext context) {
    const chartHeight = 110.0;
    const labelHeight = 14.0;
    const bottomArea = 6.0 + labelHeight;
    final maxValue = math.max(
      math.max(cap, 1.0),
      hours.fold<double>(0.0, (a, b) => math.max(a, b)),
    );
    final now = DateTime.now();

    return SizedBox(
      height: chartHeight + labelHeight + 2 + bottomArea,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: bottomArea + chartHeight * (cap / maxValue),
            child: Container(height: 1, color: kRed.withValues(alpha: 0.5)),
          ),
          Positioned.fill(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(days.length, (i) {
                final h = hours[i];
                final ratio = cap <= 0 ? 0.0 : h / cap;
                final color = ratio >= 1.0
                    ? kRed
                    : ratio >= 0.7
                        ? kOrange
                        : kGreen;
                final isToday = sameDay(days[i], now);
                final barHeight = h > 0 ? math.max(3.0, chartHeight * (h / maxValue)) : 0.0;

                return Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      SizedBox(
                        height: labelHeight,
                        child: Text(
                          h > 0 ? h.toStringAsFixed(1) : '',
                          style: const TextStyle(fontSize: 9, color: kMuted),
                        ),
                      ),
                      const SizedBox(height: 2),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 500),
                        height: barHeight,
                        width: 16,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        height: labelHeight,
                        child: Text(
                          kDayShort[days[i].weekday - 1],
                          style: TextStyle(
                            fontSize: 10,
                            color: isToday ? kGreen : kMuted,
                            fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════ screens/dashboard_tab.dart ═══════════

class DashboardTab extends StatelessWidget {
  final AppState state;
  const DashboardTab({super.key, required this.state});

  Widget _infoCard(IconData icon, String title, String body, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: cardDecoration(color),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 4),
                Text(body,
                    style: const TextStyle(fontSize: 12, color: kMuted, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _syncBanner() => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: kOrange.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kOrange.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            const Icon(Icons.cloud_off_rounded, color: kOrange, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(state.syncError ?? '',
                  style: const TextStyle(fontSize: 12, color: kOrange, height: 1.4)),
            ),
            TextButton(
              onPressed: () => state.refresh(),
              child: const Text('إعادة المحاولة', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      );

  Widget _suggestionCard() {
    if (state.subjects.isEmpty) return const SizedBox.shrink();
    if (state.isRestDay(DateTime.now())) {
      return _infoCard(Icons.spa_rounded, 'النهاردة يوم راحة',
          'الراحة جزء من الخطة. ارجع بنشاط بكرة.', kIndigo);
    }
    final s = state.todaySuggestion;
    if (s == null) {
      return _infoCard(Icons.celebration_rounded, 'خلصت خطة النهاردة',
          'شغل ممتاز. أي مذاكرة زيادة اختيارية.', kGreen);
    }
    return _infoCard(
      Icons.flag_rounded,
      'ابدأ بـ ${s.subject}',
      'باقي ${fmtHours(s.remaining)} من خطة النهاردة. الأصعب أول حاجة.',
      kGreen,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final level = state.level;
        final color = levelColor(level);
        final progress = state.ratio.clamp(0.0, 1.0);
        final today = dateOnly(DateTime.now());
        final days = List.generate(7, (i) => addDays(today, i - 6));
        final hours = days.map(state.hoursOn).toList();
        final streak = state.streak;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: kGreen.withValues(alpha: 0.2),
                      child: Text(
                          String.fromCharCode(state.userName.runes.first).toUpperCase(),
                          style: const TextStyle(
                              color: kGreen, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('StudyPace',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white)),
                        InkWell(
                          onTap: supabaseReady ? () => showNameDialog(context, state) : null,
                          child: Text('${state.userName} • سنة تانية حاسبات ✎',
                              style: const TextStyle(fontSize: 12, color: kMuted)),
                        ),
                      ],
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'تعديل الحد اليومي',
                      onPressed: () => showCapDialog(context, state),
                      icon: const Icon(Icons.tune_rounded, color: kMuted),
                    ),
                    if (supabaseReady)
                      IconButton(
                        tooltip: 'تسجيل الخروج',
                        onPressed: () => supabase.auth.signOut(),
                        icon: const Icon(Icons.logout_rounded, color: kMuted),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (state.syncError != null) _syncBanner(),

            // الملخص اليومي + السلسلة
            Container(
              padding: const EdgeInsets.all(16),
              decoration: cardDecoration(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('ملخص النهاردة',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold, color: kGreen)),
                  const SizedBox(height: 8),
                  Text(
                    'مرحباً يا ${state.userName}. عندك ${state.subjects.length} مواد. '
                    'ذاكرت النهاردة ${fmtHours(state.todayHours)}.',
                    style: const TextStyle(fontSize: 13, color: kMuted, height: 1.4),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    streak > 0
                        ? '🔥 سلسلة $streak يوم متتالي'
                        : 'ابدأ سلسلتك النهاردة بأول جلسة.',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: streak > 0 ? kOrange : kMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // حارس الإرهاق
            Container(
              padding: const EdgeInsets.all(16),
              decoration: cardDecoration(color),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                          level == GuardLevel.over
                              ? Icons.warning_amber_rounded
                              : Icons.shield_outlined,
                          color: color,
                          size: 20),
                      const SizedBox(width: 8),
                      const Text('حارس الإرهاق',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${fmtHours(state.todayHours)} النهاردة',
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white)),
                      InkWell(
                        onTap: () => showCapDialog(context, state),
                        child: Text('الحد الآمن: ${state.dailySafeCap}س ✎',
                            style: TextStyle(fontSize: 12, color: color)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: progress),
                      duration: const Duration(milliseconds: 600),
                      builder: (context, value, child) => LinearProgressIndicator(
                        value: value,
                        backgroundColor: kDeep,
                        color: color,
                        minHeight: 8,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(levelMessage(level), style: TextStyle(fontSize: 12, color: color)),
                ],
              ),
            ),
            const SizedBox(height: 16),

            _suggestionCard(),
            if (state.subjects.isNotEmpty) const SizedBox(height: 16),

            // رسم آخر 7 أيام
            Container(
              padding: const EdgeInsets.all(16),
              decoration: cardDecoration(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('آخر 7 أيام',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 4),
                  const Text('الخط الأحمر هو الحد الآمن اليومي',
                      style: TextStyle(fontSize: 11, color: kMuted)),
                  const SizedBox(height: 12),
                  WeekChart(days: days, hours: hours, cap: state.dailySafeCap),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // توزيع النهاردة على المواد
            Container(
              padding: const EdgeInsets.all(16),
              decoration: cardDecoration(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('مذاكرة النهاردة حسب المادة',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 10),
                  if (state.subjects.isEmpty)
                    const Text('مفيش مواد لسه. ضيف من تبويب المواد.',
                        style: TextStyle(fontSize: 12, color: kMuted))
                  else
                    ...state.subjects.map((s) {
                      final done = state.todayHoursFor(s.name);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(s.name,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13, color: kMuted)),
                            ),
                            Text('${fmtHours(done)} / ${fmtHours(s.targetHours)}',
                                style: const TextStyle(fontSize: 12, color: Colors.white)),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// ═══════════ screens/plan_tab.dart ═══════════

class PlanTab extends StatelessWidget {
  final AppState state;
  const PlanTab({super.key, required this.state});

  Widget _badge(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text, style: TextStyle(fontSize: 10, color: color)),
      );

  Widget _banner(String text, Color color) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Text(text, style: TextStyle(fontSize: 12, color: color, height: 1.4)),
      );

  Widget _settingsCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('إعادة جدولة تلقائية',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                    SizedBox(height: 2),
                    Text('الساعات اللي فاتتك بتتوزع على الأيام الجاية',
                        style: TextStyle(fontSize: 11, color: kMuted)),
                  ],
                ),
              ),
              Switch(value: state.autoReschedule, onChanged: state.setAutoReschedule),
            ],
          ),
          const SizedBox(height: 12),
          const Text('يوم الراحة', style: TextStyle(fontSize: 12, color: kMuted)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              ChoiceChip(
                label: const Text('بدون'),
                selected: state.restDay == 0,
                onSelected: (_) => state.setRestDay(0),
              ),
              for (final wd in [6, 7, 1, 2, 3, 4, 5])
                ChoiceChip(
                  label: Text(kDayNames[wd - 1]),
                  selected: state.restDay == wd,
                  onSelected: (_) => state.setRestDay(wd),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dayCard(DayPlan d, DateTime today, Map<String, SubjectModel> byName) {
    final isToday = sameDay(d.date, today);
    final isPast = d.date.isBefore(today);
    final names = d.subjects.toList()
      ..sort((a, b) => (byName[a]?.rank ?? 9).compareTo(byName[b]?.rank ?? 9));

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: cardDecoration(isToday ? kGreen : null),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('${dayName(d.date)} • ${shortDate(d.date)}',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
              const Spacer(),
              if (d.isRest) _badge('راحة', kIndigo),
              if (isToday) ...[
                const SizedBox(width: 6),
                _badge('النهاردة', kGreen),
              ],
            ],
          ),
          if (d.isRest)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text('يوم راحة، مفيش مذاكرة مخططة 🌿',
                  style: TextStyle(fontSize: 12, color: kMuted)),
            )
          else if (names.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text('مفيش مواد مخططة في اليوم ده.',
                  style: TextStyle(fontSize: 12, color: kMuted)),
            )
          else ...[
            ...names.map((n) {
              final planned = d.hoursFor(n);
              final carried = d.carried[n] ?? 0.0;
              final done = state.hoursForOn(n, d.date);
              final met = planned > 0 && done >= planned - 0.05;
              final IconData icon;
              final Color iconColor;
              if (met) {
                icon = Icons.check_circle;
                iconColor = kGreen;
              } else if (isPast) {
                icon = Icons.cancel_outlined;
                iconColor = kOrange;
              } else {
                icon = Icons.circle_outlined;
                iconColor = kMuted;
              }
              final showActual = isPast || isToday;
              return Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  children: [
                    Icon(icon, size: 16, color: iconColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(n,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13, color: Colors.white)),
                          if (carried > 0.02)
                            Text('منها ${fmtHours(carried)} من اللي فاتك',
                                style: const TextStyle(fontSize: 10, color: kOrange)),
                        ],
                      ),
                    ),
                    Text(
                      showActual
                          ? '${fmtHours(done)} / ${fmtHours(planned)}'
                          : fmtHours(planned),
                      style: const TextStyle(fontSize: 12, color: kMuted),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 10),
            Text('إجمالي المخطط: ${fmtHours(d.total)}',
                style: const TextStyle(fontSize: 11, color: kMuted)),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final plan = state.weekPlan;
        final today = dateOnly(DateTime.now());
        final byName = {for (final s in state.subjects) s.name: s};

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('الخطة الأسبوعية',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 4),
            Text(
              'المواد الصعبة الأول، ومفيش يوم بيعدّي ${state.dailySafeCap}س.',
              style: const TextStyle(fontSize: 13, color: kMuted),
            ),
            const SizedBox(height: 16),
            if (state.subjects.isEmpty)
              const Center(
                child: Text('مفيش مواد. روح لتبويب المواد وضيف موادك.',
                    style: TextStyle(color: Colors.grey)),
              )
            else ...[
              _settingsCard(),
              if (plan.carriedTotal > 0.05)
                _banner(
                  'اتوزّع ${fmtHours(plan.carriedTotal)} من اللي فاتك على باقي الأسبوع.',
                  kOrange,
                ),
              if (plan.unplaced.isNotEmpty)
                _banner(
                  'مفيش مساحة تحت الحد الآمن للساعات دي: '
                  '${plan.unplaced.entries.map((e) => '${e.key} (${fmtHours(e.value)})').join('، ')}. '
                  'ارفع الحد الآمن أو قلّل أهداف المواد.',
                  kRed,
                ),
              ...plan.days.map((d) => _dayCard(d, today, byName)),
            ],
          ],
        );
      },
    );
  }
}

// ═══════════ screens/subjects_tab.dart ═══════════

class SubjectsTab extends StatelessWidget {
  final AppState state;
  const SubjectsTab({super.key, required this.state});

  Future<void> _confirmDelete(BuildContext context, SubjectModel s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard,
        title: const Text('حذف المادة؟', style: TextStyle(color: Colors.white)),
        content: Text('هتتحذف "${s.name}" من القائمة. الجلسات القديمة هتفضل في السجل.',
            style: const TextStyle(color: kMuted)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف', style: TextStyle(color: kRed))),
        ],
      ),
    );
    if (ok != true) return;
    final deleted = await state.deleteSubject(s);
    if (!deleted && context.mounted) {
      showSnack(context, 'ما اتحذفتش. اتأكد من النت.');
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
          title: const Text('المواد', style: TextStyle(fontSize: 18)),
          actions: [
            IconButton(
              tooltip: 'مزامنة',
              onPressed: state.syncing ? null : () => state.refresh(),
              icon: state.syncing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: kMuted),
                    )
                  : const Icon(Icons.sync_rounded, color: kMuted),
            ),
            IconButton(
              tooltip: 'إضافة مادة',
              icon: const Icon(Icons.add_circle, color: kGreen, size: 28),
              onPressed: () => showSubjectDialog(context, state),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (state.subjects.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 40),
                child: Center(
                  child: Text('اضغط (+) لإضافة أول مادة.', style: TextStyle(color: kMuted)),
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
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white)),
                        ),
                        IconButton(
                          tooltip: 'تعديل',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.edit_outlined, color: kMuted, size: 20),
                          onPressed: () => showSubjectDialog(context, state, existing: s),
                        ),
                        IconButton(
                          tooltip: 'حذف',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.delete_outline, color: kMuted, size: 20),
                          onPressed: () => _confirmDelete(context, s),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${diffLabel(s.difficulty)} • الهدف ${fmtHours(s.targetHours)} • النهاردة ${fmtHours(done)}',
                      style: const TextStyle(fontSize: 12, color: kMuted),
                    ),
                    const SizedBox(height: 8),
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

// ═══════════ screens/focus_tab.dart ═══════════

enum PomoPhase { focus, shortBreak, longBreak }

class FocusTab extends StatefulWidget {
  final AppState state;
  const FocusTab({super.key, required this.state});

  @override
  State<FocusTab> createState() => _FocusTabState();
}

class _FocusTabState extends State<FocusTab> with WidgetsBindingObserver {
  static const shortBreakMin = 5;
  static const longBreakMin = 15;
  static const cyclesBeforeLongBreak = 4;

  int focusMinutes = 25;
  PomoPhase phase = PomoPhase.focus;
  int completedCycles = 0;

  late int totalSeconds = focusMinutes * 60;
  late int remainingSeconds = totalSeconds;
  DateTime? endTime; // المؤقت بيعتمد على وقت الانتهاء مش على العدّ
  Timer? ticker;
  bool isRunning = false;
  String? selectedSubject;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ticker?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    // لما ترجع للتطبيق نحسب الوقت المتبقي من جديد
    if (s == AppLifecycleState.resumed && isRunning) _tick();
  }

  String? get _currentSubject {
    final names = widget.state.subjects.map((s) => s.name).toList();
    if (names.isEmpty) return null;
    if (selectedSubject != null && names.contains(selectedSubject)) return selectedSubject;
    return names.first;
  }

  int _secondsFor(PomoPhase p) => switch (p) {
        PomoPhase.focus => focusMinutes * 60,
        PomoPhase.shortBreak => shortBreakMin * 60,
        PomoPhase.longBreak => longBreakMin * 60,
      };

  void _setPhase(PomoPhase p) {
    phase = p;
    totalSeconds = _secondsFor(p);
    remainingSeconds = totalSeconds;
  }

  Future<void> _start() async {
    if (isRunning) return;
    if (phase == PomoPhase.focus) {
      if (_currentSubject == null) return;
      if (widget.state.level == GuardLevel.over) {
        final ok = await _confirmOverCap();
        if (ok != true || !mounted) return;
      }
    }
    endTime = DateTime.now().add(Duration(seconds: remainingSeconds));
    ticker?.cancel();
    ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    setState(() => isRunning = true);
  }

  Future<bool?> _confirmOverCap() => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: kCard,
          title: const Row(children: [
            Icon(Icons.warning_amber_rounded, color: kRed),
            SizedBox(width: 8),
            Text('عديت الحد الآمن', style: TextStyle(color: Colors.white)),
          ]),
          content: Text(
            'ذاكرت ${fmtHours(widget.state.todayHours)} والحد الآمن ${widget.state.dailySafeCap}س. '
            'متأكد إنك عايز تكمل؟',
            style: const TextStyle(color: kMuted),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false), child: const Text('لأ، هرتاح')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('كمّل برضو', style: TextStyle(color: kRed))),
          ],
        ),
      );

  int _computeRemaining() {
    if (endTime == null) return remainingSeconds;
    return (endTime!.difference(DateTime.now()).inMilliseconds / 1000).ceil();
  }

  void _tick() {
    if (!isRunning) return;
    final left = _computeRemaining();
    if (left <= 0) {
      _completePhase();
    } else {
      setState(() => remainingSeconds = left);
    }
  }

  void _pause() {
    remainingSeconds = _computeRemaining().clamp(0, totalSeconds);
    ticker?.cancel();
    endTime = null;
    setState(() => isRunning = false);
  }

  void _completePhase() {
    ticker?.cancel();
    endTime = null;
    final subject = _currentSubject;

    if (phase == PomoPhase.focus) {
      if (subject != null) {
        // نسجل الوقت الفعلي للجلسة (مش رقم ثابت)
        widget.state.addSession(subject, totalSeconds / 3600);
      }
      completedCycles++;
      final long = completedCycles % cyclesBeforeLongBreak == 0;
      setState(() {
        isRunning = false;
        _setPhase(long ? PomoPhase.longBreak : PomoPhase.shortBreak);
      });
      if (mounted) {
        showSnack(
          context,
          '🎉 خلصت جلسة $focusMinutes دقيقة في ($subject). ${long ? "خد راحة طويلة" : "خد راحة قصيرة"}.',
        );
      }
    } else {
      setState(() {
        isRunning = false;
        _setPhase(PomoPhase.focus);
      });
      if (mounted) showSnack(context, 'الراحة خلصت. جاهز للجلسة الجاية؟');
    }
  }

  // إنهاء الجلسة بدري وحفظ الوقت اللي اتذاكر فعلاً
  void _finishEarly() {
    if (phase != PomoPhase.focus) return;
    final subject = _currentSubject;
    final left = isRunning ? _computeRemaining() : remainingSeconds;
    final elapsed = totalSeconds - left.clamp(0, totalSeconds);
    ticker?.cancel();
    endTime = null;
    if (subject == null || elapsed < 60) {
      showSnack(context, 'الجلسة أقل من دقيقة، مش هتتسجل.');
    } else {
      widget.state.addSession(subject, elapsed / 3600);
      showSnack(context, 'اتسجل ${fmtHours(elapsed / 3600)} في ($subject).');
    }
    setState(() {
      isRunning = false;
      remainingSeconds = totalSeconds;
    });
  }

  void _reset() {
    ticker?.cancel();
    endTime = null;
    setState(() {
      isRunning = false;
      remainingSeconds = totalSeconds;
    });
  }

  void _skipBreak() {
    ticker?.cancel();
    endTime = null;
    setState(() {
      isRunning = false;
      _setPhase(PomoPhase.focus);
    });
  }

  void _setFocusMinutes(int m) {
    setState(() {
      focusMinutes = m;
      if (phase == PomoPhase.focus) _setPhase(PomoPhase.focus);
    });
  }

  void _showManualDialog() {
    final subject = _currentSubject;
    if (subject == null) return;
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard,
        title: const Text('إضافة وقت يدوي', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: 'المدة بالدقائق (لمادة $subject)',
            labelStyle: const TextStyle(color: kMuted),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kGreen),
            onPressed: () {
              final m = int.tryParse(controller.text.trim());
              if (m == null || m < 1 || m > 480) {
                showSnack(ctx, 'اكتب مدة بين 1 و 480 دقيقة');
                return;
              }
              widget.state.addSession(subject, m / 60);
              Navigator.pop(ctx);
              showSnack(context, 'اتسجل $m دقيقة في ($subject).');
            },
            child: const Text('إضافة', style: TextStyle(color: kBg)),
          ),
        ],
      ),
    );
  }

  String get _phaseLabel => switch (phase) {
        PomoPhase.focus => 'تركيز',
        PomoPhase.shortBreak => 'راحة قصيرة',
        PomoPhase.longBreak => 'راحة طويلة',
      };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) {
        final subjects = widget.state.subjects;
        final current = _currentSubject;
        final isFocus = phase == PomoPhase.focus;
        final ringColor = isFocus ? kGreen : kIndigo;
        final m = remainingSeconds ~/ 60;
        final s = remainingSeconds % 60;
        final time = '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
        final untouched = remainingSeconds == totalSeconds;
        final progress = totalSeconds == 0 ? 0.0 : remainingSeconds / totalSeconds;

        return Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Chip(
                  label: Text('$_phaseLabel • دورة ${completedCycles + (isFocus ? 1 : 0)}',
                      style: TextStyle(color: ringColor, fontSize: 12)),
                  backgroundColor: kDeep,
                  side: BorderSide(color: ringColor.withValues(alpha: 0.4)),
                ),
                const SizedBox(height: 12),
                if (subjects.isEmpty)
                  const Text('ضيف مواد الأول من تبويب المواد', style: TextStyle(color: kOrange))
                else
                  DropdownButton<String>(
                    value: current,
                    dropdownColor: kCard,
                    style: const TextStyle(color: kGreen, fontWeight: FontWeight.bold),
                    items: subjects
                        .map((x) => DropdownMenuItem(value: x.name, child: Text(x.name)))
                        .toList(),
                    onChanged: isRunning ? null : (v) => setState(() => selectedSubject = v),
                  ),
                const SizedBox(height: 20),
                SizedBox(
                  width: 220,
                  height: 220,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox.expand(
                        child: CircularProgressIndicator(
                          value: progress,
                          strokeWidth: 8,
                          backgroundColor: kDeep,
                          color: ringColor,
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(time,
                              style: const TextStyle(
                                  fontSize: 50,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  letterSpacing: 2)),
                          Text(isFocus ? 'وقت التركيز' : 'استراحة',
                              style: const TextStyle(fontSize: 12, color: kMuted)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                if (isFocus)
                  Wrap(
                    spacing: 8,
                    children: [15, 25, 45, 60].map((min) {
                      return ChoiceChip(
                        label: Text('$min د'),
                        selected: focusMinutes == min,
                        onSelected: (isRunning || !untouched) ? null : (_) => _setFocusMinutes(min),
                      );
                    }).toList(),
                  ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isRunning ? kOrange : ringColor,
                        foregroundColor: kBg,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed:
                          (isFocus && subjects.isEmpty) ? null : (isRunning ? _pause : _start),
                      icon: Icon(isRunning ? Icons.pause : Icons.play_arrow),
                      label: Text(isRunning ? 'إيقاف مؤقت' : 'ابدأ',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        side: const BorderSide(color: kBorder),
                      ),
                      onPressed: _reset,
                      child: const Text('إعادة', style: TextStyle(color: kMuted)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (isFocus && (isRunning || !untouched))
                  TextButton.icon(
                    onPressed: _finishEarly,
                    icon: const Icon(Icons.check_circle_outline, color: kGreen, size: 18),
                    label: const Text('إنهاء وحفظ الوقت اللي ذاكرته',
                        style: TextStyle(color: kGreen, fontSize: 12)),
                  ),
                if (!isFocus)
                  TextButton(
                    onPressed: _skipBreak,
                    child: const Text('تخطي الراحة',
                        style: TextStyle(color: kMuted, fontSize: 12)),
                  ),
                if (isFocus && !isRunning && untouched)
                  TextButton(
                    onPressed: current == null ? null : _showManualDialog,
                    child: const Text('✍️ إضافة وقت يدوي',
                        style: TextStyle(color: kMuted, fontSize: 12)),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ═══════════ screens/tasks_tab.dart ═══════════

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
              if (!ok && context.mounted) showSnack(context, 'ما اتعدلتش. اتأكد من النت.');
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
                        style: const TextStyle(fontSize: 11, color: kGreen)),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'حذف',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.delete_outline, color: kMuted, size: 20),
            onPressed: () async {
              final ok = await state.deleteTask(t);
              if (!ok && context.mounted) showSnack(context, 'ما اتحذفتش. اتأكد من النت.');
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
            title: const Text('المهام', style: TextStyle(fontSize: 18)),
            actions: [
              IconButton(
                tooltip: 'مهمة جديدة',
                icon: const Icon(Icons.add_circle, color: kGreen, size: 28),
                onPressed: () => showTaskDialog(context, state),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (ordered.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: Center(
                    child: Text('اضغط (+) لإضافة أول مهمة.', style: TextStyle(color: kMuted)),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text('باقي ${pending.length} من ${ordered.length}',
                      style: const TextStyle(fontSize: 12, color: kMuted)),
                ),
              ...ordered.map((t) => _taskCard(context, t)),
            ],
          ),
        );
      },
    );
  }
}

// ═══════════ screens/app_shell.dart ═══════════

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
        // IndexedStack بيحافظ على حالة المؤقت لما تنتقل بين التبويبات
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
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.bold : FontWeight.w500)),
            if (selected) ...[
              const SizedBox(height: 3),
              Container(
                width: 4,
                height: 4,
                decoration: const BoxDecoration(color: kGreen, shape: BoxShape.circle),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ═══════════ screens/auth_gate.dart ═══════════

/// بيقرر نعرض شاشة الدخول ولا التطبيق نفسه حسب حالة تسجيل الدخول
class AuthGate extends StatefulWidget {
  final AppState state;
  const AuthGate({super.key, required this.state});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  StreamSubscription<AuthState>? _sub;
  Session? _session;

  @override
  void initState() {
    super.initState();
    if (supabaseReady) {
      _session = supabase.auth.currentSession;
      _sub = supabase.auth.onAuthStateChange.listen((data) {
        if (!mounted) return;
        final wasIn = _session != null;
        final now = data.session;
        setState(() => _session = now);
        if (now != null && !wasIn) widget.state.refresh(); // لسه داخل
        if (now == null && wasIn) widget.state.clearData(); // لسه خارج
      });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // لو Supabase مش متضبط التطبيق بيشتغل محلياً من غير دخول
    if (!supabaseReady || _session != null) return AppShell(state: widget.state);
    return const LoginScreen();
  }
}

// ═══════════ screens/login_screen.dart ═══════════

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
        message = 'اكتب إيميل صحيح';
        messageColor = kRed;
      });
      return;
    }
    if (password.length < 6) {
      setState(() {
        message = 'كلمة السر لازم تكون 6 حروف على الأقل';
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
        // لو تأكيد الإيميل شغال في Supabase مش هيرجع session
        if (res.session == null && mounted) {
          setState(() {
            message = 'اتبعتلك إيميل تأكيد. افتحه وبعدين سجّل دخول.';
            messageColor = kGreen;
            isSignUp = false;
          });
        }
      } else {
        await supabase.auth.signInWithPassword(email: email, password: password);
      }
      // لو نجح الدخول، AuthGate هو اللي بيفتح التطبيق لوحده
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
          message = 'حصلت مشكلة في الاتصال. اتأكد من النت وحاول تاني.';
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
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.spa_rounded, color: kGreen, size: 48),
                  const SizedBox(height: 12),
                  const Text('StudyPace',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 4),
                  Text(isSignUp ? 'أنشئ حساب جديد' : 'سجّل دخول',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 14, color: kMuted)),
                  const SizedBox(height: 28),
                  if (isSignUp) ...[
                    TextField(
                      controller: nameController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'اسمك',
                        labelStyle: TextStyle(color: kMuted),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'الإيميل',
                      labelStyle: TextStyle(color: kMuted),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(color: Colors.white),
                    onSubmitted: (_) => loading ? null : _submit(),
                    decoration: const InputDecoration(
                      labelText: 'كلمة السر',
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
                        child: const Text('نسيت كلمة السر؟',
                            style: TextStyle(color: kMuted, fontSize: 12)),
                      ),
                    ),
                  if (message != null) ...[
                    const SizedBox(height: 12),
                    Text(message!,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: messageColor, height: 1.4)),
                  ],
                  const SizedBox(height: 20),
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
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: kBg),
                          )
                        : Text(isSignUp ? 'إنشاء حساب' : 'دخول',
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: loading
                        ? null
                        : () => setState(() {
                              isSignUp = !isSignUp;
                              message = null;
                            }),
                    child: Text(
                      isSignUp ? 'عندي حساب بالفعل' : 'مفيش حساب؟ أنشئ واحد',
                      style: const TextStyle(color: kMuted, fontSize: 13),
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

// ═══════════ main.dart ═══════════

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // لو المفاتيح لسه placeholder، التطبيق بيشتغل محلياً من غير ما يقع
  final configured = !kSupabaseUrl.contains('YOUR_PROJECT_ID') &&
      !kSupabaseAnonKey.contains('YOUR_ANON');
  if (configured) {
    try {
      await Supabase.initialize(url: kSupabaseUrl, anonKey: kSupabaseAnonKey);
      supabaseReady = true;
    } catch (e) {
      debugPrint('Supabase.initialize failed: $e');
    }
  }

  final state = AppState();
  await state.loadLocal(); // بيانات الجهاز تظهر فوراً
  runApp(StudyPaceApp(state: state));
  // نسحب آخر نسخة من Supabase في الخلفية (بس لو المستخدم داخل بالفعل)
  if (supabaseReady && supabase.auth.currentSession != null) {
    unawaited(state.refresh());
  }
}

class StudyPaceApp extends StatelessWidget {
  final AppState state;
  const StudyPaceApp({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'StudyPace',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: buildDarkTheme(),
      // واجهة عربية بالكامل: الاتجاه من اليمين لليسار
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: AuthGate(state: state),
    );
  }
}