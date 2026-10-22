// IMEI scanner ke camera-recovery rules: yehi decide karte hain ki "genericError"
// par camera dobara khulega ya screen dead-end ban jayegi.
//
// Android par mobile_scanner har camera failure ko `genericError` bana deta hai
// aur asli wajah sirf `errorDetails.message` me hoti hai — isliye yahan message
// mapping, lifecycle rule aur start/stop queue teeno test hote hain.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:mobile_shop/screens/scanner.dart';

MobileScannerException _error(MobileScannerErrorCode code, [String? message]) => MobileScannerException(
  errorCode: code,
  errorDetails: message == null ? null : MobileScannerErrorDetails(message: message),
);

void main() {
  test('camera start and stop never overlap', () async {
    final queue = CameraTaskQueue();
    final log = <String>[];
    Future<void> op(String name, int ms) async {
      log.add('$name:start');
      await Future<void>.delayed(Duration(milliseconds: ms));
      log.add('$name:end');
    }

    // Background jaate hi stop() bhejta hai aur turant wapas aane par start():
    // bina queue ke dono ek saath chalte the aur CameraX "No camera found"
    // deta tha.
    await Future.wait([queue.run(() => op('start', 40)), queue.run(() => op('stop', 5))]);

    expect(log, ['start:start', 'start:end', 'stop:start', 'stop:end']);
  });

  test('a failed camera task does not block the next one', () async {
    final queue = CameraTaskQueue();
    await expectLater(queue.run(() async => throw StateError('no camera')), throwsStateError);

    var ran = false;
    await queue.run(() async { ran = true; });

    expect(ran, isTrue, reason: 'ek fail hua start baad ke retry ko rokna nahi chahiye');
  });

  test('permission dialog must not release the camera', () {
    // inaktive/hidden permission dialog aur system dialogs par bhi aate hain;
    // wahan stop() bhejna hi purani race thi.
    expect(shouldReleaseCameraFor(AppLifecycleState.inactive), isFalse);
    expect(shouldReleaseCameraFor(AppLifecycleState.hidden), isFalse);
    expect(shouldReleaseCameraFor(AppLifecycleState.paused), isTrue);
    expect(shouldReleaseCameraFor(AppLifecycleState.detached), isTrue);
    expect(shouldReleaseCameraFor(AppLifecycleState.resumed), isFalse);
  });

  test('busy camera message tells the user what to do', () {
    final message = cameraProblemMessage(
      _error(MobileScannerErrorCode.genericError, 'No camera found or failed to open camera!'),
    );

    expect(message, contains('busy'));
    expect(message.toLowerCase(), contains('retry'));
  });

  test('camera setup failure is not reported as a permission problem', () {
    final message = cameraProblemMessage(
      _error(MobileScannerErrorCode.genericError, 'Error occurred when setting up camera!'),
    );

    expect(message, contains('camera service'));
    expect(message.toLowerCase(), isNot(contains('permission')));
  });

  test('a late-attached preview asks for a retry, not a permission fix', () {
    final message = cameraProblemMessage(
      _error(MobileScannerErrorCode.controllerNotAttached, 'attach timed out'),
    );

    expect(message.toLowerCase(), contains('retry'));
    expect(message.toLowerCase(), isNot(contains('permission')));
  });

  test('a still-starting controller is not told to fix the hardware', () {
    final message = cameraProblemMessage(_error(MobileScannerErrorCode.controllerInitializing));

    expect(message.toLowerCase(), contains('still starting'));
  });

  test('permission denial points at Android app settings', () {
    final message = cameraProblemMessage(_error(MobileScannerErrorCode.permissionDenied));

    expect(message, contains('Settings'));
    expect(message, contains('Camera'));
  });

  test('unknown genericError still names the code and offers manual entry', () {
    final message = cameraProblemMessage(_error(MobileScannerErrorCode.genericError));

    expect(message, contains('genericError'));
    expect(message.toLowerCase(), contains('manually'));
  });

  test('platform detail is shown only when the platform sent one', () {
    final withDetail = _error(MobileScannerErrorCode.genericError, 'Called start() while already started');
    expect(cameraProblemDetail(withDetail), 'Called start() while already started');
    expect(cameraProblemDetail(_error(MobileScannerErrorCode.permissionDenied)), isNull);
    expect(cameraProblemDetail(_error(MobileScannerErrorCode.genericError, '   ')), isNull);
  });

  test('only a generic failure is retried automatically', () {
    // Permission denial aur disposed controller retry se theek nahi hote.
    expect(isTransientCameraProblem(_error(MobileScannerErrorCode.genericError)), isTrue);
    // Naya widget agle frame me attach ho jata hai.
    expect(isTransientCameraProblem(_error(MobileScannerErrorCode.controllerNotAttached)), isTrue);
    expect(isTransientCameraProblem(_error(MobileScannerErrorCode.controllerInitializing)), isFalse);
    expect(isTransientCameraProblem(_error(MobileScannerErrorCode.permissionDenied)), isFalse);
    expect(isTransientCameraProblem(_error(MobileScannerErrorCode.controllerDisposed)), isFalse);
    expect(isTransientCameraProblem(_error(MobileScannerErrorCode.unsupported)), isFalse);
  });
}
