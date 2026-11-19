class StudySession {
  final int? id;
  final String subject;
  final DateTime date;
  final double hours;

  const StudySession({
    this.id,
    required this.subject,
    required this.date,
    required this.hours,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'subject': subject,
        'date': date.toIso8601String(),
        'hours': hours,
      };

  factory StudySession.fromJson(Map<String, dynamic> j) => StudySession(
        id: (j['id'] as num?)?.toInt(),
        subject: j['subject'] as String,
        date: DateTime.parse(j['date'] as String),
        hours: (j['hours'] as num).toDouble(),
      );

  Map<String, dynamic> toRemote() => {
        'subject': subject,
        'hours': hours,
        'session_date': date.toUtc().toIso8601String(),
      };

  factory StudySession.fromRemote(Map<String, dynamic> r) => StudySession(
        id: (r['id'] as num).toInt(),
        subject: r['subject'] as String,
        date: DateTime.parse(r['session_date'] as String).toLocal(),
        hours: (r['hours'] as num).toDouble(),
      );
}
