// Dashboard ke "Credit / pending payments" card ka source of truth.
//
// Bug: card `/reports/summary` ke period-scoped `receivables` par chalta tha
// (bina from/to = sirf aaj ki sales), isliye purana udhaar ledger me pending
// dikhta tha aur dashboard par "All payments are clear".
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_shop/design/design.dart';
import 'package:mobile_shop/screens/dashboard.dart';

/// Aaj ki koi sale nahi — period-scoped receivables zero hai.
Map<String, dynamic> _summary({int pendingCount = 0, int outstanding = 0}) => {
  'purchases': {'count': 0, 'amount': 0},
  'sales': {'count': 0, 'amount': 0, 'profit': 0},
  'stock': {'count': 0, 'value': 0},
  'receivables': {'outstanding': outstanding, 'pending_count': pendingCount},
};

/// Poore card tree ko ek phone-size canvas par rakhta hai, warna lazy
/// ListView niche wale card ko build hi nahi karta.
Future<void> _pump(WidgetTester t, Map<String, dynamic> summary, {Map<String, dynamic>? dues}) async {
  t.view.physicalSize = const Size(1080, 2340);
  t.view.devicePixelRatio = 2.625;
  addTearDown(t.view.reset);
  await t.pumpWidget(_home(summary, dues: dues));
  await t.pump();
}

Widget _home(Map<String, dynamic> summary, {Map<String, dynamic>? dues}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: AppTheme.build(AppTheme.lightScheme),
  home: Scaffold(
    body: Dashboard(
      onGo: (_) {},
      shopName: 'Krishna Mobiles',
      greeting: 'Good morning',
      onOpenLedger: () {},
      testSummary: summary,
      testDues: dues,
      testRecent: const [],
    ),
  ),
);

void main() {
  testWidgets('card counts all-time dues, not only today sales', (t) async {
    // Today clear (period summary 0) par 30 din purana udhaar pending.
    await _pump(t, _summary(), dues: const {'outstanding': 16000, 'pending_count': 1});

    expect(find.text('1 customer · ₹16,000 outstanding'), findsOneWidget);
    expect(find.text('OPEN'), findsOneWidget);
    expect(find.text('All payments are clear'), findsNothing);
  });

  testWidgets('a truly cleared ledger still reads CLEAR', (t) async {
    await _pump(t, _summary(), dues: const {'outstanding': 0, 'pending_count': 0});

    expect(find.text('All payments are clear'), findsOneWidget);
    expect(find.text('CLEAR'), findsOneWidget);
    expect(find.text('OPEN'), findsNothing);
  });

  testWidgets('plural is right for more than one customer', (t) async {
    await _pump(t, _summary(), dues: const {'outstanding': 14500, 'pending_count': 2});

    expect(find.text('2 customers · ₹14,500 outstanding'), findsOneWidget);
  });

  testWidgets('older server without /ledger/summary falls back to the summary', (t) async {
    // testDues null = endpoint ne jawab nahi diya; card fir bhi bhare.
    await _pump(t, _summary(pendingCount: 2, outstanding: 9000));

    expect(find.text('2 customers · ₹9,000 outstanding'), findsOneWidget);
    expect(find.text('OPEN'), findsOneWidget);
  });
}
