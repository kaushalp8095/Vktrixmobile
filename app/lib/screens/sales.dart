// SALES: sold phones + profit; tap → glass detail sheet → cancel sale (confirm).
import 'package:flutter/material.dart';
import '../api.dart';
import '../design/components/components.dart';
import '../design/design.dart';
import 'common.dart';
import 'ledger.dart';
import 'receipt.dart';

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
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.transparent,
      isDismissible: true,
      builder: (c) => _SaleDetailSheet(
        sale: s, profit: _profit(s),
        onReceipt: () => Navigator.pop(c, 'receipt'),
        onLedger: () => Navigator.pop(c, 'ledger'),
        onCancel: () => Navigator.pop(c, 'cancel'),
      ),
    );
    if (!mounted || action == null) return;
    final saleId = int.parse('${s['id']}');
    if (action == 'receipt') {
      await SharedAxisRoute.push(context, (_) => ReceiptScreen(type: 'sale', id: saleId));
      return;
    }
    if (action == 'ledger') {
      await SharedAxisRoute.push(context, (_) => LedgerDetailScreen(saleId: saleId));
      if (mounted && widget.testItems == null) _load();
      return;
    }
    if (supportReadOnlyBlock(context, 'Cancelling a sale')) return;
    final ok = await showConfirmDialog(context,
      title: 'Cancel this sale?',
      message: '${s['brand']} ${s['model']} will go back into stock. Payment history will also be removed.',
      confirmLabel: 'Cancel sale',
      cancelLabel: 'Keep sale',
      icon: Icons.undo_outlined,
      destructive: true);
    if (ok) {
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
          actions: [
            GlassIconButton(icon: Icons.account_balance_wallet_outlined, semanticLabel: 'Open udhaar ledger',
              onPressed: () async {
                await SharedAxisRoute.push(context, (_) => const LedgerScreen());
                if (mounted && widget.testItems == null) _load();
              }),
            GlassIconButton(icon: Icons.refresh, semanticLabel: 'Refresh sales', onPressed: _load),
          ])),
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
    final due = num.tryParse('${s['balance_due'] ?? 0}') ?? 0;
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
              Text([if ((s['customer_name'] ?? '').toString().isNotEmpty) s['customer_name'], dateOnly(s['sell_date']),
                    due > 0 ? '${rs(due)} due' : pay]
                  .join(' · '), style: t.bodySmall?.copyWith(color: due > 0 ? c.warningInk : c.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
            ])),
            const SizedBox(width: Space.x12),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(rs(s['sell_price']), style: t.titleSmall),
              Text(due > 0 ? '${rs(due)} due' : (profit >= 0 ? '+${rs(profit)}' : '−${rs(-profit)}'),
                  style: t.labelSmall?.copyWith(color: due > 0 ? c.warningInk : profit >= 0 ? c.successInk : c.errorInk)),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _SaleDetailSheet extends StatelessWidget {
  final Map sale; final num profit;
  final VoidCallback onReceipt, onLedger, onCancel;
  const _SaleDetailSheet({required this.sale, required this.profit,
    required this.onReceipt, required this.onLedger, required this.onCancel});
  @override
  Widget build(BuildContext context) {
    final c = context.colors, t = context.type;
    final s = sale;
    final readOnly = Api.supportReadOnly;
    final rows = <(String, String)>[
      ('IMEI', '${s['imei']}'),
      ('RAM / Storage', '${s['ram'] ?? '—'} / ${s['storage'] ?? '—'}'),
      ('Bought at', rs(s['buy_price'])), ('Sold at', rs(s['sell_price'])),
      ('Sell date', dateOnly(s['sell_date'])), ('Payment', '${s['payment_mode'] ?? 'cash'}'.toUpperCase()),
      ('Received', rs(s['paid_amount'] ?? s['sell_price'])),
      ('Balance due', rs(s['balance_due'] ?? 0)),
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
          PrimaryButton(label: 'PDF bill & WhatsApp', icon: Icons.picture_as_pdf_outlined, onPressed: onReceipt),
          const SizedBox(height: Space.x8),
          OutlinedButton.icon(
            onPressed: onLedger,
            icon: const Icon(Icons.account_balance_wallet_outlined),
            label: Text((num.tryParse('${s['balance_due'] ?? 0}') ?? 0) > 0 ? 'Payment ledger · ${rs(s['balance_due'])} due' : 'View payment history'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
          const SizedBox(height: Space.x12),
          if (readOnly)
            const ReadOnlyNote(text: 'Support mode read-only hai — payment ya sale change shop owner khud karega.')
          else
            Center(child: TextButton(
              onPressed: onCancel,
              child: Text('Cancel sale (returns to stock)', style: t.labelLarge?.copyWith(color: c.errorInk)),
            )),
        ]),
      ))),
    );
  }
}
