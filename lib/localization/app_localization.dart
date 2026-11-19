import 'package:ai_study_planner/localization/localized_texts.dart';

String currentLanguage = 'العربية';

/// اللغة المختارة ← الإنجليزية ← النص الأصلي
String tr(String text) {
  if (currentLanguage == 'العربية') return text;
  return localizedTexts[currentLanguage]?[text] ??
      localizedTexts['English']?[text] ??
      text;
}

/// ترجمة مع متغيرات: trp('باقي {time}', {'time': '2h'})
String trp(String key, Map<String, Object> args) {
  var s = tr(key);
  args.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
  return s;
}

bool get isEnglish => currentLanguage == 'English';

String appTr(String text) => tr(text);
