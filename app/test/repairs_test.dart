// Repair module: list, detail, form aur customer-safe PDF.
//
// Yahan teen cheezein pakki hoti hain:
//   1. Customer ka device stock me nahi dikhta — workshop alag list hai.
//   2. Job sheet / delivery receipt ka payload internal cheezein (parts cost,
//      diagnosis, lock note) kabhi nahi uthata.
//   3. 200% text scale par bhi koi overflow nahi (yellow-black band = test fail).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_shop/billing/repair_document.dart';
import 'package:mobile_shop/design/components/components.dart';
import 'package:mobile_shop/design/design.dart';
import 'package:mobile_shop/screens/repair_detail.dart';
import 'package:mobile_shop/screens/repair_form.dart';
import 'package:mobile_shop/screens/repairs.dart';
import 'showcase_golden_test.dart' show loadFonts;

final _jobs = [
  {
    'id': 1, 'job_no': 'RPR-001-000001', 'customer_name': 'Ramesh Patel', 'customer_phone': '9876543210',
    'brand': 'Samsung', 'model': 'Galaxy M31', 'imei': '353328111234561', 'status': 'ready',
    'service_charge': 2800, 'paid_amount': 1300, 'balance_due': 1500, 'payment_status': 'partial',
    'promised_date': '2026-10-07', 'received_at': '2026-10-05',
  },
  {
    'id': 2, 'job_no': 'RPR-001-000002', 'customer_name': 'Nita Shah', 'brand': 'Apple', 'model': 'iPhone 12',
    'status': 'delivered', 'service_charge': 1500, 'paid_amount': 1500, 'balance_due': 0,
    'payment_status': 'paid', 'promised_date': null, 'received_at': '2026-10-01',
  },
];

const _summary = {'open_count': 3, 'ready_count': 1, 'outstanding': 1500};

Map<String, dynamic> _job() => {
  'id': 1, 'job_no': 'RPR-001-000001', 'customer_name': 'Ramesh Patel', 'customer_phone': '9876543210',
  'customer_address': 'Station Road', 'brand': 'Samsung', 'model': 'Galaxy M31',
  'imei': '353328111234561', 'color': 'Blue', 'complaint': 'Screen broken, touch not working',
  'status': 'ready', 'estimate': 2500, 'service_charge': 2800, 'parts_cost': 1200,
  'parts_note': 'Vendor display', 'diagnosis': 'Display assembly faulty', 'device_lock_note': 'PIN 1234',
  'paid_amount': 1300, 'balance_due': 1500, 'payment_status': 'partial',
  'received_at': '2026-10-05', 'promised_date': '2026-10-07', 'warranty_days': 30, 'phone': null,
  'payments': [
    {'id': 2, 'amount': 800, 'payment_date': '2026-10-06', 'payment_mode': 'upi', 'kind': 'payment'},
    {'id': 1, 'amount': 500, 'payment_date': '2026-10-05', 'payment_mode': 'cash', 'kind': 'advance'},
  ],
};

/// Server ka `GET /repairs/:id/job-sheet` payload — sirf customer-safe fields.
Map<String, dynamic> _sheet(String type) => {
  'type': type, 'number': 'RPR-001-000001', 'date': '2026-10-08',
  'shop': {'name': 'Krishna Mobiles', 'owner_name': 'Kaushal', 'phone': '9876543210', 'address': 'Mahesana'},
  'customer': {'name': 'Ramesh Patel', 'phone': '9876543210', 'address': 'Station Road'},
  'device': {'brand': 'Samsung', 'model': 'Galaxy M31', 'imei': '353328111234561', 'color': 'Blue'},
  'complaint': 'Screen broken, touch not working',
  'received_at': '2026-10-05', 'promised_date': '2026-10-07',
  'delivered_at': type == 'delivery' ? '2026-10-08' : null,
  'warranty_days': 30, 'estimate': 2500, 'amount': 2800,
  'paid_amount': 1300, 'balance_due': 1500, 'payment_status': 'partial',
  'payments': [],
};

Future<void> _pump(WidgetTester t, Widget home, {Size size = const Size(420, 900), double scale = 1}) async {
  await loadFonts();
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  t.view.padding = const FakeViewPadding(top: 24, bottom: 16);
  t.view.viewPadding = const FakeViewPadding(top: 24, bottom: 16);
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.build(AppTheme.lightScheme),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: true, textScaler: TextScaler.linear(scale)),
      child: child!),
    home: home,
  ));
  await t.pump(const Duration(milliseconds: 200));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('customer documents', () {
    test('job sheet and delivery receipt are real PDFs', () async {
      for (final type in ['job_sheet', 'delivery']) {
        final bytes = await RepairDocument.build(_sheet(type));
        expect(bytes.length, greaterThan(5000));
        expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
        expect(ascii.decode(bytes.sublist(bytes.length - 16), allowInvalid: true), contains('%%EOF'));
      }
    });

    test('the document payload never carries internal cost or diagnosis', () {
      // Contract: backend yahi keys bhejta hai, aur layout inhe padhta hi nahi.
      for (final type in ['job_sheet', 'delivery']) {
        final sheet = _sheet(type);
        expect(sheet.keys, isNot(contains('parts_cost')));
        expect(sheet.keys, isNot(contains('parts_note')));
        expect(sheet.keys, isNot(contains('diagnosis')));
        expect(sheet.keys, isNot(contains('device_lock_note')));
        expect(sheet.keys, isNot(contains('notes')));
      }
    });
  });

  group('repair list', () {
    testWidgets('shows the workshop summary and every open job', (t) async {
      await _pump(t, RepairsScreen(testItems: _jobs, testSummary: _summary));

      expect(find.text('Workshop'), findsOneWidget);
      expect(find.text('3 open'), findsOneWidget);
      expect(find.text('Ready to deliver'), findsOneWidget);
      expect(find.text('Repair dues'), findsOneWidget);
      expect(find.text('₹1,500'), findsOneWidget);
      expect(find.text('Ramesh Patel'), findsOneWidget);
      expect(find.text('RPR-001-000001 · Samsung Galaxy M31'), findsOneWidget);
      expect(find.text('READY'), findsOneWidget);
      expect(find.text('DELIVERED'), findsOneWidget);
      expect(find.text('₹1,500 due'), findsOneWidget);
      expect(find.text('Open'), findsOneWidget);
      expect(find.text('Delivered'), findsWidgets);
      expect(find.text('New repair job'), findsOneWidget);
    });

    testWidgets('empty workshop explains what to do next', (t) async {
      await _pump(t, const RepairsScreen(testItems: [], testSummary: {'open_count': 0, 'ready_count': 0}));
      expect(find.text('No open repair jobs'), findsOneWidget);
      expect(find.textContaining('Add a job when a customer leaves a phone'), findsOneWidget);
    });

    testWidgets('200% text scale does not overflow the list', (t) async {
      await _pump(t, RepairsScreen(testItems: _jobs, testSummary: _summary),
        size: const Size(1080, 2340), scale: 2);
      expect(t.takeException(), isNull);
    });
  });

  group('repair detail', () {
    testWidgets('shows money, status actions and internal costing separately', (t) async {
      await _pump(t, RepairDetailScreen(id: 1, testJob: _job()), size: const Size(420, 2200));

      expect(find.text('Ramesh Patel'), findsOneWidget);
      expect(find.text('READY'), findsOneWidget);
      expect(find.text('₹2,800'), findsOneWidget);           // service charge
      expect(find.text('₹1,300'), findsOneWidget);           // received
      expect(find.text('₹1,500'), findsOneWidget);           // balance stat
      expect(find.text('₹1,500 DUE'), findsOneWidget);       // chip
      expect(find.text('Internal — never printed'), findsOneWidget);
      expect(find.text('₹1,200'), findsOneWidget);           // parts cost
      expect(find.text('₹1,600'), findsOneWidget);           // margin
      expect(find.textContaining('Display assembly faulty'), findsOneWidget);
      expect(find.textContaining('PIN 1234'), findsOneWidget);
      expect(find.text('Collect payment'), findsOneWidget);
      expect(find.text('Mark delivered'), findsOneWidget);
      expect(find.text('Repairing'), findsOneWidget);        // status action
      expect(find.text('Delivery receipt PDF'), findsNothing); // not delivered yet
      expect(find.text('Job sheet PDF'), findsOneWidget);
    });

    testWidgets('a delivered job is closed and offers its receipt', (t) async {
      final delivered = _job()
        ..['status'] = 'delivered'
        ..['balance_due'] = 0
        ..['paid_amount'] = 2800;
      await _pump(t, RepairDetailScreen(id: 1, testJob: delivered), size: const Size(420, 2200));

      expect(find.text('DELIVERED'), findsOneWidget);
      expect(find.text('Delivered — this job is closed.'), findsOneWidget);
      expect(find.text('Delivery receipt PDF'), findsOneWidget);
      expect(find.text('Mark delivered'), findsNothing);
      expect(find.text('Collect payment'), findsNothing);
      expect(find.text('PAID'), findsOneWidget);
    });

    testWidgets('200% text scale does not overflow the detail screen', (t) async {
      await _pump(t, RepairDetailScreen(id: 1, testJob: _job()),
        size: const Size(1080, 2340), scale: 2);
      expect(t.takeException(), isNull);
    });
  });

  group('repair form', () {
    Finder field(String label) => find.byWidgetPredicate((w) => w is GlassTextField && w.label == label);

    testWidgets('required customer name and complaint are enforced', (t) async {
      await _pump(t, const RepairForm(testStock: []), size: const Size(420, 3200));
      await t.tap(find.widgetWithText(PrimaryButton, 'Create repair job'));
      await t.pump();
      expect(find.text('Customer name is required'), findsOneWidget);
      expect(find.text('Complaint is required'), findsOneWidget);
    });

    testWidgets('a valid job posts a clean body (zero money stays 0, no silent nulls)', (t) async {
      Map<String, dynamic>? body;
      await _pump(t, RepairForm(testStock: [], testSave: (b) async => body = b), size: const Size(420, 3200));
      t.widget<GlassTextField>(field('Customer name')).controller.text = 'Ramesh Patel';
      t.widget<GlassTextField>(field('Mobile')).controller.text = '9876543210';
      t.widget<GlassTextField>(field('Brand')).controller.text = 'Samsung';
      t.widget<GlassTextField>(field('Model')).controller.text = 'Galaxy M31';
      t.widget<GlassTextField>(field('Complaint')).controller.text = 'Screen broken';
      t.widget<GlassTextField>(field('Service charge (₹)')).controller.text = '2800';
      t.widget<GlassTextField>(field('Advance received (₹)')).controller.text = '500';
      await t.tap(find.widgetWithText(PrimaryButton, 'Create repair job'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));

      expect(body, isNotNull);
      expect(body!['customer_name'], 'Ramesh Patel');
      expect(body!['complaint'], 'Screen broken');
      expect(body!['service_charge'], '2800');
      expect(body!['advance'], '500');
      expect(body!['parts_cost'], '0', reason: 'empty money fields must send 0, not an empty string');
      expect(body!['warranty_days'], isNull);
      expect(body!['phone_id'], isNull);
      expect(body!.containsKey('received_at'), isTrue);
    });

    testWidgets('a bad IMEI is caught before it reaches the server', (t) async {
      await _pump(t, const RepairForm(testStock: []), size: const Size(420, 3200));
      t.widget<GlassTextField>(field('IMEI (optional)')).controller.text = '123456789012345';
      await t.tap(find.widgetWithText(PrimaryButton, 'Create repair job'));
      await t.pump();
      expect(find.text('IMEI check digit is not valid'), findsOneWidget);
    });

    testWidgets('200% text scale does not overflow the form', (t) async {
      await _pump(t, const RepairForm(testStock: []), size: const Size(1080, 3000), scale: 2);
      expect(t.takeException(), isNull);
    });
  });
}
