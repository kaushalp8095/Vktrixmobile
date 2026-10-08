// SUPER ADMIN: free community TAC catalog (Osmocom) — coverage, sync button, last run,
// and the data limitations (incomplete, brand/model only, unverified). Test hook: testStatus.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api.dart';
import '../design/components/components.dart';
import '../design/design.dart';
import 'common.dart';

/// Shown if an older server does not send its own list.
const tacFallbackLimitations = [
  'Community catalog is incomplete: many recent and India-only models are missing.',
  'Only brand and model are provided. RAM, storage and colour must still be entered by the shop.',
  'One TAC can cover several variants; names may be model codes instead of marketing names.',
  'Entries are crowd-sourced and not verified by GSMA. Always check the phone itself before buying.',
  'Sync never deletes rows and never overwrites details learned from your own purchases.',
];

class TacCatalogScreen extends StatefulWidget {
  final Map<String, dynamic>? testStatus;
  const TacCatalogScreen({super.key, this.testStatus});
  @override
  State<TacCatalogScreen> createState() => _TacCatalogScreenState();
}

class _TacCatalogScreenState extends State<TacCatalogScreen> {
  final _scroll = ScrollController();
  Map? _s;
  bool _loading = true, _starting = false;
  Object? _error;
  Timer? _poll;

  bool get _running => _s?['running'] != null;

  @override
  void initState() {
    super.initState();
    if (widget.testStatus != null) { _s = widget.testStatus; _loading = false; }
    else { _load(); }
  }

  @override
  void dispose() { _poll?.cancel(); _scroll.dispose(); super.dispose(); }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) setState(() { _loading = true; _error = null; });
    try {
      final s = await Api.get('/admin/tac/status') as Map;
      if (!mounted) return;
      final wasRunning = _running;
      setState(() { _s = s; _error = null; });
      if (wasRunning && !_running) _announce();
    } catch (e) {
      if (mounted && !quiet) setState(() => _error = e);
    }
    if (!mounted) return;
    if (!quiet) setState(() => _loading = false);
    _poll?.cancel();
    if (_running) _poll = Timer(const Duration(seconds: 3), () => _load(quiet: true));
  }

  void _announce() {
    final r = _s?['last_run'];
    if (r == null) return;
    if (r['status'] == 'success') {
      toast(context, 'TAC sync done: ${r['inserted'] ?? 0} new, ${r['updated'] ?? 0} updated');
    } else if (r['status'] == 'failed') {
      toast(context, 'TAC sync failed: ${r['error'] ?? 'unknown error'}', err: true);
    }
  }

  Future<void> _sync() async {
    final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(
      title: const Text('Sync free TAC catalog?'),
      content: const Text('The server downloads the free Osmocom community TAC list (a few MB) and adds missing '
          'models. Nothing is deleted, and models learned from your shops\' purchases are never overwritten.\n\n'
          'The community list is incomplete — many new or India-only phones will still need manual entry.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Start sync')),
      ],
    ));
    if (ok != true || !mounted) return;
    setState(() => _starting = true);
    try {
      await Api.post('/admin/tac/sync', {});
      if (mounted) toast(context, 'Sync started — this can take a minute or two');
    } catch (e) {
      // 409 = already running; refreshing shows the active run either way.
      if (mounted) toast(context, '$e'.replaceFirst('Exception: ', ''), err: true);
    }
    if (!mounted) return;
    setState(() => _starting = false);
    await _load(quiet: true);
  }

  static String _when(dynamic v) {
    if (v == null) return '—';
    final d = DateTime.tryParse('$v');
    return d == null ? '$v' : DateFormat('d MMM yyyy, h:mm a').format(d.toLocal());
  }

  static int _n(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.viewPaddingOf(context).top;
    return Scaffold(
      body: AuroraBackground(child: Stack(children: [
        RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(Space.screen, top + 64 + Space.x8, Space.screen, 48),
            children: [
              if (_loading)
                GlassCard(blur: false, child: Shimmer(child: Column(children: List.generate(3, (_) => const SkeletonListTile()))))
              else if (_error != null)
                ErrorState(title: "Couldn't load TAC catalog", message: 'Check your internet and pull to retry.', onRetry: _load)
              else ...[
                _LimitationsCard(items: [for (final x in (_s?['limitations'] as List? ?? tacFallbackLimitations)) '$x']),
                const SizedBox(height: Space.section),
                const SectionHeader(title: 'Catalog coverage'),
                const SizedBox(height: Space.x12),
                _coverage(context),
                const SizedBox(height: Space.section),
                const SectionHeader(title: 'Last sync'),
                const SizedBox(height: Space.x12),
                _lastRun(context),
                const SizedBox(height: Space.section),
                PrimaryButton(
                  label: _running ? 'Sync running…' : 'Sync free catalog now', icon: Icons.sync,
                  phase: _running || _starting ? ButtonPhase.loading : ButtonPhase.idle,
                  onPressed: _running || _starting ? null : _sync,
                ),
                const SizedBox(height: Space.x16),
                _attribution(context),
              ],
            ],
          ),
        ),
        Positioned(top: 0, left: 0, right: 0, child: GlassTopBar(title: 'TAC catalog', scroll: _scroll, leading: const BackButton())),
      ])),
    );
  }

  Widget _coverage(BuildContext context) {
    final c = context.colors, t = context.type;
    final counts = (_s?['counts'] as Map?) ?? const {};
    final rows = [
      (Icons.public, 'Community catalog (Osmocom)', _n(counts['osmocom'])),
      (Icons.storefront_outlined, 'Learned from shop purchases', _n(counts['learned'])),
      (Icons.upload_file_outlined, 'Admin CSV import', _n(counts['csv'])),
      (Icons.history, 'Older / sample entries', _n(counts['legacy']) + _n(counts['seed'])),
    ];
    return GlassCard(blur: false, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${_n(_s?['total'])}', style: t.headlineSmall),
      Text('TACs known to the server', style: t.bodySmall?.copyWith(color: c.textSecondary)),
      const SizedBox(height: Space.x12),
      for (final r in rows) Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.x4),
        child: Row(children: [
          Icon(r.$1, size: 20, color: c.brandInk),
          const SizedBox(width: Space.x12),
          Expanded(child: Text(r.$2, style: t.bodyMedium)),
          Text('${r.$3}', style: t.titleSmall),
        ]),
      ),
    ]));
  }

  Widget _lastRun(BuildContext context) {
    final c = context.colors, t = context.type;
    final run = (_s?['running'] ?? _s?['last_run']) as Map?;
    final ok = _s?['last_success'] as Map?;
    if (run == null) {
      return GlassCard(blur: false, child: Row(children: [
        const StatusChip(label: 'Never synced', tone: ChipTone.neutral, icon: Icons.cloud_off_outlined),
        const SizedBox(width: Space.x12),
        Expanded(child: Text('Tap sync to add the free community list.', style: t.bodySmall?.copyWith(color: c.textSecondary))),
      ]));
    }
    final (tone, icon, label) = switch (run['status']) {
      'running' => (ChipTone.brand, Icons.sync, 'Running'),
      'success' => (ChipTone.success, Icons.check_circle_outline, 'Success'),
      _ => (ChipTone.error, Icons.error_outline, 'Failed'),
    };
    final details = run['status'] == 'success'
        ? '${_n(run['inserted'])} new · ${_n(run['updated'])} updated · ${_n(run['unchanged'])} unchanged · '
          '${_n(run['protected'])} kept (shop/CSV data) · ${_n(run['invalid'])} skipped'
        : null;
    return GlassCard(blur: false, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        StatusChip(label: label, tone: tone, icon: icon),
        const SizedBox(width: Space.x12),
        Expanded(child: Text(_when(run['finished_at'] ?? run['started_at']),
            style: t.bodySmall?.copyWith(color: c.textSecondary), textAlign: TextAlign.end)),
      ]),
      if (run['status'] == 'running') ...[
        const SizedBox(height: Space.x12),
        Text('Downloading and merging on the server. You can leave this screen.', style: t.bodySmall),
      ],
      if (details != null) ...[
        const SizedBox(height: Space.x12),
        Text('${_n(run['rows_seen'])} TACs in upstream file', style: t.bodyMedium),
        const SizedBox(height: Space.x4),
        Text(details, style: t.bodySmall?.copyWith(color: c.textSecondary)),
      ],
      if (run['status'] == 'failed') ...[
        const SizedBox(height: Space.x12),
        Text('${run['error'] ?? 'Unknown error'}', style: t.bodySmall?.copyWith(color: c.errorInk)),
        const SizedBox(height: Space.x4),
        Text('Nothing was changed. Existing data is still used for IMEI auto-fill.', style: t.bodySmall?.copyWith(color: c.textSecondary)),
        if (ok != null) ...[
          const SizedBox(height: Space.x4),
          Text('Last successful sync: ${_when(ok['finished_at'])}', style: t.bodySmall?.copyWith(color: c.textSecondary)),
        ],
      ],
    ]));
  }

  Widget _attribution(BuildContext context) {
    final c = context.colors, t = context.type;
    final cat = (_s?['catalog'] as Map?) ?? const {};
    final text = cat['attribution'] ?? 'TAC data: Osmocom TAC database, CC-BY-SA 3.0';
    final home = cat['homepage'] ?? 'http://tacdb.osmocom.org/';
    return Text('$text\n$home', textAlign: TextAlign.center, style: t.labelSmall?.copyWith(color: c.textSecondary));
  }
}

class _LimitationsCard extends StatelessWidget {
  final List<String> items;
  const _LimitationsCard({required this.items});
  @override
  Widget build(BuildContext context) {
    final c = context.colors, t = context.type;
    return GlassCard(blur: false, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.info_outline, color: c.warningInk),
        const SizedBox(width: Space.x8),
        Expanded(child: Text('Community data — verify before buying', style: t.titleSmall)),
      ]),
      const SizedBox(height: Space.x8),
      for (final x in items) Padding(
        padding: const EdgeInsets.only(top: Space.x4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('•  ', style: t.bodySmall),
          Expanded(child: Text(x, style: t.bodySmall?.copyWith(color: c.textSecondary))),
        ]),
      ),
    ]));
  }
}
