import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_shop/design/components/components.dart';
import 'package:mobile_shop/design/design.dart';
import 'package:mobile_shop/screens/admin_home.dart';
import 'package:mobile_shop/screens/reports.dart';
import 'package:mobile_shop/screens/sales.dart';
import 'showcase_golden_test.dart' show loadFonts;

final _sales = [
  {'id': 11, 'brand': 'Samsung', 'model': 'Galaxy S23', 'ram': '8GB', 'storage': '256GB', 'imei': '351122334455667',
   'sell_price': 26500, 'buy_price': 23000, 'sell_date': '2026-09-28', 'customer_name': 'Ramesh Patel', 'payment_mode': 'upi'},
  {'id': 10, 'brand': 'Redmi', 'model': 'Note 12', 'ram': '6GB', 'storage': '128GB', 'imei': '867788990011223',
   'sell_price': 9200, 'buy_price': 7800, 'sell_date': '2026-09-26', 'customer_name': 'Walk-in', 'payment_mode': 'cash'},
];

const _summary = {
  'purchases': {'count': 9, 'amount': 84500},
  'sales': {'count': 7, 'amount': 112000, 'profit': 27500},
  'stock': {'count': 18, 'value': 124500},
  'by_payment': [
    {'mode': 'cash', 'count': 4, 'total': 61500},
    {'mode': 'upi', 'count': 2, 'total': 38500},
    {'mode': 'card', 'count': 1, 'total': 12000},
  ],
  'top_models': [
    {'brand': 'Samsung', 'model': 'Galaxy S23', 'count': 3},
    {'brand': 'Apple', 'model': 'iPhone 13', 'count': 2},
    {'brand': 'Redmi', 'model': 'Note 12', 'count': 2},
  ],
};

final _daily = [
  {'date': '2026-09-23', 'sales': 0}, {'date': '2026-09-24', 'sales': 12500}, {'date': '2026-09-25', 'sales': 8200},
  {'date': '2026-09-26', 'sales': 21400}, {'date': '2026-09-27', 'sales': 5600}, {'date': '2026-09-28', 'sales': 30200},
  {'date': '2026-09-29', 'sales': 14100}, {'date': '2026-09-30', 'sales': 20000},
];

const _dash = {'shops': 3, 'stock_count': 41, 'stock_value': 312000, 'sales_count': 25, 'sales_value': 402500};
final _shops = [
  {'id': 1, 'name': 'Krishna Mobiles', 'login': {'username': 'krishna'}, 'stock_count': 18, 'active': 1},
  {'id': 2, 'name': 'Shree Ganesh Mobile', 'login': {'username': 'ganesh22'}, 'stock_count': 15, 'active': 1},
  {'id': 3, 'name': 'Om Communication', 'login': {'username': 'omcomm'}, 'stock_count': 8, 'active': 0},
];

void main() {
  final cases = <String, Widget Function(bool)>{
    'sales': (dark) => MaterialApp(debugShowCheckedModeBanner: false,
        theme: AppTheme.build(dark ? AppTheme.darkScheme : AppTheme.lightScheme),
        home: Scaffold(body: AuroraBackground(child: SalesScreen(testItems: _sales)))),
    'reports': (dark) => MaterialApp(debugShowCheckedModeBanner: false,
        theme: AppTheme.build(dark ? AppTheme.darkScheme : AppTheme.lightScheme),
        home: Scaffold(body: AuroraBackground(child: ReportsScreen(testSummary: _summary, testDaily: _daily, testPreset: 'week')))),
    'admin': (dark) => MaterialApp(debugShowCheckedModeBanner: false,
        theme: AppTheme.build(dark ? AppTheme.darkScheme : AppTheme.lightScheme),
        home: AdminHome(testDash: _dash, testShops: _shops)),
  };
  for (final e in cases.entries) {
    for (final dark in [false, true]) {
      testWidgets('${e.key} ${dark ? 'dark' : 'light'}', (t) async {
        await loadFonts();
        t.view.physicalSize = const Size(1080, 2340);
        t.view.devicePixelRatio = 2.625;
        t.view.padding = const FakeViewPadding(top: 63, bottom: 63);
        t.view.viewPadding = const FakeViewPadding(top: 63, bottom: 63);
        await t.pumpWidget(e.value(dark));
        await t.pump(const Duration(milliseconds: 100));
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
        for (var i = 0; i < 16; i++) { await t.pump(const Duration(milliseconds: 50)); }
        await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/${e.key}_${dark ? 'dark' : 'light'}.png'));
        await t.pumpWidget(const SizedBox());
      });
    }
  }
}
