import 'package:flutter_test/flutter_test.dart';
import 'package:personal_assistant/core/voice/command_parser.dart';

void main() {
  // السبت ٢١ نوفمبر ٢٠٢٦ الساعة ١٠ صباحًا
  final now = DateTime(2026, 11, 21, 10);
  const clients = [NamedRef('c1', 'شركة نكسس'), NamedRef('c2', 'الراس'), NamedRef('c3', 'Nexus Middle East')];
  const team = [NamedRef('u1', 'أحمد علي'), NamedRef('u2', 'Sara Khan')];

  test('مهمة عاجلة غدًا صباحًا لعميل', () {
    final p = parseCommand('ذكرني أتصل بشركة نكسس بكرة الساعة عشرة الصبح عاجل', clients: clients.sublist(0, 2), now: now);
    expect(p.intent, VoiceIntent.task);
    expect(p.title, 'أتصل بشركة نكسس');
    expect(p.when, DateTime(2026, 11, 22, 10));
    expect(p.hasTime, true);
    expect(p.clientId, 'c1');
    expect(p.priority, 'urgent');
  });

  test('اجتماع يوم الأحد الساعة ٣:٣٠ (عصرًا)', () {
    final p = parseCommand('اجتماع مع الراس يوم الأحد الساعة ٣:٣٠', clients: clients, now: now);
    expect(p.intent, VoiceIntent.meeting);
    expect(p.when, DateTime(2026, 11, 22, 15, 30));
    expect(p.clientId, 'c2');
    expect(p.title, 'اجتماع مع الراس');
  });

  test('متابعة بانتظار رد بعد ٣ أيام مع مسؤول', () {
    final p = parseCommand('تابع مع أحمد بانتظار رد العميل بعد 3 أيام', team: team, now: now);
    expect(p.intent, VoiceIntent.followup);
    expect(p.waiting, true);
    expect(p.assigneeId, 'u1');
    expect(p.when, DateTime(2026, 11, 24));
    expect(p.hasTime, false);
    expect(p.title, 'بانتظار رد العميل');
  });

  test('English meeting tomorrow at 3pm', () {
    final p = parseCommand('Meeting with Nexus tomorrow at 3pm', clients: clients, now: now);
    expect(p.intent, VoiceIntent.meeting);
    expect(p.when, DateTime(2026, 11, 22, 15));
    expect(p.clientId, 'c3');
    expect(p.title, 'Meeting with Nexus');
  });

  test('الساعة عشرة ونص بدون يوم: اليوم إن لم يمضِ الوقت', () {
    final p = parseCommand('مراجعة العقد الساعة عشرة ونص', now: now);
    expect(p.when, DateTime(2026, 11, 21, 10, 30));
  });

  test('استخراج المهام من المحضر', () {
    const minutes = 'ناقشنا العقد السنوي\n- أحمد يرسل العرض المحدث يوم الخميس\n- تجهيز ملف الترخيص بعد يومين';
    final tasks = extractTasks(minutes, team: team, now: now);
    expect(tasks.length, 2);
    expect(tasks.every((t) => t.selected), true);
    expect(tasks[0].parsed.assigneeId, 'u1');
    expect(tasks[0].parsed.when, DateTime(2026, 11, 26));
    expect(tasks[0].parsed.title, 'يرسل العرض المحدث');
    expect(tasks[1].parsed.when, DateTime(2026, 11, 23));
    expect(tasks[1].parsed.title, 'تجهيز ملف الترخيص');
  });

  test('محضر بلا أسطر واضحة: اقتراحات غير مختارة', () {
    final tasks = extractTasks('تمت مناقشة الخطة\nالعميل موافق مبدئيًا', now: now);
    expect(tasks.length, 2);
    expect(tasks.any((t) => t.selected), false);
  });

  test('التأجيل في المحضر: يُكتشف الموعد ولا يتحول لمهمة', () {
    const minutes = 'تم تأجيل الاجتماع الى يوم غداً\n- أحمد يجهز العرض';
    final p = findPostponement(minutes, now: now);
    expect(p?.when, DateTime(2026, 11, 22));
    final tasks = extractTasks(minutes, team: team, now: now);
    expect(tasks.length, 1);
    expect(tasks.first.parsed.title, 'يجهز العرض');
    expect(isPostponeLine('أجل الاجتماع الى الأحد'), true);
    expect(isPostponeLine('نرسل العرض من أجل العميل'), false);
  });
}
