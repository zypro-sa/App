import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters.dart';
import '../../core/permissions.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../data/section_models.dart';
import '../../data/section_repository.dart';
import '../../widgets/common.dart';
import '../../widgets/forms.dart';

/// ٩ · المشاريع
class ProjectsScreen extends ConsumerStatefulWidget {
  const ProjectsScreen({super.key});

  @override
  ConsumerState<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends ConsumerState<ProjectsScreen> {
  ProjectStatus _status = ProjectStatus.active;

  @override
  Widget build(BuildContext context) {
    final projects = ref.watch(projectsProvider(_status));
    final counts = ref.watch(projectCountsProvider).valueOrNull ?? const {};
    final labels = {
      for (final l in ref.watch(statusLabelsProvider(ConfigEntity.project)).valueOrNull ?? const <StatusLabel>[])
        l.status: l,
    };
    final active = counts[ProjectStatus.active] ?? 0;
    final soon = projects.valueOrNull?.where((p) => (p.daysLeft ?? 99) <= 7 && (p.daysLeft ?? -1) >= 0).length ?? 0;
    final canCreate = ref.watch(profileProvider).valueOrNull?.can(Permissions.projectsManage) ?? false;

    return Scaffold(
      appBar: sectionAppBar(
        'المشاريع',
        subtitle: '$active مشاريع جارية${soon > 0 ? ' · $soon يقترب موعده' : ''}',
        actions: [
          if (canCreate)
            IconButton.filled(
              tooltip: 'مشروع جديد',
              onPressed: () => showFormSheet(context, const NewProjectSheet()),
              icon: const Icon(Icons.add),
              style: IconButton.styleFrom(backgroundColor: AppColors.ink),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => refreshSections(ref),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
          children: [
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: ProjectStatus.values.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final s = ProjectStatus.values[i];
                  final sel = s == _status;
                  return ChoiceChip(
                    label: Text('${labels[s.db]?.label ?? s.label} ${counts[s] ?? 0}'),
                    selected: sel,
                    showCheckmark: false,
                    selectedColor: AppColors.ink,
                    labelStyle: TextStyle(color: sel ? Colors.white : AppColors.ink, fontWeight: sel ? FontWeight.w600 : FontWeight.w400),
                    onSelected: (_) => setState(() => _status = s),
                  );
                },
              ),
            ),
            const SizedBox(height: 14),
            AsyncBody<List<Project>>(
              value: projects,
              onRetry: () => ref.invalidate(projectsProvider(_status)),
              builder: (list) => list.isEmpty
                  ? const EmptyState('لا توجد مشاريع هنا', icon: Icons.folder_open)
                  : Column(
                      children: [
                        for (final p in list) ...[
                          _ProjectCard(p),
                          const SizedBox(height: 12),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard(this.p);
  final Project p;

  @override
  Widget build(BuildContext context) {
    final days = p.daysLeft;
    final urgent = days != null && days >= 0 && days <= 7 && p.status == ProjectStatus.active;
    final late = days != null && days < 0 && p.status == ProjectStatus.active;
    return CardBox(
      borderColor: (urgent || late) ? AppColors.urgentBorder : AppColors.line,
      onTap: () => context.go('/more/projects/${p.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(p.clientName ?? '', style: const TextStyle(fontSize: 12, color: AppColors.muted))),
              if (late)
                Pill.urgent('متأخر ${-days} يومًا')
              else if (urgent)
                Pill.urgent(days == 0 ? 'التسليم اليوم' : 'التسليم بعد $days أيام')
              else if (p.endDate != null)
                Pill.neutral('ينتهي ${formatShortDate(p.endDate!)}'),
            ],
          ),
          const SizedBox(height: 8),
          Text(p.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: ProgressLine(p.progress, height: 8)),
              const SizedBox(width: 10),
              Text('${p.progress}٪', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  p.nextMilestone != null
                      ? 'المرحلة التالية: ${p.nextMilestone}'
                      : (p.milestonesTotal > 0 ? '${p.milestonesDone} من ${p.milestonesTotal} مراحل' : 'لم تُضف مراحل بعد'),
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ),
              if (p.managerName != null && p.managerName!.isNotEmpty) Avatar(p.managerName!.substring(0, 1)),
            ],
          ),
        ],
      ),
    );
  }
}

/// نافذة مشروع جديد.
class NewProjectSheet extends ConsumerStatefulWidget {
  const NewProjectSheet({super.key, this.clientId});
  final String? clientId;

  @override
  ConsumerState<NewProjectSheet> createState() => _NewProjectSheetState();
}

class _NewProjectSheetState extends ConsumerState<NewProjectSheet> {
  final _name = TextEditingController();
  late String? _clientId = widget.clientId;
  String? _managerId;
  DateTime? _end;
  num? _value;
  final Map<String, dynamic> _custom = {};
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save(FieldConfig cfg) async {
    final missing = _name.text.trim().isEmpty
        ? 'اكتب اسم المشروع'
        : _clientId == null
            ? 'اختر العميل'
            : (cfg.isRequired('end_date') && _end == null)
                ? 'حدّد تاريخ التسليم'
                : (cfg.isRequired('contract_value') && _value == null)
                    ? 'أدخل قيمة العقد'
                    : missingRequired(cfg.customVisible, _custom);
    if (missing != null) {
      showSnack(context, missing);
      return;
    }
    setState(() => _busy = true);
    final repo = ref.read(sectionRepoProvider);
    String? id;
    final ok = await runAction(context, () async {
      id = await repo.createProject(
        name: _name.text.trim(),
        clientId: _clientId!,
        managerId: _managerId,
        endDate: _end,
        contractValue: _value,
        custom: _custom,
      );
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      refreshSections(ref);
      Navigator.pop(context);
      if (id != null) context.go('/more/projects/$id');
    }
  }

  @override
  Widget build(BuildContext context) {
    final clients = ref.watch(clientsProvider).valueOrNull ?? const <Client>[];
    final team = ref.watch(teamProvider).valueOrNull ?? const <Profile>[];
    final cfg = ref.watch(fieldConfigProvider(ConfigEntity.project)).valueOrNull ?? FieldConfig(const []);

    return SheetBody(
      title: 'مشروع جديد',
      busy: _busy,
      onSubmit: () => _save(cfg),
      children: [
        TextField(
          controller: _name,
          autofocus: true,
          decoration: InputDecoration(labelText: cfg.labelOf('name', 'اسم المشروع')),
        ),
        const SizedBox(height: 14),
        FormCard(children: [
          FormDropdown<String>(
            label: '${cfg.labelOf('client_id', 'العميل')} *',
            value: _clientId,
            items: {for (final c in clients) c.id: c.name},
            onChanged: (v) => setState(() => _clientId = v),
          ),
          FormDropdown<String>(
            label: 'مدير المشروع',
            value: _managerId,
            emptyLabel: 'أنا',
            items: {for (final p in team) p.id: p.name},
            onChanged: (v) => setState(() => _managerId = v),
          ),
          if (cfg.isVisible('end_date'))
            FormRow(
              label: cfg.labelOf('end_date', 'تاريخ التسليم'),
              value: _end == null ? 'اختر' : formatShortDate(_end!),
              onTap: () async {
                final d = await pickDate(context, initial: _end);
                if (d != null) setState(() => _end = d);
              },
            ),
          if (cfg.isVisible('contract_value'))
            FormRow(
              label: cfg.labelOf('contract_value', 'قيمة العقد'),
              value: _value == null ? 'أدخل' : money(_value!),
              onTap: () async {
                final v = await promptNumber(context, 'قيمة العقد', label: 'بالريال');
                if (v != null) setState(() => _value = v);
              },
            ),
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
