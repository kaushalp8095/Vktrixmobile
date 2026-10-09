// SHOP SHELL: aurora + page content + floating AnimatedTabBar (Home/Buy/Stock/Sales/Reports).
// System back: any tab → Home tab, back again within 2s → exit (see _onBack).
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../api.dart';
import '../design/components/components.dart';
import '../design/design.dart';
import 'dashboard.dart';
import 'buy_form.dart';
import 'stock.dart';
import 'sales.dart';
import 'reports.dart';
import 'update_checker.dart';

class ShopHome extends StatefulWidget {
  final String? adminShopName; // super admin viewing a shop
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

  /// How long a first back press stays "armed" for the exit.
  static const _exitWindow = Duration(seconds: 2);

  String get _name => widget.adminShopName ?? (Api.user?['shop']?['name'] ?? 'My Shop');

  @override
  void initState() {
    super.initState();
    _updateTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) UpdateChecker.checkForUpdate(context);
    });
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

  @override
  void dispose() {
    _pager.dispose();
    _updateTimer?.cancel();
    _exitTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    // Admin view is a pushed route: back pops to the shop list as usual (canPop true).
    // For a shop user canPop is false, so the press lands in _onBack instead of dying.
    return PopScope<Object?>(
      canPop: widget.adminShopName != null,
      onPopInvokedWithResult: (didPop, _) { if (!didPop) _onBack(); },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        body: AuroraBackground(child: Stack(children: [
          Positioned.fill(
            bottom: 76 + bottom + Space.x16,
            child: PageView(
              controller: _pager,
              physics: const NeverScrollableScrollPhysics(),
              onPageChanged: (i) => setState(() => tab = i),
              children: [
                Dashboard(key: _keys[0], onGo: go, shopName: _name, isAdminView: widget.adminShopName != null),
                KeyedSubtree(key: _keys[1], child: BuyForm(onSaved: () { go(2); })),
                KeyedSubtree(key: _keys[2], child: StockScreen(onBuy: () => go(1))),
                KeyedSubtree(key: _keys[3], child: const SalesScreen()),
                KeyedSubtree(key: _keys[4], child: const ReportsScreen()),
              ],
            ),
          ),
          Positioned(left: Space.x16, right: Space.x16, bottom: bottom + Space.x16,
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
        ])),
        // Logout lives at shell level until the Profile screen arrives in D3.
        persistentFooterAlignment: AlignmentDirectional.center,
      ),
    );
  }
}
