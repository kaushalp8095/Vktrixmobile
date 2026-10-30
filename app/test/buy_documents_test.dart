import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:mobile_shop/design/components/components.dart';
import 'package:mobile_shop/design/design.dart';
import 'package:mobile_shop/screens/buy_form.dart';
import 'showcase_golden_test.dart' show loadFonts;
import 'support/golden_shadows.dart';

final _jpeg = img.encodeJpg(img.Image(width: 160, height: 100));

Future<void> _pump(WidgetTester t, BuyForm form, {bool dark = false, double textScale = 1}) async {
  await loadFonts();
  t.view.physicalSize = const Size(420, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.build(dark ? AppTheme.darkScheme : AppTheme.lightScheme),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: true, textScaler: TextScaler.linear(textScale)), child: child!),
    home: Scaffold(body: AuroraBackground(child: form)),
  ));
  await t.pumpAndSettle();
}

Finder _field(String label) => find.byWidgetPredicate((w) => w is GlassTextField && w.label == label);

Future<void> _scrollTo(WidgetTester t, Finder finder) async {
  await t.scrollUntilVisible(finder, 200, scrollable: find.byType(Scrollable).first);
  // The Buy form has an overlaid top bar; align targets below it, not at y=0.
  await Scrollable.ensureVisible(t.element(finder), alignment: .4);
  await t.pumpAndSettle();
}

Future<void> _fillRequired(WidgetTester t) async {
  for (final entry in {'IMEI 1': '353328111234561', 'Brand': 'Apple', 'Model': 'iPhone 13',
    'Buy price (₹)': '10000', 'Customer name': 'Test Customer'}.entries) {
    await _scrollTo(t, _field(entry.key));
    t.widget<GlassTextField>(_field(entry.key)).controller.text = entry.value;
  }
}

Future<void> _chooseSource(WidgetTester t, int side, {bool camera = false}) async {
  await _scrollTo(t, find.byKey(ValueKey('id-photo-$side')));
  await t.tap(find.byKey(ValueKey('id-photo-$side')));
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
  await t.tap(find.text(camera ? 'Take a photo' : 'Choose from gallery'));
  await t.pump(const Duration(milliseconds: 300));
}

void main() {
  setUpAll(useRealShadows);
  test('storage and colour suggestions include requested variants', () {
    expect(kDefaultStorageOptions, contains('2TB'));
    expect(kDefaultStorageOptions, contains('Others'));
    expect(kDefaultColorOptions, contains('Red / Burgundy'));
  });

  for (final dark in [false, true]) {
    for (final entry in {'RAM (e.g. 8GB)': '8GB', 'Storage (e.g. 128GB)': '256GB', 'Color': 'Blue'}.entries) {
      final title = entry.key.split(' ').first;
      testWidgets('$title themed options select, highlight and retain manual values (${dark ? 'dark' : 'light'})', (t) async {
        await _pump(t, BuyForm(onSaved: () {}), dark: dark);
        final tooltip = 'Choose ${entry.key}';
        await _scrollTo(t, find.byTooltip(tooltip));
        await t.tap(find.byTooltip(tooltip));
        await t.pumpAndSettle();
        expect(find.text('Choose $title'), findsOneWidget);
        await t.tap(find.text(entry.value));
        await t.pumpAndSettle();
        expect(t.widget<GlassTextField>(_field(entry.key)).controller.text, entry.value);
        await t.tap(find.byTooltip(tooltip));
        await t.pumpAndSettle();
        expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
        await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/buy_${title.toLowerCase()}_${dark ? 'dark' : 'light'}.png'));
        await t.tap(find.byTooltip('Close $title options'));
        await t.pumpAndSettle();
        t.widget<GlassTextField>(_field(entry.key)).controller.text = 'Custom variant';
        await t.tap(find.byTooltip(tooltip));
        await t.pumpAndSettle();
        expect(find.text('Custom variant'), findsWidgets);
        expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
        await t.pumpWidget(const SizedBox());
      });
    }

    testWidgets('document upload cards ${dark ? 'dark' : 'light'}', (t) async {
      await _pump(t, BuyForm(onSaved: () {}), dark: dark);
      await _scrollTo(t, find.byKey(const ValueKey('id-photo-1')));
      expect(find.text('Front photo'), findsOneWidget);
      expect(find.text('Back photo'), findsOneWidget);
      expect(find.text('0/2'), findsOneWidget);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/buy_documents_${dark ? 'dark' : 'light'}.png'));
    });
  }

  for (final sides in [[0], [1], [0, 1]]) {
    testWidgets('saves document sides $sides as separate JPEG data URLs', (t) async {
      Map<String, dynamic>? saved;
      final sources = <ImageSource>[];
      await _pump(t, BuyForm(onSaved: () {}, testSave: (body) async => saved = body,
        testPickPhoto: (source) async { sources.add(source); return _jpeg; },
        testPreparePhoto: (bytes) async => bytes));
      await _fillRequired(t);
      for (final side in sides) {
        await _chooseSource(t, side, camera: side == 1);
        await t.pumpAndSettle();
      }
      expect(find.text('${sides.length}/2'), findsOneWidget);
      expect(sources, sides.map((side) => side == 1 ? ImageSource.camera : ImageSource.gallery).toList());
      await _scrollTo(t, find.byType(PrimaryButton));
      await t.tap(find.byType(PrimaryButton));
      await t.pumpAndSettle();
      expect(saved, isNotNull);
      expect(saved!['customer_id_photo'], sides.contains(0) ? 'data:image/jpeg;base64,${base64Encode(_jpeg)}' : '');
      expect(saved!['customer_id_photo_back'], sides.contains(1) ? 'data:image/jpeg;base64,${base64Encode(_jpeg)}' : '');
    });
  }

  testWidgets('compression blocks save; cancel/failure preserve photo; preview and remove are independent', (t) async {
    var cancel = false, fail = false;
    Completer<Uint8List>? processing;
    await _pump(t, BuyForm(onSaved: () {},
      testPickPhoto: (_) async => cancel ? null : _jpeg,
      testPreparePhoto: (bytes) async {
        if (fail) throw const FormatException('invalid photo');
        return processing == null ? bytes : await processing.future;
      }));
    await _chooseSource(t, 0);
    await t.pumpAndSettle();
    expect(find.text('1/2'), findsOneWidget);
    await t.tap(find.text('Preview'));
    await t.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsOneWidget);
    await t.tap(find.byTooltip('Close preview'));
    await t.pumpAndSettle();
    cancel = true;
    await _chooseSource(t, 0);
    await t.pumpAndSettle();
    expect(find.text('1/2'), findsOneWidget);
    cancel = false;
    fail = true;
    await _chooseSource(t, 0);
    await t.pumpAndSettle();
    expect(find.text('1/2'), findsOneWidget);
    fail = false;
    processing = Completer<Uint8List>();
    await _chooseSource(t, 1);
    expect(find.text('Processing…'), findsOneWidget);
    // Bring the save button into view without waiting for the busy spinner.
    await t.scrollUntilVisible(find.byType(PrimaryButton), 150, scrollable: find.byType(Scrollable).first);
    expect(t.widget<PrimaryButton>(find.byType(PrimaryButton)).onPressed, isNull);
    processing.complete(_jpeg);
    await t.pumpAndSettle();
    await _scrollTo(t, find.byKey(const ValueKey('id-photo-0')));
    expect(find.text('2/2'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('id-photo-0')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    await t.tap(find.text('Remove photo'));
    await t.pumpAndSettle();
    expect(find.text('1/2'), findsOneWidget);
    expect(find.text('Preview'), findsOneWidget);
  });

  testWidgets('option sheet works with large text', (t) async {
    await _pump(t, BuyForm(onSaved: () {}), textScale: 2);
    await _scrollTo(t, find.byTooltip('Choose RAM (e.g. 8GB)'));
    await t.tap(find.byTooltip('Choose RAM (e.g. 8GB)'));
    await t.pumpAndSettle();
    expect(find.text('Choose RAM'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
