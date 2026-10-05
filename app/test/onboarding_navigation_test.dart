import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_shop/api.dart';
import 'package:mobile_shop/design/design.dart';
import 'package:mobile_shop/screens/onboarding.dart';
import 'package:mobile_shop/screens/splash.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Api.token = null;
    Api.user = null;
    Api.viewShopId = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Widget app() => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.build(AppTheme.lightScheme),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: const SplashScreen(),
      );

  Future<void> launch(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    tester.view.padding = const FakeViewPadding(top: 63, bottom: 63);
    tester.view.viewPadding = const FakeViewPadding(top: 63, bottom: 63);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.byType(OnboardingScreen), findsOneWidget);
  }

  testWidgets('Skip routes from onboarding to login', (tester) async {
    await launch(tester);

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.byType(OnboardingScreen), findsNothing);
    expect(await Api.onboardingSeen(), isTrue);
  });

  testWidgets('Get started routes from the final slide to login', (tester) async {
    await launch(tester);

    for (var i = 0; i < 2; i++) {
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
    }
    expect(find.text('Get started'), findsOneWidget);

    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.byType(OnboardingScreen), findsNothing);
    expect(await Api.onboardingSeen(), isTrue);
  });
}
