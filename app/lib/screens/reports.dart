// REPORTS: preset range chips → summary hero → custom daily bar chart (CustomPainter,
// no chart dependency) → payment split → top models. Test hooks: testSummary/testDaily.
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api.dart';
import '../design/components/components.dart';
import '../design/design.dart';

class ReportsScreen extends StatefulWidget {
  final Map<String, dynamic>? testSummary;
  final List<dynamic>? testDaily;
  final String testPreset;
  const ReportsScreen({super.key, this.testSummary, this.testDaily, this.testPreset = 'month'});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final f = DateFormat('yyyy-MM-dd');
  late DateTimeRange range;
  String preset = 'month';
  Map? d; List daily = [];
  bool loading = true;
  Object? _error;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _applyPreset(widget.testPreset);
    if (widget.testSummary != null) { d = widget.testSummary; daily = widget.testDaily ?? []; loading = false; }
    else _load();
  }

  void _applyPreset(String p) {
    final n = DateTime.now();
    preset = p;
    range = switch (p) {
      'today' => DateTimeRange(start: n, end: n),
      'week' => DateTimeRange(start: n.subtract(const Duration(days: 6)), end: n),
      'year' => DateTimeRange(start: DateTime(n.year, 1, 1), end: n),
      _ => DateTimeRange(start: DateTime(n.year, n.month, 1), end: n),
    };
  }

  Future<void> _load() async {
    setState(() { loading = true; _error = null; });
    final q = {'from': f.format(range.start), 'to': f.format(range.end)};
    try {
      final r = await Future.wait([Api.get('/reports/summary', q), Api.get('/reports/daily', q)]);
      if (!mounted) return;
      setState(() { d = r[0] as Map; daily = r[1] as List; });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  void dispose() { _scroll.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final c = context.colors, t = context.type;
    final top = MediaQuery.viewPaddingOf(context).top;
    final presets = {'today': 'Today', 'week': '7 days', 'month': 'This month', 'year': 'This year'};
    return Stack(children: [
      ListView(
        controller: _scroll,
        padding: EdgeInsets.fromLTRB(Space.screen, top + 64 + Space.x8, Space.screen, Space.x24),
        children: [
          // ---- Range picker ----
          SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
            for (final e in presets.entries) Padding(
              padding: const EdgeInsets.only(right: Space.x8),
              child: _RangeChip(label: e.value, selected: preset == e.key,
                  onTap: () { Haptics.tick(); _applyPreset(e.key); _load(); })),
            _RangeChip(label: preset == 'custom' ? 'Custom ✓' : 'Custom', selected: preset == 'custom',
                icon: Icons.date_range, onTap: () async {
                  final r = await showDateRangePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime.now(), initialDateRange: range);
                  if (r != null) { setState(() { range = r; preset = 'custom'; }); _load(); }
                }),
          ])),
          const SizedBox(height: Space.x8),
          Padding(padding: const EdgeInsets.only(left: Space.x4),
            child: Text('${DateFormat('d MMM').format(range.start)} → ${DateFormat('d MMM yyyy').format(range.end)}',
                style: t.bodySmall?.copyWith(color: c.textSecondary))),
          const SizedBox(height: Space.x16),
          if (loading)
            GlassCard(child: Shimmer(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
                  SkeletonBox(width: 90, height: 14), SizedBox(height: Space.x12), SkeletonBox(width: 180, height: 34),
                  SizedBox(height: Space.x16), SkeletonBox(height: 140)])))
          else if (_error != null)
            ErrorState(title: "Couldn't load report", message: 'Check your internet and try again.', onRetry: _load)
          else ...[
            // ---- Profit hero ----
            GlassCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Net profit', style: t.labelLarge?.copyWith(color: c.textSecondary)),
              const SizedBox(height: Space.x4),
              Text(rs(d!['sales']['profit']), style: t.displaySmall?.copyWith(
                  color: (d!['sales']['profit'] ?? 0) >= 0 ? c.brandInk : c.errorInk)),
              const SizedBox(height: Space.x8),
              Wrap(spacing: Space.x8, runSpacing: Space.x8, children: [
                StatusChip(label: '${d!['sales']['count']} sold · ${rs(d!['sales']['amount'])}', tone: ChipTone.brand, icon: Icons.sell_outlined),
                StatusChip(label: '${d!['purchases']['count']} bought · ${rs(d!['purchases']['amount'])}', tone: ChipTone.neutral, icon: Icons.call_received),
              ]),
            ])),
            const SizedBox(height: Space.x16),
            // ---- Daily chart ----
            if (daily.isNotEmpty) ...[
              GlassCard(blur: false, child: DailyChart(daily: daily)),
              const SizedBox(height: Space.x16),
            ] else
              Padding(padding: const EdgeInsets.only(bottom: Space.x16),
                child: GlassCard(blur: false, child: const EmptyState(icon: Icons.show_chart, title: 'No sales in this range',
                    message: 'Pick a wider range above to see the daily chart.'))),
            // ---- Payment split + top models ----
            if ((d!['by_payment'] as List).isNotEmpty || (d!['top_models'] as List).isNotEmpty)
              GlassCard(blur: false, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if ((d!['by_payment'] as List).isNotEmpty) ...[
                  Text('By payment', style: t.titleMedium),
                  const SizedBox(height: Space.x8),
                  for (final p in d!['by_payment'])
                    _BreakRow(label: '${p['mode']}'.toUpperCase(), count: '${p['count']}', amount: rs(p['total']),
                        total: (d!['by_payment'] as List).fold<num>(1, (a, b) => b['total'] > a ? b['total'] : a), value: p['total']),
                  const SizedBox(height: Space.x16),
                ],
                if ((d!['top_models'] as List).isNotEmpty) ...[
                  Text('Top selling models', style: t.titleMedium),
                  const SizedBox(height: Space.x8),
                  for (final m in (d!['top_models'] as List).take(5))
                    _BreakRow(label: '${m['brand']} ${m['model']}', count: '${m['count']} sold', amount: '',
                        total: (d!['top_models'] as List).first['count'], value: m['count']),
                ],
              ])),
          ],
        ],
      ),
      Positioned(top: 0, left: 0, right: 0, child: GlassTopBar(title: 'Reports', scroll: _scroll,
          leading: const SizedBox(width: Space.x12),
          actions: [GlassIconButton(icon: Icons.refresh, semanticLabel: 'Refresh report', onPressed: _load)])),
    ]);
  }
}

class _RangeChip extends StatelessWidget {
  final String label; final bool selected; final IconData? icon; final VoidCallback onTap;
  const _RangeChip({required this.label, required this.selected, this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final c = context.colors, t = context.type, s = context.scheme;
    return Semantics(
      button: true, selected: selected, label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.full), onTap: onTap,
        child: AnimatedContainer(
          duration: Motion.of(context).d(Durations2.enter), curve: Curves2.enter,
          height: 40, padding: const EdgeInsets.symmetric(horizontal: Space.x16),
          decoration: BoxDecoration(
            color: selected ? c.brandInk : c.textPrimary.withValues(alpha: .06),
            borderRadius: BorderRadius.circular(Radii.full),
            border: Border.all(color: selected ? Colors.transparent : c.textPrimary.withValues(alpha: .10)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 16, color: selected ? s.onPrimary : c.textSecondary), const SizedBox(width: Space.x4)],
            Text(label, style: t.labelLarge?.copyWith(color: selected ? s.onPrimary : c.textPrimary)),
          ]),
        ),
      ),
    );
  }
}

class _BreakRow extends StatelessWidget {
  final String label, count, amount; final num total, value;
  const _BreakRow({required this.label, required this.count, required this.amount, required this.total, required this.value});
  @override
  Widget build(BuildContext context) {
    final c = context.colors, t = context.type, s = context.scheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(label, style: t.bodyMedium, maxLines: 1, overflow: TextOverflow.ellipsis)),
          Text(count, style: t.bodySmall?.copyWith(color: c.textSecondary)),
          if (amount.isNotEmpty) ...[const SizedBox(width: Space.x8), Text(amount, style: t.titleSmall)],
        ]),
        const SizedBox(height: 5),
        Semantics(
          label: '$label $count $amount',
          child: ClipRRect(borderRadius: BorderRadius.circular(3),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: (value / total).clamp(0.0, 1.0)),
              duration: Motion.of(context).d(const Duration(milliseconds: 500)), curve: Curves2.enter,
              builder: (context, f, _) => LinearProgressIndicator(value: f, minHeight: 6,
                  color: s.primary, backgroundColor: c.textPrimary.withValues(alpha: .08)),
            ))),
      ]),
    );
  }
}

/// Daily sales bar chart painted by hand — no chart package. Bars animate in;
/// each bar announces its day + amount to TalkBack via the semantics summary below.
class DailyChart extends StatelessWidget {
  final List daily;
  const DailyChart({super.key, required this.daily});
  @override
  Widget build(BuildContext context) {
    final c = context.colors, t = context.type, s = context.scheme;
    final maxV = daily.fold<num>(1, (a, b) => (b['sales'] as num? ?? 0) > a ? b['sales'] : a);
    final bars = daily.take(14).toList();
    final summary = bars.map((x) => '${x['date']}: ${rs(x['sales'])}').join(', ');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Daily sales', style: t.titleMedium),
      const SizedBox(height: Space.x12),
      Semantics(
        label: 'Bar chart of daily sales. Largest day ${rs(maxV)}. $summary', image: true,
        child: SizedBox(height: 150, child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: Motion.of(context).d(const Duration(milliseconds: 600)), curve: Curves2.enter,
          builder: (context, anim, _) => CustomPaint(
            size: Size.infinite,
            painter: _BarsPainter(
              values: [for (final x in bars) (x['sales'] as num? ?? 0).toDouble()],
              labels: [for (final x in bars) '${x['date']}'.substring(8)],
              max: maxV.toDouble(), anim: anim, color: s.primary,
              grid: c.textPrimary.withValues(alpha: .10), labelColor: c.textSecondary,
            ),
          )))),
      const SizedBox(height: Space.x4),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('₹0', style: t.labelSmall?.copyWith(color: c.textSecondary)),
        Text(rs(maxV), style: t.labelSmall?.copyWith(color: c.textSecondary)),
      ]),
    ]);
  }
}

class _BarsPainter extends CustomPainter {
  final List<double> values; final List<String> labels; final double max, anim;
  final Color color, grid, labelColor;
  _BarsPainter({required this.values, required this.labels, required this.max, required this.anim,
      required this.color, required this.grid, required this.labelColor});

  @override
  void paint(Canvas canvas, Size size) {
    final gp = Paint()..color = grid..strokeWidth = 1;
    for (final f in [0.0, 0.25, 0.5, 0.75, 1.0]) {
      final y = size.height - 20 - (size.height - 28) * f;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gp);
    }
    if (values.isEmpty) return;
    final slot = size.width / values.length;
    final bw = (slot * 0.52).clamp(6.0, 40.0);
    final tp = TextPainter(textDirection: ui.TextDirection.ltr);
    for (var i = 0; i < values.length; i++) {
      final v = values[i] / max;
      final h = (size.height - 28) * v * anim;
      final x = slot * i + (slot - bw) / 2;
      final rect = RRect.fromRectAndRadius(Rect.fromLTWH(x, size.height - 20 - h, bw, h < 2 ? 2 : h), const Radius.circular(4));
      canvas.drawRRect(rect, Paint()..color = color.withValues(alpha: values[i] == 0 ? .25 : 1));
      if (values.length <= 10 || i.isEven) {
        tp.text = TextSpan(text: labels[i], style: TextStyle(color: labelColor, fontSize: 9, fontFamily: 'Manrope'));
        tp.layout();
        tp.paint(canvas, Offset(slot * i + (slot - tp.width) / 2, size.height - 16));
      }
    }
  }

  @override
  bool shouldRepaint(_BarsPainter o) => o.anim != anim || o.values != values || o.color != color;
}
