import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../widgets/common.dart';

/// قائمة العملاء
class ClientsScreen extends ConsumerStatefulWidget {
  const ClientsScreen({super.key});

  @override
  ConsumerState<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends ConsumerState<ClientsScreen> {
  String _query = '';

  Future<void> _addClient() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('عميل جديد'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'اسم الشركة أو الجهة'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('إضافة')),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    try {
      final id = await ref.read(repositoryProvider).createClient(name);
      refreshAll(ref);
      if (mounted) context.go('/more/clients/$id');
    } catch (e) {
      if (mounted) showSnack(context, 'تعذّرت الإضافة (تحتاج صلاحية مدير): $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final clients = ref.watch(clientsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('العملاء'),
        actions: [
          IconButton(tooltip: 'عميل جديد', onPressed: _addClient, icon: const Icon(Icons.person_add_alt)),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
        children: [
          TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'ابحث عن عميل',
            ),
            onChanged: (v) => setState(() => _query = v.trim()),
          ),
          const SizedBox(height: 14),
          AsyncBody<List<Client>>(
            value: clients,
            onRetry: () => ref.invalidate(clientsProvider),
            builder: (list) {
              final filtered = _query.isEmpty ? list : list.where((c) => c.name.contains(_query)).toList();
              if (filtered.isEmpty) return const EmptyState('لا يوجد عملاء', icon: Icons.people_outline);
              return CardBox(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < filtered.length; i++) ...[
                      if (i > 0) const Divider(height: 1, color: AppColors.divider),
                      ListTile(
                        leading: Avatar(filtered[i].initial, size: 40, radius: 12),
                        title: Text(filtered[i].name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          [filtered[i].sector, filtered[i].city].whereType<String>().join(' · '),
                          style: const TextStyle(color: AppColors.muted, fontSize: 12),
                        ),
                        trailing: const Icon(Icons.chevron_left, color: Color(0xFF9AA2AE)),
                        onTap: () => context.go('/more/clients/${filtered[i].id}'),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
