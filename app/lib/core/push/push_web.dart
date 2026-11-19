import 'dart:js_interop';

@JS('zyproPushSupported')
external JSBoolean _supported();

@JS('zyproPushPermission')
external JSString _permission();

@JS('zyproPushStandalone')
external JSBoolean _standalone();

@JS('zyproPushSubscribe')
external JSPromise<JSString> _subscribe(JSString key);

@JS('zyproPushUnsubscribe')
external JSPromise<JSString> _unsubscribe();

bool supported() {
  try {
    return _supported().toDart;
  } catch (_) {
    return false;
  }
}

String permission() {
  try {
    return _permission().toDart;
  } catch (_) {
    return 'unsupported';
  }
}

bool standalone() {
  try {
    return _standalone().toDart;
  } catch (_) {
    return false;
  }
}

Future<String?> subscribe(String key) async {
  final s = (await _subscribe(key.toJS).toDart).toDart;
  return s.isEmpty ? null : s;
}

Future<String?> unsubscribe() async {
  final s = (await _unsubscribe().toDart).toDart;
  return s.isEmpty ? null : s;
}
