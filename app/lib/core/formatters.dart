import 'package:intl/intl.dart';
import 'i18n.dart';

DateFormat get _dayFormat => DateFormat('EEEE d MMMM', L.code);
DateFormat get _shortDate => DateFormat('d MMMM', L.code);
DateFormat get _timeFormat => DateFormat('h:mm a', L.code);
DateFormat get _weekday => DateFormat('EEEE', L.code);

/// تنسيق تاريخ بنمط معيّن حسب لغة التطبيق.
String formatPattern(String pattern, DateTime d) => DateFormat(pattern, L.code).format(d);

String formatDay(DateTime d) => _dayFormat.format(d);
String formatShortDate(DateTime d) => _shortDate.format(d);
String formatTime(DateTime d) => _timeFormat.format(d);
String formatWeekdayShort(DateTime d) =>
    DateFormat('E', L.code).format(d);

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// تسمية نسبية للتاريخ: اليوم، غدًا، أمس، اسم اليوم، أو التاريخ.
String relativeDay(DateTime d) {
  final today = dateOnly(DateTime.now());
  final diff = dateOnly(d).difference(today).inDays;
  if (diff == 0) return tr('اليوم');
  if (diff == 1) return tr('غدًا');
  if (diff == -1) return tr('أمس');
  if (diff < -1) return tr('منذ {0} أيام', [-diff]);
  if (diff < 7) return _weekday.format(d);
  return formatShortDate(d);
}

/// «بعد ٢٥ دقيقة» أو «بعد ساعتين».
String timeUntil(DateTime d) {
  final mins = d.difference(DateTime.now()).inMinutes;
  if (mins <= 0) return tr('الآن');
  if (mins < 60) return tr('بعد {0} دقيقة', [mins]);
  final hours = (mins / 60).round();
  return hours == 1 ? tr('بعد ساعة') : tr('بعد {0} ساعات', [hours]);
}

String greeting() {
  final h = DateTime.now().hour;
  return h < 12 ? tr('صباح الخير') : tr('مساء الخير');
}
