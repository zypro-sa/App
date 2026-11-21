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
    final canInvite = isOwner || (me?.can(Permissions.teamAdd) ?? false);
    final canManage = isOwner || (me?.can(Permissions.teamEdit) ?? false) || (me?.can(Permissions.teamDelete) ?? false);
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
            if (canInvite) ...[
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
                            _MemberTile(members[i], isMe: members[i].id == me?.id, canOpen: canManage || (me?.can(Permissions.teamView) ?? false)),
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
                          onTap: canManage ? () => context.go('/more/team/${m.id}') : null,
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(m.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                                    Text(m.email, textDirection: TextDirection.ltr, style: TextStyle(fontSize: 12, color: AppColors.muted)),
                                    Text(canManage ? tr('{0} · اضغط لتحديد الصلاحيات', [m.role.label]) : m.role.label,
                                        style: TextStyle(fontSize: 12, color: AppColors.muted)),
                                  ],
                                ),
                              ),
                              if (canInvite)
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
      onTap: isMe ? () => context.go('/more/account') : (canOpen ? () => context.go('/more/team/${m.id}') : null),
      leading: Avatar(
        m.initial,
        size: 40,
        radius: 12,
        imageUrl: m.avatarUrl,
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
/// صفحة العضو: بياناته، دوره، صلاحياته التفصيلية، وإدارة حسابه (للمالك).
class MemberScreen extends ConsumerWidget {
  const MemberScreen({super.key, required this.memberId});
  final String memberId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final team = ref.watch(teamMembersProvider);
    final repo = ref.read(sectionRepoProvider);
    final me = ref.watch(profileProvider).valueOrNull;
    final isOwner = me?.role == UserRole.owner;

    return Scaffold(
      appBar: AppBar(title: Text(tr('العضو')), centerTitle: true),
      body: AsyncBody<List<TeamMember>>(
        value: team,
        onRetry: () => ref.invalidate(teamMembersProvider),
        builder: (all) {
          final m = all.where((x) => x.id == memberId).firstOrNull;
          if (m == null) return EmptyState(tr('العضو غير موجود'));
          final notSelfOrOwner = m.role != UserRole.owner && m.id != me?.id;
          final editable = notSelfOrOwner && (isOwner || (me?.can(Permissions.teamEdit) ?? false));
          final canRemove = notSelfOrOwner && (isOwner || (me?.can(Permissions.teamDelete) ?? false));
          final customized = [
            for (final mod in Permissions.modules)
              for (final k in mod.allKeys)
                if (m.isCustomized(k)) 1
          ].length;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
            children: [
              CardBox(
                radius: 20,
                child: Row(
                  children: [
                    Avatar(m.initial, size: 56, radius: 18, fg: AppColors.done, bg: AppColors.doneSoft, imageUrl: m.avatarUrl),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(m.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                          if (m.jobTitle != null) Text(m.jobTitle!, style: TextStyle(fontSize: 13, color: AppColors.muted)),
                          Text(m.email, textDirection: TextDirection.ltr, style: TextStyle(fontSize: 12, color: AppColors.muted)),
                          if (m.phone != null)
                            Text(m.phone!, textDirection: TextDirection.ltr, style: TextStyle(fontSize: 12, color: AppColors.muted)),
                        ],
                      ),
                    ),
                    if (editable)
                      IconButton(
                        tooltip: tr('تعديل البيانات'),
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => showFormSheet(context, _EditMemberSheet(member: m)),
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
              if (editable) ...[
                const SizedBox(height: 16),
                _Label(tr('الدور'), hint: tr('يحدد الصلاحيات الافتراضية، ويمكنك تخصيصها بالأسفل')),
                SegmentedButton<UserRole>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(value: UserRole.employee, label: Text(tr('موظف'))),
                    ButtonSegment(value: UserRole.manager, label: Text(tr('مدير'))),
                  ],
                  selected: {m.role},
                  onSelectionChanged: (s) async {
                    if (await runAction(context, () => repo.setMemberRole(m.id, s.first),
                        success: tr('تم تغيير الدور إلى {0}', [s.first.label]))) {
                      ref.invalidate(teamMembersProvider);
                    }
                  },
                ),
                const SizedBox(height: 14),
                _Label(tr('لغة التطبيق والإشعارات')),
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
              ],
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(child: _Label(tr('الصلاحيات'), hint: tr('الإطار الأصفر يعني أنها تختلف عن الافتراضي لدوره'))),
                  if (editable && customized > 0)
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
              _PermissionCards(member: m, editable: editable),
              if (m.role == UserRole.owner)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(tr('المالك يملك كل الصلاحيات دائمًا'), style: TextStyle(fontSize: 12, color: AppColors.muted)),
                ),
              if (editable || canRemove) ...[
                const SizedBox(height: 18),
                _Label(tr('الحساب')),
                CardBox(
                  radius: 16,
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      if (editable) ...[
                      ListTile(
                        leading: const Icon(Icons.password),
                        title: Text(tr('تغيير كلمة المرور')),
                        trailing: Icon(AppIcons.forward),
                        onTap: () => showFormSheet(context, _SetPasswordSheet(member: m)),
                      ),
                      if (canRemove) Divider(height: 1, color: AppColors.divider),
                      ],
                      if (canRemove) ...[
                      ListTile(
                        leading: Icon(m.isActive ? Icons.block : Icons.check_circle_outline,
                            color: m.isActive ? AppColors.waiting : AppColors.done),
                        title: Text(m.isActive ? tr('إيقاف الحساب') : tr('إعادة تفعيل الحساب')),
                        subtitle: Text(
                          m.isActive ? tr('يمنعه من الدخول مع بقاء أعماله') : tr('يعود بنفس الدور والصلاحيات'),
                          style: TextStyle(fontSize: 12, color: AppColors.muted),
                        ),
                        onTap: () async {
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
                      ),
                      Divider(height: 1, color: AppColors.divider),
                      ListTile(
                        leading: Icon(Icons.delete_forever_outlined, color: AppColors.urgent),
                        title: Text(tr('حذف الحساب نهائيًا'), style: TextStyle(color: AppColors.urgent)),
                        subtitle: Text(tr('تنتقل مهامه وطلباته ومتابعاته لعضو آخر'),
                            style: TextStyle(fontSize: 12, color: AppColors.muted)),
                        onTap: () => showFormSheet(context, _DeleteMemberSheet(member: m, team: all)),
                      ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text, {this.hint});
  final String text;
  final String? hint;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.subtle)),
            if (hint != null) Text(hint!, style: TextStyle(fontSize: 12, color: AppColors.muted)),
          ],
        ),
      );
}

/// الصلاحيات: بطاقة لكل قسم، فيها نطاق العرض (إن وُجد) ثم بقية الصلاحيات.
class _PermissionCards extends ConsumerWidget {
  const _PermissionCards({required this.member, required this.editable});
  final TeamMember member;
  final bool editable;

  Future<void> _save(BuildContext context, WidgetRef ref, Map<String, bool> changes) async {
    final m = member;
    final overrides = <String, bool>{
      for (final e in m.permissions.entries)
        if (e.value is bool) e.key: e.value as bool,
    };
    changes.forEach((key, value) {
      if (value == Permissions.roleDefault(m.role, key)) {
        overrides.remove(key);
      } else {
        overrides[key] = value;
      }
    });
    if (await runAction(context, () => ref.read(sectionRepoProvider).setMemberPermissions(m.id, overrides))) {
      ref.invalidate(teamMembersProvider);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = <String, List<PermModule>>{};
    for (final mod in Permissions.modules) {
      groups.putIfAbsent(mod.group, () => []).add(mod);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final g in groups.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 6),
            child: Text(g.key, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.muted)),
          ),
          for (final mod in g.value) ...[
            _card(context, ref, mod),
            const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }

  Widget _card(BuildContext context, WidgetRef ref, PermModule mod) {
    final m = member;
    final custom = mod.allKeys.any(m.isCustomized);
    return CardBox(
      radius: 16,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(mod.label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
              if (custom) Pill.info(tr('مخصص')),
            ],
          ),
          if (mod.note != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(mod.note!, style: TextStyle(fontSize: 12, color: AppColors.muted)),
            ),
          if (mod.scoped) ...[
            const SizedBox(height: 10),
            Text(tr('العرض'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.subtle)),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<int>(
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(
                  textStyle: const TextStyle(fontSize: 12),
                  visualDensity: VisualDensity.compact,
                ),
                segments: [
                  ButtonSegment(value: 2, label: Text(tr(mod.scopeAllAr!), textAlign: TextAlign.center)),
                  ButtonSegment(value: 1, label: Text(tr(mod.scopeOwnAr!), textAlign: TextAlign.center)),
                  ButtonSegment(value: 0, label: Text(tr('لا شيء'))),
                ],
                selected: {m.can(mod.viewAllKey) ? 2 : (m.can(mod.viewOwnKey) ? 1 : 0)},
                onSelectionChanged: editable
                    ? (v) => _save(context, ref, {mod.viewAllKey: v.first == 2, mod.viewOwnKey: v.first >= 1})
                    : null,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in mod.items)
                Tooltip(
                  message: item.note,
                  child: FilterChip(
                    label: Text(item.label),
                    selected: m.can(mod.keyOf(item.action)),
                    showCheckmark: true,
                    side: m.isCustomized(mod.keyOf(item.action))
                        ? BorderSide(color: AppColors.waiting, width: 1.5)
                        : BorderSide(color: AppColors.line),
                    selectedColor: AppColors.primarySoft,
                    checkmarkColor: AppColors.accentText,
                    onSelected: editable ? (v) => _save(context, ref, {mod.keyOf(item.action): v}) : null,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          InkWell(
            onTap: () => _explain(context, mod),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(tr('ماذا تعني كل صلاحية؟'),
                  style: TextStyle(fontSize: 12, color: AppColors.accentText, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  void _explain(BuildContext context, PermModule mod) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(mod.label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              if (mod.note != null) Text(mod.note!, style: TextStyle(fontSize: 12, color: AppColors.muted)),
              const SizedBox(height: 8),
              if (mod.scoped) ...[
                _line(tr(mod.scopeAllAr!), tr('يرى كل السجلات في هذا القسم')),
                _line(tr(mod.scopeOwnAr!), tr('يرى ما يخصه فقط')),
                _line(tr('لا شيء'), tr('لا يظهر له هذا القسم')),
              ],
              for (final i in mod.items) _line(i.label, i.note),
            ],
          ),
        ),
      ),
    );
  }

  Widget _line(String title, String body) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            Text(body, style: TextStyle(fontSize: 12, color: AppColors.muted)),
          ],
        ),
      );
}

/// تعديل بيانات عضو (للمالك)
class _EditMemberSheet extends ConsumerStatefulWidget {
  const _EditMemberSheet({required this.member});
  final TeamMember member;

  @override
  ConsumerState<_EditMemberSheet> createState() => _EditMemberSheetState();
}

class _EditMemberSheetState extends ConsumerState<_EditMemberSheet> {
  late final _name = TextEditingController(text: widget.member.name);
  late final _job = TextEditingController(text: widget.member.jobTitle ?? '');
  late final _phone = TextEditingController(text: widget.member.phone ?? '');
  late final _email = TextEditingController(text: widget.member.email);
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _job.dispose();
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      showSnack(context, tr('أدخل الاسم'));
      return;
    }
    setState(() => _busy = true);
    final ok = await runAction(
      context,
      () => ref.read(sectionRepoProvider).adminUpdateMember(
            widget.member.id,
            name: _name.text.trim(),
            jobTitle: _job.text.trim(),
            phone: _phone.text.trim(),
            email: _email.text.trim(),
          ),
      success: tr('حُفظت البيانات'),
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
      title: tr('تعديل بيانات {0}', [widget.member.name]),
      busy: _busy,
      onSubmit: _save,
      children: [
        TextField(controller: _name, decoration: InputDecoration(labelText: tr('الاسم'))),
        const SizedBox(height: 10),
        TextField(controller: _job, decoration: InputDecoration(labelText: tr('المسمى الوظيفي'))),
        const SizedBox(height: 10),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(labelText: tr('الجوال')),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(labelText: tr('البريد الإلكتروني'), helperText: tr('يدخل به العضو للتطبيق')),
        ),
      ],
    );
  }
}

/// تعيين كلمة مرور جديدة لعضو (للمالك)
class _SetPasswordSheet extends ConsumerStatefulWidget {
  const _SetPasswordSheet({required this.member});
  final TeamMember member;

  @override
  ConsumerState<_SetPasswordSheet> createState() => _SetPasswordSheetState();
}

class _SetPasswordSheetState extends ConsumerState<_SetPasswordSheet> {
  final _p1 = TextEditingController();
  final _p2 = TextEditingController();
  bool _busy = false;
  bool _show = false;

  @override
  void dispose() {
    _p1.dispose();
    _p2.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_p1.text.length < 8) {
      showSnack(context, tr('كلمة المرور يجب أن تكون ٨ أحرف على الأقل'));
      return;
    }
    if (_p1.text != _p2.text) {
      showSnack(context, tr('كلمتا المرور غير متطابقتين'));
      return;
    }
    setState(() => _busy = true);
    final ok = await runAction(context, () => ref.read(sectionRepoProvider).adminSetPassword(widget.member.id, _p1.text),
        success: tr('تم تغيير كلمة المرور · أبلغ {0} بها', [widget.member.name]));
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return SheetBody(
      title: tr('كلمة مرور جديدة لـ {0}', [widget.member.name]),
      busy: _busy,
      onSubmit: _save,
      children: [
        TextField(
          controller: _p1,
          obscureText: !_show,
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(
            labelText: tr('كلمة المرور الجديدة'),
            suffixIcon: IconButton(
              icon: Icon(_show ? Icons.visibility_off_outlined : Icons.visibility_outlined),
              onPressed: () => setState(() => _show = !_show),
            ),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _p2,
          obscureText: !_show,
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(labelText: tr('تأكيد كلمة المرور')),
        ),
      ],
    );
  }
}

/// حذف عضو نهائيًا مع نقل أعماله
class _DeleteMemberSheet extends ConsumerStatefulWidget {
  const _DeleteMemberSheet({required this.member, required this.team});
  final TeamMember member;
  final List<TeamMember> team;

  @override
  ConsumerState<_DeleteMemberSheet> createState() => _DeleteMemberSheetState();
}

class _DeleteMemberSheetState extends ConsumerState<_DeleteMemberSheet> {
  String? _to;
  bool _busy = false;

  List<TeamMember> get _others =>
      widget.team.where((x) => x.id != widget.member.id && x.isActive && !x.pending).toList();

  @override
  void initState() {
    super.initState();
    _to = widget.team.where((x) => x.role == UserRole.owner).map((x) => x.id).firstOrNull;
  }

  Future<void> _delete() async {
    if (_to == null) {
      showSnack(context, tr('اختر عضوًا تنتقل إليه أعماله'));
      return;
    }
    final ok = await confirmAction(
      context,
      title: tr('حذف {0} نهائيًا؟', [widget.member.name]),
      message: tr('لا يمكن التراجع عن الحذف. إن أردت منعه مؤقتًا فاستخدم «إيقاف الحساب».'),
      confirmLabel: tr('حذف نهائيًا'),
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final done = await runAction(context, () => ref.read(sectionRepoProvider).adminDeleteMember(widget.member.id, _to!),
        success: tr('حُذف الحساب'));
    if (!mounted) return;
    setState(() => _busy = false);
    if (done) {
      refreshSections(ref);
      ref.invalidate(teamProvider);
      Navigator.pop(context);
      if (context.mounted) context.go('/more/team');
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.member;
    return SheetBody(
      title: tr('حذف حساب {0}', [m.name]),
      busy: _busy,
      submitLabel: tr('حذف نهائيًا'),
      onSubmit: _delete,
      children: [
        Text(
          tr('لديه {0} مهام مفتوحة و{1} طلبات مسندة. اختر من تنتقل إليه أعماله (المهام، الطلبات، المشاريع التي يديرها، والمتابعات).',
              [m.openTasks, m.openRequests]),
          style: TextStyle(fontSize: 13, color: AppColors.muted, height: 1.6),
        ),
        const SizedBox(height: 12),
        FormCard(children: [
          FormDropdown<String>(
            label: tr('تنتقل أعماله إلى'),
            value: _to,
            allowEmpty: false,
            items: {for (final o in _others) o.id: o.name},
            onChanged: (v) => setState(() => _to = v),
          ),
        ]),
      ],
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
