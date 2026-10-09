// In-app APK updater: downloads the release APK inside the app (no browser), reports
// live progress, verifies the file and then opens the Android installer. The download
// keeps running if the update dialog is hidden; the installer opens when it finishes.
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

enum UpdatePhase { idle, downloading, installing, ready, needsPermission, failed }

/// Bridge to MainActivity.kt. Replaced by a fake in tests.
class UpdatePlatform {
  static const _channel = MethodChannel('com.vktrix.mobileapp/updater');
  const UpdatePlatform();

  bool get supported => !kIsWeb && Platform.isAndroid;
  Future<String> updateDir() async => (await _channel.invokeMethod<String>('updateDir'))!;
  Future<bool> canInstall() async => await _channel.invokeMethod<bool>('canInstall') ?? false;
  Future<void> openInstallSettings() => _channel.invokeMethod<void>('openInstallSettings');

  /// 'started' (system installer opened) or 'permission_required'.
  Future<String> installApk(String path) async =>
      await _channel.invokeMethod<String>('installApk', {'path': path}) ?? 'started';
}

class _UpdateError implements Exception {
  final String message;
  const _UpdateError(this.message);
  @override
  String toString() => message;
}

class _Cancelled implements Exception {
  const _Cancelled();
}

class ApkUpdater extends ChangeNotifier with WidgetsBindingObserver {
  ApkUpdater({
    UpdatePlatform? platform,
    http.Client Function()? clientFactory,
    this.stallTimeout = const Duration(seconds: 30),
  })  : platform = platform ?? const UpdatePlatform(),
        _newClient = clientFactory ?? http.Client.new;

  /// App-wide instance so a download survives closing the dialog.
  static final ApkUpdater instance = ApkUpdater();

  final UpdatePlatform platform;
  final http.Client Function() _newClient;
  final Duration stallTimeout;

  UpdatePhase phase = UpdatePhase.idle;
  String? versionName;
  int received = 0;
  int? total;
  double bytesPerSecond = 0;
  String? error;
  String? apkPath;

  http.Client? _client;
  StreamSubscription<List<int>>? _sub;
  IOSink? _sink;
  File? _part;
  Timer? _stall;
  Completer<void>? _done;
  Future<void>? _closing;
  bool _observing = false;
  DateTime _lastNotify = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _speedAt = DateTime.now();
  int _speedBytes = 0;

  /// 0..1, or null while the size is unknown.
  double? get progress {
    final t = total;
    if (t == null || t <= 0) return null;
    return (received / t).clamp(0.0, 1.0).toDouble();
  }

  Duration? get eta {
    final t = total;
    if (t == null || bytesPerSecond <= 0) return null;
    return Duration(seconds: ((t - received) / bytesPerSecond).ceil().clamp(0, 359999).toInt());
  }

  /// Starts (or resumes showing) the update for [versionName]. Safe to call repeatedly.
  Future<void> start({required String url, required String versionName}) async {
    if (phase == UpdatePhase.downloading || phase == UpdatePhase.installing) {
      if (this.versionName == versionName) return;
      await cancel();
    }
    await _teardown();
    this.versionName = versionName;
    received = 0;
    total = null;
    bytesPerSecond = 0;
    error = null;
    apkPath = null;

    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https') {
      _fail('The update link is invalid. Please try again later.');
      return;
    }
    _set(UpdatePhase.downloading);
    try {
      final dir = Directory(await platform.updateDir());
      await dir.create(recursive: true);
      final safe = versionName.replaceAll(RegExp(r'[^0-9A-Za-z._-]'), '_');
      final target = File('${dir.path}/vktrix-$safe.apk');
      // Keep only this version's file; older APKs are just wasted storage.
      await for (final f in dir.list()) {
        if (f is File && f.path != target.path && f.path != '${target.path}.part') {
          try { await f.delete(); } catch (_) {}
        }
      }
      if (await target.exists() && await _looksLikeApk(target)) {
        received = await target.length();
        total = received;
        apkPath = target.path;
        _set(UpdatePhase.ready);
        await install();
        return;
      }

      final part = File('${target.path}.part');
      _part = part;
      final client = _client = _newClient();
      final res = await client.send(http.Request('GET', uri)).timeout(const Duration(seconds: 30));
      if (phase != UpdatePhase.downloading) throw const _Cancelled();
      if (res.statusCode != 200) throw _UpdateError('Update server returned error ${res.statusCode}. Please retry.');
      total = res.contentLength;

      final sink = _sink = part.openWrite();
      final done = _done = Completer<void>();
      _speedAt = DateTime.now();
      _speedBytes = 0;
      _armStall();
      notifyListeners();
      _sub = res.stream.listen(
        (chunk) {
          sink.add(chunk);
          received += chunk.length;
          _armStall();
          _tick();
        },
        onError: (Object e) { if (!done.isCompleted) done.completeError(e); },
        onDone: () { if (!done.isCompleted) done.complete(); },
        cancelOnError: true,
      );
      await done.future;
      _stall?.cancel();
      await sink.flush();
      await sink.close();
      _sink = null;

      final t = total;
      if (t != null && received != t) throw const _UpdateError('Download was incomplete. Please retry.');
      if (!await _looksLikeApk(part)) throw const _UpdateError('The downloaded file is not a valid app package.');
      await part.rename(target.path);
      _part = null;
      apkPath = target.path;
      _closeClient();
      _set(UpdatePhase.ready);
      await install();
    } on _Cancelled {
      await _teardown();
      await _deletePartial();
    } catch (e) {
      debugPrint('Update download failed: $e');
      if (phase != UpdatePhase.downloading) return; // cancelled meanwhile
      await _teardown();
      await _deletePartial();
      _fail(e is _UpdateError ? e.message : 'Download failed. Check your internet connection and try again.');
    }
  }

  /// Opens the system installer for the downloaded APK.
  Future<void> install() async {
    final path = apkPath;
    if (path == null) return;
    _set(UpdatePhase.installing);
    try {
      final r = await platform.installApk(path);
      if (r == 'permission_required') {
        _observe(true);
        _set(UpdatePhase.needsPermission);
      } else {
        _observe(false);
        _set(UpdatePhase.ready); // installer is open; "Install now" re-opens it if dismissed
      }
    } catch (e) {
      debugPrint('Could not open installer: $e');
      error = 'Could not open the installer. Tap Retry to try again.';
      _set(UpdatePhase.failed); // apkPath is kept, so Retry installs without re-downloading
    }
  }

  Future<void> openInstallSettings() async {
    _observe(true);
    await platform.openInstallSettings();
  }

  /// Stops an active download and deletes the partial file.
  Future<void> cancel() async {
    if (phase != UpdatePhase.downloading) return;
    _set(UpdatePhase.idle);
    final d = _done;
    if (d != null && !d.isCompleted) d.completeError(const _Cancelled());
    await _teardown();
    await _deletePartial();
  }

  // Back from "Install unknown apps" settings → continue installing automatically.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || phase != UpdatePhase.needsPermission) return;
    platform.canInstall().then((ok) { if (ok && phase == UpdatePhase.needsPermission) install(); });
  }

  @visibleForTesting
  void debugSetState(UpdatePhase p, {String? version, int received = 0, int? total, double bytesPerSecond = 0, String? error}) {
    phase = p;
    versionName = version;
    this.received = received;
    this.total = total;
    this.bytesPerSecond = bytesPerSecond;
    this.error = error;
    notifyListeners();
  }

  void _tick() {
    final now = DateTime.now();
    final dt = now.difference(_speedAt).inMilliseconds;
    if (dt >= 700) {
      final instant = (received - _speedBytes) * 1000 / dt;
      bytesPerSecond = bytesPerSecond == 0 ? instant : bytesPerSecond * .6 + instant * .4;
      _speedBytes = received;
      _speedAt = now;
    }
    if (now.difference(_lastNotify).inMilliseconds >= 80) {
      _lastNotify = now;
      notifyListeners();
    }
  }

  void _armStall() {
    _stall?.cancel();
    _stall = Timer(stallTimeout, () {
      final d = _done;
      if (d != null && !d.isCompleted) d.completeError(const _UpdateError('Download stopped responding. Check your internet and retry.'));
    });
  }

  Future<bool> _looksLikeApk(File f) async {
    try {
      if (await f.length() < 4) return false;
      final raf = await f.open();
      final head = await raf.read(2);
      await raf.close();
      return head.length == 2 && head[0] == 0x50 && head[1] == 0x4B; // "PK" (zip)
    } catch (_) {
      return false;
    }
  }

  void _observe(bool on) {
    if (on == _observing) return;
    _observing = on;
    if (on) {
      WidgetsBinding.instance.addObserver(this);
    } else {
      WidgetsBinding.instance.removeObserver(this);
    }
  }

  /// Stops network + file writing. Awaiting it guarantees the partial file is closed;
  /// concurrent callers (cancel + the download loop) share the same close.
  Future<void> _teardown() => _closing ??= _closeAll().whenComplete(() { _closing = null; });

  Future<void> _closeAll() async {
    _stall?.cancel();
    _stall = null;
    final sub = _sub;
    _sub = null;
    final s = _sink;
    _sink = null;
    _closeClient();
    try { await sub?.cancel(); } catch (_) {}
    try { await s?.close(); } catch (_) {}
  }

  void _closeClient() {
    _client?.close();
    _client = null;
  }

  Future<void> _deletePartial() async {
    final p = _part;
    _part = null;
    if (p == null) return;
    try { if (await p.exists()) await p.delete(); } catch (_) {}
  }

  void _fail(String message) {
    error = message;
    _set(UpdatePhase.failed);
  }

  void _set(UpdatePhase p) {
    phase = p;
    _lastNotify = DateTime.now();
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_teardown());
    _observe(false);
    super.dispose();
  }
}
