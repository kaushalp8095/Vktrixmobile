// Super Admin ke shop Add/Edit dialog ka "Bill logo" row.
//
// Bug tha: edit karte waqt hamesha generic store icon + "Add" dikhta tha, chahe
// shop ka logo upload ho chuka ho — admin ko pata hi nahi chalta tha ki kaunsa
// logo laga hua hai. Ab preview me asli logo aata hai aur status text batata hai
// ki logo uploaded hai, naya chuna gaya hai, ya hataya ja raha hai.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_shop/design/design.dart';
import 'package:mobile_shop/screens/bill_logo_field.dart';

import 'fixtures/logo.dart';

final Uint8List _logoBytes = base64Decode(kTestLogoJpegBase64);

Widget _app(BillLogoField field) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(AppTheme.lightScheme),
      home: Scaffold(body: Center(child: SizedBox(width: 360, child: field))),
    );

BillLogoField _field({
  Uint8List? bytes,
  bool loading = false,
  bool uploaded = false,
  bool changed = false,
  VoidCallback? onPick,
  VoidCallback? onRemove,
}) =>
    BillLogoField(
      bytes: bytes,
      loading: loading,
      uploaded: uploaded,
      changed: changed,
      onPick: onPick ?? () {},
      onRemove: onRemove ?? () {},
    );

void main() {
  testWidgets('logo na ho to placeholder + "Add" dikhta hai', (tester) async {
    await tester.pumpWidget(_app(_field()));

    expect(find.text('Bill logo'), findsOneWidget);
    expect(find.text('No logo uploaded yet'), findsOneWidget);
    expect(find.text('Add'), findsOneWidget);
    expect(find.byIcon(Icons.storefront_outlined), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(find.byTooltip('Remove logo'), findsNothing);
  });

  testWidgets('uploaded logo aate waqt spinner, phir asli logo dikhta hai', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_app(_field(loading: true, uploaded: true)));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Loading the uploaded logo…'), findsOneWidget);
    expect(find.text('Add'), findsNothing, reason: 'logo hai to "Change" hi sahi hai');

    // Fetch khatam: server se aaya logo preview me.
    await tester.pumpWidget(_app(_field(bytes: _logoBytes, uploaded: true)));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('Uploaded · prints on PDF bills'), findsOneWidget);
    expect(find.text('Change'), findsOneWidget);
    expect(find.byTooltip('Remove logo'), findsOneWidget);
    expect(find.bySemanticsLabel('Uploaded bill logo'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('preview load fail ho jaye to bhi pata rahe ki logo uploaded hai', (tester) async {
    final f = _field(uploaded: true);
    await tester.pumpWidget(_app(f));

    expect(find.text('Logo uploaded · preview unavailable'), findsOneWidget);
    expect(find.text('Change'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('naya logo chunne par "Save" ki yaad dilati hai', (tester) async {
    await tester.pumpWidget(_app(_field(bytes: _logoBytes, uploaded: true, changed: true)));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('New logo · tap Save to apply'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('Change'), findsOneWidget);
  });

  testWidgets('remove karne ke baad "Add" wapas aata hai aur X chhup jata hai', (tester) async {
    await tester.pumpWidget(_app(_field(uploaded: true, changed: true)));

    expect(find.text('Removed · tap Save to apply'), findsOneWidget);
    expect(find.text('Add'), findsOneWidget);
    expect(find.byTooltip('Remove logo'), findsNothing);
  });

  testWidgets('Add/Change aur Remove buttons callback chalate hain', (tester) async {
    var picked = 0, removed = 0;

    await tester.pumpWidget(_app(_field(onPick: () => picked++, onRemove: () => removed++)));
    await tester.tap(find.text('Add'));
    expect(picked, 1);
    expect(find.byTooltip('Remove logo'), findsNothing, reason: 'kuch hatane ko nahi hai');

    await tester.pumpWidget(_app(_field(
        bytes: _logoBytes, uploaded: true, onPick: () => picked++, onRemove: () => removed++)));
    await tester.tap(find.text('Change'));
    await tester.tap(find.byTooltip('Remove logo'));
    expect(picked, 2);
    expect(removed, 1);
  });
}
