/// تحليل جملة مكتوبة أو منطوقة إلى حقول جاهزة (بلا خدمات خارجية).
///
/// مثال: «ذكرني أتصل بشركة نكسس بكرة الساعة عشرة الصبح عاجل»
///   → مهمة · العنوان: «أتصل بشركة نكسس» · الموعد: غدًا 10:00 · العميل: Nexus · عاجلة
library;

enum VoiceIntent { task, request, meeting, followup, note }

class NamedRef {
  const NamedRef(this.id, this.name);
  final String id;
  final String name;
}

class ParsedCommand {
  ParsedCommand({
    required this.title,
    this.intent,
    this.when,
    this.hasTime = false,
    this.clientId,
    this.assigneeId,
    this.priority,
    this.waiting = false,
  });

  final String title;
  final VoiceIntent? intent; // null = لم تُذكر صراحة
  final DateTime? when;
  final bool hasTime;
  final String? clientId;
  final String? assigneeId;
  final String? priority; // urgent | high
  final bool waiting; // متابعة: أنتظرها (وإلا: وعدتُ بها)

  @override
  String toString() =>
      'ParsedCommand(intent: $intent, title: $title, when: $when, hasTime: $hasTime, client: $clientId, assignee: $assigneeId, priority: $priority, waiting: $waiting)';
}

/// توحيد الكتابة العربية للمقارنة: بلا تشكيل، والألف والتاء المربوطة والياء موحّدة.
String normalizeArabic(String s) {
  var out = s
      .replaceAll(RegExp('[\u064B-\u0652\u0670\u0640]'), '')
      .replaceAll(RegExp('[أإآٱ]'), 'ا')
      .replaceAll('ة', 'ه')
      .replaceAll('ى', 'ي')
      .replaceAll('ؤ', 'و')
      .replaceAll('ئ', 'ي')
      .toLowerCase();
  const arabicDigits = '٠١٢٣٤٥٦٧٨٩';
  const persianDigits = '۰۱۲۳۴۵۶۷۸۹';
  for (var i = 0; i < 10; i++) {
    out = out.replaceAll(arabicDigits[i], '$i').replaceAll(persianDigits[i], '$i');
  }
  return out;
}

class _Tok {
  _Tok(this.raw) : n = normalizeArabic(raw).replaceAll(RegExp(r'^[^\w\u0600-\u06FF:]+|[^\w\u0600-\u06FF:]+$'), '');
  final String raw;
  final String n;
  bool used = false;

  /// الكلمة بلا حروف الجر/العطف الملتصقة (و، ب، ل، ف)
  String get bare {
    if (n.length > 3 && RegExp(r'^(و|ب|ل|ف)').hasMatch(n)) return n.substring(1);
    return n;
  }

  bool isAny(Iterable<String> words) => words.contains(n) || words.contains(bare);
}

const _numberWords = {
  'واحد': 1, 'واحده': 1, 'one': 1,
  'اثنين': 2, 'اتنين': 2, 'ثنتين': 2, 'اثنتين': 2, 'two': 2,
  'ثلاث': 3, 'ثلاثه': 3, 'تلات': 3, 'three': 3,
  'اربع': 4, 'اربعه': 4, 'four': 4,
  'خمس': 5, 'خمسه': 5, 'five': 5,
  'ست': 6, 'سته': 6, 'six': 6,
  'سبع': 7, 'سبعه': 7, 'seven': 7,
  'ثمان': 8, 'ثمانيه': 8, 'ثماني': 8, 'تمان': 8, 'تمانيه': 8, 'eight': 8,
  'تسع': 9, 'تسعه': 9, 'nine': 9,
  'عشر': 10, 'عشره': 10, 'ten': 10,
  'احدعش': 11, 'حداش': 11, 'احداش': 11, 'eleven': 11,
  'اثنعش': 12, 'اطنعش': 12, 'اتناش': 12, 'twelve': 12,
};

const _weekdays = {
  // DateTime.weekday: الاثنين=1 ... الأحد=7
  'الاثنين': 1, 'الاتنين': 1, 'monday': 1,
  'الثلاثاء': 2, 'الثلاثا': 2, 'الثلوث': 2, 'tuesday': 2,
  'الاربعاء': 3, 'الاربعا': 3, 'الاربع': 3, 'wednesday': 3,
  'الخميس': 4, 'خميس': 4, 'thursday': 4,
  'الجمعه': 5, 'جمعه': 5, 'friday': 5,
  'السبت': 6, 'سبت': 6, 'saturday': 6,
  'الاحد': 7, 'sunday': 7,
};

const _amWords = {'الصبح', 'صباحا', 'صباح', 'الصباح', 'ص', 'am', 'morning', 'الفجر'};
const _pmWords = {'الظهر', 'ظهرا', 'العصر', 'عصرا', 'المغرب', 'مساء', 'مساءا', 'المسا', 'مسا', 'بالليل', 'الليل', 'ليلا', 'العشاء', 'م', 'pm', 'evening', 'afternoon'};
const _nextWords = {'الجاي', 'الياي', 'القادم', 'القادمه', 'الجايه', 'الياية', 'next'};

const _leadWords = {
  'اضف', 'ضيف', 'سجل', 'حط', 'انشي', 'اعمل', 'ذكرني', 'ذكرنى', 'فكرني', 'نبهني',
  'add', 'create', 'new', 'remind', 'me', 'to', 'schedule', 'please', 'لو', 'سمحت',
  'مهمه', 'task', 'ان', 'اني', 'بان', 'باني',
};
const _edgeWords = {'في', 'يوم', 'على', 'الساعه', 'ساعه', 'at', 'on', 'in', 'by', 'و', 'مع', 'الى', 'for', 'عن'};
const _genericNameWords = {
  'شركه', 'مؤسسه', 'موسسه', 'مكتب', 'مجموعه', 'مصنع', 'متجر', 'company', 'co', 'est', 'ltd', 'llc', 'group',
  'the', 'and', 'لل', 'ال', 'للتجاره', 'التجاريه', 'middle', 'east', 'العربيه', 'السعوديه', 'trading',
};

ParsedCommand parseCommand(
  String text, {
  List<NamedRef> clients = const [],
  List<NamedRef> team = const [],
  DateTime? now,
}) {
  final clock = now ?? DateTime.now();
  final today = DateTime(clock.year, clock.month, clock.day);
  final toks = text
      .replaceAll(RegExp(r'[،,؛;.!؟?]+'), ' ')
      .split(RegExp(r'\s+'))
      .where((t) => t.trim().isNotEmpty)
      .map(_Tok.new)
      .toList();

  VoiceIntent? intent;
  DateTime? date;
  int? hour;
  var minute = 0;
  String? period; // am | pm
  String? priority;
  var waiting = false;

  int? numAt(int i) {
    if (i < 0 || i >= toks.length) return null;
    final s = toks[i].bare;
    final d = int.tryParse(s);
    if (d != null) return d;
    return _numberWords[s] ?? _numberWords[toks[i].n];
  }

  bool isWord(int i, Set<String> words) => i >= 0 && i < toks.length && !toks[i].used && toks[i].isAny(words);

  void readPeriod(int i) {
    if (isWord(i, _amWords)) {
      period = 'am';
      toks[i].used = true;
    } else if (isWord(i, _pmWords)) {
      period = toks[i].n == 'الظهر' || toks[i].n == 'ظهرا' ? 'noon' : 'pm';
      toks[i].used = true;
    }
  }

  /// يقرأ وقتًا يبدأ عند i، ويعيد عدد الكلمات المستهلكة
  int readTime(int i) {
    final t = toks[i];
    // 10:30 أو 10:30pm
    final m = RegExp(r'^(\d{1,2})[:.](\d{2})(am|pm)?$').firstMatch(t.bare);
    final m2 = RegExp(r'^(\d{1,2})(am|pm)$').firstMatch(t.bare);
    var used = 0;
    if (m != null) {
      hour = int.parse(m.group(1)!);
      minute = int.parse(m.group(2)!);
      if (m.group(3) != null) period = m.group(3);
      used = 1;
    } else if (m2 != null) {
      hour = int.parse(m2.group(1)!);
      period = m2.group(2);
      used = 1;
    } else {
      final h = numAt(i);
      if (h == null || h < 0 || h > 23) return 0;
      hour = h;
      used = 1;
    }
    // ونص / وربع / الا ربع / وثلث
    var j = i + used;
    if (j < toks.length) {
      final w = toks[j].n;
      if (w == 'ونص' || w == 'ونصف' || w == 'نص') {
        minute = 30;
        used++;
      } else if (w == 'وربع') {
        minute = 15;
        used++;
      } else if (w == 'وثلث') {
        minute = 20;
        used++;
      } else if (w == 'و' && j + 1 < toks.length && {'نص', 'نصف', 'ربع', 'ثلث'}.contains(toks[j + 1].n)) {
        minute = {'نص': 30, 'نصف': 30, 'ربع': 15, 'ثلث': 20}[toks[j + 1].n]!;
        used += 2;
      } else if ((w == 'الا' || w == 'إلا') && j + 1 < toks.length && toks[j + 1].n.startsWith('ربع')) {
        minute = 45;
        hour = (hour! + 23) % 24;
        used += 2;
      }
    }
    for (var k = i; k < i + used; k++) {
      toks[k].used = true;
    }
    readPeriod(i + used);
    return used;
  }

  for (var i = 0; i < toks.length; i++) {
    final t = toks[i];
    if (t.used) continue;
    final w = t.n;
    final b = t.bare;

    // ---------- التاريخ ----------
    if (b == 'اليوم' || w == 'today') {
      date = today;
      t.used = true;
    } else if ((w == 'بعد' || w == 'وبعد') && i + 1 < toks.length && {'بكره', 'بكرا', 'غد', 'غدا', 'باكر'}.contains(toks[i + 1].n)) {
      date = today.add(const Duration(days: 2));
      t.used = toks[i + 1].used = true;
    } else if (t.isAny(const {'بكره', 'بكرا', 'غدا', 'غد', 'باكر', 'tomorrow'})) {
      date = today.add(const Duration(days: 1));
      t.used = true;
    } else if (w == 'بعد' || w == 'in' || w == 'خلال') {
      // بعد يومين / بعد 3 ايام / بعد اسبوع
      if (i + 1 < toks.length) {
        final next = toks[i + 1].n;
        if (next == 'يومين') {
          date = today.add(const Duration(days: 2));
          t.used = toks[i + 1].used = true;
        } else if (next == 'اسبوع' || next == 'week' || next == 'a' && i + 2 < toks.length && toks[i + 2].n == 'week') {
          date = today.add(const Duration(days: 7));
          t.used = toks[i + 1].used = true;
          if (next == 'a') toks[i + 2].used = true;
        } else if (next == 'اسبوعين') {
          date = today.add(const Duration(days: 14));
          t.used = toks[i + 1].used = true;
        } else {
          final n = numAt(i + 1);
          if (n != null && i + 2 < toks.length && {'ايام', 'يوم', 'days', 'day'}.contains(toks[i + 2].n)) {
            date = today.add(Duration(days: n));
            t.used = toks[i + 1].used = toks[i + 2].used = true;
          } else if (n != null && i + 2 < toks.length && {'ساعات', 'ساعه', 'hours', 'hour'}.contains(toks[i + 2].n)) {
            final at = clock.add(Duration(hours: n));
            date = DateTime(at.year, at.month, at.day);
            hour = at.hour;
            minute = at.minute;
            period = 'abs';
            t.used = toks[i + 1].used = toks[i + 2].used = true;
          }
        }
      }
    } else if (_weekdays.containsKey(w) || _weekdays.containsKey(b)) {
      final wd = _weekdays[w] ?? _weekdays[b]!;
      var diff = (wd - today.weekday) % 7;
      if (diff == 0) diff = 7;
      date = today.add(Duration(days: diff));
      t.used = true;
      if (i > 0 && !toks[i - 1].used && (toks[i - 1].n == 'يوم' || toks[i - 1].n == 'on')) toks[i - 1].used = true;
      if (isWord(i + 1, _nextWords)) toks[i + 1].used = true;
    } else if ((w == 'الاسبوع' || w == 'week') && isWord(i + 1, _nextWords)) {
      date ??= today.add(const Duration(days: 7));
      t.used = toks[i + 1].used = true;
    } else if (w == 'next' && i + 1 < toks.length && toks[i + 1].n == 'week') {
      date ??= today.add(const Duration(days: 7));
      t.used = toks[i + 1].used = true;
    } else if (RegExp(r'^\d{1,2}[/-]\d{1,2}$').hasMatch(b)) {
      final p = b.split(RegExp('[/-]'));
      final d = int.parse(p[0]), mo = int.parse(p[1]);
      if (mo >= 1 && mo <= 12 && d >= 1 && d <= 31) {
        var dt = DateTime(today.year, mo, d);
        if (dt.isBefore(today)) dt = DateTime(today.year + 1, mo, d);
        date = dt;
        t.used = true;
      }
    }
    if (t.used) continue;

    // ---------- الوقت ----------
    if (w == 'الساعه' || w == 'ساعه' || b == 'الساعه' || w == 'at') {
      if (i + 1 < toks.length && readTime(i + 1) > 0) {
        t.used = true;
        continue;
      }
    }
    if (RegExp(r'^\d{1,2}([:.]\d{2})?(am|pm)?$').hasMatch(b) && (b.contains(':') || b.endsWith('am') || b.endsWith('pm'))) {
      readTime(i);
      continue;
    }
    if (RegExp(r'^\d{1,2}$').hasMatch(b) && i + 1 < toks.length && (isWord(i + 1, _amWords) || isWord(i + 1, _pmWords))) {
      readTime(i);
      continue;
    }

    // ---------- الأولوية ----------
    if (t.isAny(const {'عاجل', 'عاجله', 'ضروري', 'مستعجل', 'urgent', 'asap'})) {
      priority = 'urgent';
      t.used = true;
      continue;
    }
    if (w == 'مهم' || w == 'important') {
      priority ??= 'high';
      t.used = true;
      continue;
    }

    // ---------- النوع ----------
    if (intent == null) {
      if (t.isAny(const {'ملاحظه', 'فكره', 'note', 'idea'}) && i <= 2) {
        intent = VoiceIntent.note;
        t.used = true;
      } else if (t.isAny(const {'اجتماع', 'ميتنج', 'ميتينج', 'meeting', 'زياره'})) {
        intent = VoiceIntent.meeting;
      } else if (t.isAny(const {'موعد'}) && i + 1 < toks.length && toks[i + 1].n == 'مع') {
        intent = VoiceIntent.meeting;
      } else if (t.isAny(const {'تابع', 'متابعه', 'follow', 'followup'}) && i <= 3) {
        intent = VoiceIntent.followup;
        t.used = i == 0 || t.isAny(const {'تابع'});
      } else if (w == 'طلب' && i <= 2 && i + 1 < toks.length && {'جديد', 'new'}.contains(toks[i + 1].n)) {
        intent = VoiceIntent.request;
        t.used = toks[i + 1].used = true;
      } else if (t.isAny(const {'ذكرني', 'فكرني', 'نبهني', 'remind', 'مهمه', 'task'}) && i <= 2) {
        intent = VoiceIntent.task;
      }
    }
    if (t.isAny(const {'انتظر', 'بانتظار', 'ينتظر', 'ننتظر', 'waiting', 'منتظر'})) waiting = true;
  }

  // ---------- العميل ----------
  final normText = ' ${toks.map((t) => t.n).join(' ')} ';
  final textWords = toks.expand((t) => {t.n, t.bare, if (t.bare.startsWith('ال')) t.bare.substring(2)}).toSet();
  String? clientId;
  var best = 0;
  var tie = false;
  for (final c in clients) {
    final cn = normalizeArabic(c.name).replaceAll(RegExp(r'[^\w\u0600-\u06FF ]'), ' ').trim();
    if (cn.isEmpty) continue;
    var score = 0;
    if (normText.contains(' $cn ')) {
      score = 100 + cn.length;
    } else {
      for (final part in cn.split(RegExp(r'\s+'))) {
        final p = part.startsWith('ال') && part.length > 4 ? part.substring(2) : part;
        if (p.length < 3 || _genericNameWords.contains(part) || _genericNameWords.contains(p)) continue;
        if (textWords.contains(part) || textWords.contains(p)) score += p.length;
      }
    }
    if (score > best) {
      best = score;
      clientId = c.id;
      tie = false;
    } else if (score == best && score > 0) {
      tie = true;
    }
  }
  if (tie) clientId = null;

  // ---------- المسؤول ----------
  String? assigneeId;
  for (final m in team) {
    final first = normalizeArabic(m.name).split(RegExp(r'\s+')).first;
    if (first.length < 2) continue;
    for (var i = 0; i < toks.length; i++) {
      final t = toks[i];
      final bare = t.n.startsWith('ل') && t.n.length > first.length ? t.n.substring(1) : t.n;
      if (bare == first || t.bare == first) {
        assigneeId = m.id;
        t.used = true;
        if (i > 0 && {'الى', 'ل', 'for', 'to'}.contains(toks[i - 1].n)) toks[i - 1].used = true;
        break;
      }
    }
    if (assigneeId != null) break;
  }

  // ---------- بناء الموعد ----------
  DateTime? when;
  var hasTime = false;
  if (hour != null) {
    var h = hour!;
    if (period == 'pm' && h < 12) h += 12;
    if (period == 'am' && h == 12) h = 0;
    if (period == 'noon' && h < 6) h += 12;
    if (period == null && h >= 1 && h <= 6) h += 12; // «الساعة ٣» في الدوام = ٣ العصر
    final d = date ?? today;
    when = DateTime(d.year, d.month, d.day, h, minute);
    if (date == null && when.isBefore(clock)) when = when.add(const Duration(days: 1));
    hasTime = true;
  } else if (date != null) {
    when = date;
  }

  // ---------- العنوان ----------
  final rest = toks.where((t) => !t.used).toList();
  // حذف أفعال الأمر في البداية
  while (rest.isNotEmpty && rest.first.isAny(_leadWords)) {
    rest.removeAt(0);
  }
  while (rest.isNotEmpty && rest.first.isAny(_edgeWords)) {
    rest.removeAt(0);
  }
  while (rest.isNotEmpty && rest.last.isAny(_edgeWords)) {
    rest.removeLast();
  }
  var title = rest.map((t) => t.raw).join(' ').trim();
  title = title.replaceAll(RegExp(r'^[\s:\-–]+|[\s:\-–]+$'), '');
  if (title.isEmpty) title = text.trim();

  return ParsedCommand(
    title: title,
    intent: intent,
    when: when,
    hasTime: hasTime,
    clientId: clientId,
    assigneeId: assigneeId,
    priority: priority,
    waiting: waiting,
  );
}

final _postponeWords = RegExp(
    r'(تاجيل|تاجل|يوجل|نوجل|موجل|اجلنا|اجلت|ترحيل الاجتماع|postpone|reschedul|اجل (ال)?(اجتماع|موعد|لقاء|زياره|ميتنج))',
    caseSensitive: false);

/// هل يتحدث السطر عن تأجيل الاجتماع نفسه؟ (مثل: «تم تأجيل الاجتماع إلى الغد»)
bool isPostponeLine(String line) => _postponeWords.hasMatch(normalizeArabic(line));

/// إن ذكر المحضر تأجيل الاجتماع مع موعد، نعيد الموعد الجديد.
ParsedCommand? findPostponement(String minutes, {DateTime? now}) {
  for (final line in minutes.split(RegExp(r'\r?\n'))) {
    if (!isPostponeLine(line)) continue;
    final p = parseCommand(line, now: now);
    if (p.when != null) return p;
    return ParsedCommand(title: line.trim());
  }
  return null;
}

/// استخراج المهام من نص المحضر: الأسطر النقطية أو المرقّمة أو التي تبدأ بـ «مهمة:».
class MinuteTask {
  MinuteTask(this.parsed, {required this.selected});
  final ParsedCommand parsed;
  bool selected;
}

List<MinuteTask> extractTasks(
  String minutes, {
  List<NamedRef> team = const [],
  List<NamedRef> clients = const [],
  DateTime? now,
}) {
  final lines = minutes.split(RegExp(r'\r?\n')).map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  final bullet = RegExp(r'^([-–•*▪●]|\d+[.)\-]|[\u0660-\u0669]+[.)\-])\s*');
  final marker = RegExp(r'^(مهمة|مهمه|إجراء|اجراء|قرار|تكليف|action|task|todo|to do)\s*[:：\-]\s*', caseSensitive: false);
  final verbs = RegExp(r'(يتولى|تتولى|يقوم|تقوم|سيقوم|ستقوم|يرسل|ترسل|يجهز|تجهز|يعد|تعد|يتابع|تتابع|على .{2,20} (ان|أن)|will|to send|to prepare|follow up)');
  final out = <MinuteTask>[];
  final strong = <int>{};
  for (var i = 0; i < lines.length; i++) {
    if (bullet.hasMatch(lines[i]) || marker.hasMatch(lines[i]) || verbs.hasMatch(lines[i])) strong.add(i);
  }
  for (var i = 0; i < lines.length; i++) {
    if (isPostponeLine(lines[i])) continue; // التأجيل ليس مهمة
    var l = lines[i].replaceFirst(bullet, '');
    l = l.replaceFirst(marker, '');
    if (l.trim().length < 3) continue;
    // إن وُجدت أسطر واضحة كمهام نكتفي بها؛ وإلا نقترح كل الأسطر غير مختارة
    if (strong.isNotEmpty && !strong.contains(i)) continue;
    final p = parseCommand(l, team: team, clients: clients, now: now);
    out.add(MinuteTask(p, selected: strong.isNotEmpty));
  }
  return out;
}
