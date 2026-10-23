// 200% text scale (settings → font size) par layout nahi tootna chahiye.
//
// Pehle buttons aur labels `height: 56/40/64` par fix the: font bada karte hi
// text box se bahar nikal jata tha (yellow-black overflow) aur kuch rows me
// label kat jata tha. Ab wahan `minHeight` + padding hai, to box text ke saath
// badhta hai. Flutter har overflow ko test failure banata hai; `takeException`
// se har screen par explicitly check bhi karte hain.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_shop/api.dart';
import 'package:mobile_shop/design/components/components.dart';
import 'package:mobile_shop/design/design.dart';
import 'package:mobile_shop/screens/buy_form.dart';
import 'package:mobile_shop/screens/profile.dart';
import 'package:mobile_shop/screens/reports.dart';
import 'package:mobile_shop/screens/sell_form.dart';
import 'package:mobile_shop/screens/stock.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'showcase_golden_test.dart' show loadFonts;

final _stock = [
  {'id': 1, 'brand': 'Apple', 'model': 'iPhone 13', 'ram': '4GB', 'storage': '128GB', 'condition': 'Excellent',
    'buy_price': 31000, 'buy_date': '2026-09-28', 'imei': '353328111234561'},
  {'id': 2, 'brand': 'Samsung', 'model': 'Galaxy S23', 'ram': '8GB', 'storage': '256GB', 'condition': 'Good',
    'buy_price': 23000, 'buy_date': '2026-09-20', 'imei': '351122334455667'},
];

const _summary = {
  'purchases': {'count': 9, 'amount': 84500},
  'sales': {'count': 7, 'amount': 112000, 'profit': 27500},
  'stock': {'count': 18, 'value': 124500},
  'receivables': {'outstanding': 21500, 'received': 90500, 'pending_count': 2},
  'by_payment': [{'mode': 'cash', 'count': 4, 'total': 61500}, {'mode': 'upi', 'count': 2, 'total': 38500}],
  'top_models': [{'brand': 'Samsung', 'model': 'Galaxy S23', 'count': 3}],
};

final _daily = [
  {'date': '2026-09-24', 'sales': 12500}, {'date': '2026-09-25', 'sales': 8200},
  {'date': '2026-09-26', 'sales': 21400}, {'date': '2026-09-27', 'sales': 5600},
  {'date': '2026-09-28', 'sales': 30200}, {'date': '2026-09-29', 'sales': 14100},
];

Future<void> _pump(WidgetTester t, Widget home, {double scale = 2}) async {
  await loadFonts();
  t.view.physicalSize = const Size(1080, 2340);
  t.view.devicePixelRatio = 2.625;
  t.view.padding = const FakeViewPadding(top: 63, bottom: 63);
  t.view.viewPadding = const FakeViewPadding(top: 63, bottom: 63);
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.build(AppTheme.lightScheme),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
    home: home,
  ));
  await t.pump(const Duration(milliseconds: 200));
}

/// List ko neeche tak scroll karta hai — lazy rows tab hi bante hain.
Future<void> _scrollThrough(WidgetTester t) async {
  final scrollable = find.byType(Scrollable).first;
  for (var i = 0; i < 6; i++) {
    await t.drag(scrollable, const Offset(0, -320));
    await t.pump(const Duration(milliseconds: 120));
  }
}

Widget _page(Widget child) => Scaffold(body: AuroraBackground(child: child));

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Api.token = 'test-token';
    Api.user = {'id': 7, 'name': 'Krishna Patel', 'username': 'krishna', 'role': 'shop_admin',
      'shop': {'id': 1, 'name': 'Krishna Mobiles'}};
    Api.endSupport();
  });

  tearDown(() {
    Api.token = null; Api.user = null; Api.endSupport();
  });

  testWidgets('buy form fits at 200% text scale', (t) async {
    await _pump(t, _page(BuyForm(onSaved: () {}, testLookup: (imei) async => {
      'valid': true,
      'found': false,
      'history': const [],
      'info': {'brand': 'Apple', 'model': 'iPhone 13', 'ram': '4GB', 'storage': '128GB'},
    })));
    expect(t.takeException(), isNull, reason: 'buy form must lay out at 200% text');
    await _scrollThrough(t);
    expect(t.takeException(), isNull, reason: 'buy form lower half must lay out at 200% text');
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('sell form fits at 200% text scale', (t) async {
    await _pump(t, SellForm(phone: Map<String, dynamic>.from(_stock[0]), testSave: (_) async {}));
    expect(t.takeException(), isNull, reason: 'sell form must lay out at 200% text');
    await _scrollThrough(t);
    expect(t.takeException(), isNull, reason: 'sell form lower half must lay out at 200% text');
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('reports fit at 200% text scale', (t) async {
    await _pump(t, _page(ReportsScreen(testSummary: _summary, testDaily: _daily, testPreset: 'week')));
    expect(t.takeException(), isNull, reason: 'reports (range chips, rows) must lay out at 200% text');
    await _scrollThrough(t);
    expect(t.takeException(), isNull, reason: 'reports lower half must lay out at 200% text');
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('profile fits at 200% text scale', (t) async {
    await _pump(t, const ProfileScreen());
    await t.pump(const Duration(milliseconds: 200));
    expect(t.takeException(), isNull, reason: 'profile (theme tiles, rows) must lay out at 200% text');
    await _scrollThrough(t);
    expect(t.takeException(), isNull, reason: 'profile lower half must lay out at 200% text');
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('stock list fits at 200% text scale', (t) async {
    await _pump(t, _page(StockScreen(testItems: _stock, onBuy: () {})));
    expect(t.takeException(), isNull, reason: 'stock rows must lay out at 200% text');
    await _scrollThrough(t);
    expect(t.takeException(), isNull, reason: 'stock lower half must lay out at 200% text');
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('glass form and confirm dialogs fit at 200% text scale', (t) async {
    await _pump(t, Scaffold(body: Builder(builder: (ctx) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      FilledButton(
        onPressed: () => showGlassFormDialog(ctx,
          title: 'New shop', icon: Icons.add_business_outlined, confirmLabel: 'Create shop',
          body: (_) => Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(decoration: const InputDecoration(labelText: 'Shop name *')),
            const SizedBox(height: 8),
            TextFormField(decoration: const InputDecoration(labelText: 'Mobile (new number, optional)')),
          ])),
        child: const Text('form')),
      const SizedBox(height: 12),
      FilledButton(
        onPressed: () => showConfirmDialog(ctx,
          title: 'Delete shop permanently?',
          message: 'Krishna Mobiles — all stock, sales and payment history will be deleted forever. '
              'This cannot be undone.',
          confirmLabel: 'Delete forever', destructive: true),
        child: const Text('confirm')),
    ])))));
    await t.tap(find.text('form'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byType(GlassDialogCard), findsOneWidget);
    expect(find.text('Create shop'), findsOneWidget);
    expect(t.takeException(), isNull, reason: 'form dialog must lay out at 200% text');
    await t.tap(find.text('Cancel'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byType(GlassDialogCard), findsNothing);

    await t.tap(find.text('confirm'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byType(ConfirmDialogCard), findsOneWidget);
    expect(find.text('Delete forever'), findsOneWidget);
    expect(t.takeException(), isNull, reason: 'confirm dialog must lay out at 200% text');
    await t.pumpWidget(const SizedBox());
  });
}
