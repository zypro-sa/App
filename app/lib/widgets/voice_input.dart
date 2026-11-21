import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../core/theme.dart';
import '../core/voice/speech.dart';

/// يفتح نافذة الاستماع ويعيد النص المنطوق (أو null عند الإلغاء/التعذّر).
Future<String?> listenForSpeech(BuildContext context, {bool continuous = false}) {
  if (!Speech.supported) {
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      builder: (_) => const _KeyboardMicHint(),
    );
  }
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isDismissible: false,
    backgroundColor: AppColors.surface,
    builder: (_) => _ListenSheet(continuous: continuous),
  );
}

class _ListenSheet extends StatefulWidget {
  const _ListenSheet({required this.continuous});
  final bool continuous;

  @override
  State<_ListenSheet> createState() => _ListenSheetState();
}

class _ListenSheetState extends State<_ListenSheet> {
  String _text = '';
  String? _error;
  bool _listening = true;
  bool _cancelled = false;

  @override
  void initState() {
    super.initState();
    Speech.start(
      lang: L.isEn ? 'en-US' : 'ar-SA',
      continuous: widget.continuous,
      onPartial: (t) {
        if (mounted) setState(() => _text = t);
      },
      onDone: (t) {
        if (!mounted) return;
        final result = (t.isNotEmpty ? t : _text).trim();
        setState(() => _listening = false);
        if (_cancelled) return;
        if (_error == null && result.isNotEmpty) Navigator.pop(context, result);
      },
      onError: (e) {
        if (!mounted || e == 'aborted') return;
        setState(() => _error = e == 'no-speech' ? tr('لم أسمع شيئًا. حاول مرة أخرى.') : e);
      },
    );
  }

  @override
  void dispose() {
    Speech.stop();
    super.dispose();
  }

  bool get _blocked => _error != null && _error!.contains('not-allowed') || _error == 'service-not-allowed' || _error == 'start-failed';

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: _listening ? AppColors.accent : AppColors.neutralSoft,
                  shape: BoxShape.circle,
                ),
                child: Icon(_listening ? Icons.mic : Icons.mic_off_outlined,
                    size: 36, color: _listening ? AppColors.onAccent : AppColors.muted),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              _blocked
                  ? tr('الميكروفون غير متاح هنا')
                  : _listening
                      ? tr('تحدّث الآن…')
                      : tr('توقّف الاستماع'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            if (_blocked)
              Text(
                tr('على الآيفون قد لا يعمل الاستماع داخل التطبيق المثبّت. اضغط ميكروفون لوحة المفاتيح 🎤 بجانب المسافة وتحدّث، ثم اضغط «تعبئة الحقول من النص».'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppColors.muted, height: 1.6),
              )
            else
              Container(
                constraints: const BoxConstraints(minHeight: 60),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(14)),
                child: Text(
                  _text.isEmpty
                      ? (_error ?? tr('مثال: ذكّرني أتصل بالعميل بكرة الساعة عشرة'))
                      : _text,
                  style: TextStyle(fontSize: 15, color: _text.isEmpty ? AppColors.muted : AppColors.ink, height: 1.5),
                ),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      _cancelled = true;
                      Speech.stop();
                      Navigator.pop(context);
                    },
                    child: Text(_blocked ? tr('حسنًا') : tr('إلغاء')),
                  ),
                ),
                if (!_blocked) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        if (_listening) {
                          Speech.stop();
                          if (_text.trim().isNotEmpty) Navigator.pop(context, _text.trim());
                        } else if (_text.trim().isNotEmpty) {
                          Navigator.pop(context, _text.trim());
                        } else {
                          Navigator.pop(context);
                        }
                      },
                      child: Text(tr('تم')),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _KeyboardMicHint extends StatelessWidget {
  const _KeyboardMicHint();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.keyboard_voice_outlined, size: 40, color: AppColors.accentText),
            const SizedBox(height: 10),
            Text(tr('استخدم ميكروفون لوحة المفاتيح'),
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              tr('اضغط في خانة النص، ثم زر 🎤 في لوحة المفاتيح وتحدّث. بعدها اضغط «تعبئة الحقول من النص» ليُعبّئ التطبيق الموعد والعميل تلقائيًا.'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.muted, height: 1.6),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: () => Navigator.pop(context), child: Text(tr('حسنًا'))),
          ],
        ),
      ),
    );
  }
}
