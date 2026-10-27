// STOCK: brand-wise (brand tiles → us brand ka stock) + search → phone rows →
// glass detail sheet → Sell flow.
import 'package:flutter/material.dart';
import '../api.dart';
import '../design/components/components.dart';
import '../design/design.dart';
import 'brand_art.dart';
import 'common.dart';
import 'receipt.dart';
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
  /// Selected brand ka group key (null = saare brands). Server se alag call
  /// nahi — ek hi /stock response par client-side filter (turant, offline-safe).
  String? _brand;

  @override
  void initState() {
    super.initState();
    if (widget.testItems != null) { items = widget.testItems!; loading = false; } else { _load(); }
  }

  @override
  void dispose() { _search.dispose(); _scroll.dispose(); super.dispose(); }

  Future<void> _load() async {
    // Delete/save ke baad reload ho sakta hai jab screen band ho chuki ho.
    if (!mounted) return;
    setState(() { loading = true; _error = null; });
    try { items = await Api.get('/stock', {'search': _search.text}); }
    catch (e) { if (mounted) setState(() => _error = e); }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _details(Map p) async {
    Haptics.tap();
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.transparent,
      isDismissible: true,
      builder: (c) => _PhoneDetailSheet(phone: p,
        onReceipt: () => Navigator.pop(c, 'receipt'),
        onSell: () => Navigator.pop(c, 'sell'), onDelete: () => Navigator.pop(c, 'delete')),
    );
    if (action == 'receipt' && mounted) {
      await SharedAxisRoute.push(context, (_) => ReceiptScreen(type: 'purchase', id: int.parse('${p['id']}')));
    } else if (action == 'delete') {
      if (supportReadOnlyBlock(context, 'Removing stock')) return;
      try { await Api.delete('/phones/${p['id']}'); _load(); } catch (e) { if (mounted) toast(context, '$e', err: true); }
    } else if (action == 'sell' && mounted) {
      if (supportReadOnlyBlock(context, 'Selling a phone')) return;
      final ok = await SharedAxisRoute.push<bool>(context, (_) => SellForm(phone: Map<String, dynamic>.from(p)));
      if (ok == true) _load();
    }
  }

  /// items se brand-wise groups: (brand ka asli naam, key, kitne phone).
  /// Zyada stock wale brand pehle, phir naam se — list stable rehti hai.
  List<({String name, String key, int count})> _brandGroups(List list) {
    final map = <String, ({String name, int count})>{};
    for (final p in list) {
      final info = brandInfo('${p['brand'] ?? ''}');
      final prev = map[info.key];
      map[info.key] = (name: info.name, count: (prev?.count ?? 0) + 1);
    }
    final groups = [for (final e in map.entries) (name: e.value.name, key: e.key, count: e.value.count)];
    groups.sort((a, b) {
      final byCount = b.count.compareTo(a.count);
      return byCount != 0 ? byCount : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return groups;
  }

  String _age(String? iso) {
    final d = DateTime.tryParse('${iso ?? ''}');
    if (d == null) return '';
    final days = DateTime.now().difference(d).inDays;
    return days == 0 ? 'today' : days == 1 ? '1 day' : '$days days';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors, t = context.type;
    final top = MediaQuery.viewPaddingOf(context).top;
    final groups = _brandGroups(items);
    // Brand chunne ke baad search/refresh se wo brand gayab ho jaye to filter
    // apne aap hat jata hai (khaali list par atke nahi rehte).
    final selected = groups.any((g) => g.key == _brand) ? _brand : null;
    final shown = selected == null ? items : [for (final p in items) if (brandKey('${p['brand'] ?? ''}') == selected) p];
    final selectedName = selected == null ? null : groups.firstWhere((g) => g.key == selected).name;
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
            else ...[
              if (groups.length > 1) ...[
                _BrandSection(groups: groups, selected: selected, onSelect: (key) {
                  Haptics.tap();
                  setState(() => _brand = selected == key ? null : key);
                  if (_scroll.hasClients) {
                    // Filter badalne par list ke top se dikhna shuru kare.
                    _scroll.animateTo(0,
                        duration: Durations2.enter, curve: Curves.easeOutCubic);
                  }
                }),
                const SizedBox(height: Space.x16),
              ],
              if (items.isEmpty)
                GlassCard(blur: false, child: EmptyState(icon: Icons.inventory_2_outlined, title: 'No phones in stock',
                    message: _search.text.isEmpty ? 'Buy a phone and it will appear here, ready to sell.' : 'No matches for “${_search.text}”.',
                    actionLabel: 'Buy phone', onAction: widget.onBuy))
              else ...[
                if (selectedName != null)
                  Padding(
                    padding: const EdgeInsets.only(left: Space.x4, bottom: Space.x8),
                    child: Row(children: [
                      BrandLogo(brand: selectedName, size: 26),
                      const SizedBox(width: Space.x8),
                      Expanded(child: Text('$selectedName · ${shown.length} in stock',
                          style: t.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis)),
                      // Filter hatane ka seedha rasta.
                      Semantics(button: true, label: 'Show all brands',
                          child: InkWell(
                            onTap: () { Haptics.tap(); setState(() => _brand = null); },
                            borderRadius: Shapes.sm,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: Space.x8, vertical: 4),
                              child: Text('All brands', style: t.labelLarge?.copyWith(color: c.brandInk)),
                            ),
                          )),
                    ]),
                  ),
                if (shown.isEmpty)
                  GlassCard(blur: false, child: EmptyState(icon: Icons.inventory_2_outlined, title: 'No $selectedName in stock',
                      message: 'This brand has no phones in stock right now.', actionLabel: 'Buy phone', onAction: widget.onBuy))
                else
                  GlassCard(blur: false, padding: EdgeInsets.zero, child: Column(children: [
                    for (var i = 0; i < shown.length; i++) ...[
                      if (i > 0) Divider(height: 1, indent: 68, color: c.textPrimary.withValues(alpha: .08)),
                      _StockRow(p: shown[i], age: _age(shown[i]['buy_date']), onTap: () => _details(shown[i])),
                    ],
                  ])),
              ],
            ],
          ],
        ),
      ),
      Positioned(top: 0, left: 0, right: 0, child: GlassTopBar(title: 'Stock', scroll: _scroll,
          leading: const SizedBox(width: Space.x12),
          actions: [GlassIconButton(icon: Icons.refresh, semanticLabel: 'Refresh stock', onPressed: _load)])),
    ]);
  }
}

/// Stock ke upar brand tiles — har brand logo + naam + count, tap par filter.
class _BrandSection extends StatelessWidget {
  final List<({String name, String key, int count})> groups;
  final String? selected;
  final ValueChanged<String> onSelect;
  const _BrandSection({required this.groups, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final c = context.colors, t = context.type;
    return GlassCard(
      blur: false,
      padding: const EdgeInsets.fromLTRB(Space.x12, Space.x12, Space.x12, Space.x8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(left: Space.x4, bottom: Space.x8),
          child: Row(children: [
            Text('Brands', style: t.titleSmall),
            const SizedBox(width: Space.x8),
            // 200% text scale par bhi row overflow na kare.
            Expanded(child: Semantics(header: true,
                child: Text('${groups.length} brands · ${groups.fold<int>(0, (a, g) => a + g.count)} in stock',
                    style: t.labelSmall?.copyWith(color: c.textSecondary),
                    maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.end))),
          ]),
        ),
        Wrap(
          spacing: Space.x8,
          runSpacing: Space.x12,
          children: [
            for (final g in groups)
              BrandTile(brand: g.name, count: g.count, selected: selected == g.key, onTap: () => onSelect(g.key)),
          ],
        ),
      ]),
    );
  }
}

class _StockRow extends StatelessWidget {
  final Map p; final String age; final VoidCallback onTap;
  const _StockRow({required this.p, required this.age, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final c = context.colors, t = context.type;
    final spec = [p['ram'], p['storage']].where((e) => e != null && '$e'.isNotEmpty).join(' · ');
    return Semantics(
      button: true, label: '${p['brand']} ${p['model']}, bought for ${rs(p['buy_price'])}',
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.x16, vertical: Space.x12),
          child: Row(children: [
            BrandLogo(brand: '${p['brand'] ?? ''}', size: 44),
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
  final Map phone; final VoidCallback onReceipt, onSell, onDelete;
  const _PhoneDetailSheet({required this.phone, required this.onReceipt, required this.onSell, required this.onDelete});
  @override
  Widget build(BuildContext context) {
    final c = context.colors, t = context.type;
    final p = phone;
    final readOnly = Api.supportReadOnly;
    final rows = <(String, String)>[
      ('IMEI', '${p['imei']}'),
      if (p['imei2'] != null && '${p['imei2']}'.isNotEmpty) ('IMEI 2', '${p['imei2']}'),
      if ((p['serial_number'] ?? '').toString().isNotEmpty) ('Serial', '${p['serial_number']}'),
      ('RAM / Storage', '${p['ram'] ?? '—'} / ${p['storage'] ?? '—'}'),
      if ((p['color'] ?? '').toString().isNotEmpty) ('Color', '${p['color']}'),
      if ((p['condition'] ?? '').toString().isNotEmpty) ('Condition', '${p['condition']}'),
      if ((p['accessories'] ?? '').toString().isNotEmpty) ('Accessories', '${p['accessories']}'),
      ('Buy price', rs(p['buy_price'])), ('Buy date', dateOnly(p['buy_date'])),
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
            Row(children: [
              BrandLogo(brand: '${p['brand'] ?? ''}', size: 36),
              const SizedBox(width: Space.x12),
              Expanded(child: Semantics(header: true,
                  child: Text('${p['brand']} ${p['model']}', style: t.headlineSmall))),
            ]),
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
            OutlinedButton.icon(
              onPressed: onReceipt,
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Purchase PDF & WhatsApp'),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            ),
            const SizedBox(height: Space.x8),
            if (readOnly)
              const ReadOnlyNote(text: 'Support mode is read-only. Only the shop owner can sell or remove stock.')
            else ...[
              PrimaryButton(label: 'Sell this phone', icon: Icons.sell_outlined, onPressed: onSell),
              const SizedBox(height: Space.x12),
              Center(child: TextButton(
                onPressed: () async {
                  final ok = await showConfirmDialog(context,
                    title: 'Remove from stock?',
                    message: '${p['brand']} ${p['model']} will be deleted permanently.',
                    confirmLabel: 'Delete',
                    cancelLabel: 'Cancel',
                    icon: Icons.delete_outline,
                    destructive: true);
                  if (ok) onDelete();
                },
                child: Text('Remove from stock', style: t.labelLarge?.copyWith(color: c.errorInk)),
              )),
            ],
          ]),
        )),
      ),
    );
  }
}
