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
