import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_shop/design/design.dart';
import 'package:mobile_shop/screens/login.dart';
import 'package:mobile_shop/screens/splash.dart';
import 'showcase_golden_test.dart' show loadFonts;

void main() {
  final screens = <String, Widget Function()>{
    'splash': () => const SplashScreen(autoRoute: false),
    'login': () => const LoginScreen(),
  };
  for (final e in screens.entries) {
    for (final dark in [false, true]) {
      testWidgets('${e.key} ${dark ? 'dark' : 'light'}', (t) async {
        await loadFonts();
        t.view.physicalSize = const Size(1080, 2340);
        t.view.devicePixelRatio = 2.625;
        t.view.padding = const FakeViewPadding(top: 63, bottom: 63);
        t.view.viewPadding = const FakeViewPadding(top: 63, bottom: 63);
        await t.pumpWidget(MaterialApp(debugShowCheckedModeBanner: false,
            theme: AppTheme.build(dark ? AppTheme.darkScheme : AppTheme.lightScheme), home: e.value()));
        await t.pump(const Duration(milliseconds: 100));
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
        for (var i = 0; i < 20; i++) { await t.pump(const Duration(milliseconds: 50)); }
        await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/${e.key}_${dark ? 'dark' : 'light'}.png'));
        await t.pumpWidget(const SizedBox());
      });
    }
  }
}
