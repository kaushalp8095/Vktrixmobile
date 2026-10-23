// Dashboard "Recent activity": timeline order + profit ka sign.
//
// Do bugs yahan the:
//  1. sale ko `1000000 + id` banakar sort kiya jata tha, isliye har sale har
//     purchase ke upar aa jati thi — aaj ki kharidi purani sale ke neeche.
//  2. loss par label "+" lagta tha aur `rs()` minus sign rakhta hai -> "+₹-500".
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_shop/design/design.dart';
import 'package:mobile_shop/screens/dashboard.dart';

Map<String, dynamic> _summary() => {
  'purchases': {'count': 0, 'amount': 0},
  'sales': {'count': 0, 'amount': 0, 'profit': 0},
  'stock': {'count': 0, 'value': 0},
  'receivables': {'outstanding': 0, 'pending_count': 0},
};

void main() {
  test('recent activity is newest first across purchases and sales', () {
    final rows = Dashboard.recentActivity(
      [
        {'id': 11, 'brand': 'Apple', 'model': 'iPhone 13', 'buy_date': '2026-10-23', 'buy_price': 20000, 'seller_name': null},
      ],
      [
        {'id': 4, 'brand': 'Samsung', 'model': 'Galaxy S21', 'sell_date': '2026-10-01', 'sell_price': 18000, 'buy_price': 15000, 'customer_name': 'Ravi'},
      ],
    );
    // Aaj ki purchase purani sale se upar.
    expect(rows.first.title, 'Apple iPhone 13');
    expect(rows.first.isSale, isFalse);
    expect(rows.last.title, 'Samsung Galaxy S21');
  });

  test('same day: higher id first', () {
    final rows = Dashboard.recentActivity(
      [
        {'id': 9, 'brand': 'Vivo', 'model': 'Y20', 'buy_date': '2026-10-23', 'buy_price': 8000, 'seller_name': null},
      ],
      [
        {'id': 2, 'brand': 'Oppo', 'model': 'A15', 'sell_date': '2026-10-23', 'sell_price': 9000, 'buy_price': 7000, 'customer_name': null},
      ],
    );
    // Same date par real id 9 > 2 — sale ka synthetic id sort me nahi aata.
    expect(rows.map((r) => r.title), ['Vivo Y20', 'Oppo A15']);
  });

  testWidgets('a loss reads as -₹500, never +₹-500', (t) async {
    // Lamba canvas: "Recent activity" card lazy ListView me build ho jaye.
    t.view.physicalSize = const Size(1080, 4000);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(AppTheme.lightScheme),
      home: Scaffold(body: Dashboard(
        onGo: (_) {},
        shopName: 'Krishna Mobiles',
        greeting: 'Good morning',
        testSummary: _summary(),
        testRecent: const [
          ActivityItem(isSale: true, id: 1000001, title: 'iPhone 13', subtitle: 'Sold',
              date: '2026-10-23', amount: 20000, profit: -500),
        ],
      )),
    ));
    await t.pump();
    expect(find.text('-₹500'), findsOneWidget);
    expect(find.textContaining('+-'), findsNothing);
    expect(find.textContaining('₹-'), findsNothing);
  });
}
