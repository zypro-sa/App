void download(String name, String text, String mime) {}
Future<String> share(String title, String text) async => 'failed';
void printHtml(String html) {}
void fullscreen(bool on) {}
bool sessionFlag(bool set) => true;
Future<bool> bioAvailable() async => false;
Future<String> bioRegister(String userId, String name) async => 'error:unsupported';
Future<String> bioVerify(String credentialId) async => 'error:unsupported';
