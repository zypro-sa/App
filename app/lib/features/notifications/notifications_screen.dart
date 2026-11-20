import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/section_models.dart';
import '../../data/section_repository.dart';
import '../../widgets/common.dart';
import '../../widgets/forms.dart';
import '../../core/i18n.dart';

/// مركز الإشعارات
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  static IconData iconFor(String type) => switch (type) {
        'meeting_soon' => Icons.event_outlined,
        'task_due' => Icons.check_box_outlined,
        'request_overdue' => Icons.inbox_outlined,
        'followup_due' => Icons.schedule,
        'assigned' => Icons.person_add_alt,
        'quote_no_reply' => Icons.request_quote_outlined,
        _ => Icons.notifications_none,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(notificationsProvider);
    final unread = ref.watch(unreadNotificationsProvider);
    final repo = ref.read(sectionRepoProvider);

    return Scaffold(
      appBar: sectionAppBar(
        tr('الإشعارات'),
        subtitle: unread > 0 ? tr('{0} غير مقروءة', [unread]) : tr('لا جديد'),
        actions: [
          IconButton(
            tooltip: tr('إعدادات الإشعارات'),
            onPressed: () => context.go('/more/notifications'),
            icon: const Icon(Icons.tune),
          ),
          PopupMenuButton<String>(
            tooltip: tr('خيارات'),
            onSelected: (v) async {
              final action = v == 'read' ? repo.markAllNotificationsRead : repo.clearReadNotifications;
              if (await runAction(context, action)) ref.invalidate(notificationsProvider);
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'read', child: Text(tr('تعليم الكل كمقروء'))),
              PopupMenuItem(value: 'clear', child: Text(tr('حذف المقروءة'))),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(notificationsProvider),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
          children: [
            AsyncBody<List<NotificationItem>>(
              value: items,
              onRetry: () => ref.invalidate(notificationsProvider),
              builder: (list) {
                if (list.isEmpty) {
                  return EmptyState(tr('لا توجد إشعارات بعد.\nستظهر هنا التذكيرات والإسنادات الجديدة.'),
                      icon: Icons.notifications_none);
                }
                return CardBox(
                  radius: 16,
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (var i = 0; i < list.length; i++) ...[
                        if (i > 0) Divider(height: 1, color: AppColors.divider),
                        _NotificationTile(list[i]),
                      ],
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationTile extends ConsumerWidget {
  const _NotificationTile(this.n);
  final NotificationItem n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      color: n.isRead ? AppColors.surface : AppColors.primarySoft.withValues(alpha: 0.55),
      child: InkWell(
        onTap: () async {
          if (!n.isRead) {
            await ref.read(sectionRepoProvider).markNotificationRead(n.id);
            ref.invalidate(notificationsProvider);
          }
          if (n.url != null && n.url!.startsWith('/') && context.mounted) context.go(n.url!);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: n.isRead ? AppColors.neutralSoft : AppColors.ink,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(NotificationsScreen.iconFor(n.type),
                    size: 20, color: n.isRead ? AppColors.muted : AppColors.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(n.title,
                        style: TextStyle(fontSize: 14, fontWeight: n.isRead ? FontWeight.w500 : FontWeight.w700)),
                    if (n.body != null && n.body!.isNotEmpty)
                      Text(n.body!, style: TextStyle(fontSize: 13, color: AppColors.subtle, height: 1.5)),
                    const SizedBox(height: 2),
                    Text('${relativeDay(n.createdAt)} · ${formatTime(n.createdAt)}',
                        style: TextStyle(fontSize: 11, color: AppColors.muted)),
                  ],
                ),
              ),
              if (!n.isRead)
                Container(
                  margin: const EdgeInsets.only(top: 6),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
