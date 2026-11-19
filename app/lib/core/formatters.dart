import 'package:intl/intl.dart';

final _dayFormat = DateFormat('EEEE d MMMM', 'ar');
final _shortDate = DateFormat('d MMMM', 'ar');
final _timeFormat = DateFormat('h:mm a', 'ar');
final _weekday = DateFormat('EEEE', 'ar');

String formatDay(DateTime d) => _dayFormat.format(d);
String formatShortDate(DateTime d) => _shortDate.format(d);
String formatTime(DateTime d) => _timeFormat.format(d);
String formatWeekdayShort(DateTime d) =>
    DateFormat('E', 'ar').format(d);

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// تسمية نسبية للتاريخ: اليوم، غدًا، أمس، اسم اليوم، أو التاريخ.
String relativeDay(DateTime d) {
  final today = dateOnly(DateTime.now());
  final diff = dateOnly(d).difference(today).inDays;
  if (diff == 0) return 'اليوم';
  if (diff == 1) return 'غدًا';
  if (diff == -1) return 'أمس';
  if (diff < -1) return 'منذ ${-diff} أيام';
  if (diff < 7) return _weekday.format(d);
  return formatShortDate(d);
}

/// «بعد ٢٥ دقيقة» أو «بعد ساعتين».
String timeUntil(DateTime d) {
  final mins = d.difference(DateTime.now()).inMinutes;
  if (mins <= 0) return 'الآن';
  if (mins < 60) return 'بعد $mins دقيقة';
  final hours = (mins / 60).round();
  return hours == 1 ? 'بعد ساعة' : 'بعد $hours ساعات';
}

String greeting() {
  final h = DateTime.now().hour;
  return h < 12 ? 'صباح الخير' : 'مساء الخير';
}
