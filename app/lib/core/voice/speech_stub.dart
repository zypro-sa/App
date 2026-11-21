bool supported() => false;

void start(String lang, bool continuous, void Function(String) onPartial, void Function(String) onDone,
    void Function(String) onError) {
  onError('unsupported');
  onDone('');
}

void stop() {}
