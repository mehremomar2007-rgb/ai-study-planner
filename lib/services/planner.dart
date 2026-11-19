import 'dart:math' as math;

import 'package:ai_study_planner/models/models.dart';
import 'package:ai_study_planner/utils/date_utils.dart';

class DayPlan {
  final DateTime date;
  final bool isRest;
  final Map<String, double> base = {};
  final Map<String, double> carried = {};

  DayPlan(this.date, this.isRest);

  Set<String> get subjects => {...base.keys, ...carried.keys};

  double hoursFor(String subject) => (base[subject] ?? 0) + (carried[subject] ?? 0);

  double get total =>
      base.values.fold(0.0, (a, b) => a + b) +
      carried.values.fold(0.0, (a, b) => a + b);
}

class WeekPlan {
  final List<DayPlan> days;
  final Map<String, double> unplaced;
  final double carriedTotal;

  const WeekPlan({
    required this.days,
    required this.unplaced,
    required this.carriedTotal,
  });
}

class Planner {
  static WeekPlan build({
    required List<SubjectModel> subjects,
    required double cap,
    required int restDay,
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
          plan.base[s.name] = s.targetHours * scale;
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
        final created = dateOnly(s.createdAt);

        var deficit = 0.0;
        for (final d in days) {
          if (d.isRest || !d.date.isBefore(todayDate)) continue;
          if (d.date.isBefore(created)) continue;
          final planned = d.base[s.name] ?? 0;
          if (planned <= 0) continue;
          deficit += math.max(0.0, planned - hoursFor(s.name, d.date));
        }
        if (deficit < 0.05) continue;

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
