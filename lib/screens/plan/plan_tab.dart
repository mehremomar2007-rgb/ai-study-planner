import 'package:flutter/material.dart';

import 'package:ai_study_planner/localization/app_localization.dart';
import 'package:ai_study_planner/models/models.dart';
import 'package:ai_study_planner/services/planner.dart';
import 'package:ai_study_planner/state/app_state.dart';
import 'package:ai_study_planner/theme/app_colors.dart';
import 'package:ai_study_planner/theme/app_theme.dart';
import 'package:ai_study_planner/utils/date_utils.dart';
import 'package:ai_study_planner/utils/formatters.dart';

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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(appTr('إعادة جدولة تلقائية'),
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                    SizedBox(height: 2),
                    Text(appTr('الساعات اللي فاتتك بتتوزع على الأيام الجاية'),
                        style: TextStyle(fontSize: 11, color: kMuted)),
                  ],
                ),
              ),
              Switch(value: state.autoReschedule, onChanged: state.setAutoReschedule),
            ],
          ),
          SizedBox(height: 12),
          Text(appTr('يوم الراحة'), style: TextStyle(fontSize: 12, color: kMuted)),
          SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              ChoiceChip(
                label: Text(appTr('بدون')),
                selected: state.restDay == 0,
                onSelected: (_) => state.setRestDay(0),
              ),
              for (final wd in [6, 7, 1, 2, 3, 4, 5])
                ChoiceChip(
                  label: Text(weekdayName(wd)),
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
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
              Spacer(),
              if (d.isRest) _badge(appTr('راحة'), kIndigo),
              if (isToday) ...[
                SizedBox(width: 6),
                _badge(appTr('النهاردة'), kGreen),
              ],
            ],
          ),
          if (d.isRest)
            Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(appTr('يوم راحة، مفيش مذاكرة مخططة 🌿'),
                  style: TextStyle(fontSize: 12, color: kMuted)),
            )
          else if (names.isEmpty)
            Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(appTr('مفيش مواد مخططة في اليوم ده.'),
                  style: TextStyle(fontSize: 12, color: kMuted)),
            )
          else ...[
            ...names.map((n) {
              final planned = d.hoursFor(n);
              final carried = d.carried[n] ?? 0.0;
              final done = state.hoursForOn(n, d.date);
              final met = planned > 0 && done >= planned - 0.05;

              final subj = byName[n];
              final beforeCreated =
                  subj != null && d.date.isBefore(dateOnly(subj.createdAt));

              final IconData icon;
              final Color iconColor;
              if (met) {
                icon = Icons.check_circle;
                iconColor = kGreen;
              } else if (isPast && !beforeCreated) {
                icon = Icons.cancel_outlined;
                iconColor = kOrange;
              } else {
                icon = Icons.circle_outlined;
                iconColor = kMuted;
              }
              final showActual = (isPast || isToday) && !beforeCreated;

              return Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  children: [
                    Icon(icon, size: 16, color: iconColor),
                    SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(n,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 13, color: Colors.white)),
                          if (carried > 0.02)
                            Text(trp('منها {time} من اللي فاتك', {'time': fmtHours(carried)}),
                                style: TextStyle(fontSize: 10, color: kOrange)),
                        ],
                      ),
                    ),
                    Text(
                      showActual
                          ? '${fmtHours(done)} / ${fmtHours(planned)}'
                          : fmtHours(planned),
                      style: TextStyle(fontSize: 12, color: kMuted),
                    ),
                  ],
                ),
              );
            }),
            SizedBox(height: 10),
            Text(trp('إجمالي المخطط: {time}', {'time': fmtHours(d.total)}),
                style: TextStyle(fontSize: 11, color: kMuted)),
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
            Text(appTr('الخطة الأسبوعية'),
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
            SizedBox(height: 4),
            Text(trp('المواد الصعبة الأول، ومفيش يوم بيعدّي {cap}س.', {'cap': state.dailySafeCap}),
              style: TextStyle(fontSize: 13, color: kMuted),
            ),
            SizedBox(height: 16),
            if (state.subjects.isEmpty)
              Center(
                child: Text(appTr('مفيش مواد. روح لتبويب المواد وضيف موادك.'),
                    style: TextStyle(color: Colors.grey)),
              )
            else ...[
              _settingsCard(),
              if (plan.carriedTotal > 0.05)
                _banner(
                  trp('اتوزّع {time} من اللي فاتك على باقي الأسبوع.', {'time': fmtHours(plan.carriedTotal)}),
                  kOrange,
                ),
              if (plan.unplaced.isNotEmpty)
                _banner(
                  trp('مفيش مساحة تحت الحد الآمن للساعات دي: {list}. ارفع الحد الآمن أو قلّل أهداف المواد.', {
                    'list': plan.unplaced.entries
                        .map((e) => '${e.key} (${fmtHours(e.value)})')
                        .join(', '),
                  }),
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
