import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'package:ai_study_planner/theme/app_colors.dart';
import 'package:ai_study_planner/utils/date_utils.dart';

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
                          style: TextStyle(fontSize: 9, color: kMuted),
                        ),
                      ),
                      SizedBox(height: 2),
                      AnimatedContainer(
                        duration: Duration(milliseconds: 500),
                        height: barHeight,
                        width: 16,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      SizedBox(height: 6),
                      SizedBox(
                        height: labelHeight,
                        child: Text(
                          weekdayShort(days[i].weekday),
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
