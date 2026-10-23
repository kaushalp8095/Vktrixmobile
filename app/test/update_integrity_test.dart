// In-app APK update ka integrity check: version.json me diya SHA-256 match na ho
// to installer nahi khulta aur adhoori file delete ho jaati hai.
//
// Iske bina koi bhi CDN cache/proxy (ya MITM, agar kabhi URL http ho jaye) badla
// hua APK de sakta tha. Ab release workflow hash publish karta hai aur app use
// verify karti hai.
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile_shop/update/apk_updater.dart';

class _FakePlatform extends UpdatePlatform {
  _FakePlatform(this.dir);
  final Directory dir;
  final installs = <String>[];

  @override
  bool get supported => true;
  @override
  Future<String> updateDir() async => dir.path;
  @override
  Future<bool> canInstall() async => true;
  @override
  Future<void> openInstallSettings() async {}
  @override
  Future<String> installApk(String path) async {
    installs.add(path);
    return 'started';
  }
}

const _url = 'https://github.com/kaushalp8095/Vktrixmobile/releases/download/v1.0.0.20780/app-release.apk';
const _version = '1.0.0.20780';
final _apk = [0x50, 0x4B, ...List.filled(4096, 7)];
final _sha = crypto.sha256.convert(_apk).toString();

http.Client Function() _serve(List<int> bytes) => () => MockClient.streaming((req, _) async {
      final chunks = [for (var i = 0; i < bytes.length; i += 512) bytes.sublist(i, math.min(i + 512, bytes.length))];
      return http.StreamedResponse(Stream.fromIterable(chunks), 200, contentLength: bytes.length);
    });

List<String> _names(Directory d) => d.listSync().map((e) => e.uri.pathSegments.last).toList()..sort();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late _FakePlatform platform;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('vktrix-integrity-');
    platform = _FakePlatform(dir);
  });
  tearDown(() { try { dir.deleteSync(recursive: true); } catch (_) {} });

  test('a matching SHA-256 installs normally', () async {
    final u = ApkUpdater(platform: platform, clientFactory: _serve(_apk));
    await u.start(url: _url, versionName: _version, sha256: _sha.toUpperCase());
    expect(u.phase, UpdatePhase.ready);
    expect(u.expectedSha256, _sha, reason: 'hash case-insensitive hota hai');
    expect(platform.installs, ['${dir.path}/vktrix-$_version.apk']);
  });

  test('a tampered APK is deleted and never reaches the installer', () async {
    final u = ApkUpdater(platform: platform, clientFactory: _serve(_apk));
    await u.start(url: _url, versionName: _version, sha256: '0'.padRight(64, '0'));
    expect(u.phase, UpdatePhase.failed);
    expect(u.error, contains('integrity'));
    expect(platform.installs, isEmpty);
    expect(_names(dir), isEmpty, reason: 'bad file cache me nahi chhodte');
  });

  test('a stale complete file with the wrong hash is re-downloaded', () async {
    File('${dir.path}/vktrix-$_version.apk').writeAsBytesSync([0x50, 0x4B, 1, 2, 3]);
    final u = ApkUpdater(platform: platform, clientFactory: _serve(_apk));
    await u.start(url: _url, versionName: _version, sha256: _sha);
    expect(u.phase, UpdatePhase.ready);
    expect(u.received, _apk.length);
    expect(platform.installs, hasLength(1));
  });

  test('no hash in the release means no verification (older version.json)', () async {
    final u = ApkUpdater(platform: platform, clientFactory: _serve(_apk));
    await u.start(url: _url, versionName: _version);
    expect(u.phase, UpdatePhase.ready);
    expect(u.expectedSha256, isNull);
  });

  test('a malformed hash is ignored instead of failing every update', () async {
    final u = ApkUpdater(platform: platform, clientFactory: _serve(_apk));
    await u.start(url: _url, versionName: _version, sha256: 'not-a-hash');
    expect(u.phase, UpdatePhase.ready);
    expect(u.expectedSha256, isNull);
  });
}
