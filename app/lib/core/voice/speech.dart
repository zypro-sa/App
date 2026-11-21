import 'speech_stub.dart' if (dart.library.js_interop) 'speech_web.dart' as impl;

/// التعرّف على الكلام من المتصفح نفسه (مجاني). على الآيفون يعمل في Safari،
/// وقد لا يعمل داخل التطبيق المثبّت على الشاشة الرئيسية؛ حينها نستخدم ميكروفون لوحة المفاتيح.
class Speech {
  static bool get supported => impl.supported();

  static void start({
    required String lang,
    bool continuous = false,
    required void Function(String text) onPartial,
    required void Function(String text) onDone,
    required void Function(String error) onError,
  }) =>
      impl.start(lang, continuous, onPartial, onDone, onError);

  static void stop() => impl.stop();
}
