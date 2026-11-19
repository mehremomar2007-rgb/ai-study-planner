import 'package:ai_study_planner/localization/app_localization.dart';

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

DateTime addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

DateTime weekStart(DateTime d) {
  final offset = (d.weekday - DateTime.saturday) % 7;
  return DateTime(d.year, d.month, d.day - offset);
}

const kDayNames = [
  'الإثنين',
  'الثلاثاء',
  'الأربعاء',
  'الخميس',
  'الجمعة',
  'السبت',
  'الأحد',
];

const kDayShort = ['إثن', 'ثلا', 'أرب', 'خمي', 'جمع', 'سبت', 'أحد'];
const kDayShortEn = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

const dayNamesByLang = {
  'English': ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'],
  'الإسبانية': ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'],
  'الفرنسية': ['Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche'],
  'الألمانية': ['Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag', 'Sonntag'],
  'الروسية': ['Понедельник', 'Вторник', 'Среда', 'Четверг', 'Пятница', 'Суббота', 'Воскресенье'],
  'الصينية': ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'],
  'البرتغالية': ['Segunda', 'Terça', 'Quarta', 'Quinta', 'Sexta', 'Sábado', 'Domingo'],
  'اليابانية': ['月曜日', '火曜日', '水曜日', '木曜日', '金曜日', '土曜日', '日曜日'],
  'الإيطالية': ['Lunedì', 'Martedì', 'Mercoledì', 'Giovedì', 'Venerdì', 'Sabato', 'Domenica'],
};

const dayShortByLang = {
  'English': kDayShortEn,
  'الإسبانية': ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'],
  'الفرنسية': ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'],
  'الألمانية': ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'],
  'الروسية': ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'],
  'الصينية': ['一', '二', '三', '四', '五', '六', '日'],
  'البرتغالية': ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'],
  'اليابانية': ['月', '火', '水', '木', '金', '土', '日'],
  'الإيطالية': ['Lun', 'Mar', 'Mer', 'Gio', 'Ven', 'Sab', 'Dom'],
};

String weekdayName(int wd) => (dayNamesByLang[currentLanguage] ?? kDayNames)[wd - 1];
String weekdayShort(int wd) => (dayShortByLang[currentLanguage] ?? kDayShort)[wd - 1];
String dayName(DateTime d) => weekdayName(d.weekday);

String shortDate(DateTime d) => '${d.day}/${d.month}';
