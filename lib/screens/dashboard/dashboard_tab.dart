import 'package:flutter/material.dart';

import 'package:ai_study_planner/localization/app_localization.dart';
import 'package:ai_study_planner/models/models.dart';
import 'package:ai_study_planner/screens/profile/profile_screen.dart';
import 'package:ai_study_planner/state/app_state.dart';
import 'package:ai_study_planner/theme/app_colors.dart';
import 'package:ai_study_planner/theme/app_theme.dart';
import 'package:ai_study_planner/utils/date_utils.dart';
import 'package:ai_study_planner/utils/formatters.dart';
import 'package:ai_study_planner/utils/guard_level_helpers.dart';
import 'package:ai_study_planner/widgets/charts/week_chart.dart';
import 'package:ai_study_planner/widgets/dialogs/dialogs.dart';

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
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                SizedBox(height: 4),
                Text(body,
                    style: TextStyle(fontSize: 12, color: kMuted, height: 1.4)),
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
            Icon(Icons.cloud_off_rounded, color: kOrange, size: 18),
            SizedBox(width: 8),
            Expanded(
              child: Text(appTr(state.syncError ?? ''),
                  style: TextStyle(fontSize: 12, color: kOrange, height: 1.4)),
            ),
            TextButton(
              onPressed: () => state.refresh(),
              child: Text(appTr('إعادة المحاولة'), style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      );

  Widget _suggestionCard() {
    if (state.subjects.isEmpty) return const SizedBox.shrink();
    if (state.isRestDay(DateTime.now())) {
      return _infoCard(Icons.spa_rounded, appTr('النهاردة يوم راحة'),
          appTr('الراحة جزء من الخطة. ارجع بنشاط بكرة.'), kIndigo);
    }
    final s = state.todaySuggestion;
    if (s == null) {
      return _infoCard(Icons.celebration_rounded, appTr('خلصت خطة النهاردة'),
          appTr('شغل ممتاز. أي مذاكرة زيادة اختيارية.'), kGreen);
    }
    return _infoCard(
      Icons.flag_rounded,
      trp('ابدأ بـ {subject}', {'subject': s.subject}),
      trp('باقي {time} من خطة النهاردة. الأصعب أول حاجة.', {'time': fmtHours(s.remaining)}),
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
                    InkWell(
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => ProfileScreen(state: state))),
                      borderRadius: BorderRadius.circular(30),
                      child: CircleAvatar(
                        backgroundColor: kGreen.withValues(alpha: 0.2),
                        child: Text(
                          String.fromCharCode(state.userName.runes.first).toUpperCase(),
                          style: TextStyle(color: kGreen, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr('StudyPace'),
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white)),
                        InkWell(
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => ProfileScreen(state: state))),
                          child: Text('${state.userName} • ${state.educationLevel.isEmpty ? appTr('إعداد الملف الشخصي') : appTr(state.educationLevel)}${state.educationYear.isEmpty ? '' : ' - ${appTr(state.educationYear)}'}',
                            style: TextStyle(fontSize: 12, color: kMuted)),
                        ),
                      ],
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: appTr('تعديل الحد اليومي'),
                      onPressed: () => showCapDialog(context, state),
                      icon: Icon(Icons.tune_rounded, color: kMuted),
                    ),
                  ],
                ),
              ],
            ),
            SizedBox(height: 16),

            if (state.syncError != null) _syncBanner(),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: cardDecoration(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(appTr('ملخص النهاردة'),
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold, color: kGreen)),
                  SizedBox(height: 8),
                  Text(
                    trp('مرحباً يا {name}. عندك {count} مواد. ذاكرت النهاردة {time}.', {
                      'name': state.userName,
                      'count': state.subjects.length,
                      'time': fmtHours(state.todayHours),
                    }),
                    style: TextStyle(fontSize: 13, color: kMuted, height: 1.4),
                  ),
                  SizedBox(height: 8),
                  Text(
                    streak > 0
                        ? trp('🔥 سلسلة {n} يوم متتالي', {'n': streak})
                        : appTr('ابدأ سلسلتك النهاردة بأول جلسة.'),
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: streak > 0 ? kOrange : kMuted),
                  ),
                ],
              ),
            ),
            SizedBox(height: 16),

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
                      SizedBox(width: 8),
                      Text(appTr('حارس الإرهاق'),
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white)),
                    ],
                  ),
                  SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${fmtHours(state.todayHours)} ${appTr('النهاردة')}',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white)),
                      InkWell(
                        onTap: () => showCapDialog(context, state),
                        child: Text('${appTr('الحد الآمن')}: ${state.dailySafeCap}${appTr('س')} ✎',
                            style: TextStyle(fontSize: 12, color: color)),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: progress),
                      duration: Duration(milliseconds: 600),
                      builder: (context, value, child) => LinearProgressIndicator(
                        value: value,
                        backgroundColor: kDeep,
                        color: color,
                        minHeight: 8,
                      ),
                    ),
                  ),
                  SizedBox(height: 10),
                  Text(levelMessage(level), style: TextStyle(fontSize: 12, color: color)),
                ],
              ),
            ),
            SizedBox(height: 16),

            _suggestionCard(),
            if (state.subjects.isNotEmpty) SizedBox(height: 16),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: cardDecoration(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(appTr('آخر 7 أيام'),
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                  SizedBox(height: 4),
                  Text(appTr('الخط الأحمر هو الحد الآمن اليومي'),
                      style: TextStyle(fontSize: 11, color: kMuted)),
                  SizedBox(height: 12),
                  WeekChart(days: days, hours: hours, cap: state.dailySafeCap),
                ],
              ),
            ),
            SizedBox(height: 16),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: cardDecoration(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(appTr('مذاكرة النهاردة حسب المادة'),
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                  SizedBox(height: 10),
                  if (state.subjects.isEmpty)
                    Text(appTr('مفيش مواد لسه. ضيف من تبويب المواد.'),
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
                                  style: TextStyle(fontSize: 13, color: kMuted)),
                            ),
                            Text('${fmtHours(done)} / ${fmtHours(s.targetHours)}',
                                style: TextStyle(fontSize: 12, color: Colors.white)),
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
