import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../api.dart';

/// Phone box / *#06# screen ka barcode scan karke IMEI laata hai.
///
/// `MobileScanner(onDetect: ...)` was **removed in mobile_scanner 5.0.0**, which
/// is why the old version of this screen never fired. The supported API on 5.x,
/// 6.x and 7.x alike is a [MobileScannerController] plus its `barcodes` stream,
/// so that is what this screen uses.
class ImeiScanner extends StatefulWidget {
  const ImeiScanner({super.key});

  @override
  State<ImeiScanner> createState() => _ImeiScannerState();
}

class _ImeiScannerState extends State<ImeiScanner> with WidgetsBindingObserver {
  final MobileScannerController _camera = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  StreamSubscription<BarcodeCapture>? _subscription;
  bool _done = false;
  String? _hint;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subscribe();
    unawaited(_start());
  }

  void _subscribe() {
    _subscription = _camera.barcodes.listen(_onBarcodes);
  }

  Future<void> _start() async {
    try {
      await _camera.start();
    } catch (_) {
      // Failures (camera busy, permission denied, unsupported device) are
      // published on MobileScannerState.error and rendered below.
    }
  }

  void _onBarcodes(BarcodeCapture capture) {
    if (_done) return;
    for (final barcode in capture.barcodes) {
      final match = RegExp(r'\d{15}').firstMatch(barcode.rawValue ?? '');
      if (match == null) continue;
      final imei = match.group(0)!;
      if (!validImei(imei)) {
        // A 15-digit number that fails the Luhn check is a false read.
        if (mounted) setState(() => _hint = 'Barcode mila, par IMEI sahi nahi hai: $imei');
        continue;
      }
      _done = true;
      Navigator.of(context).pop(imei);
      return;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (_done) return;
    if (state == AppLifecycleState.resumed) {
      _subscribe();
      unawaited(_start());
      return;
    }
    // Release the camera while backgrounded.
    unawaited(_subscription?.cancel());
    _subscription = null;
    unawaited(_camera.stop());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_subscription?.cancel());
    unawaited(_camera.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('IMEI scan karein')),
      body: Stack(children: [
        Positioned.fill(child: MobileScanner(controller: _camera)),
        Positioned.fill(
          child: ValueListenableBuilder<MobileScannerState>(
            valueListenable: _camera,
            builder: (context, state, _) {
              final error = state.error;
              if (error != null) return _CameraProblem(error: error, onRetry: _start);
              if (!state.isInitialized) {
                return const ColoredBox(
                  color: Colors.black,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ),
        Positioned(
          left: 20, right: 20, bottom: 28,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: .66),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(
                  _hint ?? 'Phone ke box ya *#06# screen ke 15-digit barcode par camera rakhein',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 6),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel / manually likhein', style: TextStyle(color: Colors.white)),
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

class _CameraProblem extends StatelessWidget {
  final MobileScannerException error;
  final Future<void> Function() onRetry;
  const _CameraProblem({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.no_photography_outlined, color: Colors.white, size: 48),
            const SizedBox(height: 16),
            Text(
              denied
                  ? 'Camera permission chahiye.\nPhone ki Settings > Apps > Vktrix Mobile me camera allow karke wapas aayein.'
                  : 'Camera start nahi ho paya (${error.errorCode.name}).',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => onRetry(),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('IMEI manually likhein', style: TextStyle(color: Colors.white)),
            ),
          ]),
        ),
      ),
    );
  }
}
