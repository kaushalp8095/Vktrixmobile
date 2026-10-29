// REPAIRS: workshop ki list — khuli jobs, ready (customer ko call karo) aur
// delivered ka hisaab. Har row par balance dikhta hai, isliye "kisne paisa
// dena hai" alag se yaad rakhne ki zaroorat nahi.
//
// Customer ka device kabhi stock me nahi jaata — ye list `repairs` table se
// aati hai, `phones` se nahi. Isliye stock value aur profit par iska koi asar
// nahi padta (backend bhi yahi niyam rakhta hai).
import 'dart:async';

import 'package:flutter/material.dart';
import '../api.dart';
import '../design/components/components.dart';
import '../design/design.dart';
import 'common.dart';
import 'repair_detail.dart';
import 'repair_form.dart';

enum RepairFilter { open, ready, delivered, all }

class RepairsScreen extends StatefulWidget {
  /// Test hooks — data diya to network nahi chalta.
  final List<dynamic>? testItems;
  final Map<String, dynamic>? testSummary;
  const RepairsScreen({super.key, this.testItems, this.testSummary});
  @override
  State<RepairsScreen> createState() => _RepairsScreenState();
}

class _RepairsScreenState extends State<RepairsScreen> {
  final _scroll = ScrollController();
  final _search = TextEditingController();
  List items = [];
  Map<String, dynamic>? _summary;
  bool loading = true;
  bool _dueOnly = false;
  Object? _error;
  RepairFilter filter = RepairFilter.open;
  Timer? _debounce;

  static const _statuses = ['received', 'repairing', 'ready', 'hold', 'delivered', 'cancelled'];

  @override
  void initState() {
    super.initState();
    if (widget.testItems != null) {
      items = widget.testItems!;
      _summary = widget.testSummary;
      loading = false;
    } else {
      _load();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  String get _query => switch (filter) {
        RepairFilter.open => 'open',
        RepairFilter.ready => 'ready',
        RepairFilter.delivered => 'delivered',
        RepairFilter.all => 'all',
      };

  Future<void> _load() async {
    if (!mounted) return;
    setState(() { loading = true; _error = null; });
    try {
      final q = <String, String>{'status': _query};
      if (_search.text.trim().isNotEmpty) q['search'] = _search.text.trim();
      if (_dueOnly) q['due'] = '1';
      final rows = await Api.get('/repairs', q);
      final summary = await Api.get('/ledger/repairs').catchError((Object _) => null);
      if (!mounted) return;
      setState(() {
        items = rows as List;
        _summary = summary is Map ? summary.cast<String, dynamic>() : null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
    if (mounted) setState(() => loading = false);
  }

  void _onSearch(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _load);
  }

  Future<void> _openForm([Map<String, dynamic>? job]) async {
    if (supportReadOnlyBlock(context, job == null ? 'add a repair job' : 'edit a repair job')) return;
    Haptics.tap();
    final saved = await SharedAxisRoute.push<bool>(context, (_) => RepairForm(job: job));
    if (saved == true && mounted) {
      toast(context, job == null ? 'Repair job created' : 'Repair job updated');
      _load();
    }
  }

  Future<void> _openDetail(Map row) async {
    Haptics.tap();
    final changed = await SharedAxisRoute.push<bool>(context, (_) => RepairDetailScreen(id: int.parse('${row['id']}')));
    if (changed == true && mounted) _load();
  }

  static ChipTone toneFor(String status) => switch (status) {
        'ready' => ChipTone.success,
        'hold' => ChipTone.warning,
        'cancelled' => ChipTone.error,
        'delivered' => ChipTone.neutral,
        _ => ChipTone.brand,
      };

  static String labelFor(String status) => switch (status) {
        'received' => 'Received',
        'repairing' => 'Repairing',
        'ready' => 'Ready',
        'hold' => 'On hold',
        'delivered' => 'Delivered',
        'cancelled' => 'Cancelled',
        _ => status,
      };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final top = MediaQuery.viewPaddingOf(context).top;
    final summary = _summary;
    return Scaffold(
      body: AuroraBackground(child: Stack(children: [
        RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(Space.screen, top + 64 + Space.x8, Space.screen, Space.x24),
            children: [
              if (summary != null) ...[
                _SummaryRow(summary: summary),
                const SizedBox(height: Space.x12),
              ],
              if (!Api.supportReadOnly)
                PrimaryButton(label: 'New repair job', icon: Icons.build_outlined, onPressed: () => _openForm())
              else
                const ReadOnlyNote(text: 'Support mode is read-only. The shop owner must add or change repair jobs.'),
              const SizedBox(height: Space.x12),
              GlassTextField(
                controller: _search,
                label: 'Search jobs',
                hint: 'Customer, phone, IMEI or job no.',
                prefixIcon: Icons.search,
                onChanged: _onSearch,
                textInputAction: TextInputAction.search,
              ),
              const SizedBox(height: Space.x8),
              _FilterRow(
                filter: filter,
                dueOnly: _dueOnly,
                onFilter: (f) { if (f != filter) { setState(() => filter = f); _load(); } },
                onDue: () { setState(() => _dueOnly = !_dueOnly); _load(); },
              ),
              const SizedBox(height: Space.x12),
              if (_error != null)
                GlassCard(blur: false, child: ErrorState(
                  title: "Couldn't load repairs",
                  message: 'Check your internet connection and try again.',
                  onRetry: _load))
              else if (loading)
                GlassCard(blur: false, child: Shimmer(child: Column(
                  children: List.generate(4, (_) => const SkeletonListTile()))))
              else if (items.isEmpty)
                GlassCard(blur: false, child: EmptyState(
                  icon: Icons.build_outlined,
                  title: filter == RepairFilter.open ? 'No open repair jobs' : 'No repair jobs here',
                  message: 'Add a job when a customer leaves a phone for repair. Advance, status and delivery are all tracked here.',
                  actionLabel: Api.supportReadOnly ? null : 'New repair job',
                  onAction: Api.supportReadOnly ? null : () => _openForm(),
                ))
              else
                for (final row in items) ...[
                  _RepairRow(
                    row: (row as Map).cast<String, dynamic>(),
                    onTap: () => _openDetail(row),
                  ),
                  const SizedBox(height: Space.x8),
                ],
              if (items.isNotEmpty) ...[
                const SizedBox(height: Space.x8),
                Center(child: Text('${items.length} ${items.length == 1 ? 'job' : 'jobs'}',
                  style: context.type.bodySmall?.copyWith(color: c.textSecondary))),
              ],
            ],
          ),
        ),
        Positioned(top: 0, left: 0, right: 0, child: GlassTopBar(title: 'Repairs', scroll: _scroll,
          leading: Navigator.canPop(context) ? const BackButton() : const SizedBox(width: Space.x12))),
      ])),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final Map<String, dynamic> summary;
  const _SummaryRow({required this.summary});

  @override
  Widget build(BuildContext context) {
    final c = context.colors, t = context.type;
    final open = int.tryParse('${summary['open_count'] ?? 0}') ?? 0;
    final ready = int.tryParse('${summary['ready_count'] ?? 0}') ?? 0;
    final due = num.tryParse('${summary['outstanding'] ?? 0}') ?? 0;
    return GlassCard(
      padding: const EdgeInsets.all(Space.x16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('Workshop', style: t.labelLarge?.copyWith(color: c.textSecondary))),
          StatusChip(label: '$open open', tone: open > 0 ? ChipTone.brand : ChipTone.neutral,
            icon: Icons.build_outlined),
        ]),
        const SizedBox(height: Space.x8),
        Wrap(spacing: Space.x16, runSpacing: Space.x8, children: [
          _MiniStat(label: 'Ready to deliver', value: '$ready'),
          _MiniStat(label: 'Repair dues', value: rs(due)),
        ]),
      ]),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label, value;
  const _MiniStat({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: context.type.labelSmall?.copyWith(color: context.colors.textSecondary)),
    const SizedBox(height: 2),
    Text(value, style: context.type.titleMedium),
  ]);
}

class _FilterRow extends StatelessWidget {
  final RepairFilter filter;
  final bool dueOnly;
  final ValueChanged<RepairFilter> onFilter;
  final VoidCallback onDue;
  const _FilterRow({required this.filter, required this.dueOnly, required this.onFilter, required this.onDue});

  @override
  Widget build(BuildContext context) => Wrap(spacing: Space.x8, runSpacing: Space.x8, children: [
    for (final f in RepairFilter.values)
      ChoiceChip(
        label: Text(switch (f) {
          RepairFilter.open => 'Open',
          RepairFilter.ready => 'Ready',
          RepairFilter.delivered => 'Delivered',
          RepairFilter.all => 'All',
        }),
        selected: filter == f,
        onSelected: (_) { Haptics.tick(); onFilter(f); },
      ),
    ChoiceChip(
      label: const Text('Payment due'),
      selected: dueOnly,
      onSelected: (_) { Haptics.tick(); onDue(); },
    ),
  ]);
}

class _RepairRow extends StatelessWidget {
  final Map<String, dynamic> row;
  final VoidCallback onTap;
  const _RepairRow({required this.row, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors, t = context.type;
    final status = '${row['status'] ?? 'received'}';
    final due = num.tryParse('${row['balance_due'] ?? 0}') ?? 0;
    final device = [row['brand'], row['model']].where((e) => e != null && '$e'.trim().isNotEmpty).join(' ');
    final promised = dateOnly(row['promised_date']);
    final late = status != 'delivered' && status != 'cancelled' && promised != '—' &&
        promised.compareTo(dateOnly(DateTime.now().toIso8601String())) < 0;
    return GlassCard(
      blur: false,
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(Space.x12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('${row['customer_name'] ?? 'Customer'}', style: t.titleSmall,
              maxLines: 1, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: Space.x8),
            StatusChip(label: RepairsScreen.labelFor(status).toUpperCase(), tone: RepairsScreen.toneFor(status)),
          ]),
          const SizedBox(height: Space.x4),
          Text('${row['job_no'] ?? ''} · $device',
            style: t.bodySmall?.copyWith(color: c.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: Space.x8),
          Wrap(spacing: Space.x8, runSpacing: Space.x4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            if (row['imei'] != null) Text('IMEI ${row['imei']}',
              style: t.labelSmall?.copyWith(color: c.textSecondary)),
            if (promised != '—')
              IconLabel(icon: late ? Icons.warning_amber_rounded : Icons.event_outlined,
                label: late ? 'Promised $promised' : promised,
                color: late ? c.warningInk : c.textSecondary),
            if (due > 0)
              IconLabel(icon: Icons.account_balance_wallet_outlined,
                label: '${rs(due)} due', color: c.warningInk)
            else if ((num.tryParse('${row['service_charge'] ?? 0}') ?? 0) > 0)
              IconLabel(icon: Icons.check_circle_outline, label: 'Paid', color: c.successInk),
          ]),
        ]),
      ),
    );
  }
}
