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
}
