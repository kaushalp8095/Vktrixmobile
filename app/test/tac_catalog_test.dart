import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_shop/design/components/components.dart';
import 'package:mobile_shop/design/design.dart';
import 'package:mobile_shop/screens/buy_form.dart';
import 'package:mobile_shop/screens/tac_catalog.dart';

Map<String, dynamic> _status({Map<String, dynamic>? lastRun, Map<String, dynamic>? running, Map<String, dynamic>? lastSuccess}) => {
      'total': 12450,
      'counts': {'osmocom': 12000, 'learned': 420, 'csv': 27, 'legacy': 2, 'seed': 1},
      'running': running,
      'last_run': running ?? lastRun,
      'last_success': lastSuccess,
      'catalog': {
        'attribution': 'TAC data: Osmocom TAC database (c) Harald Welte and contributors, CC-BY-SA 3.0',
        'homepage': 'http://tacdb.osmocom.org/',
      },
      'limitations': [
        'Community catalog is incomplete: many recent and India-only models are missing.',
        'Only brand and model are provided. RAM, storage and colour must still be entered by the shop.',
      ],
    };

final _success = {
  'id': 3, 'status': 'success', 'started_at': '2026-10-08T05:00:00.000Z', 'finished_at': '2026-10-08T05:01:10.000Z',
  'rows_seen': 12400, 'inserted': 11900, 'updated': 12, 'unchanged': 88, 'protected': 400, 'invalid': 31,
};

Widget _app(Widget home) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(AppTheme.lightScheme),
      builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!),
      home: home,
    );

Future<void> _pump(WidgetTester t, Widget w) async {
  t.view.physicalSize = const Size(1080, 2340);
  t.view.devicePixelRatio = 2.625;
  t.view.padding = const FakeViewPadding(top: 63, bottom: 63);
  t.view.viewPadding = const FakeViewPadding(top: 63, bottom: 63);
  addTearDown(t.view.reset);
  await t.pumpWidget(_app(w));
  for (var i = 0; i < 6; i++) { await t.pump(const Duration(milliseconds: 50)); }
}

Finder _text(String s) => find.text(s, skipOffstage: false);
Finder _textContaining(String s) => find.textContaining(s, skipOffstage: false);

void main() {
  testWidgets('shows limitations, coverage by source and last successful sync', (t) async {
    await _pump(t, TacCatalogScreen(testStatus: _status(lastRun: _success, lastSuccess: _success)));
    expect(_text('Community data — verify before buying'), findsOneWidget);
    expect(_textContaining('incomplete'), findsOneWidget);
    expect(_textContaining('RAM, storage'), findsOneWidget);
    expect(_text('12450'), findsOneWidget);
    expect(_text('Community catalog (Osmocom)'), findsOneWidget);
    expect(_text('420'), findsOneWidget);
    expect(_text('3'), findsOneWidget, reason: 'legacy + seed are shown together');
    expect(_text('Success'), findsOneWidget);
    expect(_textContaining('11900 new · 12 updated'), findsOneWidget);
    final button = t.widget<PrimaryButton>(find.byType(PrimaryButton, skipOffstage: false));
    expect(button.onPressed, isNotNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('failed sync explains that nothing changed and shows last good sync', (t) async {
    final failed = {'id': 4, 'status': 'failed', 'started_at': '2026-10-08T06:00:00.000Z',
      'finished_at': '2026-10-08T06:00:05.000Z', 'error': 'Upstream returned HTTP 503'};
    await _pump(t, TacCatalogScreen(testStatus: _status(lastRun: failed, lastSuccess: _success)));
    expect(_text('Failed'), findsOneWidget);
    expect(_text('Upstream returned HTTP 503'), findsOneWidget);
    expect(_textContaining('Nothing was changed'), findsOneWidget);
    expect(_textContaining('Last successful sync'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('running sync disables the button; never-synced state is explicit', (t) async {
    final running = {'id': 5, 'status': 'running', 'started_at': '2026-10-08T07:00:00.000Z'};
    await _pump(t, TacCatalogScreen(testStatus: _status(running: running)));
    expect(_text('Running'), findsOneWidget);
    expect(t.widget<PrimaryButton>(find.byType(PrimaryButton, skipOffstage: false)).onPressed, isNull);
    await t.pumpWidget(const SizedBox());

    await _pump(t, TacCatalogScreen(testStatus: _status()));
    expect(_text('Never synced'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('buy form flags community catalog matches for verification', (t) async {
    await _pump(t, Scaffold(body: BuyForm(onSaved: () {}, testLookup: (imei) async => {
      'valid': true, 'found': true, 'history': const [],
      'info': {'brand': 'Xiaomi', 'model': 'Redmi 9A', 'ram': null, 'storage': null, 'source': 'osmocom'},
    })));
    await t.enterText(find.byType(TextField).first, '867513060000001');
    for (var i = 0; i < 6; i++) { await t.pump(const Duration(milliseconds: 50)); }
    expect(_textContaining('community data, verify model & fill RAM/storage'), findsOneWidget);
    expect(_textContaining('details auto-filled'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });
}
