import 'package:flutter/material.dart';

import 'i18n.dart';

// ---------------- إخفاء المبالغ ----------------
/// المبالغ مخفية افتراضيًا عند فتح التطبيق، وتظهر بزر العين
final amountsHidden = ValueNotifier<bool>(true);
bool _revealForExport = false;
const hiddenAmount = '*****';
/// هل تُعرض المبالغ مخفية الآن؟
bool get amountsMasked => amountsHidden.value && !_revealForExport;

/// تنفيذ دالة بالمبالغ ظاهرة (للتصدير والطباعة)
T withAmountsShown<T>(T Function() f) {
  _revealForExport = true;
  try {
    return f();
  } finally {
    _revealForExport = false;
  }
}

/// زر إظهار/إخفاء المبالغ
class AmountsToggle extends StatelessWidget {
  const AmountsToggle({super.key, this.color, this.size});
  final Color? color;
  final double? size;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: amountsHidden,
        builder: (context, hidden, _) => IconButton(
          tooltip: hidden ? tr('إظهار المبالغ') : tr('إخفاء المبالغ'),
          iconSize: size,
          color: color,
          icon: Icon(hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined),
          onPressed: () => amountsHidden.value = !hidden,
        ),
      );
}

/// يعيد بناء كل ما بداخله عند إظهار/إخفاء المبالغ (مع الحفاظ على حالة الشاشة)
class AmountsScope extends StatefulWidget {
  const AmountsScope({super.key, required this.child});
  final Widget child;

  @override
  State<AmountsScope> createState() => _AmountsScopeState();
}

class _AmountsScopeState extends State<AmountsScope> {
  void _changed() {
    if (!mounted) return;
    void rebuild(Element e) {
      e.markNeedsBuild();
      e.visitChildren(rebuild);
    }

    (context as Element).visitChildren(rebuild);
  }

  @override
  void initState() {
    super.initState();
    amountsHidden.addListener(_changed);
  }

  @override
  void dispose() {
    amountsHidden.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

