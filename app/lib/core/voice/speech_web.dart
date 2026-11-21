import 'dart:js_interop';

@JS('zyproSpeechSupported')
external JSBoolean _supported();

@JS('zyproSpeechStart')
external void _start(JSString lang, JSBoolean continuous, JSFunction onPartial, JSFunction onDone, JSFunction onError);

@JS('zyproSpeechStop')
external void _stop();

bool supported() {
  try {
    return _supported().toDart;
  } catch (_) {
    return false;
  }
}

void start(String lang, bool continuous, void Function(String) onPartial, void Function(String) onDone,
    void Function(String) onError) {
  try {
    _start(
      lang.toJS,
      continuous.toJS,
      ((JSString s) => onPartial(s.toDart)).toJS,
      ((JSString s) => onDone(s.toDart)).toJS,
      ((JSString s) => onError(s.toDart)).toJS,
    );
  } catch (e) {
    onError('$e');
    onDone('');
  }
}

void stop() {
  try {
    _stop();
  } catch (_) {}
}
