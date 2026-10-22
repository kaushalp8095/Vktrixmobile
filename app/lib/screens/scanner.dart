// IMEI SCANNER: phone box ka barcode ya *#06# screen se 15-digit IMEI.
//
// mobile_scanner 7.4.x: CameraX 1.6, AGP 9 support aur CameraX init failure ka
// saaf error callback. Pehle (5.2.3, CameraX 1.3) Vivo/FunTouch aur naye 16 KB
// page devices par `bindToLifecycle` / HAL fail hote hi bas
// "No camera found or failed to open camera!" aata tha aur camera kabhi nahi
// khulta tha — plugin ke andar hi.
//
// Camera ka lifecycle owner sirf yahi screen hai (`autoStart: false` aur widget
// par `useAppLifecycleState: false`), kyunki widget har `inactive` par camera
// band karta hai — permission dialog bhi `inactive` bhejta hai.
//
// Android par plugin camera failures ko `genericError` me daalta hai; asli wajah
// `errorDetails.message` me hoti hai, isliye UI usi ko dikhata hai.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../api.dart';

/// Camera ke saare platform calls ek hi line me chalte hain.
///
/// `MobileScannerController.stop()` apna `isRunning` platform call se *pehle*
/// false kar deta hai. Bina queue ke, `resumed` par bheja gaya `start()` us
/// stop ke beech me ghus kar CameraX ko unbind ke dauran bind kar deta hai —
/// Vivo/FunTouch aur MIUI jaise skins usi par "No camera found or failed to
/// open camera!" dete hain (Dart me `genericError`). Isi tarah `Retry` bhi
/// pehle wale stop ke saath race karta tha.
class CameraTaskQueue {
  Future<void> _tail = Future<void>.value();

  /// [task] ko pehle queue hue kaam ke khatam hone ke baad chalata hai.
  Future<void> run(Future<void> Function() task) {
    final next = _tail.then((_) => task());
    // Ek fail hua kaam queue ko hamesha ke liye band nahi karta.
    _tail = next.catchError((Object _) {});
    return next;
  }
}

/// Sirf tab camera chhodein jab app sach me peeche chala gaya ho.
///
/// `inactive`/`hidden` tab bhi aate hain jab camera permission dialog ya koi
/// system dialog upar khula ho — us waqt camera release karna hi upar likhe
/// race ki shuruaat thi.
bool shouldReleaseCameraFor(AppLifecycleState state) =>
    state == AppLifecycleState.paused || state == AppLifecycleState.detached;

/// `genericError` ke andar chhupi asli wajah ko user ke liye padhne layak banata hai.
String cameraProblemMessage(MobileScannerException error) {
  if (error.errorCode == MobileScannerErrorCode.permissionDenied) {
    return 'Camera permission is blocked.\n\n'
        'Open Settings > Apps > Vktrix Mobile > Permissions, allow Camera, then tap Retry.';
  }
  if (error.errorCode == MobileScannerErrorCode.controllerNotAttached) {
    return 'The camera preview was not ready yet. Tap Retry.';
  }
  if (error.errorCode == MobileScannerErrorCode.controllerInitializing) {
    return 'The camera is still starting. Wait a moment, then tap Retry.';
  }
  final details = (error.errorDetails?.message ?? '').toLowerCase();
  if (details.contains('already started') || details.contains('already initiali')) {
    return 'The camera was already starting. Tap Retry.';
  }
  if (details.contains('no camera')) {
    return 'The camera could not be opened — it is busy or the phone did not '
        'release it.\n\nClose other apps that use the camera (including the '
        'system Camera app), then tap Retry.';
  }
  if (details.contains('setting up camera')) {
    return 'The camera service did not start. Close other camera apps and tap '
        'Retry, or restart the app if it keeps happening.';
  }
  return 'The camera could not be started (${error.errorCode.name}).\n\n'
      'Tap Retry, or enter the IMEI manually.';
}

/// Platform ka technical message (support/logcat ke liye), warna null.
String? cameraProblemDetail(MobileScannerException error) {
  final message = error.errorDetails?.message;
  return (message == null || message.trim().isEmpty) ? null : message;
}

/// `genericError` aksar ek busy/failed CameraX bind hota hai jo agle attempt me
/// saaf ho jata hai. `controllerNotAttached` tab aata hai jab `start()` naye
/// widget ke attach hone se pehle chala ho — agla frame usse theek kar deta hai.
/// Permission denial ya disposed controller dobara try karne se theek nahi hote.
bool isTransientCameraProblem(MobileScannerException error) =>
    error.errorCode == MobileScannerErrorCode.genericError ||
    error.errorCode == MobileScannerErrorCode.controllerNotAttached;

/// Camera controller. `autoStart: false` — start/stop ka owner ye screen hai.
///
/// 7.x me `useNewCameraSelector` hata diya gaya hai; lens ab `lensType` se
/// chunte hain. IMEI box ka barcode paas se padhna hota hai, isliye `normal`
/// (26-35mm) sabse saaf hai — `any` kai phones par ultra-wide ya telephoto
/// chun leta hai jahan close-range focus theek nahi hota.
MobileScannerController createImeiScannerController({
  CameraLensType lensType = CameraLensType.normal,
}) => MobileScannerController(
  autoStart: false,
  detectionSpeed: DetectionSpeed.noDuplicates,
  facing: CameraFacing.back,
  lensType: lensType,
);

class ImeiScanner extends StatefulWidget {
  const ImeiScanner({super.key});

  @override
  State<ImeiScanner> createState() => _ImeiScannerState();
}

class _ImeiScannerState extends State<ImeiScanner> with WidgetsBindingObserver {
  final CameraTaskQueue _queue = CameraTaskQueue();
  MobileScannerController _camera = createImeiScannerController();
  /// `normal` lens na mile to `any` par gir jate hain (kuch OEM ROMs me
  /// normal lens report hi nahi hota).
  CameraLensType _lens = CameraLensType.normal;
  StreamSubscription<BarcodeCapture>? _subscription;
  bool _done = false;
  /// Retry ke waqt purana controller tree se hata kar naya lagaya jata hai.
  bool _rebuilding = false;
  /// Ek hi automatic retry, warna fail hote rahne par loop ban jayega.
  bool _autoRetried = false;
  /// 7.x me kuch failures `start()` throw karke deta hai (state.error me nahi).
  MobileScannerException? _problem;
  int _generation = 0;
  String? _hint;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subscribe();
    // Pehla frame: MobileScanner tree me aa jaye, phir camera start karein.
    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) unawaited(_startCamera()); });
  }

  void _subscribe() {
    if (_subscription != null || _done) return;
    _subscription = _camera.barcodes.listen(_onBarcodes);
  }

  Future<void> _startCamera() => _queue.run(_startCameraNow);

  Future<void> _startCameraNow() async {
    final camera = _camera;
    if (_done || !mounted || camera.value.isRunning) return;
    MobileScannerException? thrown;
    try {
      await camera.start();
    } on MobileScannerException catch (e) {
      // Attach/lifecycle problems start() throw karta hai; camera (CameraX)
      // failures state.error me aate hain — dono ko ek jagah handle karte hain.
      thrown = e;
    } catch (e) {
      debugPrint('IMEI scanner: start() threw -> $e');
      return;
    }
    if (!mounted || _done || !identical(camera, _camera)) return;
    final error = thrown ?? camera.value.error;
    if (error == null) {
      _autoRetried = false;
      if (_problem != null) setState(() => _problem = null);
      return;
    }
    debugPrint('IMEI scanner: camera start failed -> $error; detail: ${cameraProblemDetail(error)}');
    // Busy sensor / late attach aksar agle attempt tak theek ho jate hain. Ek
    // baar khud try karein (naye controller ke saath), uske baad UI ko batayein.
    if (_autoRetried || !isTransientCameraProblem(error)) {
      if (mounted) setState(() => _problem = error);
      return;
    }
    _autoRetried = true;
    // Normal lens hi fail hua ho to any lens se ek aur koshish.
    _lens = CameraLensType.any;
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted || _done) return;
    await _replaceCamera();
    await _startCameraNow();
  }

  /// User ne Retry dabaya: purana controller native side par adhoora pada reh
  /// sakta hai (leaked listeners, half-bound camera), isliye naya banate hain.
  Future<void> _retry() async {
    _autoRetried = false;
    if (mounted) setState(() { _hint = null; _problem = null; });
    await _queue.run(() async {
      if (!mounted || _done) return;
      await _replaceCamera();
      await _startCameraNow();
    });
  }

  /// Purana controller dispose karke naya lagata hai.
  ///
  /// Beech me ek frame chahiye: `ValueListenableBuilder`/`MobileScanner` ko
  /// tree se hatne ka mauka mile, tabhi disposed controller par listener
  /// remove karne ka assert nahi lagta.
  Future<void> _replaceCamera() async {
    final previous = _camera;
    await _subscription?.cancel();
    _subscription = null;
    if (mounted) setState(() => _rebuilding = true);
    await _nextFrame();
    try {
      // Native camera yahan release hota hai; fail ho to bhi naya controller
      // lagana chahiye.
      await previous.dispose();
    } catch (e) {
      debugPrint('IMEI scanner: dispose failed -> $e');
    }
    if (!mounted) return;
    setState(() {
      _camera = createImeiScannerController(lensType: _lens);
      _generation++;
      _rebuilding = false;
      _problem = null;
    });
    _subscribe();
  }

  /// Agla frame, maximum 2 second — app background me ho to frame aane tak
  /// camera queue atakni nahi chahiye.
  Future<void> _nextFrame() {
    final binding = WidgetsBinding.instance;
    final done = Completer<void>();
    binding.addPostFrameCallback((_) { if (!done.isCompleted) done.complete(); });
    binding.ensureVisualUpdate();
    return done.future.timeout(const Duration(seconds: 2), onTimeout: () {});
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
      unawaited(_startCamera());
      return;
    }
    // Permission dialog/chhoti interruptions par camera chalta rehna chahiye.
    if (!shouldReleaseCameraFor(state)) return;
    final camera = _camera;
    unawaited(_queue.run(() async {
      await _subscription?.cancel();
      _subscription = null;
      try {
        await camera.stop();
      } catch (e) {
        debugPrint('IMEI scanner: stop failed -> $e');
      }
    }));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _done = true;
    unawaited(_subscription?.cancel());
    unawaited(_camera.dispose().catchError((Object e) {
      debugPrint('IMEI scanner: dispose failed -> $e');
    }));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan IMEI')),
      body: Stack(children: [
        Positioned.fill(child: _cameraLayer()),
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

  Widget _cameraLayer() {
    if (_rebuilding) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final camera = _camera;
    return Stack(children: [
      Positioned.fill(child: MobileScanner(
        key: ValueKey('imei-camera-$_generation'),
        controller: camera,
        // Widget har `inactive` par stop karta hai (permission dialog bhi
        // `inactive` hai) — isliye lifecycle is screen ke paas hai.
        useAppLifecycleState: false,
      )),
      Positioned.fill(
        child: ValueListenableBuilder<MobileScannerState>(
          valueListenable: camera,
          builder: (context, state, _) {
            final error = _problem ?? state.error;
            if (error != null) return _CameraProblem(error: error, onRetry: _retry);
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
    ]);
  }
}

class _CameraProblem extends StatelessWidget {
  final MobileScannerException error;
  final Future<void> Function() onRetry;
  const _CameraProblem({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final detail = cameraProblemDetail(error);
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(
              error.errorCode == MobileScannerErrorCode.permissionDenied
                  ? Icons.no_photography_outlined
                  : Icons.photo_camera_back_outlined,
              color: Colors.white, size: 48),
            const SizedBox(height: 16),
            Text(
              cameraProblemMessage(error),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, height: 1.35),
            ),
            if (detail != null) ...[
              const SizedBox(height: 12),
              // Asli platform message: support ko screenshot bhejne par wajah
              // turant pata chalti hai, andaaza nahi lagana padta.
              Text(
                detail,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ],
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
