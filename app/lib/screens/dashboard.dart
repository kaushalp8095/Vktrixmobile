// DASHBOARD (Home): shop name top bar → stock-value hero → quick actions →
// Today stats → Recent activity. Skeleton while loading, ErrorState on failure.
import 'package:flutter/material.dart';
import '../api.dart';
import '../design/components/components.dart';
import '../design/design.dart';
import 'profile.dart';

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
  final String shopName;
  final bool isAdminView;

  /// Test hook: injected data skips the network.
  final Map<String, dynamic>? testSummary;
  final List<ActivityItem>? testRecent;
  final String? greeting;
  const Dashboard({super.key, required this.onGo, required this.shopName,
      this.isAdminView = false, this.testSummary, this.greeting, this.testRecent});
  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  final _scroll = ScrollController();
  Map<String, dynamic>? _s;
  List<ActivityItem>? _recent;
  Object? _error;

  @override
  void initState() {
    super.initState();
    if (widget.testSummary != null) { _s = widget.testSummary; _recent = widget.testRecent ?? []; }
    else _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final results = await Future.wait([Api.get('/reports/summary'), Api.get('/stock'), Api.get('/sales')]);
      final stock = (results[1] as List).cast<Map>();
      final sales = (results[2] as List).cast<Map>();
      final items = <ActivityItem>[
        for (final p in stock.take(4))
          ActivityItem(isSale: false, id: p['id'] as int,
              title: '${p['brand'] ?? ''} ${p['model']}'.trim(),
              subtitle: 'Bought${p['seller_name'] != null ? ' · ${p['seller_name']}' : ''}',
              date: '${p['buy_date']}', amount: p['buy_price'] ?? 0, profit: 0),
        for (final s in sales.take(4))
          ActivityItem(isSale: true, id: 1000000 + (s['id'] as int),
              title: '${s['brand'] ?? ''} ${s['model']}'.trim(),
              subtitle: 'Sold${s['customer_name'] != null ? ' · ${s['customer_name']}' : ''}',
              date: '${s['sell_date']}', amount: s['sell_price'] ?? 0,
              profit: (s['sell_price'] ?? 0) - (s['buy_price'] ?? 0)),
      ]..sort((a, b) => b.id.compareTo(a.id));
      if (!mounted) return;
      setState(() { _s = results[0] as Map<String, dynamic>; _recent = items.take(5).toList(); });
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
              // ---- Quick actions ----
              Row(children: [
                Expanded(child: PrimaryButton(label: 'Buy phone', icon: Icons.add, expand: true, onPressed: () => widget.onGo(1))),
                const SizedBox(width: Space.x12),
                Expanded(child: _SecondaryAction(label: 'Sell phone', icon: Icons.sell_outlined, onTap: () => widget.onGo(2))),
              ]),
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
                          _ActivityRow(item: _recent![i], date: _shortDate(_recent![i].date)),
                        ],
                      ])),
            ],
          ],
        ),
      ),
      Positioned(top: 0, left: 0, right: 0, child: GlassTopBar(
        title: widget.shopName, scroll: _scroll,
        leading: widget.isAdminView ? const BackButton() : const SizedBox(width: Space.x12),
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
  final ActivityItem item; final String date;
  const _ActivityRow({required this.item, required this.date});
  @override
  Widget build(BuildContext context) {
    final c = context.colors, t = context.type, s = context.scheme;
    final tint = item.isSale ? c.success : s.primary;
    return Padding(
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
          if (item.isSale) Text('+${rs(item.profit)}', style: t.labelSmall?.copyWith(color: c.success)),
        ]),
      ]),
    );
  }
}
