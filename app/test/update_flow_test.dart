import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile_shop/design/design.dart';
import 'package:mobile_shop/screens/update_checker.dart';
import 'package:mobile_shop/update/apk_updater.dart';
import 'showcase_golden_test.dart' show loadFonts;

class _FakePlatform extends UpdatePlatform {
  _FakePlatform(this.dir);
  final Directory dir;
  bool canInstallResult = true;
  String installResult = 'started';
  final installs = <String>[];
  int settingsOpened = 0;

  @override
  bool get supported => true;
  @override
  Future<String> updateDir() async => dir.path;
  @override
  Future<bool> canInstall() async => canInstallResult;
  @override
  Future<void> openInstallSettings() async {
    settingsOpened++;
  }
  @override
  Future<String> installApk(String path) async {
    installs.add(path);
    return installResult;
  }
}

const _url = 'https://github.com/kaushalp8095/Vktrixmobile/releases/download/v1.0.0.20741/app-release.apk';
const _version = '1.0.0.20741';
final _apk = [0x50, 0x4B, ...List.filled(4096, 7)];

http.Client Function() _serve(List<int> bytes, {int status = 200, int? length, void Function()? onRequest}) =>
    () => MockClient.streaming((req, _) async {
          onRequest?.call();
          final chunks = [for (var i = 0; i < bytes.length; i += 512) bytes.sublist(i, math.min(i + 512, bytes.length))];
          return http.StreamedResponse(Stream.fromIterable(chunks), status, contentLength: length ?? bytes.length);
        });

/// Real file I/O completes outside the microtask queue, so wait with real delays.
Future<void> _until(bool Function() ok) async {
  for (var i = 0; i < 400 && !ok(); i++) { await Future<void>.delayed(const Duration(milliseconds: 5)); }
  expect(ok(), isTrue, reason: 'condition not reached in time');
}

List<String> _names(Directory d) => d.listSync().map((e) => e.uri.pathSegments.last).toList()..sort();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late _FakePlatform platform;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('vktrix-update-');
    platform = _FakePlatform(dir);
  });
  tearDown(() { try { dir.deleteSync(recursive: true); } catch (_) {} });

  group('ApkUpdater', () {
    test('downloads inside the app with progress, removes old APKs, then opens the installer', () async {
      File('${dir.path}/vktrix-1.0.0.1.apk').writeAsBytesSync(_apk);
      final u = ApkUpdater(platform: platform, clientFactory: _serve(_apk));
      final seen = <double?>[];
      u.addListener(() => seen.add(u.progress));
      await u.start(url: _url, versionName: _version);
      expect(u.phase, UpdatePhase.ready);
      expect(u.received, _apk.length);
      expect(u.progress, 1.0);
      expect(seen, isNotEmpty);
      expect(platform.installs, ['${dir.path}/vktrix-$_version.apk']);
      expect(_names(dir), ['vktrix-$_version.apk']);
    });

    test('asks for install permission and continues automatically after returning from settings', () async {
      platform.installResult = 'permission_required';
      final u = ApkUpdater(platform: platform, clientFactory: _serve(_apk));
      await u.start(url: _url, versionName: _version);
      expect(u.phase, UpdatePhase.needsPermission);

      platform.installResult = 'started';
      platform.canInstallResult = false;
      u.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await pumpEventQueue();
      expect(u.phase, UpdatePhase.needsPermission, reason: 'permission still off');

      platform.canInstallResult = true;
      u.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await pumpEventQueue();
      expect(u.phase, UpdatePhase.ready);
      expect(platform.installs, hasLength(2));
    });

    test('rejects a non-APK response (e.g. an HTML error page) and leaves no files', () async {
      final u = ApkUpdater(platform: platform, clientFactory: _serve('<html>error</html>'.codeUnits));
      await u.start(url: _url, versionName: _version);
      expect(u.phase, UpdatePhase.failed);
      expect(u.error, contains('not a valid app package'));
      expect(platform.installs, isEmpty);
      expect(_names(dir), isEmpty);
    });

    test('rejects an incomplete download', () async {
      final u = ApkUpdater(platform: platform, clientFactory: _serve(_apk, length: _apk.length + 1000));
      await u.start(url: _url, versionName: _version);
      expect(u.phase, UpdatePhase.failed);
      expect(u.error, contains('incomplete'));
      expect(_names(dir), isEmpty);
    });

    test('reports HTTP errors and invalid links', () async {
      final u = ApkUpdater(platform: platform, clientFactory: _serve(const [], status: 404));
      await u.start(url: _url, versionName: _version);
      expect(u.phase, UpdatePhase.failed);
      expect(u.error, contains('404'));

      await u.start(url: 'http://insecure.example/app.apk', versionName: _version);
      expect(u.phase, UpdatePhase.failed);
      expect(u.error, contains('invalid'));
    });

    test('cancel stops the download and deletes the partial file', () async {
      final controller = StreamController<List<int>>();
      final u = ApkUpdater(platform: platform, clientFactory: () => MockClient.streaming((req, _) async =>
          http.StreamedResponse(controller.stream, 200, contentLength: 10000)));
      final run = u.start(url: _url, versionName: _version);
      controller.add(_apk.sublist(0, 1000));
      await _until(() => u.received == 1000);
      expect(u.phase, UpdatePhase.downloading);
      expect(u.received, 1000);
      expect(u.progress, closeTo(.1, .001));
      await u.cancel();
      await run;
      expect(u.phase, UpdatePhase.idle);
      expect(platform.installs, isEmpty);
      expect(_names(dir), isEmpty);
      await controller.close();
    });

    test('a stalled connection fails instead of hanging forever', () async {
      final controller = StreamController<List<int>>();
      final u = ApkUpdater(platform: platform, stallTimeout: const Duration(milliseconds: 100),
          clientFactory: () => MockClient.streaming((req, _) async =>
              http.StreamedResponse(controller.stream, 200, contentLength: 10000)));
      final run = u.start(url: _url, versionName: _version);
      controller.add(_apk.sublist(0, 100));
      await run;
      expect(u.phase, UpdatePhase.failed);
      expect(u.error, contains('stopped responding'));
      expect(_names(dir), isEmpty);
      await controller.close();
    });

    test('an already downloaded APK is installed again without re-downloading', () async {
      var requests = 0;
      final u = ApkUpdater(platform: platform, clientFactory: _serve(_apk, onRequest: () => requests++));
      await u.start(url: _url, versionName: _version);
      await u.start(url: _url, versionName: _version);
      expect(requests, 1);
      expect(platform.installs, hasLength(2));
    });
  });

  group('UpdateDialog', () {
    Future<ApkUpdater> pumpDialog(WidgetTester t, {bool force = false}) async {
      await loadFonts();
      t.view.physicalSize = const Size(1080, 2340);
      t.view.devicePixelRatio = 2.625;
      addTearDown(t.view.reset);
      final u = ApkUpdater(platform: platform);
      await t.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.build(AppTheme.lightScheme),
        builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!),
        home: Scaffold(body: Center(child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: UpdateDialog(versionName: _version, releaseNotes: 'Auto-generated release', downloadUrl: _url,
              forceUpdate: force, updater: u),
        ))),
      ));
      await t.pump();
      return u;
    }

    testWidgets('idle shows release info with Update now and Later', (t) async {
      await pumpDialog(t);
      expect(find.text('Update available'), findsOneWidget);
      expect(find.text('v$_version'), findsOneWidget);
      expect(find.text('Later'), findsOneWidget);
      expect(find.text('Update now'), findsOneWidget);
    });

    testWidgets('downloading shows live percentage, size, speed and time left; cancel returns to idle', (t) async {
      final u = await pumpDialog(t);
      const mb = 1048576;
      u.debugSetState(UpdatePhase.downloading, version: _version, received: 47 * mb, total: 100 * mb, bytesPerSecond: 2.0 * mb);
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Downloading update'), findsOneWidget);
      expect(find.text('47%'), findsOneWidget);
      expect(find.text('47.0 MB of 100.0 MB'), findsOneWidget);
      expect(find.text('2.0 MB/s · 27s left'), findsOneWidget);
      expect(find.text('Hide'), findsOneWidget);

      await t.tap(find.text('Cancel'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(u.phase, UpdatePhase.idle);
      expect(find.text('Update available'), findsOneWidget);
    });

    testWidgets('forced update cannot be hidden while downloading', (t) async {
      final u = await pumpDialog(t, force: true);
      u.debugSetState(UpdatePhase.downloading, version: _version, received: 10, total: 100);
      await t.pump();
      expect(find.text('Required'), findsOneWidget);
      expect(find.text('Hide'), findsNothing);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('ready, permission and failed states guide the user', (t) async {
      final u = await pumpDialog(t);
      u.debugSetState(UpdatePhase.ready, version: _version);
      await t.pump();
      expect(find.text('Ready to install'), findsOneWidget);
      expect(find.text('Install now'), findsOneWidget);

      u.debugSetState(UpdatePhase.needsPermission, version: _version);
      await t.pump();
      expect(find.text('Allow installs from Vktrix Mobile'), findsOneWidget);
      await t.tap(find.text('Open settings'));
      await t.pump();
      expect(platform.settingsOpened, 1);

      u.debugSetState(UpdatePhase.failed, version: _version, error: 'Download failed. Check your internet connection and try again.');
      await t.pump();
      expect(find.text('Update paused'), findsOneWidget);
      expect(find.textContaining('Check your internet'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Download in browser instead'), findsOneWidget);
    });
  });
}
