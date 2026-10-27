// Stock screen brand-wise: har brand ka tile (logo + naam + count), tap par
// usi brand ke phones. Brand strings stock me alag spelling me aate hain, isliye
// "Apple" aur "iPhone" ek hi brand (2 phones) banne chahiye.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_shop/design/design.dart';
import 'package:mobile_shop/screens/brand_art.dart';
import 'package:mobile_shop/screens/stock.dart';

Map<String, dynamic> _phone(int id, String brand, String model, {int price = 20000}) => {
      'id': id,
      'brand': brand,
      'model': model,
      'imei': '3533281112345$id',
      'ram': '8GB',
      'storage': '128GB',
      'condition': 'Good',
      'buy_price': price,
      'buy_date': '2026-10-01T00:00:00.000Z',
    };

final _items = [
  _phone(1, 'Apple', 'iPhone 13', price: 31000),
  _phone(2, 'iPhone', 'iPhone 12', price: 26000),   // same brand as Apple
  _phone(3, 'Samsung', 'Galaxy S23', price: 23000),
  _phone(4, 'Vivo', 'Y200 5G', price: 14500),
];

Widget _app(List<dynamic> items) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(AppTheme.lightScheme),
      home: Scaffold(body: StockScreen(testItems: items, onBuy: () {})),
    );

void main() {
  testWidgets('har brand ka tile: logo + naam + kitne stock me', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_app(_items));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Brands'), findsOneWidget);
    // Apple ke naam ke do roop (Apple + iPhone) ek hi brand me.
    expect(find.text('3 brands · 4 in stock'), findsOneWidget,
        reason: 'Apple(iPhone 12+13), Samsung, Vivo');
    expect(find.text('Apple'), findsOneWidget);
    expect(find.text('Samsung'), findsOneWidget);
    expect(find.text('Vivo'), findsOneWidget);
    expect(find.text('2 in stock'), findsOneWidget, reason: 'Apple ke 2 phone');
    expect(find.text('1 in stock'), findsNWidgets(2));
    expect(find.bySemanticsLabel('Apple, 2 in stock'), findsOneWidget);
    expect(find.bySemanticsLabel('Samsung, 1 in stock'), findsOneWidget);
    // Rows par bhi brand ka logo.
    expect(find.byType(BrandLogo), findsWidgets);
    semantics.dispose();
  });

  testWidgets('brand par tap → sirf usi brand ke phones', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_app(_items));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('Samsung'));
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('Samsung · 1 in stock'), findsOneWidget, reason: 'filtered header');
    expect(find.text('Samsung Galaxy S23'), findsOneWidget);
    expect(find.text('All brands'), findsOneWidget);
    expect(find.text('Apple iPhone 13'), findsNothing);
    expect(find.text('iPhone iPhone 12'), findsNothing);
    expect(find.text('Vivo Y200 5G'), findsNothing);

    // Wahi tile dobara tap = filter off.
    await tester.tap(find.text('Samsung'));
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Apple iPhone 13'), findsOneWidget);
    expect(find.text('Vivo Y200 5G'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('"All brands" filter hata deta hai', (tester) async {
    await tester.pumpWidget(_app(_items));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('Vivo'));
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Apple iPhone 13'), findsNothing);

    await tester.tap(find.text('All brands'));
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Apple iPhone 13'), findsOneWidget);
    expect(find.text('Samsung Galaxy S23'), findsOneWidget);
    expect(find.text('All brands'), findsNothing);
  });

  testWidgets('ek hi brand ho to brand strip nahi (list simple rehti hai)', (tester) async {
    await tester.pumpWidget(_app([_phone(9, 'Apple', 'iPhone 15')]));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Brands'), findsNothing);
    expect(find.text('Apple iPhone 15'), findsOneWidget);
  });

  testWidgets('200% text scale par brand strip overflow nahi karti', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(AppTheme.lightScheme),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(2)), child: child!),
      home: Scaffold(body: StockScreen(testItems: _items, onBuy: () {})),
    ));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull, reason: 'brand tiles 200% text par fit hone chahiye');

    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);
  });
}
