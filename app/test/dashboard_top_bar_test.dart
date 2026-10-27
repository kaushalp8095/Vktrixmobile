// Shop home ka top bar: shop ka logo → shop ka naam → … → profile icon, sab ek hi
// row me. Pehle top bar me sirf naam tha (logo kahin nahi), aur Profile card me
// logo circle tha — teen jagah teen shape.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_shop/api.dart';
import 'package:mobile_shop/design/design.dart';
import 'package:mobile_shop/screens/dashboard.dart';
import 'package:mobile_shop/screens/shop_logo.dart';

import 'fixtures/logo.dart';

Map<String, dynamic> _summary() => {
      'purchases': {'count': 0, 'amount': 0},
      'sales': {'count': 0, 'amount': 0, 'profit': 0},
      'stock': {'count': 0, 'value': 0},
      'receivables': {'outstanding': 0, 'received': 0, 'pending_count': 0},
    };

Widget _app({String? logoThumb, String shopName = 'Patidar Mobile Shop'}) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(AppTheme.lightScheme),
      home: Scaffold(
        body: Dashboard(
          onGo: (_) {},
          shopName: shopName,
          greeting: 'Good afternoon',
          testSummary: _summary(),
          testRecent: const [],
          logoThumb: logoThumb,
        ),
      ),
    );

void main() {
  testWidgets('shop name se pehle logo, usi row ke aakhir me profile icon', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_app(logoThumb: kTestLogoDataUrl, shopName: 'Patidar Mobile Shop'));
    await tester.pump(const Duration(milliseconds: 100));

    final logo = find.byType(ShopLogoAvatar);
    final name = find.text('Patidar Mobile Shop');
    // GlassIconButton tooltip nahi, semantics label deta hai (a11y ke liye wahi).
    final profile = find.bySemanticsLabel('Profile and settings');
    expect(logo, findsOneWidget);
    expect(name, findsOneWidget);
    expect(profile, findsOneWidget);

    final logoX = tester.getTopLeft(logo).dx;
    final nameX = tester.getTopLeft(name).dx;
    final profileX = tester.getTopLeft(profile).dx;
    // Eski taraf se: logo → naam → profile (left to right, ek hi row).
    expect(logoX, lessThan(nameX));
    expect(nameX, lessThan(profileX));
    expect(tester.getCenter(logo).dy, closeTo(tester.getCenter(name).dy, 6),
        reason: 'logo aur naam ek hi line me');
    expect(tester.getCenter(profile).dy, closeTo(tester.getCenter(name).dy, 10),
        reason: 'profile icon bhi usi row me');
    semantics.dispose();
  });

  testWidgets('logo na ho to naam ka pehla akshar hi avatar banta hai', (tester) async {
    Api.user = null;
    await tester.pumpWidget(_app(shopName: 'Patidar Mobile Shop'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(ShopLogoAvatar), findsOneWidget);
    expect(find.text('P'), findsOneWidget);
  });

  testWidgets('login response ka logo_thumb khud se use hota hai', (tester) async {
    Api.user = {
      'id': 7, 'name': 'Krishna Patel', 'username': 'krishna', 'role': 'shop_admin',
      'shop': {'id': 1, 'name': 'Krishna Mobiles', 'logo_thumb': kTestLogoDataUrl},
    };
    await tester.pumpWidget(_app(shopName: 'Krishna Mobiles'));
    await tester.pump(const Duration(milliseconds: 100));

    final avatar = tester.widget<ShopLogoAvatar>(find.byType(ShopLogoAvatar));
    expect(avatar.size, 32);
    expect(decodeLogoThumb(avatar.thumb), isNotEmpty);
  });

  testWidgets('super admin ka support view back button dikhata hai, logo nahi', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(AppTheme.lightScheme),
      home: Scaffold(body: Dashboard(
          onGo: (_) {}, shopName: 'Krishna Mobiles', isAdminView: true,
          testSummary: _summary(), testRecent: const [], logoThumb: kTestLogoDataUrl)),
    ));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(ShopLogoAvatar), findsNothing);
    expect(find.bySemanticsLabel('Profile and settings'), findsNothing);
    semantics.dispose();
  });
}
