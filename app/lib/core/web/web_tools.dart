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
