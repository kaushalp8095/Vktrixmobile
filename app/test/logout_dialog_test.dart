// Logout popup: shop side aur Super Admin side — dono ek hi reusable dialog
// (Indigo/Mint ConfirmDialogCard) use karte hain, aur logout sirf confirm ke baad
// hota hai. "Stay logged in" dabane par screen wahi rehni chahiye.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_shop/api.dart';
import 'package:mobile_shop/design/components/components.dart';
import 'package:mobile_shop/design/design.dart';
import 'package:mobile_shop/screens/admin_home.dart';
import 'package:mobile_shop/screens/buy_form.dart';
import 'package:mobile_shop/screens/common.dart';
import 'package:mobile_shop/screens/login.dart';
import 'package:mobile_shop/screens/profile.dart';
import 'package:mobile_shop/screens/shop_home.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _dash = {'shops': 1, 'active_shops': 1, 'inactive_shops': 0, 'support_active': 0};
final _shops = [
  {'id': 1, 'name': 'Krishna Mobiles', 'login': {'username': 'krishna'}, 'active': 1,
   'phone_masked': '98•••••210', 'has_phone': true, 'created_at': '2025-04-12', 'support': null, 'support_sessions': 0},
];

void _viewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 2.625;
  tester.view.padding = const FakeViewPadding(top: 63, bottom: 63);
  tester.view.viewPadding = const FakeViewPadding(top: 63, bottom: 63);
}

Widget _app(Widget home) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(AppTheme.lightScheme),
      home: home,
    );

Future<void> _openLogoutDialog(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.logout).first);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));   // enter transition
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Api.token = 'test-token';
    Api.user = {'id': 7, 'name': 'Krishna Patel', 'username': 'krishna', 'role': 'shop_admin',
      'shop': {'id': 1, 'name': 'Krishna Mobiles'}};
    Api.endSupport();
  });

  tearDown(() {
    Api.token = null;
    Api.user = null;
    Api.endSupport();
  });

  testWidgets('shop side: profile logout asks first, and "Stay logged in" keeps the session', (tester) async {
    _viewport(tester);
    await tester.pumpWidget(_app(const ProfileScreen()));
    await tester.pump(const Duration(milliseconds: 100));

    await _openLogoutDialog(tester);
    expect(find.byType(ConfirmDialogCard), findsOneWidget);
    expect(find.text('Log out?'), findsOneWidget);
    expect(find.text('Stay logged in'), findsOneWidget);
    // Confirm button popup ke andar (Profile row par bhi 'Log out' likha hai).
    expect(find.descendant(of: find.byType(ConfirmDialogCard), matching: find.text('Log out')), findsOneWidget);
    // Identity: kaun logout kar raha hai wo popup me dikhta hai.
    expect(find.textContaining('Krishna Mobiles'), findsWidgets);

    await tester.tap(find.text('Stay logged in'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ConfirmDialogCard), findsNothing);
    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
    expect(Api.token, 'test-token', reason: 'session must survive a cancelled logout');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('super admin: logout is never immediate — the same popup appears', (tester) async {
    _viewport(tester);
    Api.user = {'id': 1, 'name': 'Super Admin', 'username': 'superadmin', 'role': 'superadmin'};
    await tester.pumpWidget(_app(AdminHome(testDash: _dash, testShops: _shops)));
    await tester.pump(const Duration(milliseconds: 100));

    // Screen par shop ka business data nahi: sirf name/status/masked contact.
    expect(find.text('Super Admin'), findsOneWidget);
    expect(find.textContaining('@krishna'), findsOneWidget);
    expect(find.textContaining('98•••••210'), findsOneWidget);
    expect(find.textContaining('in stock'), findsNothing);
    expect(find.textContaining('Sales value'), findsNothing);

    await _openLogoutDialog(tester);
    expect(find.byType(ConfirmDialogCard), findsOneWidget);
    expect(find.text('Stay logged in'), findsOneWidget);
    expect(find.descendant(of: find.byType(ConfirmDialogCard), matching: find.text('Log out')), findsOneWidget);
    expect(find.textContaining('@superadmin'), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing, reason: 'logout must wait for confirmation');
    expect(Api.token, 'test-token');

    await tester.tap(find.text('Stay logged in'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ConfirmDialogCard), findsNothing);
    expect(find.byType(AdminHome), findsOneWidget);
    expect(Api.token, 'test-token');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('support mode: shop shell shows the countdown bar and blocks Buy', (tester) async {
    _viewport(tester);
    Api.user = {'id': 1, 'name': 'Super Admin', 'username': 'superadmin', 'role': 'superadmin'};
    Api.beginSupport(shopId: 1, reason: 'Shop owner called: ledger stuck', expiresInMs: 15 * 60 * 1000);
    await tester.pumpWidget(_app(const ShopHome(adminShopName: 'Krishna Mobiles')));
    await tester.pump(const Duration(milliseconds: 100));

    expect(Api.supportReadOnly, isTrue);
    expect(find.text('Support mode · read-only'), findsOneWidget);
    expect(find.textContaining('remaining · visible to the shop owner'), findsOneWidget);

    await tester.tap(find.text('Buy').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));   // page transition
    // Buy tab support mode me write form ki jagah read-only note dikhata hai.
    expect(find.text('Buy is unavailable in support mode'), findsOneWidget);
    expect(find.textContaining('Support access is read-only'), findsOneWidget);
    expect(find.byType(BuyForm), findsNothing, reason: 'support mode must never show the write form');

    Api.endSupport();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('read-only guard: write actions are refused while support mode is on', (tester) async {
    bool? blocked;
    Widget harness() => _app(Scaffold(body: Builder(builder: (ctx) => Center(child: TextButton(
      onPressed: () => blocked = supportReadOnlyBlock(ctx, 'Selling a phone'),
      child: const Text('sell'))))));

    await tester.pumpWidget(harness());
    await tester.tap(find.text('sell'));
    await tester.pump();
    expect(blocked, isFalse, reason: 'shop owner ka apna session block nahi hota');

    Api.user = {'id': 1, 'name': 'Super Admin', 'username': 'superadmin', 'role': 'superadmin'};
    Api.beginSupport(shopId: 1, reason: 'Shop owner called: ledger stuck', expiresInMs: 60 * 1000);
    await tester.pumpWidget(harness());
    await tester.tap(find.text('sell'));
    await tester.pump();
    expect(blocked, isTrue);
    expect(find.textContaining('Support mode is read-only.'), findsOneWidget);
    Api.endSupport();
  });
}
