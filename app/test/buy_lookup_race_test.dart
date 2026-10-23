// Buy form IMEI lookup race.
//
// Bug: `_lookup` har 15-digit change par network call karta tha aur response ko
// seedha form me likh deta tha — purane IMEI ka jawab naye IMEI ke upar likh jata
// tha (galat brand/model stock me, aage galat invoice). Ab har lookup ka
// generation number hai aur response lagane se pehle live IMEI se match hota hai.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_shop/design/components/components.dart';
import 'package:mobile_shop/design/design.dart';
import 'package:mobile_shop/screens/buy_form.dart';

import 'showcase_golden_test.dart' show loadFonts;

const _imeiA = '353328111234561';
const _imeiB = '867699041234569';

Finder _field(String label) =>
    find.byWidgetPredicate((w) => w is GlassTextField && w.label == label);

Map<String, dynamic> _found(String brand, String model) => {
  'imei': '', 'valid': true, 'found': true, 'already_in_stock': false,
  'info': {'brand': brand, 'model': model, 'source': 'seed'},
  'options': {'ram': <String>[], 'storage': <String>[], 'color': <String>[]},
  'history': <dynamic>[],
};

void main() {
  testWidgets('a stale lookup response never overwrites a newer IMEI', (t) async {
    await loadFonts();
    final a = Completer<Map<String, dynamic>>();
    final b = Completer<Map<String, dynamic>>();
    // Poora form (Brand/Model fields) build ho jaye, taaki controller padha ja sake.
    t.view.physicalSize = const Size(500, 1800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);

    await t.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(AppTheme.lightScheme),
      home: Scaffold(body: AuroraBackground(child: BuyForm(
        onSaved: () {},
        testLookup: (imei) => imei == _imeiA ? a.future : b.future,
      ))),
    ));
    await t.pump();

    await t.enterText(_field('IMEI 1'), _imeiA);
    await t.pump();
    await t.enterText(_field('IMEI 1'), _imeiB);
    await t.pump();

    // Purana (A) response late aata hai — isse form nahi badalna chahiye.
    a.complete(_found('Apple', 'iPhone 13'));
    await t.pump();
    await t.pump();
    expect(find.textContaining('iPhone 13'), findsNothing);

    // Naya (B) response hi lagta hai.
    b.complete(_found('Samsung', 'Galaxy S21'));
    await t.pump();
    await t.pump();
    expect(find.textContaining('Galaxy S21'), findsWidgets);
    expect(find.textContaining('iPhone 13'), findsNothing);
    expect(t.widget<GlassTextField>(_field('Brand')).controller.text, 'Samsung');
  });
}
