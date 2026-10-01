import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_shop/design/components/components.dart';
import 'package:mobile_shop/design/design.dart';
import 'package:mobile_shop/screens/dashboard.dart';
import 'showcase_golden_test.dart' show loadFonts;

const _summary = {
  'purchases': {'count': 3, 'amount': 42500},
  'sales': {'count': 2, 'amount': 51000, 'profit': 8500},
  'stock': {'count': 18, 'value': 124500},
};
final _recent = [
  const ActivityItem(isSale: true, id: 5, title: 'Samsung Galaxy S23', subtitle: 'Sold · Ramesh Patel', date: '2026-09-28', amount: 26500, profit: 3500),
  const ActivityItem(isSale: false, id: 4, title: 'Apple iPhone 13', subtitle: 'Bought · Suresh Kumar', date: '2026-09-28', amount: 31000, profit: 0),
  const ActivityItem(isSale: false, id: 3, title: 'OnePlus Nord CE 3', subtitle: 'Bought · Meena Shah', date: '2026-09-27', amount: 11500, profit: 0),
  const ActivityItem(isSale: true, id: 2, title: 'Redmi Note 12', subtitle: 'Sold · Walk-in', date: '2026-09-26', amount: 9200, profit: 1400),
];

Widget _home() => Scaffold(
      body: AuroraBackground(child: Stack(children: [
        Positioned.fill(bottom: 92,
          child: Dashboard(onGo: _noop, shopName: 'Krishna Mobiles', greeting: 'Good afternoon', testSummary: _summary, testRecent: _recent)),
        const Positioned(left: 16, right: 16, bottom: 16,
          child: AnimatedTabBar(index: 0, onChanged: _noopInt, items: [
            TabItem(icon: Icons.space_dashboard_outlined, activeIcon: Icons.space_dashboard, label: 'Home'),
            TabItem(icon: Icons.add_circle_outline, activeIcon: Icons.add_circle, label: 'Buy'),
            TabItem(icon: Icons.inventory_2_outlined, activeIcon: Icons.inventory_2, label: 'Stock'),
            TabItem(icon: Icons.sell_outlined, activeIcon: Icons.sell, label: 'Sales'),
            TabItem(icon: Icons.bar_chart_outlined, activeIcon: Icons.bar_chart, label: 'Reports'),
          ])),
      ])),
    );
void _noop(int _) {}
void _noopInt(int _) {}

void main() {
  for (final dark in [false, true]) {
    testWidgets('home ${dark ? 'dark' : 'light'}', (t) async {
      await loadFonts();
      t.view.physicalSize = const Size(1080, 2340);
      t.view.devicePixelRatio = 2.625;
      t.view.padding = const FakeViewPadding(top: 63, bottom: 63);
      t.view.viewPadding = const FakeViewPadding(top: 63, bottom: 63);
      await t.pumpWidget(MaterialApp(debugShowCheckedModeBanner: false,
          theme: AppTheme.build(dark ? AppTheme.darkScheme : AppTheme.lightScheme), home: _home()));
      await t.pump(const Duration(milliseconds: 100));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      for (var i = 0; i < 8; i++) { await t.pump(const Duration(milliseconds: 50)); }
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/home_${dark ? 'dark' : 'light'}.png'));
      await t.pumpWidget(const SizedBox());
    });
  }
}
