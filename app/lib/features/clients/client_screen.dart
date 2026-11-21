import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../data/section_repository.dart';
import '../../widgets/common.dart';
import '../../widgets/forms.dart';
import '../../core/permissions.dart';
import '../quick_add/quick_add_sheet.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/i18n.dart';

/// ٥ · ملف العميل
class ClientScreen extends ConsumerWidget {
  const ClientScreen({super.key, required this.clientId});

  final String clientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(clientDetailProvider(clientId));
    return Scaffold(
      appBar: AppBar(title: Text(tr('ملف العميل')), centerTitle: true),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(clientDetailProvider(clientId)),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
          children: [
            AsyncBody<ClientDetail>(
              value: detail,
              onRetry: () => ref.invalidate(clientDetailProvider(clientId)),
              builder: (d) => _ClientBody(d),
            ),
          ],
        ),
      ),
    );
  }
}

NumberFormat get _money => NumberFormat.decimalPattern(L.code);

class _ClientBody extends ConsumerWidget {
  const _ClientBody(this.d);
  final ClientDetail d;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contact = d.primaryContact;
    final canEdit = ref.watch(profileProvider).valueOrNull?.can(Permissions.clientsManage) ?? false;
    final repo = ref.read(repositoryProvider);
    final c = d.client;

    void refresh() {
      ref.invalidate(clientDetailProvider(c.id));
      ref.invalidate(clientsProvider);
    }

    Future<void> editField(String column, String label, String? current) async {
      final v = await promptText(context, label, initial: current ?? '');
      if (v == null || !context.mounted) return;
      if (await runAction(context, () => repo.updateClient(c.id, {column: v.trim().isEmpty ? null : v.trim()}),
          success: tr('حُفظ التعديل'))) {
        refresh();
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CardBox(
          radius: 20,
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              Avatar(c.initial, size: 64, radius: 20),
              const SizedBox(height: 10),
              Text(c.name, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700), textAlign: TextAlign.center),
              if (contact != null)
                Text(
                  tr('جهة التواصل: {0}{1}', [contact.name, contact.position != null ? ' · ${contact.position}' : '']),
                  style: TextStyle(fontSize: 13, color: AppColors.muted),
                  textAlign: TextAlign.center,
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _Action(
                      icon: Icons.call_outlined,
                      label: tr('اتصال'),
                      onTap: contact?.phone == null ? null : () => _open(context, 'tel:${contact!.phone!.replaceAll(' ', '')}'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _Action(
                      icon: Icons.mail_outline,
                      label: tr('بريد'),
                      onTap: contact?.email == null ? null : () => _open(context, 'mailto:${contact!.email}'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _Action(
                      icon: Icons.event_outlined,
                      label: tr('موعد'),
                      onTap: () => showQuickAdd(context, initial: QuickAddType.meeting),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(child: _Metric(value: '${d.openRequests}', label: tr('طلبات مفتوحة'))),
            const SizedBox(width: 8),
            Expanded(child: _Metric(value: _money.format(d.contractsValue), label: tr('قيمة العقود'))),
            const SizedBox(width: 8),
            Expanded(
              child: _Metric(
                value: _money.format(d.amountDue),
                label: tr('مستحق الدفع'),
                warn: d.amountDue > 0,
              ),
            ),
          ],
        ),
        if (d.summaryError != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(tr('تعذّر حساب الأرقام: {0}', [d.summaryError]), style: TextStyle(fontSize: 11, color: AppColors.urgent)),
          ),
        const SizedBox(height: 18),
        SectionHeader(tr('جهات الاتصال')),
        CardBox(
          radius: 16,
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              if (d.contacts.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(tr('لا توجد جهات اتصال بعد'), style: TextStyle(color: AppColors.muted)),
                ),
              for (var i = 0; i < d.contacts.length; i++) ...[
                if (i > 0) Divider(height: 1, color: AppColors.divider),
                _ContactRow(
                  contact: d.contacts[i],
                  onEdit: canEdit
                      ? () => showFormSheet(context, _ContactSheet(clientId: c.id, contact: d.contacts[i], onSaved: refresh))
                      : null,
                ),
              ],
              if (canEdit) ...[
                Divider(height: 1, color: AppColors.divider),
                ListTile(
                  leading: Icon(Icons.person_add_alt, color: AppColors.accentText),
                  title: Text(tr('إضافة جهة اتصال'), style: TextStyle(color: AppColors.accentText, fontWeight: FontWeight.w600)),
                  onTap: () => showFormSheet(context, _ContactSheet(clientId: c.id, onSaved: refresh, firstContact: d.contacts.isEmpty)),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 18),
        SectionHeader(tr('بيانات العميل')),
        FormCard(children: [
          FormRow(label: tr('الاسم'), value: c.name, onTap: canEdit ? () => editField('name', tr('الاسم'), c.name) : null),
          FormRow(
            label: tr('القطاع'),
            value: c.sector ?? '—',
            muted: c.sector == null,
            onTap: canEdit ? () => editField('sector', tr('القطاع'), c.sector) : null,
          ),
          FormRow(
            label: tr('المدينة'),
            value: c.city ?? '—',
            muted: c.city == null,
            onTap: canEdit ? () => editField('city', tr('المدينة'), c.city) : null,
          ),
          FormRow(
            label: tr('العنوان'),
            value: c.address ?? '—',
            muted: c.address == null,
            onTap: canEdit ? () => editField('address', tr('العنوان'), c.address) : null,
          ),
          FormRow(
            label: tr('السجل التجاري'),
            value: c.crNumber ?? '—',
            muted: c.crNumber == null,
            onTap: canEdit ? () => editField('cr_number', tr('السجل التجاري'), c.crNumber) : null,
          ),
          FormRow(
            label: tr('الرقم الضريبي'),
            value: c.vatNumber ?? '—',
            muted: c.vatNumber == null,
            onTap: canEdit ? () => editField('vat_number', tr('الرقم الضريبي'), c.vatNumber) : null,
          ),
        ]),
        if (c.fromDaftra)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(tr('مرتبط بعميل في دفترة · الفواتير تأتي من هناك'), style: TextStyle(fontSize: 12, color: AppColors.muted)),
          ),
        const SizedBox(height: 18),
        _ClientRequests(clientId: c.id),
        const SizedBox(height: 18),
        SectionHeader(tr('السجل')),
        if (d.activity.isEmpty)
          EmptyState(tr('لا يوجد نشاط مسجّل بعد'), icon: Icons.history)
        else
          for (var i = 0; i < d.activity.length; i++)
            _TimelineEntry(entry: d.activity[i], first: i == 0, last: i == d.activity.length - 1),
      ],
    );
  }

  static Future<void> _open(BuildContext context, String url) async {
    final ok = await launchUrl(Uri.parse(url));
    if (!ok && context.mounted) showSnack(context, url.replaceFirst(RegExp(r'^(tel|mailto):'), ''));
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 48),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.ink,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({required this.contact, this.onEdit});
  final Contact contact;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final lines = [contact.position, contact.phone, contact.email].whereType<String>().where((x) => x.isNotEmpty);
    return InkWell(
      onTap: onEdit,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Avatar(contact.name.isEmpty ? '؟' : contact.name.characters.first, size: 36),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(child: Text(contact.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
                      if (contact.isPrimary) ...[
                        const SizedBox(width: 6),
                        Pill.info(tr('أساسي')),
                      ],
                    ],
                  ),
                  if (lines.isNotEmpty)
                    Text(lines.join(' · '),
                        textDirection: TextDirection.ltr,
                        textAlign: L.isEn ? TextAlign.left : TextAlign.right,
                        style: TextStyle(fontSize: 12, color: AppColors.muted)),
                ],
              ),
            ),
            if (contact.phone != null)
              IconButton(
                tooltip: tr('اتصال'),
                icon: Icon(Icons.call_outlined, size: 20, color: AppColors.accentText),
                onPressed: () => _ClientBody._open(context, 'tel:${contact.phone!.replaceAll(' ', '')}'),
              ),
            if (contact.email != null)
              IconButton(
                tooltip: tr('بريد'),
                icon: Icon(Icons.mail_outline, size: 20, color: AppColors.accentText),
                onPressed: () => _ClientBody._open(context, 'mailto:${contact.email}'),
              ),
          ],
        ),
      ),
    );
  }
}

/// إضافة جهة اتصال أو تعديلها.
class _ContactSheet extends ConsumerStatefulWidget {
  const _ContactSheet({required this.clientId, this.contact, required this.onSaved, this.firstContact = false});
  final String clientId;
  final Contact? contact;
  final VoidCallback onSaved;
  final bool firstContact;

  @override
  ConsumerState<_ContactSheet> createState() => _ContactSheetState();
}

class _ContactSheetState extends ConsumerState<_ContactSheet> {
  late final _name = TextEditingController(text: widget.contact?.name ?? '');
  late final _position = TextEditingController(text: widget.contact?.position ?? '');
  late final _phone = TextEditingController(text: widget.contact?.phone ?? '');
  late final _email = TextEditingController(text: widget.contact?.email ?? '');
  late bool _primary = widget.contact?.isPrimary ?? widget.firstContact;
  bool _busy = false;

  bool get _isNew => widget.contact == null;

  @override
  void dispose() {
    _name.dispose();
    _position.dispose();
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
      () => ref.read(repositoryProvider).saveContact(
            id: widget.contact?.id,
            clientId: widget.clientId,
            name: _name.text,
            position: _position.text,
            phone: _phone.text,
            email: _email.text,
            isPrimary: _primary,
          ),
      success: tr('حُفظت جهة الاتصال'),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      widget.onSaved();
      Navigator.pop(context);
    }
  }

  Future<void> _delete() async {
    final ok = await confirmAction(context,
        title: tr('حذف جهة الاتصال؟'), message: widget.contact!.name, confirmLabel: tr('حذف'), destructive: true);
    if (!ok || !mounted) return;
    if (await runAction(context, () => ref.read(repositoryProvider).deleteContact(widget.contact!.id),
        success: tr('حُذفت جهة الاتصال'))) {
      widget.onSaved();
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SheetBody(
      title: _isNew ? tr('جهة اتصال جديدة') : tr('تعديل جهة الاتصال'),
      busy: _busy,
      onSubmit: _save,
      children: [
        TextField(controller: _name, autofocus: _isNew, decoration: InputDecoration(labelText: tr('الاسم'))),
        const SizedBox(height: 10),
        TextField(controller: _position, decoration: InputDecoration(labelText: tr('المسمى الوظيفي'))),
        const SizedBox(height: 10),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(labelText: tr('الجوال'), hintText: '05xxxxxxxx'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(labelText: tr('البريد الإلكتروني')),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(tr('جهة الاتصال الأساسية'), style: const TextStyle(fontSize: 14)),
          value: _primary,
          onChanged: (v) => setState(() => _primary = v),
        ),
        if (!_isNew)
          TextButton.icon(
            onPressed: _busy ? null : _delete,
            icon: Icon(Icons.delete_outline, color: AppColors.urgent),
            label: Text(tr('حذف جهة الاتصال'), style: TextStyle(color: AppColors.urgent)),
          ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.value, required this.label, this.warn = false});

  final String value;
  final String label;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final fg = warn ? AppColors.waiting : AppColors.ink;
    return CardBox(
      radius: 14,
      padding: const EdgeInsets.all(12),
      color: warn ? AppColors.waitingSoft : AppColors.surface,
      borderColor: warn ? AppColors.warnBorder : AppColors.line,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: fg)),
          ),
          Text(label, style: TextStyle(fontSize: 12, color: warn ? AppColors.waiting : AppColors.muted)),
        ],
      ),
    );
  }
}

class _TimelineEntry extends StatelessWidget {
  const _TimelineEntry({required this.entry, required this.first, required this.last});

  final ActivityEntry entry;
  final bool first;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 4),
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: first ? AppColors.primary : AppColors.faint,
                  shape: BoxShape.circle,
                ),
              ),
              if (!last) Expanded(child: Container(width: 2, color: AppColors.line)),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.action, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  Text('${relativeDay(entry.at)} · ${formatTime(entry.at)}',
                      style: TextStyle(fontSize: 12, color: AppColors.muted)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// طلبات العميل مجمّعة في ملفه.
class _ClientRequests extends ConsumerWidget {
  const _ClientRequests({required this.clientId});
  final String clientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests = ref.watch(clientRequestsProvider(clientId));
    final list = requests.valueOrNull ?? const <RequestItem>[];
    final open = list.where((r) => r.status.isOpen).toList();
    final closed = list.where((r) => !r.status.isOpen).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(tr('الطلبات{0}', [list.isEmpty ? '' : tr(' · {0} مفتوح', [open.length])])),
        AsyncBody<List<RequestItem>>(
          value: requests,
          onRetry: () => ref.invalidate(clientRequestsProvider(clientId)),
          builder: (_) => list.isEmpty
              ? CardBox(child: Text(tr('لا توجد طلبات لهذا العميل'), style: TextStyle(color: AppColors.muted)))
              : CardBox(
                  radius: 16,
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (var i = 0; i < [...open, ...closed].length; i++) ...[
                        if (i > 0) Divider(height: 1, color: AppColors.divider),
                        _row(context, [...open, ...closed][i]),
                      ],
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _row(BuildContext context, RequestItem r) {
    return InkWell(
      onTap: () => context.go('/requests/${r.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('#${r.number} · ${r.title}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: r.status.isOpen ? AppColors.ink : AppColors.muted,
                      )),
                ),
                const SizedBox(width: 8),
                Pill.forRequest(r),
              ],
            ),
            if (r.status.isOpen) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: ProgressLine(r.progress, color: r.isOverdue ? AppColors.danger : AppColors.accent)),
                  const SizedBox(width: 8),
                  Text(tr('{0}٪', [r.progress]), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
