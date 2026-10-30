import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_shop/design/components/components.dart';
import 'package:mobile_shop/design/design.dart';
import 'package:mobile_shop/screens/admin_home.dart';
import 'package:mobile_shop/screens/reports.dart';
import 'package:mobile_shop/screens/sales.dart';
import 'package:mobile_shop/screens/ledger.dart';
import 'fixtures/logo.dart';
import 'showcase_golden_test.dart' show loadFonts;
import 'support/golden_shadows.dart';

final _sales = [
  {'id': 11, 'brand': 'Samsung', 'model': 'Galaxy S23', 'ram': '8GB', 'storage': '256GB', 'imei': '351122334455667',
   'sell_price': 26500, 'buy_price': 23000, 'sell_date': '2026-09-28', 'customer_name': 'Ramesh Patel', 'payment_mode': 'upi',
   'paid_amount': 12000, 'balance_due': 14500, 'payment_status': 'partial'},
  {'id': 10, 'brand': 'Redmi', 'model': 'Note 12', 'ram': '6GB', 'storage': '128GB', 'imei': '867788990011223',
   'sell_price': 9200, 'buy_price': 7800, 'sell_date': '2026-09-26', 'customer_name': 'Walk-in', 'payment_mode': 'cash',
   'paid_amount': 9200, 'balance_due': 0, 'payment_status': 'paid'},
];

final _ledger = <String, dynamic>{
  'summary': {'outstanding': 21500, 'pending_count': 2, 'received': 27000, 'sales_total': 48500},
  'items': [
    {'id': 11, 'brand': 'Samsung', 'model': 'Galaxy S23', 'imei': '351122334455667',
      'sell_price': 26500, 'sell_date': '2026-09-28', 'customer_name': 'Ramesh Patel',
      'paid_amount': 12000, 'balance_due': 14500, 'payment_status': 'partial'},
    {'id': 9, 'brand': 'Apple', 'model': 'iPhone 13', 'imei': '353328111234561',
      'sell_price': 22000, 'sell_date': '2026-09-22', 'customer_name': 'Mehul Shah',
      'paid_amount': 15000, 'balance_due': 7000, 'payment_status': 'partial'},
  ],
};

const _summary = {
  'purchases': {'count': 9, 'amount': 84500},
  'sales': {'count': 7, 'amount': 112000, 'profit': 27500},
  'stock': {'count': 18, 'value': 124500},
  'receivables': {'outstanding': 21500, 'received': 90500, 'pending_count': 2},
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

// Super Admin ko sirf operational counts milte hain — shop ka stock/sales/profit nahi.
const _dash = {'shops': 3, 'active_shops': 2, 'inactive_shops': 1, 'support_active': 1};
final _shops = [
  {'id': 1, 'name': 'Krishna Mobiles', 'owner_name': 'Krishna Patel', 'login': {'username': 'krishna'}, 'active': 1,
   'phone_masked': '98•••••210', 'has_phone': true, 'created_at': '2025-04-12',
   // List row me asli logo ka 96px thumbnail (poora logo kabhi list me nahi jaata).
   'has_logo': true, 'logo_thumb': kTestLogoDataUrl,
   'support': {'reason': 'Shop owner called: sale entry stuck in ledger', 'expires_in_ms': 12 * 60 * 1000}, 'support_sessions': 2},
  {'id': 2, 'name': 'Shree Ganesh Mobile', 'login': {'username': 'ganesh22'}, 'active': 1,
   'phone_masked': '99•••••451', 'has_phone': true, 'created_at': '2025-06-02', 'support': null, 'support_sessions': 0},
  {'id': 3, 'name': 'Om Communication', 'login': {'username': 'omcomm'}, 'active': 0,
   'phone_masked': '97•••••884', 'has_phone': true, 'created_at': '2025-09-18', 'support': null, 'support_sessions': 1},
];

void main() {
  setUpAll(useRealShadows);
  final cases = <String, Widget Function(bool)>{
    'sales': (dark) => MaterialApp(debugShowCheckedModeBanner: false,
        theme: AppTheme.build(dark ? AppTheme.darkScheme : AppTheme.lightScheme),
        home: Scaffold(body: AuroraBackground(child: SalesScreen(testItems: _sales)))),
    'reports': (dark) => MaterialApp(debugShowCheckedModeBanner: false,
        theme: AppTheme.build(dark ? AppTheme.darkScheme : AppTheme.lightScheme),
        home: Scaffold(body: AuroraBackground(child: ReportsScreen(testSummary: _summary, testDaily: _daily, testPreset: 'week')))),
    'ledger': (dark) => MaterialApp(debugShowCheckedModeBanner: false,
        theme: AppTheme.build(dark ? AppTheme.darkScheme : AppTheme.lightScheme),
        home: LedgerScreen(testData: _ledger)),
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
