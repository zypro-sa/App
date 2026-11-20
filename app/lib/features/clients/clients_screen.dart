import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/permissions.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../data/section_models.dart';
import '../../data/section_repository.dart';
import '../../widgets/common.dart';
import '../../widgets/forms.dart';
import '../../core/i18n.dart';

/// قائمة العملاء
class ClientsScreen extends ConsumerStatefulWidget {
  const ClientsScreen({super.key});

  @override
  ConsumerState<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends ConsumerState<ClientsScreen> {
  String _query = '';

  Future<void> _addClient() async {
    final id = await showFormSheet<String>(context, const NewClientSheet());
    if (id != null && mounted) context.go('/more/clients/$id');
  }

  @override
  Widget build(BuildContext context) {
    final clients = ref.watch(clientsProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('العملاء')),
        actions: [
          if (ref.watch(profileProvider).valueOrNull?.can(Permissions.clientsManage) ?? false)
            IconButton(tooltip: tr('عميل جديد'), onPressed: _addClient, icon: const Icon(Icons.person_add_alt)),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
        children: [
          TextField(
            decoration: InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: tr('ابحث عن عميل'),
            ),
            onChanged: (v) => setState(() => _query = v.trim()),
          ),
          const SizedBox(height: 14),
          AsyncBody<List<Client>>(
            value: clients,
            onRetry: () => ref.invalidate(clientsProvider),
            builder: (list) {
              final filtered = _query.isEmpty ? list : list.where((c) => c.name.contains(_query)).toList();
              if (filtered.isEmpty) return EmptyState(tr('لا يوجد عملاء'), icon: Icons.people_outline);
              return CardBox(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < filtered.length; i++) ...[
                      if (i > 0) Divider(height: 1, color: AppColors.divider),
                      ListTile(
                        leading: Avatar(filtered[i].initial, size: 40, radius: 12),
                        title: Text(filtered[i].name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          [filtered[i].sector, filtered[i].city].whereType<String>().join(' · '),
                          style: TextStyle(color: AppColors.muted, fontSize: 12),
                        ),
                        trailing: Icon(AppIcons.forward, color: AppColors.faint),
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

/// نافذة عميل جديد (تحترم إعدادات الحقول والحقول المخصصة).
class NewClientSheet extends ConsumerStatefulWidget {
  const NewClientSheet({super.key});

  @override
  ConsumerState<NewClientSheet> createState() => _NewClientSheetState();
}

class _NewClientSheetState extends ConsumerState<NewClientSheet> {
  final _name = TextEditingController();
  String? _sector;
  String? _city;
  String? _cr;
  String? _vat;
  final Map<String, dynamic> _custom = {};
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save(FieldConfig cfg) async {
    bool req(String k) => cfg.isVisible(k) && cfg.isRequired(k);
    final missing = _name.text.trim().isEmpty
        ? tr('اكتب اسم العميل')
        : (req('sector') && _sector == null)
            ? tr('اختر {0}', [cfg.labelOf('sector', tr('القطاع'))])
            : (req('city') && (_city ?? '').isEmpty)
                ? tr('أدخل {0}', [cfg.labelOf('city', tr('المدينة'))])
                : (req('cr_number') && (_cr ?? '').isEmpty)
                    ? tr('أدخل {0}', [cfg.labelOf('cr_number', tr('السجل التجاري'))])
                    : (req('vat_number') && (_vat ?? '').isEmpty)
                        ? tr('أدخل {0}', [cfg.labelOf('vat_number', tr('الرقم الضريبي'))])
                        : missingRequired(cfg.customVisible, _custom);
    if (missing != null) {
      showSnack(context, missing);
      return;
    }
    setState(() => _busy = true);
    String? id;
    final ok = await runAction(context, () async {
      id = await ref.read(repositoryProvider).createClient(
            _name.text.trim(),
            sector: _sector,
            city: _city,
            crNumber: _cr,
            vatNumber: _vat,
            custom: Map.of(_custom),
          );
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      refreshSections(ref);
      Navigator.pop(context, id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfg = ref.watch(fieldConfigProvider(ConfigEntity.client)).valueOrNull ?? FieldConfig(const []);
    String star(String k, String l) => cfg.isRequired(k) ? '${cfg.labelOf(k, l)} *' : cfg.labelOf(k, l);

    Widget textRow(String key, String label, String? value, ValueChanged<String> set) => FormRow(
          label: star(key, label),
          value: value ?? tr('أدخل'),
          muted: value == null,
          onTap: () async {
            final v = await promptText(context, cfg.labelOf(key, label), initial: value);
            if (v != null) setState(() => set(v));
          },
        );

    return SheetBody(
      title: tr('عميل جديد'),
      busy: _busy,
      onSubmit: () => _save(cfg),
      children: [
        TextField(controller: _name, autofocus: true, decoration: InputDecoration(labelText: cfg.labelOf('name', tr('اسم الشركة أو الجهة')))),
        const SizedBox(height: 14),
        FormCard(children: [
          if (cfg.isVisible('sector'))
            FormDropdown<String>(
              label: star('sector', tr('القطاع')),
              value: _sector,
              items: {for (final o in cfg.optionsOf('sector')) o: o},
              onChanged: (v) => setState(() => _sector = v),
            ),
          if (cfg.isVisible('city')) textRow('city', tr('المدينة'), _city, (v) => _city = v),
          if (cfg.isVisible('cr_number')) textRow('cr_number', tr('السجل التجاري'), _cr, (v) => _cr = v),
          if (cfg.isVisible('vat_number')) textRow('vat_number', tr('الرقم الضريبي'), _vat, (v) => _vat = v),
          ...customFieldRows(
            context: context,
            fields: cfg.customVisible,
            values: _custom,
            onChanged: (k, v) => setState(() => _custom[k] = v),
          ),
        ]),
      ],
    );
  }
}
