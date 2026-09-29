import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Phone box / *#06# screen ka barcode scan karke IMEI laata hai
class ImeiScanner extends StatefulWidget {
  const ImeiScanner({super.key});
  @override
  State<ImeiScanner> createState() => _ImeiScannerState();
}

class _ImeiScannerState extends State<ImeiScanner> {
  bool done = false;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('IMEI Scan karein')),
        body: MobileScanner(onDetect: (cap) {
          if (done) return;
          for (final b in cap.barcodes) {
            final m = RegExp(r'\d{15}').firstMatch(b.rawValue ?? '');
            if (m != null) { done = true; Navigator.pop(context, m.group(0)); return; }
          }
        }),
      );
}
