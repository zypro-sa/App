import 'dart:js_interop';

@JS('zyproDownload')
external void _download(JSString name, JSString text, JSString mime);

@JS('zyproShare')
external JSPromise<JSString> _share(JSString title, JSString text);

@JS('zyproPrintHtml')
external void _print(JSString html);

@JS('zyproFullscreen')
external void _fullscreen(JSBoolean on);

void download(String name, String text, String mime) {
  try {
    _download(name.toJS, text.toJS, mime.toJS);
  } catch (_) {}
}

Future<String> share(String title, String text) async {
  try {
    return (await _share(title.toJS, text.toJS).toDart).toDart;
  } catch (_) {
    return 'failed';
  }
}

void printHtml(String html) {
  try {
    _print(html.toJS);
  } catch (_) {}
}

void fullscreen(bool on) {
  try {
    _fullscreen(on.toJS);
  } catch (_) {}
}

@JS('zyproSessionFlag')
external JSBoolean _sessionFlag(JSBoolean set);

@JS('zyproBioAvailable')
external JSPromise<JSBoolean> _bioAvailable();

@JS('zyproBioRegister')
external JSPromise<JSString> _bioRegister(JSString userId, JSString name);

@JS('zyproBioVerify')
external JSPromise<JSString> _bioVerify(JSString id);

bool sessionFlag(bool set) {
  try {
    return _sessionFlag(set.toJS).toDart;
  } catch (_) {
    return true;
  }
}

Future<bool> bioAvailable() async {
  try {
    return (await _bioAvailable().toDart).toDart;
  } catch (_) {
    return false;
  }
}

Future<String> bioRegister(String userId, String name) async {
  try {
    return (await _bioRegister(userId.toJS, name.toJS).toDart).toDart;
  } catch (_) {
    return 'error:unknown';
  }
}

Future<String> bioVerify(String credentialId) async {
  try {
    return (await _bioVerify(credentialId.toJS).toDart).toDart;
  } catch (_) {
    return 'error:unknown';
  }
}

@JS('zyproBioSeal')
external JSPromise<JSString> _bioSeal(JSString id, JSString text);

@JS('zyproBioOpen')
external JSPromise<JSString> _bioOpen(JSString id, JSString sealed);

Future<String> bioSeal(String credentialId, String text) async {
  try {
    return (await _bioSeal(credentialId.toJS, text.toJS).toDart).toDart;
  } catch (_) {
    return 'error:unknown';
  }
}

Future<String> bioOpen(String credentialId, String sealed) async {
  try {
    return (await _bioOpen(credentialId.toJS, sealed.toJS).toDart).toDart;
  } catch (_) {
    return 'error:unknown';
  }
}
