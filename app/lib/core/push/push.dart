import 'push_stub.dart' if (dart.library.js_interop) 'push_web.dart' as impl;

/// تفعيل إشعارات الجوال (Web Push). على غير الويب لا يعمل بعد.
class PushSupport {
  static bool get supported => impl.supported();

  /// granted | denied | default | unsupported
  static String get permission => impl.permission();

  /// هل التطبيق مفتوح من الشاشة الرئيسية (شرط الآيفون للإشعارات)
  static bool get standalone => impl.standalone();

  /// يجب استدعاؤها مباشرة من ضغطة زر، قبل أي await.
  static Future<String?> subscribe(String vapidPublicKey) => impl.subscribe(vapidPublicKey);

  static Future<String?> unsubscribe() => impl.unsubscribe();
}
