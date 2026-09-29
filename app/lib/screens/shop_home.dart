import 'package:flutter/material.dart';
import '../api.dart';
import 'login.dart';
import 'dashboard.dart';
import 'buy_form.dart';
import 'stock.dart';
import 'sales.dart';
import 'reports.dart';

class ShopHome extends StatefulWidget {
  final String? adminShopName; // super admin dekh raha ho to
  const ShopHome({super.key, this.adminShopName});
  @override
  State<ShopHome> createState() => _ShopHomeState();
}

class _ShopHomeState extends State<ShopHome> {
  int tab = 0;
  final keys = List.generate(5, (_) => UniqueKey());

  void go(int i) => setState(() { tab = i; keys[i] = UniqueKey(); });

  @override
  Widget build(BuildContext context) {
    final name = widget.adminShopName ?? Api.user?['shop']?['name'] ?? 'Shop';
    final pages = [
      Dashboard(key: keys[0], onGo: go),
      BuyForm(key: keys[1], onSaved: () => go(2)),
      StockScreen(key: keys[2]),
      SalesScreen(key: keys[3]),
      ReportsScreen(key: keys[4]),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(name), actions: [
        if (widget.adminShopName == null)
          IconButton(icon: const Icon(Icons.logout), onPressed: () async {
            await Api.logout();
            if (context.mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
          }),
      ]),
      body: pages[tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab, onDestinationSelected: go,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.add_shopping_cart), label: 'Buy'),
          NavigationDestination(icon: Icon(Icons.inventory_2), label: 'Stock'),
          NavigationDestination(icon: Icon(Icons.sell), label: 'Sales'),
          NavigationDestination(icon: Icon(Icons.bar_chart), label: 'Reports'),
        ],
      ),
    );
  }
}
