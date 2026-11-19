import 'package:ai_study_planner/utils/date_utils.dart';

class SubjectModel {
  final int? id;
  final String name;
  final String difficulty;
  final double targetHours;
  final DateTime createdAt;

  const SubjectModel({
    this.id,
    required this.name,
    required this.difficulty,
    required this.targetHours,
    required this.createdAt,
  });

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
        createdAt: j['createdAt'] is String
            ? DateTime.parse(j['createdAt'] as String)
            : dateOnly(DateTime.now()),
      );

  factory SubjectModel.fromRemote(Map<String, dynamic> r) => SubjectModel(
        id: (r['id'] as num).toInt(),
        name: r['name'] as String,
        difficulty: (r['difficulty'] as String?) ?? 'Medium',
        targetHours: ((r['max_hours'] as num?) ?? 2).toDouble(),
        createdAt: dateOnly(DateTime.parse(r['created_at'] as String).toLocal()),
      );
}
