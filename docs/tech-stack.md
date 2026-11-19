# التقنيات المعتمدة (Tech Stack)

**تاريخ القرار:** ١٩ نوفمبر ٢٠٢٦

| الطبقة | التقنية | سبب الاختيار |
|-------|--------|-------------|
| تطبيق الجوال | **Flutter** (Dart) | تطبيق واحد لآيفون وأندرويد، دعم ممتاز للعربية واتجاه RTL، أداء عالٍ، وتطابق دقيق مع التصميم المعتمد |
| الخلفية وقاعدة البيانات | **Supabase** (PostgreSQL) | قاعدة بيانات علائقية تطابق [نموذج البيانات](data-model.md)، مع تسجيل دخول وصلاحيات (RLS) وتخزين ملفات وتحديثات لحظية جاهزة |
| الإشعارات | Firebase Cloud Messaging عبر Supabase Edge Functions | الطريقة المعتمدة لإرسال الإشعارات للجوال |
| التقويم والبريد (لاحقًا) | Google Calendar / Microsoft 365 | مزامنة الاجتماعات |

## حزم Flutter المقترحة

| الغرض | الحزمة |
|------|-------|
| الاتصال بـ Supabase | `supabase_flutter` |
| إدارة الحالة | `flutter_riverpod` |
| التنقل بين الشاشات | `go_router` |
| التعريب والتواريخ | `flutter_localizations` + `intl` |
| الخط | `google_fonts` (IBM Plex Sans Arabic) |
| الإشعارات | `firebase_messaging` |
| الإدخال الصوتي | `speech_to_text` |

## هيكل المستودع

```
App/
├── README.md
├── docs/
│   ├── data-model.md        نموذج البيانات
│   └── tech-stack.md        هذا الملف
├── supabase/
│   └── migrations/          ملفات إنشاء قاعدة البيانات
└── app/                     تطبيق Flutter (يُضاف لاحقًا)
```

## تشغيل قاعدة البيانات

**الطريقة الأسهل (من المتصفح):**
1. أنشئ مشروعًا جديدًا في [supabase.com](https://supabase.com)، واختر أقرب منطقة (مثل Frankfurt أو Mumbai).
2. افتح **SQL Editor** في لوحة التحكم.
3. انسخ محتوى الملف `supabase/migrations/20261119000000_initial_schema.sql` والصقه، ثم اضغط **Run**.

**أو باستخدام Supabase CLI:**
```bash
supabase link --project-ref <معرّف-المشروع>
supabase db push
```
