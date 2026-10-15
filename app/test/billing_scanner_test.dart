import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:mobile_shop/billing/receipt_document.dart';
import 'package:mobile_shop/screens/scanner.dart';

const _png = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFAAH/q842iQAAAABJRU5ErkJggg==';

Map<String, dynamic> _receipt(String type) => {
  'type': type,
  'number': type == 'sale' ? 'INV-001-000042' : 'PUR-001-000042',
  'date': '2026-10-15',
  'shop': {
    'name': 'Krishna Mobiles', 'owner_name': 'Kaushal', 'phone': '9876543210',
    'address': 'Mahesana, Gujarat', 'gst_no': '24ABCDE1234F1Z5', 'logo_data': _png,
  },
  'customer': {'name': 'Ramesh Patel', 'phone': '9988776655', 'address': 'Station Road'},
  'phone': {
    'brand': 'Apple', 'model': 'iPhone 13', 'imei': '353328111234561',
    'imei2': '353328111234579', 'serial_number': 'SERIAL-42', 'ram': '4GB',
    'storage': '128GB', 'color': 'Blue', 'condition': 'Good', 'accessories': 'Box, charger',
  },
  'amount': type == 'sale' ? 36500 : 30000,
  if (type == 'sale') ...{
    'warranty': '7 days shop warranty', 'payment_mode': 'upi',
    'paid_amount': 10000, 'balance_due': 26500, 'payment_status': 'partial',
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('sale and purchase PDFs are real renderable PDF files', () async {
    for (final type in ['sale', 'purchase']) {
      final bytes = await ReceiptDocument.build(_receipt(type));
      expect(bytes.length, greaterThan(5000));
      expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
      // A complete PDF must end with an EOF marker (allow the final newline).
      expect(ascii.decode(bytes.sublist(bytes.length - 16), allowInvalid: true), contains('%%EOF'));
    }
  });

  test('IMEI scanner has one start owner and uses the Android camera selector', () async {
    final controller = createImeiScannerController();
    expect(controller.autoStart, isFalse,
      reason: 'autoStart plus the screen start call races CameraX and causes genericError');
    expect(controller.facing, CameraFacing.back);
    expect(controller.detectionSpeed, DetectionSpeed.noDuplicates);
    expect(controller.useNewCameraSelector, isTrue);
    await controller.dispose();
  });
}
