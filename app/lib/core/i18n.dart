import 'i18n_en.dart';

/// اللغة الحالية للتطبيق. تُضبط من إعدادات العضو ويُعاد بناء الشجرة عند تغييرها.
class L {
  static String code = 'ar';
  static bool get isEn => code == 'en';
  static bool get isAr => !isEn;
}

/// ترجمة نص عربي حسب لغة التطبيق.
/// النص العربي هو المفتاح؛ والقيم المتغيرة تُمرَّر كقائمة وتظهر مكان {0}، {1}...
String tr(String ar, [List<Object?> args = const []]) {
  var s = L.isEn ? (enStrings[ar] ?? ar) : ar;
  for (var i = 0; i < args.length; i++) {
    s = s.replaceAll('{$i}', '${args[i] ?? ''}');
  }
  return s;
}

/// اختيار نص من قاعدة البيانات حسب اللغة (مثل أسماء الحالات والحقول).
String pickLang(String ar, String? en) =>
    L.isEn && en != null && en.trim().isNotEmpty ? en : ar;
