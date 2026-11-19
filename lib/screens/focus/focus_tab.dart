import 'dart:async';
import 'package:flutter/material.dart';

import 'package:ai_study_planner/localization/app_localization.dart';
import 'package:ai_study_planner/models/models.dart';
import 'package:ai_study_planner/state/app_state.dart';
import 'package:ai_study_planner/theme/app_colors.dart';
import 'package:ai_study_planner/utils/formatters.dart';
import 'package:ai_study_planner/widgets/common/snack.dart';

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
  DateTime? endTime;
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
    ticker = Timer.periodic(Duration(seconds: 1), (_) => _tick());
    setState(() => isRunning = true);
  }

  Future<bool?> _confirmOverCap() => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: kCard,
          title: Row(children: [
            Icon(Icons.warning_amber_rounded, color: kRed),
            SizedBox(width: 8),
            Text(appTr('عديت الحد الآمن'), style: TextStyle(color: Colors.white)),
          ]),
          content: Text(
            trp('ذاكرت {time} والحد الآمن {cap}س. متأكد إنك عايز تكمل؟', {
              'time': fmtHours(widget.state.todayHours),
              'cap': widget.state.dailySafeCap,
            }),
            style: TextStyle(color: kMuted),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false), child: Text(appTr('لأ، هرتاح'))),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(appTr('كمّل برضو'), style: TextStyle(color: kRed))),
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
          trp(
            long
                ? '🎉 خلصت جلسة {min} دقيقة في ({subject}). خد راحة طويلة.'
                : '🎉 خلصت جلسة {min} دقيقة في ({subject}). خد راحة قصيرة.',
            {'min': focusMinutes, 'subject': subject ?? ''},
          ),
        );
      }
    } else {
      setState(() {
        isRunning = false;
        _setPhase(PomoPhase.focus);
      });
      if (mounted) showSnack(context, appTr('الراحة خلصت. جاهز للجلسة الجاية؟'));
    }
  }

  void _finishEarly() {
    if (phase != PomoPhase.focus) return;
    final subject = _currentSubject;
    final left = isRunning ? _computeRemaining() : remainingSeconds;
    final elapsed = totalSeconds - left.clamp(0, totalSeconds);
    ticker?.cancel();
    endTime = null;
    if (subject == null || elapsed < 60) {
      showSnack(context, appTr('جلسة أقل من دقيقة، مش هتتسجل.'));
    } else {
      widget.state.addSession(subject, elapsed / 3600);
      showSnack(context, trp('اتسجل {time} في ({subject}).', {
        'time': fmtHours(elapsed / 3600),
        'subject': subject,
      }));
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
        title: Text(appTr('إضافة وقت يدوي'), style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          style: TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: trp('المدة بالدقائق (لمادة {subject})', {'subject': subject}),
            labelStyle: TextStyle(color: kMuted),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(appTr('إلغاء'))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kGreen),
            onPressed: () {
              final m = int.tryParse(controller.text.trim());
              if (m == null || m < 1 || m > 480) {
                showSnack(ctx, appTr('اكتب مدة بين 1 و 480 دقيقة'));
                return;
              }
              widget.state.addSession(subject, m / 60);
              Navigator.pop(ctx);
              showSnack(context, trp('اتسجل {min} دقيقة في ({subject}).', {
                'min': m,
                'subject': subject,
              }));
            },
            child: Text(appTr('إضافة'), style: TextStyle(color: kBg)),
          ),
        ],
      ),
    );
  }

  String get _phaseLabel => switch (phase) {
        PomoPhase.focus => appTr('تركيز'),
        PomoPhase.shortBreak => appTr('راحة قصيرة'),
        PomoPhase.longBreak => appTr('راحة طويلة'),
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
                  label: Text('$_phaseLabel • ${appTr('دورة')} ${completedCycles + (isFocus ? 1 : 0)}',
                      style: TextStyle(color: ringColor, fontSize: 12)),
                  backgroundColor: kDeep,
                  side: BorderSide(color: ringColor.withValues(alpha: 0.4)),
                ),
                SizedBox(height: 12),
                if (subjects.isEmpty)
                  Text(appTr('ضيف مواد الأول من تبويب المواد'), style: TextStyle(color: kOrange))
                else
                  DropdownButton<String>(
                    value: current,
                    dropdownColor: kCard,
                    style: TextStyle(color: kGreen, fontWeight: FontWeight.bold),
                    items: subjects
                        .map((x) => DropdownMenuItem(value: x.name, child: Text(x.name)))
                        .toList(),
                    onChanged: isRunning ? null : (v) => setState(() => selectedSubject = v),
                  ),
                SizedBox(height: 20),
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
                              style: TextStyle(
                                  fontSize: 50,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  letterSpacing: 2)),
                          Text(appTr(isFocus ? 'وقت التركيز' : 'استراحة'),
                              style: TextStyle(fontSize: 12, color: kMuted)),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 20),
                if (isFocus)
                  Wrap(
                    spacing: 8,
                    children: [15, 25, 45, 60].map((min) {
                      return ChoiceChip(
                        label: Text('$min ${appTr('د')}'),
                        selected: focusMinutes == min,
                        onSelected: (isRunning || !untouched) ? null : (_) => _setFocusMinutes(min),
                      );
                    }).toList(),
                  ),
                SizedBox(height: 20),
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
                      label: Text(appTr(isRunning ? 'إيقاف مؤقت' : 'ابدأ'),
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    SizedBox(width: 12),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        side: BorderSide(color: kBorder),
                      ),
                      onPressed: _reset,
                      child: Text(appTr('إعادة'), style: TextStyle(color: kMuted)),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                if (isFocus && (isRunning || !untouched))
                  TextButton.icon(
                    onPressed: _finishEarly,
                    icon: Icon(Icons.check_circle_outline, color: kGreen, size: 18),
                    label: Text(appTr('إنهاء وحفظ الوقت اللي ذاكرته'),
                        style: TextStyle(color: kGreen, fontSize: 12)),
                  ),
                if (!isFocus)
                  TextButton(
                    onPressed: _skipBreak,
                    child: Text(appTr('تخطي الراحة'),
                        style: TextStyle(color: kMuted, fontSize: 12)),
                  ),
                if (isFocus && !isRunning && untouched)
                  TextButton(
                    onPressed: current == null ? null : _showManualDialog,
                    child: Text(appTr('✍️ إضافة وقت يدوي'),
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
