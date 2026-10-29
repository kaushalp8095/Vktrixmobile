// DASHBOARD (Home): shop name top bar → stock-value hero → quick actions →
// Today stats → Recent activity. Skeleton while loading, ErrorState on failure.
import 'package:flutter/material.dart';
import '../api.dart';
import '../design/components/components.dart';
import '../design/design.dart';
import 'profile.dart';
import 'receipt.dart';
import 'shop_logo.dart';

class ActivityItem {
  final bool isSale;
  final String title, subtitle, date;
  final num amount, profit;
  final int id;
  const ActivityItem({required this.isSale, required this.title, required this.subtitle,
      required this.date, required this.amount, required this.profit, required this.id});
}

class Dashboard extends StatefulWidget {
  final void Function(int) onGo;
  final VoidCallback? onOpenLedger;
  /// Workshop (repair jobs) ka entry point — Home tab par card.
  final VoidCallback? onOpenRepairs;
  final String shopName;
  final bool isAdminView;

  /// Test hook: injected data skips the network.
  final Map<String, dynamic>? testSummary;
  /// All-time pending dues (`/ledger/summary`). Test hook, network path ke liye.
  final Map<String, dynamic>? testDues;
  /// Repair workshop ka summary (`/ledger/repairs`). Test hook.
  final Map<String, dynamic>? testRepairs;
  final List<ActivityItem>? testRecent;
  final String? greeting;
  /// Shop ka auto-adjusted logo thumbnail (`logo_thumb`). Na do to login
  /// response se (`Api.user['shop']['logo_thumb']`) aata hai — top bar me shop
  /// name ke aage wahi dikhta hai.
  final String? logoThumb;
  const Dashboard({super.key, required this.onGo, required this.shopName, this.onOpenLedger,
      this.onOpenRepairs, this.isAdminView = false, this.testSummary, this.testDues, this.testRepairs,
      this.greeting, this.testRecent, this.logoThumb});
  /// "Recent activity" rows — sale aur purchase dono ek hi timeline par, newest
  /// first. Pehle sale ko `1000000 + id` banakar sort kiya jata tha, isliye har
  /// sale har purchase ke upar aa jati thi aur aaj ki kharidi purani sale ke neeche
  /// chhup jati thi.
  static List<ActivityItem> recentActivity(List<dynamic> stock, List<dynamic> sales) {
    final items = <ActivityItem>[
      for (final p in stock.take(4))
        ActivityItem(isSale: false, id: p['id'] as int,
            title: '${p['brand'] ?? ''} ${p['model']}'.trim(),
            subtitle: 'Bought${p['seller_name'] != null ? ' · ${p['seller_name']}' : ''}',
            date: '${p['buy_date']}', amount: num.tryParse('${p['buy_price']}') ?? 0, profit: 0),
      for (final s in sales.take(4))
        ActivityItem(isSale: true, id: 1000000 + (s['id'] as int),
            title: '${s['brand'] ?? ''} ${s['model']}'.trim(),
            subtitle: 'Sold${s['customer_name'] != null ? ' · ${s['customer_name']}' : ''}',
            date: '${s['sell_date']}', amount: num.tryParse('${s['sell_price']}') ?? 0,
            profit: (num.tryParse('${s['sell_price']}') ?? 0) -
                (num.tryParse('${s['buy_price']}') ?? 0)),
    ]..sort((a, b) {
        final byDate = b.date.compareTo(a.date);
        if (byDate != 0) return byDate;
        // Same din: synthetic id (sale = 1000000 + id) se compare karne par har sale
        // purchase se upar aa jati thi. Tie-break real id se.
        int real(ActivityItem x) => x.isSale ? x.id - 1000000 : x.id;
        return real(b).compareTo(real(a));
      });
    return items;
  }

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  final _scroll = ScrollController();
  Map<String, dynamic>? _s;
  /// All-time pending dues — ledger screen ka hi source (`/ledger/summary`).
  Map<String, dynamic>? _dues;
  /// Workshop ka summary — same source jo Repairs screen ke top par dikhta hai.
  Map<String, dynamic>? _repairs;
  List<ActivityItem>? _recent;
  Object? _error;

  @override
  void initState() {
    super.initState();
    if (widget.testSummary != null) {
      _s = widget.testSummary;
      _dues = widget.testDues;
      _repairs = widget.testRepairs;
      _recent = widget.testRecent ?? [];
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _error = null);
    try {
      final results = await Future.wait([
        Api.get('/reports/summary'),
        Api.get('/stock'),
        Api.get('/sales'),
        // All-time dues: ledger screen bhi yahi endpoint use karta hai, isliye
        // card aur ledger ka number alag nahi ho sakta. `/reports/summary` ka
        // `receivables` period-scoped hai (bina from/to = sirf aaj ki sales),
        // isliye purani udhaar par card galti se "clear" dikhata tha.
        Api.get('/ledger/summary').catchError((Object _) => null),
        // Repair workshop: open/ready jobs aur unka udhaar. Alag call hai taaki
        // koi bhi ek endpoint fail ho to baaki dashboard na ruke.
        widget.onOpenRepairs == null
            ? Future<dynamic>.value(null)
            : Api.get('/ledger/repairs').catchError((Object _) => null),
      ]);
      final stock = (results[1] as List).cast<Map>();
      final sales = (results[2] as List).cast<Map>();
      final items = Dashboard.recentActivity(stock, sales);
      if (!mounted) return;
      final dues = results[3];
      final repairs = results.length > 4 ? results[4] : null;
      setState(() {
        _s = results[0] as Map<String, dynamic>;
        _dues = dues is Map ? dues.cast<String, dynamic>() : null;
        _repairs = repairs is Map ? repairs.cast<String, dynamic>() : null;
        _recent = items.take(5).toList();
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  String _greeting() {
    final h = DateTime.now().hour;
    return h < 12 ? 'Good morning' : h < 17 ? 'Good afternoon' : 'Good evening';
  }

  static String _shortDate(String iso) {
    final d = DateTime.tryParse(iso.length >= 10 ? iso.substring(0, 10) : '');
    if (d == null) return iso;
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${d.day} ${m[d.month - 1]}';
  }

  @override
  void dispose() { _scroll.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final c = context.colors, t = context.type;
    final top = MediaQuery.viewPaddingOf(context).top;
    return Stack(children: [
      RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(Space.screen, top + 64 + Space.x8, Space.screen, Space.x24),
          children: [
            Padding(
              padding: const EdgeInsets.only(left: Space.x4, bottom: Space.x8),
              child: Text('${widget.greeting ?? _greeting()}, ${(Api.user?['name'] ?? widget.shopName)}', style: t.titleMedium?.copyWith(color: c.textSecondary)),
            ),
            if (_error != null)
              ErrorState(title: "Couldn't load dashboard",
                  message: 'Check your internet and pull to retry.', onRetry: _load)
            else if (_s == null)
              ...[GlassCard(child: Shimmer(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
                    SkeletonBox(width: 100, height: 14), SizedBox(height: Space.x12), SkeletonBox(width: 200, height: 34)]))),
                const SizedBox(height: Space.x16),
                GlassCard(blur: false, child: Shimmer(child: Column(children: List.generate(4, (_) => const SkeletonListTile()))))]
            else ...[
              // ---- Hero: stock value ----
              GlassCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Stock value', style: t.labelLarge?.copyWith(color: c.textSecondary)),
                const SizedBox(height: Space.x4),
                Text(rs(_s!['stock']['value']), style: t.displaySmall?.copyWith(color: c.brandInk)),
                const SizedBox(height: Space.x8),
                Wrap(spacing: Space.x8, children: [
                  StatusChip(label: '${_s!['stock']['count']} in stock', tone: ChipTone.brand, icon: Icons.smartphone_outlined),
                  StatusChip(label: 'Profit today ${rs(_s!['sales']['profit'])}', tone: ChipTone.success, icon: Icons.trending_up),
                ]),
              ])),
              const SizedBox(height: Space.x16),
              // ---- Quick actions (support mode me read-only note) ----
              if (Api.supportReadOnly)
                const ReadOnlyNote(text: 'Support mode is read-only. The shop owner must handle buying, selling, and payments.')
              else
                Row(children: [
                  Expanded(child: PrimaryButton(label: 'Buy phone', icon: Icons.add, expand: true, onPressed: () => widget.onGo(1))),
                  const SizedBox(width: Space.x12),
                  Expanded(child: _SecondaryAction(label: 'Sell phone', icon: Icons.sell_outlined, onTap: () => widget.onGo(2))),
                ]),
              if (widget.onOpenLedger != null) ...[
                const SizedBox(height: Space.x12),
                _LedgerAction(
                  outstanding: _dues?['outstanding'] ?? _s!['receivables']?['outstanding'] ?? 0,
                  count: int.tryParse('${_dues?['pending_count'] ?? _s!['receivables']?['pending_count'] ?? 0}') ?? 0,
                  onTap: widget.onOpenLedger!,
                ),
              ],
              if (widget.onOpenRepairs != null) ...[
                const SizedBox(height: Space.x12),
                _RepairsAction(summary: _repairs, onTap: widget.onOpenRepairs!),
              ],
              const SizedBox(height: Space.section),
              // ---- Today ----
              SectionHeader(title: 'Today'),
              const SizedBox(height: Space.x12),
              Row(children: [
                Expanded(child: _StatTile(icon: Icons.call_received, label: 'Bought',
                    value: '${_s!['purchases']['count']}', sub: rs(_s!['purchases']['amount']))),
                const SizedBox(width: Space.x12),
                Expanded(child: _StatTile(icon: Icons.call_made, label: 'Sold',
                    value: '${_s!['sales']['count']}', sub: rs(_s!['sales']['amount']))),
              ]),
              const SizedBox(height: Space.section),
              // ---- Recent ----
              SectionHeader(title: 'Recent activity'),
              const SizedBox(height: Space.x12),
              GlassCard(blur: false, padding: EdgeInsets.zero,
                child: (_recent ?? []).isEmpty
                    ? const EmptyState(icon: Icons.history, title: 'No activity yet',
                        message: 'Phones you buy and sell will appear here.')
                    : Column(children: [
                        for (var i = 0; i < _recent!.length; i++) ...[
                          if (i > 0) Divider(height: 1, indent: 68, color: c.textPrimary.withValues(alpha: .08)),
                          _ActivityRow(item: _recent![i], date: _shortDate(_recent![i].date), onTap: () {
                            final item = _recent![i];
                            final id = item.isSale ? item.id - 1000000 : item.id;
                            SharedAxisRoute.push(context, (_) => ReceiptScreen(type: item.isSale ? 'sale' : 'purchase', id: id));
                          }),
                        ],
                      ])),
            ],
          ],
        ),
      ),
      Positioned(top: 0, left: 0, right: 0, child: GlassTopBar(
        title: widget.shopName, scroll: _scroll,
        // Shop ka logo naam se pehle, aur usi row ke aakhir me profile icon.
        leading: Row(mainAxisSize: MainAxisSize.min, children: [
          if (widget.isAdminView) const BackButton()
          else ...[
            const SizedBox(width: Space.x4),
            ShopLogoAvatar(
              thumb: widget.logoThumb ?? (Api.user?['shop']?['logo_thumb'] as String?),
              fallbackLetter: widget.shopName,
              active: true, size: 32,
            ),
            const SizedBox(width: Space.x8),
          ],
        ]),
        actions: [
          GlassIconButton(icon: Icons.refresh, semanticLabel: 'Refresh dashboard', onPressed: _load),
          if (!widget.isAdminView)
            GlassIconButton(icon: Icons.person_outline, semanticLabel: 'Profile and settings',
                onPressed: () => SharedAxisRoute.push(context, (_) => const ProfileScreen())),
        ],
      )),
    ]);
  }
}

class _LedgerAction extends StatelessWidget {
  final dynamic outstanding;
  final int count;
  final VoidCallback onTap;
  const _LedgerAction({required this.outstanding, required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors, t = context.type;
    return GlassCard(
      blur: false,
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(Space.x12),
        child: Row(children: [
          Container(width: 42, height: 42,
            decoration: BoxDecoration(color: c.warning.withValues(alpha: .12), borderRadius: Shapes.md),
            child: Icon(Icons.account_balance_wallet_outlined, color: c.warningInk, size: 21)),
          const SizedBox(width: Space.x12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Credit / pending payments', style: t.titleSmall),
            Text(count > 0
                ? '$count ${count == 1 ? 'customer' : 'customers'} · ${rs(outstanding)} outstanding'
                : 'All payments are clear',
              style: t.bodySmall?.copyWith(color: c.textSecondary)),
          ])),
          StatusChip(label: count > 0 ? 'OPEN' : 'CLEAR', tone: count > 0 ? ChipTone.warning : ChipTone.success),
          const SizedBox(width: Space.x4),
          Icon(Icons.chevron_right, color: c.textSecondary, size: 20),
        ]),
      ),
    );
  }
}

/// Workshop ka Home card: kitni jobs khuli hain, kitni deliver karne layak hain
/// aur unka udhaar — ek nazar me. Repair ka paisa sale/profit me mix nahi hota,
/// isliye ye card stock value ke bilkul alag dikhta hai.
class _RepairsAction extends StatelessWidget {
  final Map<String, dynamic>? summary;
  final VoidCallback onTap;
  const _RepairsAction({required this.summary, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors, t = context.type;
    final open = int.tryParse('${summary?['open_count'] ?? 0}') ?? 0;
    final ready = int.tryParse('${summary?['ready_count'] ?? 0}') ?? 0;
    final due = num.tryParse('${summary?['outstanding'] ?? 0}') ?? 0;
    return GlassCard(
      blur: false,
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(Space.x12),
        child: Row(children: [
          Container(width: 42, height: 42,
            decoration: BoxDecoration(color: c.brandInk.withValues(alpha: .10), borderRadius: Shapes.md),
            child: Icon(Icons.build_outlined, color: c.brandInk, size: 21)),
          const SizedBox(width: Space.x12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Repairs', style: t.titleSmall),
            Text(
              open == 0 && ready == 0
                ? 'No open repair jobs'
                : '$open open${ready > 0 ? ' · $ready ready' : ''}${due > 0 ? ' · ${rs(due)} due' : ''}',
              style: t.bodySmall?.copyWith(color: c.textSecondary)),
          ])),
          StatusChip(label: ready > 0 ? 'READY $ready' : open > 0 ? 'OPEN $open' : 'CLEAR',
            tone: ready > 0 ? ChipTone.success : open > 0 ? ChipTone.brand : ChipTone.neutral),
          const SizedBox(width: Space.x4),
          Icon(Icons.chevron_right, color: c.textSecondary, size: 20),
        ]),
      ),
    );
  }
}

class _SecondaryAction extends StatelessWidget {
  final String label; final IconData icon; final VoidCallback onTap;
  const _SecondaryAction({required this.label, required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GlassCard(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: Space.x16),
      onTap: onTap,
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, size: 20, color: c.brandInk), const SizedBox(width: Space.x8),
        Flexible(child: Text(label, style: context.type.labelLarge?.copyWith(color: c.brandInk), overflow: TextOverflow.ellipsis)),
      ]),
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon; final String label, value, sub;
  const _StatTile({required this.icon, required this.label, required this.value, required this.sub});
  @override
  Widget build(BuildContext context) {
    final c = context.colors, t = context.type;
    return GlassCard(blur: false, padding: const EdgeInsets.all(Space.x16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 18, color: c.textSecondary), const SizedBox(width: Space.x8),
          Text(label, style: t.labelLarge?.copyWith(color: c.textSecondary)),
        ]),
        const SizedBox(height: Space.x8),
        Text(value, style: t.headlineMedium),
        const SizedBox(height: 2),
        Text(sub, style: t.bodySmall?.copyWith(color: c.textSecondary)),
      ]));
  }
}

class _ActivityRow extends StatelessWidget {
  final ActivityItem item; final String date; final VoidCallback onTap;
  const _ActivityRow({required this.item, required this.date, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final c = context.colors, t = context.type, s = context.scheme;
    final tint = item.isSale ? c.success : s.primary;
    return Semantics(
      button: true, label: 'Open ${item.isSale ? 'sale' : 'purchase'} details for ${item.title}',
      child: InkWell(onTap: onTap, child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.x16, vertical: Space.x12),
      child: Row(children: [
        Container(width: 44, height: 44,
          decoration: BoxDecoration(color: tint.withValues(alpha: .12), borderRadius: BorderRadius.circular(Radii.md)),
          child: Icon(item.isSale ? Icons.sell_outlined : Icons.add_shopping_cart, color: tint, size: 22)),
        const SizedBox(width: Space.x12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(item.title, style: t.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text('${item.subtitle} · $date', style: t.bodySmall?.copyWith(color: c.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
        ])),
        const SizedBox(width: Space.x12),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(rs(item.amount), style: t.titleSmall),
          // Sign pehle: loss "₹-500" nahi, "-₹500" (aur pehle "+-₹500" chhapta tha).
          if (item.isSale) Text('${item.profit < 0 ? '-' : '+'}${rs(item.profit.abs())}',
            style: t.labelSmall?.copyWith(color: item.profit < 0 ? c.errorInk : c.successInk)),
        ]),
      ]),
    )),
    );
  }
}
