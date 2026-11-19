/// إعدادات الاتصال بمشروع Supabase.
///
/// هذه القيم عامة ومصممة لتكون داخل التطبيق (Publishable key)،
/// والحماية الفعلية تأتي من صلاحيات RLS في قاعدة البيانات.
/// لا تضع هنا أبدًا مفتاح service_role أو secret key.
///
/// يمكن تجاوزها عند البناء:
/// flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_KEY=...
class AppConfig {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://xtnpjkunewcjdqyexjnc.supabase.co',
  );

  static const supabaseKey = String.fromEnvironment(
    'SUPABASE_KEY',
    defaultValue: 'sb_publishable_HAIgTj1vIqH0_7yGc4iq6g_zr6Xia7V',
  );

  /// المفتاح العام لإشعارات الجوال (VAPID). عام وآمن داخل التطبيق.
  static const vapidPublicKey = String.fromEnvironment(
    'VAPID_PUBLIC_KEY',
    defaultValue: 'BFT3fSPaey9hO4IjZeuth7Wp6EQ_JftHdUP21LC9s84UWwt9bz52YcDW8dQTcVUKFIj_3oIZk4C5nnzB6aQxMWE',
  );
}
