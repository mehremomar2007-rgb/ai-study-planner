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
