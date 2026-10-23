// SUPER ADMIN: free TAC catalogs — coverage, per-catalog sync (Osmocom community +
// extended India-models list), last run and the data limitations. Test hook: testStatus.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api.dart';
import '../design/components/components.dart';
import '../design/design.dart';
import 'common.dart';

/// Shown if an older server does not send its own list.
const tacFallbackLimitations = [
  'Free catalogs are incomplete: many recent and India-only models are still missing.',
  'Only brand and model are provided. RAM, storage and colour must still be entered by the shop.',
  'One TAC can cover several variants; names may be model codes instead of marketing names.',
  'Entries are crowd-sourced and not verified by GSMA. Always check the phone itself before buying.',
  'Sync never deletes rows and never overwrites details learned from your own purchases.',
];

/// Shown if an older server does not send its own catalog list.
const tacFallbackCatalogs = <Map<String, dynamic>>[
  {
    'source': 'osmocom', 'label': 'Community catalog (Osmocom)', 'short': 'Osmocom',
    'note': 'Free community list (brand + model only). Weakest for recent India-only phones.',
    'homepage': 'http://tacdb.osmocom.org/',
  },
  {
    'source': 'tacdb', 'label': 'Extended catalog (India models)', 'short': 'Extended',
    'note': 'Free third-party list of ~250k TACs with recent India variants and internal model codes.',
    'homepage': 'https://github.com/MoazEb/tac-database',
  },
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
  bool _loading = true;
  String? _starting; // catalog source whose sync request is in flight
  Object? _error;
  Timer? _poll;

  Map? get _running => _s?['running'] as Map?;
  bool get _busy => _running != null;

  /// Catalogs the server can sync; older servers only know the Osmocom one.
  List<Map> get _catalogs {
    final fromServer = _s?['catalogs'] as List?;
    if (fromServer != null && fromServer.isNotEmpty) return [for (final c in fromServer) Map<String, dynamic>.from(c as Map)];
    final counts = (_s?['counts'] as Map?) ?? const {};
    return [for (final c in tacFallbackCatalogs) {...c, 'count': _n(counts['${c['source']}'])}];
  }

  @override
  void initState() {
    super.initState();
    if (widget.testStatus != null) { _s = widget.testStatus; _loading = false; }
    else { _load(); }
  }

  @override
  void dispose() { _poll?.cancel(); _scroll.dispose(); super.dispose(); }

  Future<void> _load({bool quiet = false}) async {
    if (!mounted) return;
    if (!quiet) setState(() { _loading = true; _error = null; });
    try {
      final s = await Api.get('/admin/tac/status') as Map;
      if (!mounted) return;
      final wasRunning = _busy;
      setState(() { _s = s; _error = null; _starting = null; });
      if (wasRunning && !_busy) _announce();
    } catch (e) {
      if (mounted && !quiet) setState(() => _error = e);
    }
    if (!mounted) return;
    if (!quiet) setState(() => _loading = false);
    _poll?.cancel();
    if (_busy) _poll = Timer(const Duration(seconds: 3), () => _load(quiet: true));
  }

  static String _short(Map? run, List<Map> catalogs) {
    final source = '${run?['source'] ?? ''}';
    for (final c in catalogs) if ('${c['source']}' == source) return '${c['short'] ?? c['label'] ?? source}';
    return source.isEmpty ? 'TAC' : source;
  }

  void _announce() {
    final r = _s?['last_run'];
    if (r == null) return;
    final name = _short(Map<String, dynamic>.from(r as Map), _catalogs);
    if (r['status'] == 'success') {
      toast(context, '$name sync done: ${r['inserted'] ?? 0} new, ${r['updated'] ?? 0} updated');
    } else if (r['status'] == 'failed') {
      toast(context, '$name sync failed: ${r['error'] ?? 'unknown error'}', err: true);
    }
  }

  Future<void> _sync(Map catalog) async {
    final label = '${catalog['label'] ?? 'catalog'}';
    final note = '${catalog['note'] ?? ''}';
    final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(
      title: Text('Sync $label?'),
      content: Text('The server downloads the free $label and adds missing brand + model entries. '
          'Nothing is deleted and models learned from your shop\'s purchases are never overwritten.\n\n'
          '${note.isEmpty ? '' : '$note\n\n'}'
          'The sync runs in the background — you can leave this screen.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Start sync')),
      ],
    ));
    if (ok != true || !mounted) return;
    setState(() => _starting = '${catalog['source']}');
    try {
      await Api.post('/admin/tac/sync/${catalog['source']}', {});
      if (mounted) toast(context, 'Sync started — this can take a few minutes');
    } catch (e) {
      // 409 = already running; refreshing shows the active run either way.
      if (mounted) toast(context, '$e'.replaceFirst('Exception: ', ''), err: true);
    }
    if (!mounted) return;
    setState(() => _starting = null);
    await _load(quiet: true);
  }

  static String _when(dynamic v) {
    if (v == null) return '—';
    final d = DateTime.tryParse('$v');
    return d == null ? '$v' : DateFormat('d MMM yyyy, h:mm a').format(d.toLocal());
  }

  static int _n(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

  static IconData _sourceIcon(String source) => switch (source) {
        'learned' => Icons.storefront_outlined,
        'csv' => Icons.upload_file_outlined,
        'api' => Icons.cloud_download_outlined,
        _ => Icons.history,
      };

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
              else ..._body(context),
            ],
          ),
        ),
        Positioned(top: 0, left: 0, right: 0, child: GlassTopBar(title: 'TAC catalog', scroll: _scroll, leading: const BackButton())),
      ])),
    );
  }

  List<Widget> _body(BuildContext context) => [
        _LimitationsCard(items: [for (final x in (_s?['limitations'] as List? ?? tacFallbackLimitations)) '$x']),
        const SizedBox(height: Space.section),
        const SectionHeader(title: 'Catalog coverage'),
        const SizedBox(height: Space.x12),
        _coverage(context),
        const SizedBox(height: Space.x16),
        _ownData(context),
        const SizedBox(height: Space.section),
        const SectionHeader(title: 'Last sync'),
        const SizedBox(height: Space.x12),
        _lastRun(context),
        const SizedBox(height: Space.x16),
        _attribution(context),
      ];

  Widget _coverage(BuildContext context) {
    final c = context.colors, t = context.type;
    return GlassCard(blur: false, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${_n(_s?['total'])}', style: t.headlineSmall),
      Text('TACs known to the server', style: t.bodySmall?.copyWith(color: c.textSecondary)),
      const SizedBox(height: Space.x16),
      for (var i = 0; i < _catalogs.length; i++) ...[
        if (i > 0) Divider(height: Space.x24, color: c.textPrimary.withValues(alpha: .08)),
        _catalogRow(context, _catalogs[i]),
      ],
    ]));
  }

  Widget _catalogRow(BuildContext context, Map catalog) {
    final c = context.colors, t = context.type;
    final source = '${catalog['source']}';
    final running = _busy && '${_running?['source']}' == source;
    final lastSuccess = catalog['last_success'] as Map?;
    final count = _n(catalog['count']);
    final note = '${catalog['note'] ?? ''}'.trim();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.public, size: 20, color: c.brandInk),
        const SizedBox(width: Space.x12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${catalog['label'] ?? source}', style: t.titleSmall),
          if (note.isNotEmpty) ...[
            const SizedBox(height: Space.x4),
            Text(note, style: t.bodySmall?.copyWith(color: c.textSecondary)),
          ],
          const SizedBox(height: Space.x8),
          Wrap(spacing: Space.x8, runSpacing: Space.x4, children: [
            StatusChip(label: '$count TACs', tone: ChipTone.brand, icon: Icons.tag),
            if (lastSuccess != null)
              StatusChip(label: 'Synced ${_when(lastSuccess['finished_at'])}', tone: ChipTone.neutral, icon: Icons.check_circle_outline)
            else
              const StatusChip(label: 'Never synced', tone: ChipTone.neutral, icon: Icons.cloud_off_outlined),
          ]),
        ])),
        const SizedBox(width: Space.x12),
        PrimaryButton(
          label: 'Sync', icon: Icons.sync, expand: false,
          phase: running || _starting == source ? ButtonPhase.loading : ButtonPhase.idle,
          onPressed: _busy || _starting != null ? null : () => _sync(catalog),
        ),
      ]),
      if (running) ...[
        const SizedBox(height: Space.x8),
        Text('Downloading and merging on the server. You can leave this screen.',
            style: t.bodySmall?.copyWith(color: c.textSecondary)),
      ],
    ]);
  }

  Widget _ownData(BuildContext context) {
    final c = context.colors, t = context.type;
    final counts = (_s?['counts'] as Map?) ?? const {};
    final fromServer = _s?['local'] as List?;
    final rows = fromServer != null
        ? [for (final l in fromServer) ('${l['source']}', '${l['label']}', _n(l['count']))]
        : [
            ('learned', 'Learned from shop purchases', _n(counts['learned'])),
            ('csv', 'Admin CSV import', _n(counts['csv'])),
            if (_n(counts['api']) > 0) ('api', 'External TAC API (optional)', _n(counts['api'])),
            ('older', 'Older / sample entries', _n(counts['legacy']) + _n(counts['seed'])),
          ];
    return GlassCard(blur: false, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.lock_outline, size: 18, color: c.successInk),
        const SizedBox(width: Space.x8),
        Expanded(child: Text('Your own data', style: t.titleSmall)),
      ]),
      const SizedBox(height: Space.x4),
      Text('A sync never deletes or overwrites these — they are what the buy form trusts most.',
          style: t.bodySmall?.copyWith(color: c.textSecondary)),
      const SizedBox(height: Space.x12),
      for (final r in rows) Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.x4),
        child: Row(children: [
          Icon(_sourceIcon(r.$1), size: 20, color: c.brandInk),
          const SizedBox(width: Space.x12),
          Expanded(child: Text(r.$2, style: t.bodyMedium)),
          Text('${r.$3}', style: t.titleSmall),
        ]),
      ),
    ]));
  }

  Widget _lastRun(BuildContext context) {
    final c = context.colors, t = context.type;
    final run = _running ?? (_s?['last_run'] as Map?);
    final ok = _s?['last_success'] as Map?;
    if (run == null) {
      return GlassCard(blur: false, child: Row(children: [
        const StatusChip(label: 'Never synced', tone: ChipTone.neutral, icon: Icons.cloud_off_outlined),
        const SizedBox(width: Space.x12),
        Expanded(child: Text('Tap Sync on a catalog to add the free lists.', style: t.bodySmall?.copyWith(color: c.textSecondary))),
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
        const SizedBox(width: Space.x8),
        StatusChip(label: _short(Map<String, dynamic>.from(run), _catalogs), tone: ChipTone.neutral, icon: Icons.public),
        const Spacer(),
        Text(_when(run['finished_at'] ?? run['started_at']),
            style: t.bodySmall?.copyWith(color: c.textSecondary), textAlign: TextAlign.end),
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
    final licenses = _s?['licenses'] as List?;
    final lines = licenses != null && licenses.isNotEmpty
        ? [for (final l in licenses) '${l['attribution'] ?? l['name']}\n${l['homepage'] ?? ''}'.trim()]
        : [
            '${(_s?['catalog'] as Map?)?['attribution'] ?? 'TAC data: Osmocom TAC database, CC-BY-SA 3.0'}\n'
                '${(_s?['catalog'] as Map?)?['homepage'] ?? 'http://tacdb.osmocom.org/'}',
          ];
    return Text(lines.join('\n\n'), textAlign: TextAlign.center, style: t.labelSmall?.copyWith(color: c.textSecondary));
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
