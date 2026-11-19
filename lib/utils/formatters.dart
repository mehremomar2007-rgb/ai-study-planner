import 'package:ai_study_planner/localization/app_localization.dart';

String fmtHours(double hours) {
  final totalMin = (hours * 60).round();
  final h = totalMin ~/ 60;
  final m = totalMin % 60;
  final hu = tr('س'), mu = tr('د');
  if (h == 0) return '$m$mu';
  if (m == 0) return '$h$hu';
  return '$h$hu $m$mu';
}

String diffLabel(String d) => switch (d) {
      'Easy' => tr('سهلة'),
      'Hard' => tr('صعبة'),
      _ => tr('متوسطة'),
    };

double? parseNumber(String text) =>
    double.tryParse(text.trim().replaceAll(',', '.'));
