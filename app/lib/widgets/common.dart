import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../data/models.dart';

/// بطاقة بيضاء بحدود خفيفة — الوحدة الأساسية في التصميم.
class CardBox extends StatelessWidget {
  const CardBox({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.borderColor = AppColors.line,
    this.color = AppColors.surface,
    this.radius = 18,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color borderColor;
  final Color color;
  final double radius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: BorderSide(color: borderColor),
    );
    return Material(
      color: color,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// شارة حالة ملونة.
class Pill extends StatelessWidget {
  const Pill(this.label, {super.key, required this.fg, required this.bg});

  final String label;
  final Color fg;
  final Color bg;

  factory Pill.urgent(String label) =>
      Pill(label, fg: AppColors.urgent, bg: AppColors.urgentSoft);
  factory Pill.waiting(String label) =>
      Pill(label, fg: AppColors.waiting, bg: AppColors.waitingSoft);
  factory Pill.info(String label) =>
      Pill(label, fg: AppColors.primary, bg: AppColors.primarySoft);
  factory Pill.neutral(String label) =>
      Pill(label, fg: AppColors.subtle, bg: AppColors.neutralSoft);
  factory Pill.done(String label) =>
      Pill(label, fg: AppColors.done, bg: AppColors.doneSoft);

  factory Pill.forRequest(RequestItem r) {
    if (r.isOverdue) {
      final d = r.overdueDays;
      return Pill.urgent(d <= 1 ? 'متأخر' : 'متأخر $d أيام');
    }
    switch (r.status) {
      case RequestStatus.newRequest:
        return Pill.info(r.status.label);
      case RequestStatus.waitingClient:
        return Pill.waiting(r.status.label);
      case RequestStatus.closed:
        return Pill.done(r.status.label);
      default:
        return Pill.neutral(r.status.label);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }
}

/// عنوان قسم مع رابط «عرض الكل».
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.onSeeAll, this.color});

  final String title;
  final VoidCallback? onSeeAll;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: color ?? AppColors.ink,
              ),
            ),
          ),
          if (onSeeAll != null)
            TextButton(onPressed: onSeeAll, child: const Text('عرض الكل')),
        ],
      ),
    );
  }
}

/// حرف أول داخل دائرة.
class Avatar extends StatelessWidget {
  const Avatar(this.letter, {super.key, this.size = 26, this.fg = AppColors.primary, this.bg = AppColors.primarySoft, this.radius});

  final String letter;
  final double size;
  final Color fg;
  final Color bg;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(radius ?? size / 2),
      ),
      child: Text(
        letter,
        style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: size * 0.45),
      ),
    );
  }
}

/// مربع إنجاز المهمة.
class TaskCheck extends StatelessWidget {
  const TaskCheck({super.key, required this.done, required this.onChanged, this.overdue = false});

  final bool done;
  final bool overdue;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final border = done
        ? AppColors.done
        : overdue
            ? const Color(0xFFC2410C)
            : const Color(0xFF9AA2AE);
    return Semantics(
      checked: done,
      button: true,
      label: done ? 'المهمة منجزة' : 'إنجاز المهمة',
      child: InkResponse(
        onTap: () => onChanged(!done),
        radius: 22,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: done ? AppColors.done : Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: border, width: 2),
              ),
              child: done ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
            ),
          ),
        ),
      ),
    );
  }
}

/// شريط تقدم رفيع.
class ProgressLine extends StatelessWidget {
  const ProgressLine(this.value, {super.key, this.color = AppColors.primary, this.height = 6});

  final int value;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: LinearProgressIndicator(
        value: value.clamp(0, 100) / 100,
        minHeight: height,
        color: color,
        backgroundColor: AppColors.divider,
      ),
    );
  }
}

/// حالة فارغة.
class EmptyState extends StatelessWidget {
  const EmptyState(this.message, {super.key, this.icon = Icons.inbox_outlined});

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(icon, size: 36, color: AppColors.muted),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
        ],
      ),
    );
  }
}

/// عرض حالة التحميل أو الخطأ لأي بيانات غير متزامنة.
class AsyncBody<T> extends StatelessWidget {
  const AsyncBody({super.key, required this.value, required this.builder, this.onRetry});

  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    if (value.hasError) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.wifi_off, color: AppColors.muted, size: 36),
            const SizedBox(height: 8),
            const Text('تعذّر تحميل البيانات', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('${value.error}', textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted, fontSize: 12)),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              OutlinedButton(onPressed: onRetry, child: const Text('إعادة المحاولة')),
            ],
          ],
        ),
      );
    }
    if (!value.hasValue) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return builder(value.requireValue);
  }
}

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
