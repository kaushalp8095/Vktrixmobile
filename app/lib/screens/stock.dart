// STOCK: search + in-stock phone rows → glass detail sheet → Sell flow.
import 'package:flutter/material.dart';
import '../api.dart';
import '../design/components/components.dart';
import '../design/design.dart';
import 'common.dart';
import 'sell_form.dart';

class StockScreen extends StatefulWidget {
  final List<dynamic>? testItems; // test hook
  final VoidCallback? onBuy;
  const StockScreen({super.key, this.testItems, this.onBuy});
  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> {
  List items = [];
  bool loading = true;
  Object? _error;
  final _search = TextEditingController();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    if (widget.testItems != null) { items = widget.testItems!; loading = false; } else { _load(); }
  }

  @override
  void dispose() { _search.dispose(); _scroll.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() { loading = true; _error = null; });
    try { items = await Api.get('/stock', {'search': _search.text}); }
    catch (e) { if (mounted) setState(() => _error = e); }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _details(Map p) async {
    Haptics.tap();
    final action = await showModalBottomSheet<String>(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (c) => _PhoneDetailSheet(phone: p, onSell: () => Navigator.pop(c, 'sell'), onDelete: () => Navigator.pop(c, 'delete')),
    );
    if (action == 'delete') {
      try { await Api.delete('/phones/${p['id']}'); _load(); } catch (e) { if (mounted) toast(context, '$e', err: true); }
    } else if (action == 'sell' && mounted) {
      final ok = await SharedAxisRoute.push<bool>(context, (_) => SellForm(phone: Map<String, dynamic>.from(p)));
      if (ok == true) _load();
    }
  }

  String _age(String? iso) {
    final d = DateTime.tryParse('${iso ?? ''}');
    if (d == null) return '';
    final days = DateTime.now().difference(d).inDays;
    return days == 0 ? 'today' : days == 1 ? '1 day' : '$days days';
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
            GlassTextField(controller: _search, label: 'Search model, brand or IMEI', prefixIcon: Icons.search,
                onChanged: (_) => _load()),
            const SizedBox(height: Space.x16),
            if (loading)
              GlassCard(blur: false, child: Shimmer(child: Column(children: List.generate(5, (_) => const SkeletonListTile()))))
            else if (_error != null)
              ErrorState(title: "Couldn't load stock", message: 'Check your internet and pull to retry.', onRetry: _load)
            else if (items.isEmpty)
              GlassCard(blur: false, child: EmptyState(icon: Icons.inventory_2_outlined, title: 'No phones in stock',
                  message: _search.text.isEmpty ? 'Buy a phone and it will appear here, ready to sell.' : 'No matches for “${_search.text}”.',
                  actionLabel: 'Buy phone', onAction: widget.onBuy))
            else
              GlassCard(blur: false, padding: EdgeInsets.zero, child: Column(children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) Divider(height: 1, indent: 68, color: c.textPrimary.withValues(alpha: .08)),
                  _StockRow(p: items[i], age: _age(items[i]['buy_date']), onTap: () => _details(items[i])),
                ],
              ])),
          ],
        ),
      ),
      Positioned(top: 0, left: 0, right: 0, child: GlassTopBar(title: 'Stock', scroll: _scroll,
          leading: const SizedBox(width: Space.x12),
          actions: [GlassIconButton(icon: Icons.refresh, semanticLabel: 'Refresh stock', onPressed: _load)])),
    ]);
  }
}

class _StockRow extends StatelessWidget {
  final Map p; final String age; final VoidCallback onTap;
  const _StockRow({required this.p, required this.age, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final c = context.colors, t = context.type, s = context.scheme;
    final spec = [p['ram'], p['storage']].where((e) => e != null && '$e'.isNotEmpty).join(' · ');
    return Semantics(
      button: true, label: '${p['brand']} ${p['model']}, bought for ${rs(p['buy_price'])}',
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.x16, vertical: Space.x12),
          child: Row(children: [
            Container(width: 44, height: 44,
              decoration: BoxDecoration(color: s.primary.withValues(alpha: .12), borderRadius: BorderRadius.circular(Radii.md)),
              child: Icon(Icons.smartphone_outlined, color: s.primary, size: 22)),
            const SizedBox(width: Space.x12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${p['brand']} ${p['model']}', style: t.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text([if (spec.isNotEmpty) spec, if ((p['condition'] ?? '').toString().isNotEmpty) p['condition'], if (age.isNotEmpty) 'in stock $age']
                  .join(' · '), style: t.bodySmall?.copyWith(color: c.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
            ])),
            const SizedBox(width: Space.x12),
            Text(rs(p['buy_price']), style: t.titleSmall),
            const SizedBox(width: Space.x4),
            Icon(Icons.chevron_right, color: c.textSecondary, size: 20),
          ]),
        ),
      ),
    );
  }
}

class _PhoneDetailSheet extends StatelessWidget {
  final Map phone; final VoidCallback onSell, onDelete;
  const _PhoneDetailSheet({required this.phone, required this.onSell, required this.onDelete});
  @override
  Widget build(BuildContext context) {
    final c = context.colors, t = context.type;
    final p = phone;
    final rows = <(String, String)>[
      ('IMEI', '${p['imei']}'),
      if (p['imei2'] != null && '${p['imei2']}'.isNotEmpty) ('IMEI 2', '${p['imei2']}'),
      if ((p['serial_number'] ?? '').toString().isNotEmpty) ('Serial', '${p['serial_number']}'),
      ('RAM / Storage', '${p['ram'] ?? '—'} / ${p['storage'] ?? '—'}'),
      if ((p['color'] ?? '').toString().isNotEmpty) ('Color', '${p['color']}'),
      if ((p['condition'] ?? '').toString().isNotEmpty) ('Condition', '${p['condition']}'),
      if ((p['accessories'] ?? '').toString().isNotEmpty) ('Accessories', '${p['accessories']}'),
      ('Buy price', rs(p['buy_price'])), ('Buy date', '${p['buy_date']}'),
      if ((p['seller_name'] ?? '').toString().isNotEmpty) ('Customer', '${p['seller_name']}${p['seller_phone'] != null ? ' · ${p['seller_phone']}' : ''}'),
      if ((p['seller_id_type'] ?? '').toString().isNotEmpty) ('ID', '${p['seller_id_type']} ${p['seller_id_no'] ?? ''}'),
      if ((p['notes'] ?? '').toString().isNotEmpty) ('Notes', '${p['notes']}'),
    ];
    return Padding(
      padding: EdgeInsets.fromLTRB(Space.x16, 0, Space.x16, MediaQuery.viewInsetsOf(context).bottom + MediaQuery.viewPaddingOf(context).bottom + Space.x16),
      child: GlassSurface(
        child: SafeArea(top: false, child: SingleChildScrollView(
          padding: const EdgeInsets.all(Space.x20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: c.textPrimary.withValues(alpha: .20), borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: Space.x16),
            Semantics(header: true, child: Text('${p['brand']} ${p['model']}', style: t.headlineSmall)),
            const SizedBox(height: Space.x4),
            Wrap(spacing: Space.x8, children: [
              StatusChip(label: 'In stock', tone: ChipTone.success),
              if ((p['condition'] ?? '').toString().isNotEmpty) StatusChip(label: '${p['condition']}', tone: ChipTone.neutral),
            ]),
            const SizedBox(height: Space.x16),
            for (final r in rows) Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 110, child: Text(r.$1, style: t.bodyMedium?.copyWith(color: c.textSecondary))),
                Expanded(child: SelectableText(r.$2, style: t.bodyMedium)),
              ])),
            const SizedBox(height: Space.x20),
            Row(children: [
              Expanded(child: PrimaryButton(label: 'Sell this phone', icon: Icons.sell_outlined, onPressed: onSell)),
            ]),
            const SizedBox(height: Space.x12),
            Center(child: TextButton(
              onPressed: () async {
                final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(
                  title: const Text('Remove from stock?'),
                  content: Text('${p['brand']} ${p['model']} will be deleted permanently.'),
                  actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
                      FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Delete'))],
                ));
                if (ok == true) onDelete();
              },
              child: Text('Remove from stock', style: t.labelLarge?.copyWith(color: c.errorInk)),
            )),
          ]),
        )),
      ),
    );
  }
}
