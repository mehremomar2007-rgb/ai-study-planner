import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  final String name;
  final String difficulty; // Easy, Medium, Hard
  final double targetHours; // هدف المادة اليومي (مش الحد الآمن)
  final DateTime createdAt; // عشان الخطة ما تحسبش أيام قبل إضافة المادة

  const SubjectModel({
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
        name: name ?? this.name,
        difficulty: difficulty ?? this.difficulty,
        targetHours: targetHours ?? this.targetHours,
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'difficulty': difficulty,
        'targetHours': targetHours,
        'createdAt': createdAt.toIso8601String(),
      };

  factory SubjectModel.fromJson(Map<String, dynamic> j) => SubjectModel(
        name: j['name'] as String,
        difficulty: j['difficulty'] as String,
        targetHours: (j['targetHours'] as num).toDouble(),
        // البيانات القديمة ماكانش فيها تاريخ إنشاء، فبنعتبرها اتضافت النهاردة
        createdAt: j['createdAt'] is String
            ? DateTime.parse(j['createdAt'] as String)
            : dateOnly(DateTime.now()),
      );
}


// ═══════════ models/study_session.dart ═══════════

class StudySession {
  final String subject;
  final DateTime date;
  final double hours;

  const StudySession({
    required this.subject,
    required this.date,
    required this.hours,
  });

  Map<String, dynamic> toJson() =>
      {'subject': subject, 'date': date.toIso8601String(), 'hours': hours};

  factory StudySession.fromJson(Map<String, dynamic> j) => StudySession(
        subject: j['subject'] as String,
        date: DateTime.parse(j['date'] as String),
        hours: (j['hours'] as num).toDouble(),
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

/// حالة التطبيق كلها + الحفظ الدائم.
/// ChangeNotifier + ListenableBuilder بيعملوا نفس شغل Provider من غير أي حزمة زيادة.
class AppState extends ChangeNotifier {
  List<SubjectModel> subjects = [];
  List<StudySession> sessions = [];
  double dailySafeCap = 4.5;
  int restDay = DateTime.friday; // 0 = مفيش يوم راحة
  bool autoReschedule = true;

  List<SubjectModel> _defaultSubjects() {
    final now = dateOnly(DateTime.now());
    return [
      SubjectModel(
          name: 'System Analysis & Design',
          difficulty: 'Hard',
          targetHours: 2.0,
          createdAt: now),
      SubjectModel(
          name: 'Data Structures & Algorithms',
          difficulty: 'Medium',
          targetHours: 2.5,
          createdAt: now),
    ];
  }

  // ───────────── التحميل والحفظ ─────────────
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    dailySafeCap = prefs.getDouble('dailySafeCap') ?? 4.5;
    restDay = prefs.getInt('restDay') ?? DateTime.friday;
    autoReschedule = prefs.getBool('autoReschedule') ?? true;
    final subjectsRaw = prefs.getString('subjects');
    final sessionsRaw = prefs.getString('sessions');
    try {
      subjects = subjectsRaw == null
          ? _defaultSubjects()
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
    } catch (_) {
      // لو البيانات المحفوظة بايظة نبدأ من جديد بدل ما التطبيق يقع
      subjects = _defaultSubjects();
      sessions = [];
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
  }

  void _changed() {
    notifyListeners();
    _save();
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

  void addSubject(String name, String difficulty, double target) {
    subjects = [
      ...subjects,
      SubjectModel(
        name: name,
        difficulty: difficulty,
        targetHours: target,
        createdAt: dateOnly(DateTime.now()),
      ),
    ];
    _changed();
  }

  /// تعديل مادة. لو الاسم اتغيّر، الجلسات القديمة بتتنقل للاسم الجديد.
  void updateSubject(String oldName, SubjectModel updated) {
    subjects = subjects.map((s) => s.name == oldName ? updated : s).toList();
    if (oldName != updated.name) {
      sessions = sessions
          .map((s) => s.subject == oldName
              ? StudySession(subject: updated.name, date: s.date, hours: s.hours)
              : s)
          .toList();
    }
    _changed();
  }

  void deleteSubject(String name) {
    subjects = subjects.where((s) => s.name != name).toList();
    _changed();
  }

  void addSession(String subject, double hours) {
    sessions = [
      ...sessions,
      StudySession(subject: subject, date: DateTime.now(), hours: hours),
    ];
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kGreen),
            onPressed: () {
              final name = nameController.text.trim();
              final target = parseNumber(targetController.text);
              if (name.isEmpty) {
                showSnack(ctx, 'اكتب اسم المادة');
                return;
              }
              final clash = state.subjects.any((s) =>
                  s.name.toLowerCase() == name.toLowerCase() && s.name != existing?.name);
              if (clash) {
                showSnack(ctx, 'المادة دي موجودة بالفعل');
                return;
              }
              if (target == null || target <= 0 || target > 12) {
                showSnack(ctx, 'الهدف لازم يكون أكبر من 0 وأقل من 12 ساعة');
                return;
              }
              if (existing != null) {
                state.updateSubject(
                  existing.name,
                  existing.copyWith(name: name, difficulty: difficulty, targetHours: target),
                );
              } else {
                state.addSubject(name, difficulty, target);
              }
              Navigator.pop(ctx);
            },
            child: const Text('حفظ', style: TextStyle(color: kBg)),
          ),
        ],
      ),
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
                      child: const Text('O',
                          style: TextStyle(color: kGreen, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 12),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('StudyPace',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white)),
                        Text('عمر • سنة تانية حاسبات',
                            style: TextStyle(fontSize: 12, color: kMuted)),
                      ],
                    ),
                  ],
                ),
                IconButton(
                  tooltip: 'تعديل الحد اليومي',
                  onPressed: () => showCapDialog(context, state),
                  icon: const Icon(Icons.tune_rounded, color: kMuted),
                ),
              ],
            ),
            const SizedBox(height: 16),

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
                    'مرحباً يا عمر. عندك ${state.subjects.length} مواد. '
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
    if (ok == true) state.deleteSubject(s.name);
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


// ═══════════ main.dart ═══════════




Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState();
  await state.load();
  runApp(StudyPaceApp(state: state));
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
      home: AppShell(state: state),
    );
  }
}
