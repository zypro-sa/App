import 'web_tools_stub.dart' if (dart.library.js_interop) 'web_tools_web.dart' as impl;

/// تنزيل نص كملف (CSV يُضاف له BOM ليفتح بالعربية في Excel).
void downloadText(String name, String text, {String mime = 'text/csv;charset=utf-8'}) =>
    impl.download(name, text, mime);

/// مشاركة نص عبر نافذة المشاركة، أو نسخه إن لم تتوفر. يعيد shared | copied | cancelled | failed.
Future<String> shareText(String title, String text) => impl.share(title, text);

/// فتح نافذة الطباعة لصفحة HTML (للحفظ PDF).
void printHtml(String html) => impl.printHtml(html);

/// ملء الشاشة (لشاشة المكتب).
void setFullscreen(bool on) => impl.fullscreen(on);

/// علامة الجلسة الحالية (تُمسح عند إغلاق التطبيق) — لخيار «تذكرني»
bool sessionFlag({bool set = false}) => impl.sessionFlag(set);

/// هل يدعم الجهاز Face ID / البصمة؟
Future<bool> bioAvailable() => impl.bioAvailable();

/// تسجيل بصمة الجهاز؛ يعيد معرّف الاعتماد أو نصًا يبدأ بـ error:
Future<String> bioRegister(String userId, String name) => impl.bioRegister(userId, name);

/// التحقق بالبصمة؛ يعيد ok أو error:...
Future<String> bioVerify(String credentialId) => impl.bioVerify(credentialId);

/// تشفير نص بمفتاح يُستخرج بعد Face ID؛ يعيد النص المشفّر أو error:...
Future<String> bioSeal(String credentialId, String text) => impl.bioSeal(credentialId, text);

/// فك التشفير بعد Face ID؛ يعيد ok:النص أو error:...
Future<String> bioOpen(String credentialId, String sealed) => impl.bioOpen(credentialId, sealed);
