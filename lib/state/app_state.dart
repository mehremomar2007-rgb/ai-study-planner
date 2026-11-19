import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ai_study_planner/config/supabase_config.dart';
import 'package:ai_study_planner/localization/app_localization.dart';
import 'package:ai_study_planner/models/models.dart';
import 'package:ai_study_planner/services/planner.dart';
import 'package:ai_study_planner/utils/date_utils.dart';

int _localTaskId = -1;

class Suggestion {
  final String subject;
  final double remaining;
  const Suggestion(this.subject, this.remaining);
}

class AppState extends ChangeNotifier {
  List<SubjectModel> subjects = [];
  List<StudySession> sessions = [];
  List<TaskModel> tasks = [];
  double dailySafeCap = 4.5;
  int restDay = DateTime.friday;
  bool autoReschedule = true;
  String profileName = '';
  String educationLevel = '';
  String educationYear = '';
  String major = '';
  String appLanguage = 'العربية';

  bool syncing = false;
  String? syncError;
  bool _again = false;

  Future<void> loadLocal() async {
    final prefs = await SharedPreferences.getInstance();
    dailySafeCap = prefs.getDouble('dailySafeCap') ?? 4.5;
    restDay = prefs.getInt('restDay') ?? DateTime.friday;
    autoReschedule = prefs.getBool('autoReschedule') ?? true;
    profileName = prefs.getString('profileName') ?? '';
    educationLevel = prefs.getString('educationLevel') ?? '';
    educationYear = prefs.getString('educationYear') ?? '';
    major = prefs.getString('major') ?? '';
    appLanguage = prefs.getString('appLanguage') ?? 'العربية';
    currentLanguage = appLanguage;
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
      final cutoff = DateTime.now().subtract(Duration(days: 180));
      sessions = sessions.where((s) => s.date.isAfter(cutoff)).toList();
      tasks = tasksRaw == null
          ? []
          : (jsonDecode(tasksRaw) as List)
              .map((e) => TaskModel.fromJson(e as Map<String, dynamic>))
              .toList();
    } catch (_) {
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
    await prefs.setString('profileName', profileName);
    await prefs.setString('educationLevel', educationLevel);
    await prefs.setString('educationYear', educationYear);
    await prefs.setString('major', major);
    await prefs.setString('appLanguage', appLanguage);
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

  Future<void> refresh() async {
    if (!isSignedIn) {
      syncError = null;
      notifyListeners();
      return;
    }
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

      final cutoff = DateTime.now().subtract(Duration(days: 180));
      final subjectRows =
          await netCall(supabase.from('subject').select().eq('user_id', supabase.auth.currentUser!.id).order('created_at'));
      final sessionRows = await netCall(supabase
          .from('sessions')
          .select()
          .eq('user_id', supabase.auth.currentUser!.id)
          .gte('session_date', cutoff.toUtc().toIso8601String())
          .order('session_date'));
      final taskRows =
          await netCall(supabase.from('tasks').select().eq('user_id', supabase.auth.currentUser!.id).order('created_at'));

      tasks = taskRows.map(TaskModel.fromRemote).toList();
      subjects = subjectRows.map(SubjectModel.fromRemote).toList();
      final inFlight = sessions.where((s) => s.id == null).toList();
      sessions = [...sessionRows.map(StudySession.fromRemote), ...inFlight];
      syncError = null;
    } catch (e) {
      debugPrint('Supabase sync failed: $e');
      syncError = 'تعذّر الاتصال بالسيرفر. بنعرض آخر بيانات محفوظة.';
    }
  }

  Future<void> _pushLocalOnly() async {
    if (!isSignedIn) return;
    final uid = supabase.auth.currentUser!.id;

    final localSubjects = subjects.where((s) => s.id == null).toList();
    for (final s in localSubjects) {
      final row = await netCall(supabase.from('subject').insert({
        'user_id': uid,
        'name': s.name,
        'difficulty': s.difficulty,
        'max_hours': s.targetHours,
        'created_at': s.createdAt.toUtc().toIso8601String(),
      }).select().single());
      final saved = SubjectModel.fromRemote(row);
      subjects = subjects.map((x) => identical(x, s) ? saved : x).toList();
    }

    final localSessions = sessions.where((s) => s.id == null).toList();
    for (final s in localSessions) {
      final row = await netCall(supabase.from('sessions').insert({
        ...s.toRemote(),
        'user_id': uid,
      }).select().single());
      final saved = StudySession.fromRemote(row);
      sessions = sessions.map((x) => identical(x, s) ? saved : x).toList();
    }

    final localTasks = tasks.where((t) => t.id < 0).toList();
    for (final t in localTasks) {
      final row = await netCall(supabase.from('tasks').insert({
        'user_id': uid,
        'title': t.title,
        'is_done': t.isDone,
        'subject_name': t.subjectName,
      }).select().single());
      final saved = TaskModel.fromRemote(row);
      tasks = tasks.map((x) => x.id == t.id ? saved : x).toList();
    }
  }

  Future<void> migrateGuestDataAndRefresh() async {
    if (!isSignedIn) return;
    await refresh();
  }

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

  Future<bool> addSubject(String name, String difficulty, double target) async {
    if (isSignedIn) {
      try {
        final row = await netCall(supabase.from('subject').insert({
          'user_id': supabase.auth.currentUser!.id,
          'name': name,
          'difficulty': difficulty,
          'max_hours': target,
        }).select().single());
        subjects = [...subjects, SubjectModel.fromRemote(row)];
      } catch (e) {
        debugPrint('addSubject remote failed; saved locally: $e');
        subjects = [...subjects, SubjectModel(name: name, difficulty: difficulty, targetHours: target, createdAt: DateTime.now())];
      }
    } else {
      subjects = [...subjects, SubjectModel(name: name, difficulty: difficulty, targetHours: target, createdAt: DateTime.now())];
    }
    _changed();
    return true;
  }

  Future<bool> updateSubject(String oldName, SubjectModel updated) async {
    try {
      if (isSignedIn && updated.id != null) {
        await netCall(supabase.from('subject').update({
          'name': updated.name,
          'difficulty': updated.difficulty,
          'max_hours': updated.targetHours,
        }).eq('id', updated.id!).eq('user_id', supabase.auth.currentUser!.id));
        if (oldName != updated.name) {
          await netCall(supabase
              .from('sessions')
              .update({'subject': updated.name}).eq('subject', oldName).eq('user_id', supabase.auth.currentUser!.id));
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
    try {
      if (isSignedIn && subject.id != null) {
        await netCall(supabase.from('subject').delete().eq('id', subject.id!).eq('user_id', supabase.auth.currentUser!.id));
      }
      subjects = subjects.where((s) => s.name != subject.name).toList();
      _changed();
      return true;
    } catch (e) {
      debugPrint('deleteSubject failed: $e');
      return false;
    }
  }

  void addSession(String subject, double hours) {
    sessions = [
      ...sessions,
      StudySession(subject: subject, date: DateTime.now(), hours: hours),
    ];
    _changed();
    if (isSignedIn) unawaited(refresh());
  }

  int _nextLocalTaskId() {
    final smallestExisting = tasks.where((t) => t.id < 0).fold<int>(0, (v, t) => math.min(v, t.id));
    _localTaskId = math.min(_localTaskId, smallestExisting - 1);
    return _localTaskId--;
  }

  Future<bool> addTask(String title, String? subjectName) async {
    if (isSignedIn) {
      try {
        final row = await netCall(supabase.from('tasks').insert({
          'user_id': supabase.auth.currentUser!.id,
          'title': title,
          'is_done': false,
          'subject_name': subjectName,
        }).select().single());
        tasks = [...tasks, TaskModel.fromRemote(row)];
      } catch (e) {
        debugPrint('addTask remote failed; saved locally: $e');
        tasks = [...tasks, TaskModel(id: _nextLocalTaskId(), title: title, isDone: false, subjectName: subjectName)];
      }
    } else {
      tasks = [...tasks, TaskModel(id: _nextLocalTaskId(), title: title, isDone: false, subjectName: subjectName)];
    }
    _changed();
    return true;
  }

  Future<bool> toggleTask(TaskModel t) async {
    final updated = t.copyWith(isDone: !t.isDone);
    if (isSignedIn && t.id > 0) {
      try {
        await netCall(supabase.from('tasks').update({'is_done': updated.isDone}).eq('id', t.id).eq('user_id', supabase.auth.currentUser!.id));
      } catch (e) {
        debugPrint('toggleTask failed: $e');
        return false;
      }
    }
    tasks = tasks.map((x) => x.id == t.id ? updated : x).toList();
    _changed();
    return true;
  }

  Future<bool> deleteTask(TaskModel t) async {
    if (isSignedIn && t.id > 0) {
      try {
        await netCall(supabase.from('tasks').delete().eq('id', t.id).eq('user_id', supabase.auth.currentUser!.id));
      } catch (e) {
        debugPrint('deleteTask failed: $e');
        return false;
      }
    }
    tasks = tasks.where((x) => x.id != t.id).toList();
    _changed();
    return true;
  }

  String? get userNameOrNull {
    if (!supabaseReady) return null;
    final n = supabase.auth.currentUser?.userMetadata?['name'];
    return (n is String && n.trim().isNotEmpty) ? n.trim() : null;
  }

  String get userName => profileName.trim().isNotEmpty ? profileName.trim() : (userNameOrNull ?? tr('صديقي'));

  Future<void> saveProfile({String? name, String? level, String? year, String? selectedMajor, String? language}) async {
    if (name != null) profileName = name.trim();
    if (level != null) educationLevel = level;
    if (year != null) educationYear = year;
    if (selectedMajor != null) major = selectedMajor;
    if (language != null) {
      appLanguage = language;
      currentLanguage = appLanguage;
    }
    await _save();
    notifyListeners();
  }

  Future<bool> setUserName(String name) async {
    if (!supabaseReady) return false;
    try {
      await netCall(supabase.auth.updateUser(UserAttributes(data: {'name': name})));
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('setUserName failed: $e');
      return false;
    }
  }

  Future<void> clearData() async {
    subjects = [];
    sessions = [];
    tasks = [];
    syncError = null;
    _changed();
  }
}
