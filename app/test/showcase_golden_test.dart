import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_shop/design/design.dart';
import 'package:mobile_shop/design/showcase.dart';

Future<void> loadFonts() async {
  final l = FontLoader('Manrope');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    l.addFont(Future.value(ByteData.sublistView(File('assets/fonts/Manrope-$w.ttf').readAsBytesSync())));
  }
  await l.load();
  final m = FontLoader('MaterialIcons');
  final icons = File('${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (icons.existsSync()) { m.addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync()))); await m.load(); }
}

void main() {
  testWidgets('showcase', (t) async {
    await loadFonts();
    t.view.physicalSize = const Size(1080, 7600);
    t.view.devicePixelRatio = 2.625;
    await t.pumpWidget(MaterialApp(debugShowCheckedModeBanner: false,
        theme: AppTheme.build(AppTheme.lightScheme), home: const DesignSystemShowcase()));
    await t.pumpAndSettle();
    await expectLater(find.byType(DesignSystemShowcase), matchesGoldenFile('goldens/showcase.png'));
  });
}
