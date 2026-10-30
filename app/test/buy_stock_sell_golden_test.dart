import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_shop/design/components/components.dart';
import 'package:mobile_shop/design/design.dart';
import 'package:mobile_shop/screens/buy_form.dart';
import 'package:mobile_shop/screens/sell_form.dart';
import 'package:mobile_shop/screens/stock.dart';
import 'showcase_golden_test.dart' show loadFonts;

final _stock = [
  {'id': 1, 'brand': 'Apple', 'model': 'iPhone 13', 'ram': '4GB', 'storage': '128GB', 'condition': 'Excellent', 'buy_price': 31000, 'buy_date': '2026-09-28', 'imei': '353328111234561'},
  {'id': 2, 'brand': 'Samsung', 'model': 'Galaxy S23', 'ram': '8GB', 'storage': '256GB', 'condition': 'Good', 'buy_price': 23000, 'buy_date': '2026-09-20', 'imei': '351122334455667'},
  {'id': 3, 'brand': 'OnePlus', 'model': 'Nord CE 3', 'ram': '8GB', 'storage': '128GB', 'condition': 'Fair', 'buy_price': 11500, 'buy_date': '2026-09-14', 'imei': '867788990011223'},
];

void main() {
  final cases = <String, Widget Function(bool dark)>{
    'buy': (dark) => MaterialApp(debugShowCheckedModeBanner: false,
        theme: AppTheme.build(dark ? AppTheme.darkScheme : AppTheme.lightScheme),
        home: Scaffold(body: AuroraBackground(child: BuyForm(
          onSaved: () {},
          testLookup: (imei) async => {'valid': true, 'found': true, 'history': const [{}],
              'info': {'brand': 'Apple', 'model': 'iPhone 13', 'ram': '4GB', 'storage': '128GB', 'color': 'Black'},
              // Dropdown options, as /imei/:imei returns them.
              'options': {
                'ram': ['4GB', '6GB', '8GB'],
                'storage': ['128GB', '256GB'],
                'color': ['Black', 'Blue', 'Silver'],
              }})))),
    'stock': (dark) => MaterialApp(debugShowCheckedModeBanner: false,
        theme: AppTheme.build(dark ? AppTheme.darkScheme : AppTheme.lightScheme),
        home: Scaffold(body: AuroraBackground(child: StockScreen(testItems: _stock, onBuy: () {})))),
    'sell': (dark) => MaterialApp(debugShowCheckedModeBanner: false,
        theme: AppTheme.build(dark ? AppTheme.darkScheme : AppTheme.lightScheme),
        home: SellForm(phone: Map<String, dynamic>.from(_stock[0]), testSave: (_) async {})),
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
        if (e.key == 'buy') {
          await t.enterText(find.byType(TextField).first, '353328111234561');
          for (var i = 0; i < 10; i++) { await t.pump(const Duration(milliseconds: 60)); }
        } else if (e.key == 'sell') {
          await t.enterText(find.byType(TextField).first, '34500');
          await t.pump(const Duration(milliseconds: 100));
        }
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
        for (var i = 0; i < 8; i++) { await t.pump(const Duration(milliseconds: 50)); }
        await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/${e.key}_${dark ? 'dark' : 'light'}.png'));
        await t.pumpWidget(const SizedBox());
      });
    }
  }
}
