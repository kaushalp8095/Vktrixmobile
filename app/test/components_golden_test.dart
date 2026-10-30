import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_shop/design/components_gallery.dart';
import 'package:mobile_shop/design/design.dart';
import 'showcase_golden_test.dart' show loadFonts;

void main() {
  for (final dark in [false, true]) {
    testWidgets('components ${dark ? 'dark' : 'light'}', (t) async {
      await loadFonts();
      t.view.physicalSize = const Size(1080, 5600);
      t.view.devicePixelRatio = 2.625;
      await t.pumpWidget(MaterialApp(debugShowCheckedModeBanner: false,
          theme: AppTheme.build(dark ? AppTheme.darkScheme : AppTheme.lightScheme), home: const ComponentsGallery()));
      await t.pump(const Duration(milliseconds: 500));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200))); // grain image decode
      await t.pump(const Duration(milliseconds: 300));
      await expectLater(find.byType(ComponentsGallery), matchesGoldenFile('goldens/components_${dark ? 'dark' : 'light'}.png'));
      await t.pumpWidget(const SizedBox());
    });
  }
}
