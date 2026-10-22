// SHOP SHELL: aurora + page content + floating AnimatedTabBar (Home/Buy/Stock/Sales/Reports).
// System back: any tab → Home tab, back again within 2s → exit (see _onBack).
//
// SUPER ADMIN SUPPORT VIEW: ye shell tab khulta hai jab admin ne reason ke saath
// temporary, read-only support session li ho. Neeche ek patli bar countdown dikhati
// hai (kitna time bacha hai) aur "End access" deti hai. Buy page band rehta hai —
// support mode me shop ka koi data badla nahi ja sakta (backend bhi rokta hai).
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../api.dart';
import '../design/components/components.dart';
import '../design/design.dart';
import 'common.dart';
import 'dashboard.dart';
import 'buy_form.dart';
import 'stock.dart';
import 'sales.dart';
import 'reports.dart';
import 'ledger.dart';
import 'update_checker.dart';

class ShopHome extends StatefulWidget {
  final String? adminShopName; // super admin viewing a shop (support session)
  const ShopHome({super.key, this.adminShopName});
  @override
  State<ShopHome> createState() => _ShopHomeState();
}

class _ShopHomeState extends State<ShopHome> {
  int tab = 0;
  final _keys = List.generate(5, (_) => GlobalKey());
  final _pager = PageController();
  Timer? _updateTimer;
  Timer? _exitTimer;
  Timer? _supportTimer;

  /// How long a first back press stays "armed" for the exit.
  static const _exitWindow = Duration(seconds: 2);

  String get _name => widget.adminShopName ?? (Api.user?['shop']?['name'] ?? 'My Shop');
  bool get _adminView => widget.adminShopName != null;
  bool get _readOnly => Api.supportReadOnly;

  @override
  void initState() {
    super.initState();
    _updateTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) UpdateChecker.checkForUpdate(context);
    });
    if (_readOnly) {
      // Countdown har second: time khatam hone par screen apne aap lock ho jati hai.
      _supportTimer = Timer.periodic(const Duration(seconds: 1), (_) { if (mounted) setState(() {}); });
    }
  }

  void go(int i) {
    if (i == tab) return;
    Haptics.tick();
    _pager.animateToPage(i, duration: Motion.of(context).d(Durations2.enter), curve: Curves2.enter);
  }

  /// System/gesture back on the shop shell. The tabs are pages, not routes, so back
  /// has nothing to pop: step to Home first, and only exit once Home is already showing.
  /// Second press inside [_exitWindow] closes the app; otherwise the arm expires quietly.
  void _onBack() {
    if (tab != 0) { go(0); return; }
    if (_exitTimer?.isActive ?? false) {
      _exitTimer?.cancel();
      SystemNavigator.pop();
      return;
    }
    Haptics.tick();
    _exitTimer?.cancel();
    _exitTimer = Timer(_exitWindow, () {});
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
          content: Text('Press back again to exit'), duration: _exitWindow));
  }

  Future<void> _endSupport() async {
    final shopId = Api.viewShopId;
    final ok = await showConfirmDialog(context,
      title: 'End support access?',
      message: 'The session will end immediately and shop data will be locked. This will be recorded in the access log.',
      confirmLabel: 'End access',
      cancelLabel: 'Keep open',
      icon: Icons.lock_outline);
    if (ok != true || !mounted) return;
    try {
      if (shopId != null) await Api.delete('/admin/shops/$shopId/support-access');
      Api.endSupport();
      if (mounted) toast(context, 'Support access ended');
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) toast(context, '$e', err: true);
    }
  }

  @override
  void dispose() {
    _pager.dispose();
    _updateTimer?.cancel();
    _exitTimer?.cancel();
    _supportTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    final expired = Api.supportExpired;
    final locked = _readOnly && expired;
    final barSpace = _readOnly ? 92.0 : 0.0;
    // Admin view is a pushed route: back pops to the shop list as usual (canPop true).
    // For a shop user canPop is false, so the press lands in _onBack instead of dying.
    return PopScope<Object?>(
      canPop: _adminView,
      onPopInvokedWithResult: (didPop, _) { if (!didPop) _onBack(); },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        body: AuroraBackground(child: Stack(children: [
          Positioned.fill(
            bottom: 76 + bottom + Space.x16 + barSpace,
            child: IgnorePointer(
              ignoring: locked,
              child: PageView(
                controller: _pager,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() => tab = i),
                children: [
                  Dashboard(key: _keys[0], onGo: go, shopName: _name, isAdminView: _adminView,
                    onOpenLedger: () => SharedAxisRoute.push(context, (_) => const LedgerScreen())),
                  KeyedSubtree(key: _keys[1],
                    child: _readOnly
                      ? _SupportBlocked(action: 'Buy', onHome: () => go(0))
                      : BuyForm(onSaved: () { go(2); })),
                  KeyedSubtree(key: _keys[2], child: StockScreen(onBuy: () => go(1))),
                  KeyedSubtree(key: _keys[3], child: const SalesScreen()),
                  KeyedSubtree(key: _keys[4], child: const ReportsScreen()),
                ],
              ),
            ),
          ),
          Positioned(left: Space.x16, right: Space.x16, bottom: bottom + Space.x16,
            child: IgnorePointer(
              ignoring: locked,
              child: AnimatedTabBar(
                index: tab, onChanged: go,
                items: const [
                  TabItem(icon: Icons.space_dashboard_outlined, activeIcon: Icons.space_dashboard, label: 'Home'),
                  TabItem(icon: Icons.add_circle_outline, activeIcon: Icons.add_circle, label: 'Buy'),
                  TabItem(icon: Icons.inventory_2_outlined, activeIcon: Icons.inventory_2, label: 'Stock'),
                  TabItem(icon: Icons.sell_outlined, activeIcon: Icons.sell, label: 'Sales'),
                  TabItem(icon: Icons.bar_chart_outlined, activeIcon: Icons.bar_chart, label: 'Reports'),
                ],
              )),
          ),
          if (_readOnly)
            Positioned(left: Space.x16, right: Space.x16, bottom: bottom + 76 + Space.x16,
              child: _SupportBar(expired: expired, onEnd: _endSupport,
                  onBack: () { Api.endSupport(); Navigator.of(context).pop(); })),
        ])),
      ),
    );
  }
}

/// Support mode ki patli bar: read-only + countdown + end.
class _SupportBar extends StatelessWidget {
  final bool expired;
  final VoidCallback onEnd, onBack;
  const _SupportBar({required this.expired, required this.onEnd, required this.onBack});

  @override
  Widget build(BuildContext context) {
    final c = context.colors, t = context.type;
    final tint = expired ? c.errorInk : c.brandInk;
    return GlassCard(
      blur: false,
      padding: const EdgeInsets.symmetric(horizontal: Space.x12, vertical: Space.x8),
      child: Row(children: [
        Container(width: 34, height: 34,
          decoration: BoxDecoration(color: tint.withValues(alpha: .12), borderRadius: BorderRadius.circular(Radii.sm),
              border: Border.all(color: tint.withValues(alpha: .24))),
          child: Icon(expired ? Icons.lock_outline : Icons.shield_outlined, size: 18, color: tint)),
        const SizedBox(width: Space.x12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(expired ? 'Support access expired' : 'Support mode · read-only',
            style: t.titleSmall?.copyWith(color: tint), maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(expired ? 'Shop data is locked.' : '${clock(Api.supportRemaining)} remaining · visible to the shop owner',
            style: t.bodySmall?.copyWith(color: c.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
        ])),
        const SizedBox(width: Space.x8),
        TextButton(onPressed: expired ? onBack : onEnd, child: Text(expired ? 'Back' : 'End')),
      ]),
    );
  }
}

/// Support mode me wo tab jahan likhna padta hai (Buy).
class _SupportBlocked extends StatelessWidget {
  final String action;
  final VoidCallback onHome;
  const _SupportBlocked({required this.action, required this.onHome});
  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.viewPaddingOf(context).top;
    return Stack(children: [
      ListView(
        padding: EdgeInsets.fromLTRB(Space.screen, top + 64 + Space.x8, Space.screen, Space.x24),
        children: [
          GlassCard(blur: false, child: EmptyState(
            icon: Icons.lock_outline,
            title: '$action is unavailable in support mode',
            message: 'Support access is read-only. Only the shop owner can change shop data.',
            actionLabel: 'Back to Home',
            onAction: onHome,
          )),
        ],
      ),
      Positioned(top: 0, left: 0, right: 0, child: GlassTopBar(title: action, leading: const SizedBox(width: Space.x12))),
    ]);
  }
}
