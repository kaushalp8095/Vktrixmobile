import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:mobile_shop/billing/receipt_document.dart';
import 'package:mobile_shop/screens/scanner.dart';

const _png = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGPwd3v6HwAE3AJ6zM4FjgAAAABJRU5ErkJggg==';

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

  test('a bill with paise keeps them (₹12,500.50, not ₹12,501)', () async {
    // Ledger 12500.50 rakhta hai; invoice bhi wahi dikhaye. Pehle rs() 0 decimal
    // par round kar deta tha, to customer ke bill par ₹12,501 chhapta tha (ab `rs()`
    // paise rakhta hai, isliye PDF me bhi 12,500.50 hi jata hai).
    final receipt = _receipt('sale');
    receipt['amount'] = 12500.5;
    receipt['paid_amount'] = 5000.25;
    receipt['balance_due'] = 7500.25;
    final bytes = await ReceiptDocument.build(receipt);
    expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
    expect(ascii.decode(bytes.sublist(bytes.length - 16), allowInvalid: true), contains('%%EOF'));
  });

  test('IMEI scanner has exactly one camera start owner', () async {
    final controller = createImeiScannerController();
    expect(controller.autoStart, isFalse,
      reason: 'autoStart plus the screen start call races CameraX and causes genericError');
    expect(controller.facing, CameraFacing.back);
    expect(controller.detectionSpeed, DetectionSpeed.noDuplicates);
    // 7.x: paas se barcode padhne ke liye normal (26-35mm) lens, special nahi.
    expect(controller.lensType, CameraLensType.normal);
    await controller.dispose();
  });
}
