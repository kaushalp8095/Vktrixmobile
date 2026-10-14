import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_shop/design/components/components.dart';
import 'package:mobile_shop/design/design.dart';
import 'package:mobile_shop/screens/buy_form.dart';
import 'package:mobile_shop/screens/tac_catalog.dart';
import 'showcase_golden_test.dart' show loadFonts;

final _success = {
  'id': 3, 'source': 'osmocom', 'status': 'success', 'started_at': '2026-10-08T05:00:00.000Z', 'finished_at': '2026-10-08T05:01:10.000Z',
  'rows_seen': 12400, 'inserted': 11900, 'updated': 12, 'unchanged': 88, 'protected': 400, 'invalid': 31,
};

Map<String, dynamic> _status({Map<String, dynamic>? lastRun, Map<String, dynamic>? running, Map<String, dynamic>? lastSuccess}) => {
      'total': 12450,
      'counts': {'osmocom': 12000, 'tacdb': 9000, 'learned': 420, 'csv': 27, 'legacy': 2, 'seed': 1},
      'catalogs': [
        {
          'source': 'osmocom', 'label': 'Community catalog (Osmocom)', 'short': 'Osmocom',
          'note': 'Free community list of ~30k TACs. Brand + model only.',
          'license': 'CC-BY-SA 3.0 Unported', 'homepage': 'http://tacdb.osmocom.org/',
          'count': 12000, 'enabled': true, 'last_run': lastRun, 'last_success': lastSuccess,
        },
        {
          'source': 'tacdb', 'label': 'Extended catalog (India models)', 'short': 'Extended',
          'note': 'Free third-party list of ~250k TACs with India variants and internal model codes.',
          'license': 'MIT', 'homepage': 'https://github.com/MoazEb/tac-database',
          'count': 9000, 'enabled': true, 'last_run': null, 'last_success': null,
        },
      ],
      'local': [
        {'source': 'learned', 'label': 'Learned from shop purchases', 'count': 420},
        {'source': 'csv', 'label': 'Admin CSV import', 'count': 27},
        {'source': 'api', 'label': 'External TAC API (optional)', 'count': 0, 'enabled': false},
        {'source': 'older', 'label': 'Older / sample entries', 'count': 3},
      ],
      'licenses': [
        {'name': 'Community catalog (Osmocom)', 'homepage': 'http://tacdb.osmocom.org/',
          'attribution': 'TAC data: Osmocom TAC database (c) Harald Welte and contributors, CC-BY-SA 3.0'},
        {'name': 'Extended catalog (India models)', 'homepage': 'https://github.com/MoazEb/tac-database',
          'attribution': 'TAC data: MoazEb/tac-database (MIT), community maintained from public databases'},
      ],
      'running': running,
      'last_run': running ?? lastRun,
      'last_success': lastSuccess,
      'catalog': {
        'attribution': 'TAC data: Osmocom TAC database (c) Harald Welte and contributors, CC-BY-SA 3.0',
        'homepage': 'http://tacdb.osmocom.org/',
      },
      'limitations': [
        'Free catalogs are incomplete: many recent and India-only models are still missing.',
        'Only brand and model are provided. RAM, storage and colour must still be entered by the shop.',
      ],
    };

Widget _app(Widget home) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(AppTheme.lightScheme),
      builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!),
      home: home,
    );

Future<void> _pump(WidgetTester t, Widget w) async {
  await loadFonts(); // same real fonts as the golden tests (default test font is much wider)
  t.view.physicalSize = const Size(1080, 2340);
  t.view.devicePixelRatio = 2.625;
  t.view.padding = const FakeViewPadding(top: 63, bottom: 63);
  t.view.viewPadding = const FakeViewPadding(top: 63, bottom: 63);
  addTearDown(t.view.reset);
  await t.pumpWidget(_app(w));
  for (var i = 0; i < 6; i++) { await t.pump(const Duration(milliseconds: 50)); }
}

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 8; i++) { await t.pump(const Duration(milliseconds: 50)); }
}

Finder _text(String s) => find.text(s, skipOffstage: false);
Finder _textContaining(String s) => find.textContaining(s, skipOffstage: false);
List<PrimaryButton> _buttons(WidgetTester t) =>
    t.widgetList<PrimaryButton>(find.byType(PrimaryButton, skipOffstage: false)).toList();

void main() {
  testWidgets('shows limitations, both free catalogs and the last successful sync', (t) async {
    await _pump(t, TacCatalogScreen(testStatus: _status(lastRun: _success, lastSuccess: _success)));
    expect(_text('Community data — verify before buying'), findsOneWidget);
    expect(_textContaining('incomplete'), findsOneWidget);
    expect(_textContaining('RAM, storage'), findsOneWidget);
    expect(_text('12450'), findsOneWidget);
    expect(_text('TACs known to the server'), findsOneWidget);
    expect(_text('Community catalog (Osmocom)'), findsOneWidget);
    expect(_text('Extended catalog (India models)'), findsOneWidget);
    expect(_text('12000 TACs'), findsOneWidget);
    expect(_text('9000 TACs'), findsOneWidget);
    expect(_textContaining('India variants'), findsOneWidget, reason: 'the note explains what this catalog adds');
    // "Your own data" card: what a sync must never touch.
    expect(_text('Your own data'), findsOneWidget);
    expect(_text('Learned from shop purchases'), findsOneWidget);
    expect(_text('420'), findsOneWidget);
    expect(_text('Admin CSV import'), findsOneWidget);
    expect(_text('Older / sample entries'), findsOneWidget);
    expect(_text('3'), findsOneWidget, reason: 'legacy + seed are shown together');
    expect(_text('Never synced'), findsOneWidget, reason: 'only the extended catalog has no run yet');
    expect(_text('Success'), findsOneWidget);
    expect(_textContaining('11900 new · 12 updated'), findsOneWidget);
    expect(_textContaining('Osmocom TAC database'), findsOneWidget, reason: 'attribution for the community data');
    expect(_textContaining('MoazEb/tac-database'), findsOneWidget, reason: 'attribution for the extended data');
    expect(_buttons(t).length, 2, reason: 'one sync action per free catalog');
    expect(_buttons(t).every((b) => b.onPressed != null), isTrue);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('each catalog has its own sync action', (t) async {
    await _pump(t, TacCatalogScreen(testStatus: _status(lastRun: _success, lastSuccess: _success)));
    final extendedSync = find.byType(PrimaryButton, skipOffstage: false).at(1); // extended catalog row
    await t.ensureVisible(extendedSync);
    await t.tap(extendedSync);
    await _settle(t);
    expect(_text('Sync Extended catalog (India models)?'), findsOneWidget);
    expect(_textContaining('never overwritten'), findsOneWidget);
    expect(_textContaining('India variants'), findsWidgets);
    await t.tap(_text('Cancel'));
    await _settle(t);
    expect(_text('Sync Extended catalog (India models)?'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('failed sync explains that nothing changed and shows last good sync', (t) async {
    final failed = {'id': 4, 'source': 'tacdb', 'status': 'failed', 'started_at': '2026-10-08T06:00:00.000Z',
      'finished_at': '2026-10-08T06:00:05.000Z', 'error': 'Upstream returned HTTP 503'};
    await _pump(t, TacCatalogScreen(testStatus: _status(lastRun: failed, lastSuccess: _success)));
    expect(_text('Failed'), findsOneWidget);
    expect(_text('Upstream returned HTTP 503'), findsOneWidget);
    expect(_textContaining('Nothing was changed'), findsOneWidget);
    expect(_textContaining('Last successful sync'), findsOneWidget);
    expect(_text('Extended'), findsOneWidget, reason: 'the failed run names its catalog');
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('a running sync disables every button; never-synced state is explicit', (t) async {
    final running = {'id': 5, 'source': 'tacdb', 'status': 'running', 'started_at': '2026-10-08T07:00:00.000Z'};
    await _pump(t, TacCatalogScreen(testStatus: _status(running: running)));
    expect(_text('Running'), findsOneWidget);
    expect(_textContaining('Downloading and merging'), findsWidgets);
    expect(_buttons(t).every((b) => b.onPressed == null), isTrue, reason: 'only one sync runs at a time');
    await t.pumpWidget(const SizedBox());

    await _pump(t, TacCatalogScreen(testStatus: _status()));
    expect(_text('Never synced'), findsNWidgets(3), reason: 'both catalog rows plus the last-sync card');
    expect(_textContaining('Tap Sync'), findsOneWidget);
    expect(_buttons(t).every((b) => b.onPressed != null), isTrue);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('an older server (no catalogs field) still shows both sync actions', (t) async {
    final legacy = Map<String, dynamic>.from(_status(lastRun: _success, lastSuccess: _success))
      ..remove('catalogs')..remove('local')..remove('licenses');
    await _pump(t, TacCatalogScreen(testStatus: legacy));
    expect(_text('Community catalog (Osmocom)'), findsOneWidget);
    expect(_text('Extended catalog (India models)'), findsOneWidget);
    expect(_text('Learned from shop purchases'), findsOneWidget);
    expect(_text('12000 TACs'), findsOneWidget, reason: 'counts fall back to the counts map');
    expect(_buttons(t).length, 2);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('buy form flags every community catalog match for verification', (t) async {
    for (final source in ['osmocom', 'tacdb', 'api']) {
      await _pump(t, Scaffold(body: AuroraBackground(child: BuyForm(onSaved: () {}, testLookup: (imei) async => {
        'valid': true, 'found': true, 'history': const [],
        'info': {'brand': 'Xiaomi', 'model': 'Redmi 9A', 'ram': null, 'storage': null, 'source': source},
      }))));
      await t.enterText(find.byType(TextField).first, '867513060000001');
      await _settle(t);
      expect(_textContaining('community data, verify model & fill RAM/storage'), findsOneWidget, reason: source);
      expect(_textContaining('details auto-filled'), findsNothing, reason: source);
      await t.pumpWidget(const SizedBox());
    }
  });

  testWidgets("catalog miss: the shop's own earlier entry for that IMEI fills the form", (t) async {
    String value(String label) => t.widget<GlassTextField>(
        find.byWidgetPredicate((w) => w is GlassTextField && w.label == label)).controller.text;

    await _pump(t, Scaffold(body: AuroraBackground(child: BuyForm(onSaved: () {}, testLookup: (imei) async => {
      'valid': true, 'found': false, 'info': null, 'already_in_stock': false,
      'history': const [
        {'brand': 'Samsung', 'model': 'Galaxy S21', 'ram': '8GB', 'storage': '128GB',
          'color': 'Phantom Grey', 'notes': 'bill missing'},
      ],
    }))));
    await t.enterText(find.byType(TextField).first, '867513060000001');
    await _settle(t);
    expect(_textContaining('Samsung Galaxy S21 · filled from your earlier entry'), findsOneWidget);
    expect(_textContaining('bought 1× before'), findsOneWidget);
    expect(_textContaining('New model'), findsNothing);
    expect(value('Brand'), 'Samsung');
    expect(value('Model'), 'Galaxy S21');
    expect(value('RAM (e.g. 8GB)'), '8GB');
    expect(value('Storage (e.g. 128GB)'), '128GB');
    expect(value('Color'), 'Phantom Grey');
    expect(value('IMEI 2 (optional)'), '', reason: 'history fills device fields only');
    await t.pumpWidget(const SizedBox());
  });
}
