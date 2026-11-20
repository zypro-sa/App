import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_settings.dart';
import '../core/i18n.dart';
import '../core/theme.dart';

/// زرّان سريعان: تبديل المظهر (فاتح/داكن) وتبديل اللغة.
class DisplayToggles extends ConsumerWidget {
  const DisplayToggles({super.key, this.showTheme = true});
  final bool showTheme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(appSettingsProvider.notifier);
    ref.watch(appSettingsProvider);
    final isDark = AppColors.dark;
    final style = IconButton.styleFrom(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.ink,
      side: BorderSide(color: AppColors.line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      fixedSize: const Size(38, 38),
      minimumSize: const Size(38, 38),
      padding: EdgeInsets.zero,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showTheme) ...[
          IconButton(
            tooltip: isDark ? tr('المظهر الفاتح') : tr('المظهر الداكن'),
            style: style,
            iconSize: 20,
            onPressed: () => notifier.toggleTheme(isDark ? Brightness.dark : Brightness.light),
            icon: Icon(isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
          ),
          const SizedBox(width: 6),
        ],
        IconButton(
          tooltip: L.isEn ? 'العربية' : 'English',
          style: style,
          onPressed: () => notifier.setLocale(L.isEn ? 'ar' : 'en'),
          icon: Text(
            L.isEn ? 'ع' : 'EN',
            style: TextStyle(fontSize: L.isEn ? 16 : 13, fontWeight: FontWeight.w700, color: AppColors.ink),
          ),
        ),
      ],
    );
  }
}
