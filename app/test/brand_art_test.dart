// Brand tiles: Stock screen har brand ko brand logo + naam ke saath dikhata
// hai. Brands ki spelling stock me alag-alag hoti hai ("iPhone", "Apple",
// "samsung", "Mi", "REDMI") — sab ek hi tile par aane chahiye.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_shop/design/design.dart';
import 'package:mobile_shop/screens/brand_art.dart';

Widget _app(Widget child) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(AppTheme.lightScheme),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  group('brandInfo', () {
    test('popular brands ka apna naam, rang aur mark', () {
      final apple = brandInfo('Apple');
      expect(apple.name, 'Apple');
      expect(apple.mark, 'A');
      final samsung = brandInfo('Samsung');
      expect(samsung.name, 'Samsung');
      expect(samsung.mark, 'S');
      expect(samsung.color, isNot(apple.color), reason: 'har brand ka apna rang');
      expect(brandInfo('Vivo').name, 'Vivo');
      expect(brandInfo('OnePlus').name, 'OnePlus');
    });

    test('spelling variants ek hi brand par aate hain', () {
      for (final raw in ['iPhone', 'iphone', 'Apple', 'apple inc', 'Apple iPhone']) {
        expect(brandInfo(raw).key, 'apple', reason: '$raw → Apple');
      }
      for (final raw in ['samsung', 'SAMSUNG', 'Samsung Galaxy', 'samsung electronics']) {
        expect(brandInfo(raw).key, 'samsung', reason: '$raw → Samsung');
      }
      expect(brandInfo('Mi').key, 'xiaomi');
      expect(brandInfo('xiaomi').key, 'xiaomi');
      expect(brandInfo('redmi').key, 'redmi');
      expect(brandInfo('  redmi  ').key, 'redmi');
      expect(brandInfo('iQOO').key, 'iqoo');
      expect(brandInfo('one plus').key, 'oneplus');
      expect(brandInfo('moto').key, 'motorola');
    });

    test('anjaan brand bhi tile paata hai (naam ka pehla akshar)', () {
      final unknown = brandInfo('Nord');
      expect(unknown.name, 'Nord');
      expect(unknown.mark, 'N');
      expect(unknown.color, isNotNull);
      // Jaan-pehchan brand ka pehla shabd ho to wahi brand (Lava Agni → Lava).
      expect(brandInfo('Lava Agni').name, 'Lava');
      // Bilkul anjaan do-shabd brand → dono ke initials.
      expect(brandInfo('Nexus Mobile').mark, 'NM');
      expect(brandInfo(null).name, 'Unknown');
      expect(brandInfo('').name, 'Unknown');
    });

    test('brandKey grouping ke liye stable hai', () {
      expect(brandKey('Redmi'), brandKey('redmi'));
      expect(brandKey('Xiaomi'), brandKey('MI'));
      expect(brandKey('Samsung'), isNot(brandKey('Vivo')));
    });
  });

  group('BrandLogo', () {
    testWidgets('brand ka mark aur semantics dikhta hai', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(_app(const BrandLogo(brand: 'Samsung', size: 44)));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.bySemanticsLabel('Samsung logo'), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
      final box = tester.getSize(find.byType(BrandLogo));
      expect(box, const Size(44, 44));
      semantics.dispose();
    });

    testWidgets('unknown brand bhi crash nahi karta', (tester) async {
      await tester.pumpWidget(_app(const BrandLogo(brand: 'Karbonn', size: 44)));
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
    });
  });

  group('BrandTile', () {
    testWidgets('naam + stock count + tap callback', (tester) async {
      final semantics = tester.ensureSemantics();
      var taps = 0;
      await tester.pumpWidget(_app(BrandTile(brand: 'Vivo', count: 3, selected: false, onTap: () => taps++)));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Vivo'), findsOneWidget);
      expect(find.text('3 in stock'), findsOneWidget);
      expect(find.bySemanticsLabel('Vivo, 3 in stock'), findsOneWidget);

      await tester.tap(find.byType(BrandTile));
      await tester.pump(const Duration(milliseconds: 50));
      expect(taps, 1);
      semantics.dispose();
    });

    testWidgets('selected tile ka naam highlight hota hai', (tester) async {
      await tester.pumpWidget(_app(BrandTile(brand: 'Apple', count: 1, selected: true, onTap: () {})));
      await tester.pump(const Duration(milliseconds: 50));
      final text = tester.widget<Text>(find.text('Apple'));
      final c = tester.element(find.text('Apple')).colors;
      expect(text.style?.color, c.brandInk);
      expect(text.style?.fontWeight, FontWeight.w700);
    });
  });
}
