import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../widgets/common.dart';
import '../../widgets/forms.dart' show sectionAppBar;
import 'meetings_screen.dart';

/// الاجتماعات السابقة: الأحدث أولًا، مع بحث وتصفية وتحميل تدريجي.
class PastMeetingsScreen extends ConsumerStatefulWidget {
  const PastMeetingsScreen({super.key});

  @override
  ConsumerState<PastMeetingsScreen> createState() => _PastMeetingsScreenState();
}

enum _Filter { all, done, noMinutes, postponed, cancelled }

class _PastMeetingsScreenState extends ConsumerState<PastMeetingsScreen> {
  static const _page = 30;
  final _search = TextEditingController();
  Timer? _debounce;
  _Filter _filter = _Filter.all;
  final List<Meeting> _items = [];
  bool _loading = false;
  bool _hasMore = true;
  Object? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading && !reset) return;
    final gen = reset ? ++_generation : _generation;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _items.clear();
        _hasMore = true;
      }
    });
    try {
      final rows = await ref.read(repositoryProvider).pastMeetings(
            query: _search.text,
            status: switch (_filter) {
              _Filter.done => MeetingStatus.done,
              _Filter.postponed => MeetingStatus.postponed,
              _Filter.cancelled => MeetingStatus.cancelled,
              _ => null,
            },
            withoutMinutes: _filter == _Filter.noMinutes,
            offset: _items.length,
            limit: _page,
          );
      if (!mounted || gen != _generation) return;
      setState(() {
        _items.addAll(rows);
        _hasMore = rows.length == _page;
      });
    } catch (e) {
      if (mounted && gen == _generation) setState(() => _error = e);
    } finally {
      if (mounted && gen == _generation) setState(() => _loading = false);
    }
  }

  void _onSearch(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _load(reset: true));
  }

  @override
  Widget build(BuildContext context) {
    final labels = {
      _Filter.all: tr('الكل'),
      _Filter.done: tr('منعقد'),
      _Filter.noMinutes: tr('بلا محضر'),
      _Filter.postponed: tr('مؤجل'),
      _Filter.cancelled: tr('ملغى'),
    };

    // تجميع حسب الشهر
    final children = <Widget>[];
    String? month;
    for (final m in _items) {
      final key = formatPattern('MMMM y', m.startAt);
      if (key != month) {
        month = key;
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
          child: Text(key, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.subtle)),
        ));
      }
      children.add(Padding(padding: const EdgeInsets.only(bottom: 8), child: _PastMeetingTile(m)));
    }

    return Scaffold(
      appBar: sectionAppBar(tr('الاجتماعات السابقة'), subtitle: tr('الأحدث أولًا')),
      body: RefreshIndicator(
        onRefresh: () => _load(reset: true),
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n.metrics.extentAfter < 300 && _hasMore && !_loading && _error == null) _load();
            return false;
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
            children: [
              TextField(
                controller: _search,
                onChanged: _onSearch,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: tr('ابحث بالعنوان أو المكان أو نص المحضر'),
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: tr('مسح'),
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _search.clear();
                            _load(reset: true);
                          },
                        ),
                ),
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final f in _Filter.values) ...[
                      ChoiceChip(
                        label: Text(labels[f]!),
                        selected: _filter == f,
                        showCheckmark: false,
                        onSelected: (_) {
                          setState(() => _filter = f);
                          _load(reset: true);
                        },
                      ),
                      const SizedBox(width: 6),
                    ],
                  ],
                ),
              ),
              ...children,
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Text(tr('تعذّر تحميل البيانات'), style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      OutlinedButton(onPressed: () => _load(), child: Text(tr('إعادة المحاولة'))),
                    ],
                  ),
                )
              else if (_loading)
                const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
              else if (_items.isEmpty)
                EmptyState(tr('لا توجد اجتماعات سابقة مطابقة'), icon: Icons.history)
              else if (!_hasMore)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Center(child: Text(tr('نهاية القائمة'), style: TextStyle(fontSize: 12, color: AppColors.faint))),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PastMeetingTile extends StatelessWidget {
  const _PastMeetingTile(this.m);
  final Meeting m;

  @override
  Widget build(BuildContext context) {
    final hasMinutes = (m.minutes ?? '').trim().isNotEmpty;
    return CardBox(
      onTap: () => openMeetingMinutes(context, m),
      padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 4, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(10)),
            child: Column(
              children: [
                Text('${m.startAt.day}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                Text(formatPattern('EEE', m.startAt), style: TextStyle(fontSize: 11, color: AppColors.muted)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(m.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    ),
                    if (m.status != MeetingStatus.scheduled) meetingStatusPill(m.status),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    formatTime(m.startAt),
                    m.type.label,
                    if (m.clientName != null) m.clientName!,
                    if ((m.location ?? '').isNotEmpty) m.location!,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(hasMinutes ? Icons.description_outlined : Icons.edit_note, size: 15, color: hasMinutes ? AppColors.done : AppColors.faint),
                    const SizedBox(width: 4),
                    Text(hasMinutes ? tr('يوجد محضر') : tr('لا يوجد محضر'),
                        style: TextStyle(fontSize: 11, color: hasMinutes ? AppColors.done : AppColors.faint)),
                  ],
                ),
              ],
            ),
          ),
          MeetingActions(meeting: m),
        ],
      ),
    );
  }
}
