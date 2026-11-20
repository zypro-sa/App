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
        tr('الفريق والصلاحيات'),
        subtitle: tr('{0} أعضاء{1}', [list.where((m) => !m.pending).length, pendingCount > 0 ? tr(' · {0} دعوة معلّقة', [pendingCount]) : '']),
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
                label: Text(tr('إضافة عضو')),
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
                          Text(r.label, style: TextStyle(fontSize: 12, color: AppColors.muted)),
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
                            if (i > 0) Divider(height: 1, color: AppColors.divider),
                            _MemberTile(members[i], isMe: members[i].id == me?.id, canOpen: isOwner),
                          ],
                        ],
                      ),
                    ),
                    if (pending.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(tr('دعوات معلّقة'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.subtle)),
                      const SizedBox(height: 8),
                      for (final m in pending) ...[
                        CardBox(
                          radius: 16,
                          borderColor: AppColors.lineStrong,
                          onTap: isOwner ? () => context.go('/more/team/${m.id}') : null,
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(m.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                                    Text(m.email, textDirection: TextDirection.ltr, style: TextStyle(fontSize: 12, color: AppColors.muted)),
                                    Text(isOwner ? tr('{0} · اضغط لتحديد الصلاحيات', [m.role.label]) : m.role.label,
                                        style: TextStyle(fontSize: 12, color: AppColors.muted)),
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
                                    success: tr('أُعيد إرسال الدعوة'),
                                  ),
                                  child: Text(tr('إعادة إرسال')),
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
        ? Pill.urgent(tr('موقوف'))
        : switch (m.role) {
            UserRole.owner => Pill(tr('مالك'), fg: AppColors.onInkBlock, bg: AppColors.inkBlock),
            UserRole.manager => Pill.info(tr('مدير')),
            UserRole.employee => Pill.neutral(tr('موظف')),
          };
    return ListTile(
      onTap: (canOpen && !isMe) ? () => context.go('/more/team/${m.id}') : null,
      leading: Avatar(
        m.initial,
        size: 40,
        radius: 12,
        fg: m.role == UserRole.owner ? AppColors.onInkBlock : (m.isActive ? AppColors.primary : AppColors.muted),
        bg: m.role == UserRole.owner ? AppColors.inkBlock : (m.isActive ? AppColors.primarySoft : AppColors.neutralSoft),
      ),
      title: Text(isMe ? tr('{0} (أنت)', [m.name]) : m.name,
          style: TextStyle(fontWeight: FontWeight.w600, color: m.isActive ? AppColors.ink : AppColors.muted)),
      subtitle: Text(m.isActive ? (m.jobTitle ?? m.email) : tr('الحساب موقوف'),
          style: TextStyle(fontSize: 12, color: AppColors.muted)),
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
  String _locale = 'ar';
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
      showSnack(context, tr('أدخل الاسم والبريد الإلكتروني'));
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
            locale: _locale,
          ),
      success: tr('أُرسلت الدعوة إلى {0}', [_email.text.trim()]),
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
      title: tr('إضافة عضو للفريق'),
      submitLabel: tr('إرسال الدعوة'),
      busy: _busy,
      onSubmit: _send,
      children: [
        TextField(controller: _name, autofocus: true, decoration: InputDecoration(labelText: tr('الاسم'))),
        const SizedBox(height: 12),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(labelText: tr('البريد الإلكتروني'), hintText: 'name@company.sa'),
        ),
        const SizedBox(height: 12),
        TextField(controller: _job, decoration: InputDecoration(labelText: tr('المسمى الوظيفي'), hintText: tr('مثال: مستشار أول'))),
        const SizedBox(height: 14),
        Text(tr('الدور'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.subtle)),
        const SizedBox(height: 8),
        for (final r in [UserRole.employee, UserRole.manager]) ...[
          _RoleOption(
            role: r,
            selected: _role == r,
            onTap: () => setState(() => _role = r),
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 6),
        Text(tr('لغة التطبيق والإشعارات'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.subtle)),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 'ar', label: Text('العربية')),
            ButtonSegment(value: 'en', label: Text('English')),
          ],
          selected: {_locale},
          onSelectionChanged: (s) => setState(() => _locale = s.first),
        ),
        const SizedBox(height: 12),
        Text(
          tr('يصله بريد برابط لتعيين كلمة المرور والدخول للتطبيق'),
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

  static Map<UserRole, String> get _desc => {
    UserRole.employee: tr('يرى المسند إليه فقط · يمكن تخصيص صلاحياته لاحقًا'),
    UserRole.manager: tr('يرى كل الطلبات والمهام · يُسند ويضيف عملاء'),
  };

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? AppColors.primarySoft : AppColors.surface,
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
                    color: selected ? AppColors.primary : AppColors.faint),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(role.label, style: TextStyle(fontSize: 14, fontWeight: selected ? FontWeight.w700 : FontWeight.w600)),
                      Text(_desc[role]!, style: TextStyle(fontSize: 12, color: AppColors.subtle)),
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
      appBar: AppBar(title: Text(tr('صلاحيات العضو')), centerTitle: true),
      body: AsyncBody<List<TeamMember>>(
        value: team,
        onRetry: () => ref.invalidate(teamMembersProvider),
        builder: (all) {
          final m = all.where((x) => x.id == memberId).firstOrNull;
          if (m == null) return EmptyState(tr('العضو غير موجود'));
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
                          if (m.jobTitle != null) Text(m.jobTitle!, style: TextStyle(fontSize: 13, color: AppColors.muted)),
                          Text(m.email, textDirection: TextDirection.ltr, style: TextStyle(fontSize: 12, color: AppColors.muted)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _Stat('${m.openTasks}', tr('مهام مفتوحة'))),
                  const SizedBox(width: 8),
                  Expanded(child: _Stat('${m.openRequests}', tr('طلبات مسندة'))),
                ],
              ),
              const SizedBox(height: 14),
              Text(tr('الدور'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.subtle)),
              const SizedBox(height: 4),
              Text(tr('يحدد الصلاحيات الافتراضية، ويمكنك تخصيصها بالأسفل'),
                  style: TextStyle(fontSize: 12, color: AppColors.muted)),
              const SizedBox(height: 8),
              SegmentedButton<UserRole>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: UserRole.employee, label: Text(tr('موظف'))),
                  ButtonSegment(value: UserRole.manager, label: Text(tr('مدير'))),
                ],
                selected: {m.role == UserRole.owner ? UserRole.manager : m.role},
                onSelectionChanged: m.role == UserRole.owner
                    ? null
                    : (s) async {
                        if (await runAction(context, () => repo.setMemberRole(m.id, s.first),
                            success: tr('تم تغيير الدور إلى {0}', [s.first.label]))) {
                          ref.invalidate(teamMembersProvider);
                        }
                      },
              ),
              const SizedBox(height: 14),
              Text(tr('لغة التطبيق والإشعارات'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.subtle)),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 'ar', label: Text('العربية')),
                  ButtonSegment(value: 'en', label: Text('English')),
                ],
                selected: {m.locale},
                onSelectionChanged: (s) async {
                  if (await runAction(context, () => repo.setMemberLocale(m.id, s.first), success: tr('حُفظت اللغة'))) {
                    ref.invalidate(teamMembersProvider);
                  }
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(tr('الصلاحيات'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.subtle)),
                  ),
                  if (customized > 0)
                    TextButton(
                      onPressed: () async {
                        if (await runAction(context, () => repo.setMemberPermissions(m.id, {}),
                            success: tr('أُعيدت الصلاحيات الافتراضية لدور {0}', [m.role.label]))) {
                          ref.invalidate(teamMembersProvider);
                        }
                      },
                      child: Text(tr('إعادة الافتراضي ({0})', [customized])),
                    ),
                ],
              ),
              for (final g in groups.entries) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 6),
                  child: Text(g.key, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.muted)),
                ),
                CardBox(
                  radius: 16,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    children: [
                      for (var i = 0; i < g.value.length; i++) ...[
                        if (i > 0) Divider(height: 1, color: AppColors.divider),
                        SwitchListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                          value: m.can(g.value[i].key),
                          onChanged: m.role == UserRole.owner ? null : (v) => savePermissions(m, g.value[i].key, v),
                          title: Row(
                            children: [
                              Flexible(child: Text(g.value[i].label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
                              if (m.isCustomized(g.value[i].key)) ...[
                                const SizedBox(width: 6),
                                Pill.info(tr('مخصص')),
                              ],
                            ],
                          ),
                          subtitle: Text(g.value[i].description, style: TextStyle(fontSize: 12, color: AppColors.muted)),
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
                    title: m.isActive ? tr('إيقاف حساب {0}؟', [m.name]) : tr('إعادة تفعيل {0}؟', [m.name]),
                    message: m.isActive
                        ? tr('لن يستطيع الدخول أو رؤية أي بيانات. مهامه وطلباته تبقى كما هي ويمكن إسنادها لغيره.')
                        : tr('سيستطيع الدخول مجددًا بنفس الدور والصلاحيات.'),
                    confirmLabel: m.isActive ? tr('إيقاف') : tr('تفعيل'),
                    destructive: m.isActive,
                  );
                  if (!ok || !context.mounted) return;
                  if (await runAction(context, () => repo.setMemberActive(m.id, !m.isActive))) {
                    ref.invalidate(teamMembersProvider);
                  }
                },
                child: Text(m.isActive ? tr('إيقاف الحساب') : tr('إعادة تفعيل الحساب')),
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
            Text(label, style: TextStyle(fontSize: 12, color: AppColors.muted)),
          ],
        ),
      );
}
