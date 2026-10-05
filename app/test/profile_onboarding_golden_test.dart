import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_shop/design/design.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_shop/screens/onboarding.dart';
import 'package:mobile_shop/screens/profile.dart';
import 'showcase_golden_test.dart' show loadFonts;

void main() {
  setUpAll(() => SharedPreferences.setMockInitialValues({}));
  final cases = <String, Widget Function(bool)>{
    'onboarding': (dark) => MaterialApp(debugShowCheckedModeBanner: false,
        theme: AppTheme.build(dark ? AppTheme.darkScheme : AppTheme.lightScheme),
        home: OnboardingScreen(onDone: (_) {})),
    'profile': (dark) => MaterialApp(debugShowCheckedModeBanner: false,
        theme: AppTheme.build(dark ? AppTheme.darkScheme : AppTheme.lightScheme),
        home: const ProfileScreen()),
  };
  for (final e in cases.entries) {
    for (final dark in [false, true]) {
      testWidgets('${e.key} ${dark ? 'dark' : 'light'}', (t) async {
        await loadFonts();
        t.view.physicalSize = const Size(1080, 2340);
        t.view.devicePixelRatio = 2.625;
        t.view.padding = const FakeViewPadding(top: 63, bottom: 63);
        t.view.viewPadding = const FakeViewPadding(top: 63, bottom: 63);
        await t.pumpWidget(e.value(dark));
        await t.pump(const Duration(milliseconds: 100));
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
        for (var i = 0; i < 8; i++) { await t.pump(const Duration(milliseconds: 50)); }
        await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/${e.key}_${dark ? 'dark' : 'light'}.png'));
        await t.pumpWidget(const SizedBox());
      });
    }
  }
}
