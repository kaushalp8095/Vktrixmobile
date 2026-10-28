// Shop list ke row me bill logo ka chhota thumbnail.
//
// Poora logo (base64) list me nahi bhejna chahiye — 20 shops = 10 MB+ response.
// Server har logo ka 96px thumbnail (`logo_thumb`, ~2-3 KB) bhejta hai; ye widget
// usi ko dikhata hai aur kuch bhi galat ho to pehle jaisa store icon.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_shop/design/design.dart';
import 'package:mobile_shop/screens/shop_logo.dart';

import 'fixtures/logo.dart';

Widget _app(Widget child) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(AppTheme.lightScheme),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  group('decodeLogoThumb', () {
    test('data URL aur seedha base64 dono decode hote hain', () {
      expect(decodeLogoThumb(kTestLogoDataUrl), isNotEmpty);
      expect(decodeLogoThumb(kTestLogoJpegBase64), isNotEmpty);
      expect(decodeLogoThumb(kTestLogoDataUrl), decodeLogoThumb(kTestLogoJpegBase64),
          reason: 'dono raste same bytes dete hain');
    });

    test('khaali / null / kharab data par crash nahi', () {
      expect(decodeLogoThumb(null), isNull);
      expect(decodeLogoThumb(''), isNull);
      expect(decodeLogoThumb('null'), isNull);
      expect(decodeLogoThumb('data:image/jpeg;base64,'), isNull);
      expect(decodeLogoThumb('%%% not base64 %%%'), isNull);
    });
  });

  group('ShopLogoAvatar', () {
    testWidgets('thumbnail ho to logo dikhta hai, icon nahi', (tester) async {
      await tester.pumpWidget(_app(const ShopLogoAvatar(thumb: kTestLogoDataUrl, active: true)));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(Image), findsOneWidget);
      expect(find.byIcon(Icons.store_outlined), findsNothing);
    });

    testWidgets('thumbnail na ho to purana store icon', (tester) async {
      await tester.pumpWidget(_app(const ShopLogoAvatar(thumb: null, active: true)));

      expect(find.byType(Image), findsNothing);
      expect(find.byIcon(Icons.store_outlined), findsOneWidget);
    });

    testWidgets('kharab thumbnail bytes par bhi icon par gir jata hai', (tester) async {
      // Valid base64, par JPEG nahi — Image.memory decode fail karega.
      await tester.pumpWidget(_app(const ShopLogoAvatar(thumb: 'aGVsbG8gd29ybGQ=', active: true)));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byIcon(Icons.store_outlined), findsOneWidget);
    });

    testWidgets('deactivated shop ka icon muted tone me hota hai', (tester) async {
      await tester.pumpWidget(_app(const ShopLogoAvatar(thumb: null, active: false)));
      final icon = tester.widget<Icon>(find.byIcon(Icons.store_outlined));
      final c = AppTheme.build(AppTheme.lightScheme).extension<AppColors>()!;
      expect(icon.color, c.textSecondary);
    });

    testWidgets('size badalne par logo usi box me fit hota hai', (tester) async {
      await tester.pumpWidget(_app(const ShopLogoAvatar(thumb: kTestLogoDataUrl, active: true, size: 22)));
      await tester.pump(const Duration(milliseconds: 50));

      final box = tester.getSize(find.byType(ShopLogoAvatar));
      expect(box.width, 22);
      expect(box.height, 22);
    });
  });

  group('shape (Oct 2026 rounded-square)', () {
    test('radius size ka ~26% hota hai (app-icon squircle ratio)', () {
      expect(logoRadius(44), closeTo(11.44, .01));
      expect(logoRadius(56), closeTo(14.56, .01));
      // 16dp radius (purana Radii.md) 44dp tile par bahut gol lagta tha.
      expect(logoRadius(44), lessThan(Radii.md));
    });

    testWidgets('default rounded square hai, circle nahi', (tester) async {
      await tester.pumpWidget(_app(const ShopLogoAvatar(thumb: kTestLogoDataUrl, active: true, size: 44)));
      await tester.pump(const Duration(milliseconds: 50));

      final container = tester.widget<Container>(find.descendant(
          of: find.byType(ShopLogoAvatar), matching: find.byType(Container)).first);
      final radius = (container.decoration as BoxDecoration).borderRadius as BorderRadius;
      expect(radius.topLeft.x, closeTo(logoRadius(44), .01));
      expect(radius.topLeft.x, isNot(Radii.full));
    });

    testWidgets('circle: true par purana gola shape milta hai', (tester) async {
      await tester.pumpWidget(_app(
          const ShopLogoAvatar(thumb: kTestLogoDataUrl, active: true, size: 44, circle: true)));
      await tester.pump(const Duration(milliseconds: 50));

      final container = tester.widget<Container>(find.descendant(
          of: find.byType(ShopLogoAvatar), matching: find.byType(Container)).first);
      final radius = (container.decoration as BoxDecoration).borderRadius as BorderRadius;
      expect(radius.topLeft.x, 44);
    });

    testWidgets('image poora box bharta hai (cover), chhota floating nahi', (tester) async {
      await tester.pumpWidget(_app(const ShopLogoAvatar(thumb: kTestLogoDataUrl, active: true)));
      await tester.pump(const Duration(milliseconds: 50));

      final image = tester.widget<Image>(find.byType(Image));
      expect(image.fit, BoxFit.cover);
    });

    testWidgets('logo na ho to shop ke naam ka pehla akshar dikhta hai', (tester) async {
      await tester.pumpWidget(_app(
          const ShopLogoAvatar(thumb: null, active: true, fallbackLetter: 'Patidar Mobile Shop')));

      expect(find.text('P'), findsOneWidget);
      expect(find.byIcon(Icons.store_outlined), findsNothing);
    });

    testWidgets('letter bhi na ho to store icon (kabhi khaali box nahi)', (tester) async {
      await tester.pumpWidget(_app(const ShopLogoAvatar(thumb: null, active: true, fallbackLetter: '   ')));

      expect(find.byIcon(Icons.store_outlined), findsOneWidget);
    });
  });

  group('box me logo poora set (full-bleed, koi plate/frame nahi)', () {
    testWidgets('logo ho to peeche koi plate nahi (na safed, na tinted)', (tester) async {
      await tester.pumpWidget(_app(
          const ShopLogoAvatar(thumb: kTestLogoDataUrl, active: true, size: 44)));
      await tester.pump(const Duration(milliseconds: 50));

      final plate = tester.widget<Container>(find
          .descendant(of: find.byType(ShopLogoAvatar), matching: find.byType(Container))
          .first);
      final decoration = plate.decoration as BoxDecoration;
      expect(decoration.color, isNull, reason: 'plate ki jagah image hi box bhare');
      expect(decoration.border, isNull, reason: 'border container ka nahi, image ke upar');
      expect(plate.clipBehavior, Clip.antiAlias, reason: 'corners box ke radius par cut');
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('image box ko poora bharta hai aur border image ke upar hota hai', (tester) async {
      await tester.pumpWidget(_app(
          const ShopLogoAvatar(thumb: kTestLogoDataUrl, active: true, size: 44)));
      await tester.pump(const Duration(milliseconds: 50));

      final image = tester.widget<Image>(find.byType(Image));
      expect(image.fit, BoxFit.cover, reason: 'contain se patti bachti hai');
      // Image aur box ka size exactly same — koi inset/padding nahi.
      expect(tester.getSize(find.byType(Image)), const Size(44, 44));
      expect(tester.getSize(find.byType(ShopLogoAvatar)), const Size(44, 44));

      // Hairline border image ke upar (IgnorePointer) draw hota hai.
      final overlay = find.descendant(
          of: find.byType(IgnorePointer), matching: find.byType(DecoratedBox));
      expect(overlay, findsWidgets);
      final decoration = tester.widget<DecoratedBox>(overlay.first).decoration as BoxDecoration;
      final border = decoration.border! as Border;
      expect(border.top.color.a, lessThan(.30), reason: 'patli hairline, moti frame nahi');
      expect((decoration.borderRadius as BorderRadius).topLeft.x,
          closeTo(logoRadius(44), .01), reason: 'border wahi radius jo box ka hai');
    });

    testWidgets('logo na ho to hi tinted plate + border (fallback box)', (tester) async {
      await tester.pumpWidget(_app(const ShopLogoAvatar(thumb: null, active: true, fallbackLetter: 'K')));
      final plate = tester.widget<Container>(find
          .descendant(of: find.byType(ShopLogoAvatar), matching: find.byType(Container))
          .first);
      final decoration = plate.decoration as BoxDecoration;
      expect(decoration.color, isNotNull);
      expect(decoration.border, isNotNull);
    });
  });
}
