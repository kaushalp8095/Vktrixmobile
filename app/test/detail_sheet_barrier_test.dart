import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_shop/design/design.dart';
import 'package:mobile_shop/screens/sales.dart';
import 'package:mobile_shop/screens/stock.dart';

void main() {
  testWidgets('stock detail sheet stays bright and remains dismissible', (tester) async {
    _setViewport(tester);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.build(AppTheme.lightScheme),
      home: Scaffold(body: StockScreen(testItems: [
        {
          'id': 1,
          'brand': 'VIVO',
          'model': 'Y200 5G',
          'imei': '868956062133750',
          'ram': '4GB',
          'storage': '64GB',
          'color': 'Silver',
          'condition': 'Good',
          'buy_price': 20000,
          'buy_date': '2026-10-14T00:00:00.000Z',
        },
      ])),
    ));

    await _expectTransparentDismissibleSheet(
      tester,
      row: find.text('VIVO Y200 5G').first,
      actionLabel: 'Sell this phone',
    );
  });

  testWidgets('sales detail sheet stays bright and remains dismissible', (tester) async {
    _setViewport(tester);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.build(AppTheme.lightScheme),
      home: Scaffold(body: SalesScreen(testItems: [
        {
          'id': 1,
          'brand': 'Samsung',
          'model': 'S24',
          'imei': '866221052843351',
          'ram': '16GB',
          'storage': '256GB',
          'sell_price': 70000,
          'buy_price': 60000,
          'sell_date': '2026-10-09T00:00:00.000Z',
          'customer_name': 'Kaushal Patel',
          'customer_phone': '5896478596',
          'payment_mode': 'cash',
          'paid_amount': 70000,
          'balance_due': 0,
          'warranty': '5 month',
        },
      ])),
    ));

    await _expectTransparentDismissibleSheet(
      tester,
      row: find.text('Samsung S24').first,
      actionLabel: 'PDF bill & WhatsApp',
    );
  });
}

void _setViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1000);
  tester.view.devicePixelRatio = 1;
}

Future<void> _expectTransparentDismissibleSheet(
  WidgetTester tester, {
  required Finder row,
  required String actionLabel,
}) async {
  await tester.tap(row);
  await tester.pumpAndSettle();

  final barriers = tester.widgetList<ModalBarrier>(
    find.byWidgetPredicate((widget) => widget is ModalBarrier),
  );
  expect(barriers, isNotEmpty);
  expect(barriers.last.color, Colors.transparent);
  expect(barriers.last.dismissible, isTrue);
  expect(find.text(actionLabel), findsOneWidget);

  // The route barrier occupies the area above the bottom sheet; tapping it
  // should still dismiss the sheet, not leave a darkened page behind.
  await tester.tapAt(const Offset(10, 10));
  await tester.pumpAndSettle();
  expect(find.text(actionLabel), findsNothing);
}
