// SALES: sold phones + profit; tap → glass detail sheet → cancel sale (confirm).
import 'package:flutter/material.dart';
import '../api.dart';
import '../design/components/components.dart';
import '../design/design.dart';
import 'common.dart';

class SalesScreen extends StatefulWidget {
  final List<dynamic>? testItems; // test hook
  const SalesScreen({super.key, this.testItems});
  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  List items = [];
  bool loading = true;
  Object? _error;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    if (widget.testItems != null) { items = widget.testItems!; loading = false; } else { _load(); }
  }

  @override
  void dispose() { _scroll.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() { loading = true; _error = null; });
    try { items = await Api.get('/sales'); }
    catch (e) { if (mounted) setState(() => _error = e); }
    if (mounted) setState(() => loading = false);
  }

  num _profit(Map s) => (num.tryParse('${s['sell_price']}') ?? 0) - (num.tryParse('${s['buy_price']}') ?? 0);

  Future<void> _details(Map s) async {
    Haptics.tap();
    final cancel = await showModalBottomSheet<bool>(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (c) => _SaleDetailSheet(sale: s, profit: _profit(s), onCancel: () => Navigator.pop(c, true)),
    );
    if (cancel != true || !mounted) return;
    final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(
      title: const Text('Cancel this sale?'),
      content: Text('${s['brand']} ${s['model']} will go back into stock.'),
      actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Keep sale')),
        FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Cancel sale'))],
    ));
    if (ok == true) {
      try { await Api.delete('/sales/${s['id']}'); if (mounted) toast(context, 'Sale cancelled — phone is back in stock'); _load(); }
      catch (e) { if (mounted) toast(context, '$e', err: true); }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final top = MediaQuery.viewPaddingOf(context).top;
    return Stack(children: [
      RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(Space.screen, top + 64 + Space.x8, Space.screen, Space.x24),
          children: [
            if (loading)
              GlassCard(blur: false, child: Shimmer(child: Column(children: List.generate(5, (_) => const SkeletonListTile()))))
            else if (_error != null)
              ErrorState(title: "Couldn't load sales", message: 'Check your internet and pull to retry.', onRetry: _load)
            else if (items.isEmpty)
              const GlassCard(blur: false, child: EmptyState(icon: Icons.sell_outlined, title: 'No sales yet',
                  message: 'Sell a phone from Stock and it will appear here with its profit.'))
            else
              GlassCard(blur: false, padding: EdgeInsets.zero, child: Column(children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) Divider(height: 1, indent: 68, color: c.textPrimary.withValues(alpha: .08)),
                  _SaleRow(s: items[i], profit: _profit(items[i]), onTap: () => _details(items[i])),
                ],
              ])),
          ],
        ),
      ),
      Positioned(top: 0, left: 0, right: 0, child: GlassTopBar(title: 'Sales', scroll: _scroll,
          leading: const SizedBox(width: Space.x12),
          actions: [GlassIconButton(icon: Icons.refresh, semanticLabel: 'Refresh sales', onPressed: _load)])),
    ]);
  }
}

class _SaleRow extends StatelessWidget {
  final Map s; final num profit; final VoidCallback onTap;
  const _SaleRow({required this.s, required this.profit, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final c = context.colors, t = context.type;
    final pay = '${s['payment_mode'] ?? 'cash'}'.toUpperCase();
    return Semantics(
      button: true, label: '${s['brand']} ${s['model']}, sold for ${rs(s['sell_price'])}, profit ${rs(profit)}',
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.x16, vertical: Space.x12),
          child: Row(children: [
            Container(width: 44, height: 44,
              decoration: BoxDecoration(color: c.success.withValues(alpha: .12), borderRadius: BorderRadius.circular(Radii.md)),
              child: Icon(Icons.sell_outlined, color: c.success, size: 22)),
            const SizedBox(width: Space.x12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${s['brand']} ${s['model']}', style: t.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text([if ((s['customer_name'] ?? '').toString().isNotEmpty) s['customer_name'], '${s['sell_date']}', pay]
                  .join(' · '), style: t.bodySmall?.copyWith(color: c.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
            ])),
            const SizedBox(width: Space.x12),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(rs(s['sell_price']), style: t.titleSmall),
              Text(profit >= 0 ? '+${rs(profit)}' : '−${rs(-profit)}',
                  style: t.labelSmall?.copyWith(color: profit >= 0 ? c.successInk : c.errorInk)),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _SaleDetailSheet extends StatelessWidget {
  final Map sale; final num profit; final VoidCallback onCancel;
  const _SaleDetailSheet({required this.sale, required this.profit, required this.onCancel});
  @override
  Widget build(BuildContext context) {
    final c = context.colors, t = context.type;
    final s = sale;
    final rows = <(String, String)>[
      ('IMEI', '${s['imei']}'),
      ('RAM / Storage', '${s['ram'] ?? '—'} / ${s['storage'] ?? '—'}'),
      ('Bought at', rs(s['buy_price'])), ('Sold at', rs(s['sell_price'])),
      ('Sell date', '${s['sell_date']}'), ('Payment', '${s['payment_mode'] ?? 'cash'}'.toUpperCase()),
      if ((s['customer_name'] ?? '').toString().isNotEmpty) ('Customer', '${s['customer_name']}${s['customer_phone'] != null ? ' · ${s['customer_phone']}' : ''}'),
      if ((s['customer_address'] ?? '').toString().isNotEmpty) ('Address', '${s['customer_address']}'),
      if ((s['warranty'] ?? '').toString().isNotEmpty) ('Warranty', '${s['warranty']}'),
      if ((s['notes'] ?? '').toString().isNotEmpty) ('Notes', '${s['notes']}'),
    ];
    return Padding(
      padding: EdgeInsets.fromLTRB(Space.x16, 0, Space.x16, MediaQuery.viewPaddingOf(context).bottom + Space.x16),
      child: GlassSurface(child: SafeArea(top: false, child: SingleChildScrollView(
        padding: const EdgeInsets.all(Space.x20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: c.textPrimary.withValues(alpha: .20), borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: Space.x16),
          Semantics(header: true, child: Text('${s['brand']} ${s['model']}', style: t.headlineSmall)),
          const SizedBox(height: Space.x4),
          StatusChip(label: profit >= 0 ? '+${rs(profit)} profit' : '−${rs(-profit)} loss', tone: profit >= 0 ? ChipTone.success : ChipTone.error),
          const SizedBox(height: Space.x16),
          for (final r in rows) Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 100, child: Text(r.$1, style: t.bodyMedium?.copyWith(color: c.textSecondary))),
              Expanded(child: SelectableText(r.$2, style: t.bodyMedium)),
            ])),
          const SizedBox(height: Space.x20),
          Center(child: TextButton(
            onPressed: onCancel,
            child: Text('Cancel sale (returns to stock)', style: t.labelLarge?.copyWith(color: c.errorInk)),
          )),
        ]),
      ))),
    );
  }
}
