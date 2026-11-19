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

/// ١٤ · الفريق والصلاحيات
class TeamScreen extends ConsumerWidget {
  const TeamScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final team = ref.watch(teamMembersProvider);
    final me = ref.watch(profileProvider).valueOrNull;
    final isOwner = me?.role == UserRole.owner;
    final list = team.valueOrNull ?? const <TeamMember>[];
    final pendingCount = list.where((m) => m.pending && m.isActive).length;

    return Scaffold(
      appBar: sectionAppBar(
        'الفريق والصلاحيات',
        subtitle: '${list.where((m) => !m.pending).length} أعضاء${pendingCount > 0 ? ' · $pendingCount دعوة معلّقة' : ''}',
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(teamMembersProvider),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
          children: [
            if (isOwner) ...[
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: () => showFormSheet(context, const InviteMemberSheet()),
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('إضافة عضو'),
              ),
              const SizedBox(height: 14),
            ],
            Row(
              children: [
                for (final r in UserRole.values) ...[
                  if (r != UserRole.owner) const SizedBox(width: 8),
                  Expanded(
                    child: CardBox(
                      radius: 14,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Column(
                        children: [
                          Text('${list.where((m) => m.role == r && m.isActive && !m.pending).length}',
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                          Text(r.label, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 14),
            AsyncBody<List<TeamMember>>(
              value: team,
              onRetry: () => ref.invalidate(teamMembersProvider),
              builder: (all) {
                final members = all.where((m) => !m.pending || !m.isActive).toList();
                final pending = all.where((m) => m.pending && m.isActive).toList();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CardBox(
                      radius: 16,
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          for (var i = 0; i < members.length; i++) ...[
                            if (i > 0) const Divider(height: 1, color: AppColors.divider),
                            _MemberTile(members[i], isMe: members[i].id == me?.id, canOpen: isOwner),
                          ],
                        ],
                      ),
                    ),
                    if (pending.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Text('دعوات معلّقة', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.subtle)),
                      const SizedBox(height: 8),
                      for (final m in pending) ...[
                        CardBox(
                          radius: 16,
                          borderColor: const Color(0xFFC5CAD3),
                          onTap: isOwner ? () => context.go('/more/team/${m.id}') : null,
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(m.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                                    Text(m.email, textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                                    Text(isOwner ? '${m.role.label} · اضغط لتحديد الصلاحيات' : m.role.label,
                                        style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                                  ],
                                ),
                              ),
                              if (isOwner)
                                OutlinedButton(
                                  onPressed: () => runAction(
                                    context,
                                    () => ref.read(sectionRepoProvider).inviteMember(
                                          email: m.email,
                                          name: m.name,
                                          role: m.role,
                                          jobTitle: m.jobTitle,
                                          resend: true,
                                        ),
                                    success: 'أُعيد إرسال الدعوة',
                                  ),
                                  child: const Text('إعادة إرسال'),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile(this.m, {required this.isMe, required this.canOpen});
  final TeamMember m;
  final bool isMe;
  final bool canOpen;

  @override
  Widget build(BuildContext context) {
    final rolePill = !m.isActive
        ? Pill.urgent('موقوف')
        : switch (m.role) {
            UserRole.owner => Pill('مالك', fg: Colors.white, bg: AppColors.ink),
            UserRole.manager => Pill.info('مدير'),
            UserRole.employee => Pill.neutral('موظف'),
          };
    return ListTile(
      onTap: (canOpen && !isMe) ? () => context.go('/more/team/${m.id}') : null,
      leading: Avatar(
        m.initial,
        size: 40,
        radius: 12,
        fg: m.role == UserRole.owner ? Colors.white : (m.isActive ? AppColors.primary : AppColors.muted),
        bg: m.role == UserRole.owner ? AppColors.primary : (m.isActive ? AppColors.primarySoft : AppColors.neutralSoft),
      ),
      title: Text(isMe ? '${m.name} (أنت)' : m.name,
          style: TextStyle(fontWeight: FontWeight.w600, color: m.isActive ? AppColors.ink : AppColors.muted)),
      subtitle: Text(m.isActive ? (m.jobTitle ?? m.email) : 'الحساب موقوف',
          style: const TextStyle(fontSize: 12, color: AppColors.muted)),
      trailing: rolePill,
    );
  }
}

/// ١٥ · إضافة عضو
class InviteMemberSheet extends ConsumerStatefulWidget {
  const InviteMemberSheet({super.key});

  @override
  ConsumerState<InviteMemberSheet> createState() => _InviteMemberSheetState();
}

class _InviteMemberSheetState extends ConsumerState<InviteMemberSheet> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _job = TextEditingController();
  UserRole _role = UserRole.employee;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _job.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_name.text.trim().isEmpty || !_email.text.contains('@')) {
      showSnack(context, 'أدخل الاسم والبريد الإلكتروني');
      return;
    }
    setState(() => _busy = true);
    final ok = await runAction(
      context,
      () => ref.read(sectionRepoProvider).inviteMember(
            email: _email.text.trim(),
            name: _name.text.trim(),
            role: _role,
            jobTitle: _job.text.trim(),
          ),
      success: 'أُرسلت الدعوة إلى ${_email.text.trim()}',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      ref.invalidate(teamMembersProvider);
      ref.invalidate(teamProvider);
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SheetBody(
      title: 'إضافة عضو للفريق',
      submitLabel: 'إرسال الدعوة',
      busy: _busy,
      onSubmit: _send,
      children: [
        TextField(controller: _name, autofocus: true, decoration: const InputDecoration(labelText: 'الاسم')),
        const SizedBox(height: 12),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          textDirection: TextDirection.ltr,
          decoration: const InputDecoration(labelText: 'البريد الإلكتروني', hintText: 'name@company.sa'),
        ),
        const SizedBox(height: 12),
        TextField(controller: _job, decoration: const InputDecoration(labelText: 'المسمى الوظيفي', hintText: 'مثال: مستشار أول')),
        const SizedBox(height: 14),
        const Text('الدور', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.subtle)),
        const SizedBox(height: 8),
        for (final r in [UserRole.employee, UserRole.manager]) ...[
          _RoleOption(
            role: r,
            selected: _role == r,
            onTap: () => setState(() => _role = r),
          ),
          const SizedBox(height: 8),
        ],
        const Text(
          'يصله بريد برابط لتعيين كلمة المرور والدخول للتطبيق',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: AppColors.muted),
        ),
      ],
    );
  }
}

class _RoleOption extends StatelessWidget {
  const _RoleOption({required this.role, required this.selected, required this.onTap});
  final UserRole role;
  final bool selected;
  final VoidCallback onTap;

  static const _desc = {
    UserRole.employee: 'يرى المسند إليه فقط · يمكن تخصيص صلاحياته لاحقًا',
    UserRole.manager: 'يرى كل الطلبات والمهام · يُسند ويضيف عملاء',
  };

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? AppColors.primarySoft : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: selected ? AppColors.primary : AppColors.line, width: selected ? 2 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off,
                    color: selected ? AppColors.primary : const Color(0xFF9AA2AE)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(role.label, style: TextStyle(fontSize: 14, fontWeight: selected ? FontWeight.w700 : FontWeight.w600)),
                      Text(_desc[role]!, style: const TextStyle(fontSize: 12, color: AppColors.subtle)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// ١٦ · صلاحيات العضو: الدور + تشغيل وإيقاف كل صلاحية على حدة
class MemberScreen extends ConsumerWidget {
  const MemberScreen({super.key, required this.memberId});
  final String memberId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final team = ref.watch(teamMembersProvider);
    final repo = ref.read(sectionRepoProvider);

    Future<void> savePermissions(TeamMember m, String key, bool value) async {
      final overrides = <String, bool>{
        for (final e in m.permissions.entries)
          if (e.value is bool) e.key: e.value as bool,
      };
      if (value == Permissions.roleDefault(m.role, key)) {
        overrides.remove(key);
      } else {
        overrides[key] = value;
      }
      if (await runAction(context, () => repo.setMemberPermissions(m.id, overrides))) {
        ref.invalidate(teamMembersProvider);
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('صلاحيات العضو'), centerTitle: true),
      body: AsyncBody<List<TeamMember>>(
        value: team,
        onRetry: () => ref.invalidate(teamMembersProvider),
        builder: (all) {
          final m = all.where((x) => x.id == memberId).firstOrNull;
          if (m == null) return const EmptyState('العضو غير موجود');
          final customized = Permissions.all.where((p) => m.isCustomized(p.key)).length;
          final groups = <String, List<Permission>>{};
          for (final p in Permissions.all) {
            groups.putIfAbsent(p.group, () => []).add(p);
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
            children: [
              CardBox(
                radius: 20,
                child: Row(
                  children: [
                    Avatar(m.initial, size: 56, radius: 18, fg: AppColors.done, bg: AppColors.doneSoft),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(m.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                          if (m.jobTitle != null) Text(m.jobTitle!, style: const TextStyle(fontSize: 13, color: AppColors.muted)),
                          Text(m.email, textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _Stat('${m.openTasks}', 'مهام مفتوحة')),
                  const SizedBox(width: 8),
                  Expanded(child: _Stat('${m.openRequests}', 'طلبات مسندة')),
                ],
              ),
              const SizedBox(height: 14),
              const Text('الدور', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.subtle)),
              const SizedBox(height: 4),
              const Text('يحدد الصلاحيات الافتراضية، ويمكنك تخصيصها بالأسفل',
                  style: TextStyle(fontSize: 12, color: AppColors.muted)),
              const SizedBox(height: 8),
              SegmentedButton<UserRole>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: UserRole.employee, label: Text('موظف')),
                  ButtonSegment(value: UserRole.manager, label: Text('مدير')),
                ],
                selected: {m.role == UserRole.owner ? UserRole.manager : m.role},
                onSelectionChanged: m.role == UserRole.owner
                    ? null
                    : (s) async {
                        if (await runAction(context, () => repo.setMemberRole(m.id, s.first),
                            success: 'تم تغيير الدور إلى ${s.first.label}')) {
                          ref.invalidate(teamMembersProvider);
                        }
                      },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Expanded(
                    child: Text('الصلاحيات', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.subtle)),
                  ),
                  if (customized > 0)
                    TextButton(
                      onPressed: () async {
                        if (await runAction(context, () => repo.setMemberPermissions(m.id, {}),
                            success: 'أُعيدت الصلاحيات الافتراضية لدور ${m.role.label}')) {
                          ref.invalidate(teamMembersProvider);
                        }
                      },
                      child: Text('إعادة الافتراضي ($customized)'),
                    ),
                ],
              ),
              for (final g in groups.entries) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 6),
                  child: Text(g.key, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.muted)),
                ),
                CardBox(
                  radius: 16,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    children: [
                      for (var i = 0; i < g.value.length; i++) ...[
                        if (i > 0) const Divider(height: 1, color: AppColors.divider),
                        SwitchListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                          value: m.can(g.value[i].key),
                          onChanged: m.role == UserRole.owner ? null : (v) => savePermissions(m, g.value[i].key, v),
                          title: Row(
                            children: [
                              Flexible(child: Text(g.value[i].label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
                              if (m.isCustomized(g.value[i].key)) ...[
                                const SizedBox(width: 6),
                                Pill.info('مخصص'),
                              ],
                            ],
                          ),
                          subtitle: Text(g.value[i].description, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 6),
              ],
              const SizedBox(height: 10),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: m.isActive ? AppColors.urgent : AppColors.done,
                  side: BorderSide(color: m.isActive ? AppColors.urgentBorder : AppColors.done),
                  minimumSize: const Size.fromHeight(46),
                ),
                onPressed: () async {
                  final ok = await confirmAction(
                    context,
                    title: m.isActive ? 'إيقاف حساب ${m.name}؟' : 'إعادة تفعيل ${m.name}؟',
                    message: m.isActive
                        ? 'لن يستطيع الدخول أو رؤية أي بيانات. مهامه وطلباته تبقى كما هي ويمكن إسنادها لغيره.'
                        : 'سيستطيع الدخول مجددًا بنفس الدور والصلاحيات.',
                    confirmLabel: m.isActive ? 'إيقاف' : 'تفعيل',
                    destructive: m.isActive,
                  );
                  if (!ok || !context.mounted) return;
                  if (await runAction(context, () => repo.setMemberActive(m.id, !m.isActive))) {
                    ref.invalidate(teamMembersProvider);
                  }
                },
                child: Text(m.isActive ? 'إيقاف الحساب' : 'إعادة تفعيل الحساب'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label);
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => CardBox(
        radius: 14,
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            Text(label, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          ],
        ),
      );
}
