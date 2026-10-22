import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../api.dart';

/// Scans the barcode on a phone box or the *#06# screen to read its IMEI.
///
/// The controller is deliberately `autoStart: false`: starting it manually while
/// MobileScanner also auto-starts causes two overlapping CameraX start calls and
/// surfaces as `genericError` on Android. One owner now controls start/stop, and
/// the newer CameraX selector handles devices with unusual rear-camera layouts.
/// Kept as a small public factory so a regression test can guarantee that the
/// widget and this screen never both auto-start the same camera again.
MobileScannerController createImeiScannerController() => MobileScannerController(
  autoStart: false,
  detectionSpeed: DetectionSpeed.noDuplicates,
  facing: CameraFacing.back,
  useNewCameraSelector: true,
);

class ImeiScanner extends StatefulWidget {
  const ImeiScanner({super.key});

  @override
  State<ImeiScanner> createState() => _ImeiScannerState();
}

class _ImeiScannerState extends State<ImeiScanner> with WidgetsBindingObserver {
  final MobileScannerController _camera = createImeiScannerController();
  StreamSubscription<BarcodeCapture>? _subscription;
  bool _done = false;
  bool _starting = false;
  String? _hint;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subscribe();
    // Wait until MobileScanner has attached the controller before starting it.
    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) unawaited(_start()); });
  }

  void _subscribe() {
    if (_subscription != null) return;
    _subscription = _camera.barcodes.listen(_onBarcodes);
  }

  Future<void> _start() async {
    if (_done || _starting || _camera.value.isRunning) return;
    _starting = true;
    try {
      await _camera.start();
    } catch (_) {
      // The controller publishes camera failures in MobileScannerState.error.
      if (mounted) setState(() => _hint = 'Could not start the camera. Check camera permission and retry.');
    } finally {
      _starting = false;
    }
  }

  Future<void> _restart() async {
    if (_starting) return;
    try { await _camera.stop(); } catch (_) { /* It may not have started yet. */ }
    _subscribe();
    await _start();
  }

  void _onBarcodes(BarcodeCapture capture) {
    if (_done) return;
    for (final barcode in capture.barcodes) {
      final match = RegExp(r'\d{15}').firstMatch(barcode.rawValue ?? '');
      if (match == null) continue;
      final imei = match.group(0)!;
      if (!validImei(imei)) {
        // A 15-digit number that fails the Luhn check is a false read.
        if (mounted) setState(() => _hint = 'Barcode found, but the IMEI is invalid: $imei');
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
      appBar: AppBar(title: const Text('Scan IMEI')),
      body: Stack(children: [
        Positioned.fill(child: MobileScanner(controller: _camera)),
        Positioned.fill(
          child: ValueListenableBuilder<MobileScannerState>(
            valueListenable: _camera,
            builder: (context, state, _) {
              final error = state.error;
              if (error != null) return _CameraProblem(error: error, onRetry: _restart);
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
                  _hint ?? 'Point the camera at the 15-digit barcode on the phone box or *#06# screen',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 6),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel / enter manually', style: TextStyle(color: Colors.white)),
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
                  ? 'Camera permission is required.\nGo to Settings > Apps > Vktrix Mobile, allow camera access, then return here.'
                  : 'Could not start the camera (${error.errorCode.name}).',
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
              child: const Text('Enter IMEI manually', style: TextStyle(color: Colors.white)),
            ),
          ]),
        ),
      ),
    );
  }
}
