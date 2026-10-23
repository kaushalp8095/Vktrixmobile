import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('APK updates and bill PDFs use one restricted FileProvider', () async {
    final manifest = await File('android/app/src/main/AndroidManifest.xml').readAsString();
    final providers = RegExp(r'<provider\b[\s\S]*?</provider>')
        .allMatches(manifest)
        .map((match) => match.group(0)!)
        .toList();

    expect(providers, hasLength(1));
    expect(providers.single, contains(r'android:authorities="${applicationId}.updates"'));
    expect(providers.single, contains('android:exported="false"'));
    expect(providers.single, contains('android:grantUriPermissions="true"'));

    final paths = await File('android/app/src/main/res/xml/update_paths.xml').readAsString();
    expect(RegExp(r'<cache-path\b').allMatches(paths), hasLength(2));
    expect(paths, contains('name="updates" path="updates/"'));
    expect(paths, contains('name="bills" path="bills/"'));
    expect(paths, isNot(contains('<external-path')));

    final activity = await File(
      'android/app/src/main/kotlin/com/vktrix/mobileapp/MainActivity.kt',
    ).readAsString();
    expect(
      RegExp(r'FileProvider\.getUriForFile\(this, "\$packageName\.updates"')
          .allMatches(activity),
      hasLength(2),
      reason: 'both the updater APK and bill PDF must use the declared authority',
    );
    expect(activity, isNot(contains(r'$packageName.bills')));
    expect(activity, contains('grantUriPermission(target, uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)'));
    expect(activity, contains('Intent.createChooser(shareIntent, "Share PDF bill")'));
    expect(activity, contains('writeSharedPdf(bytes, name)'));
  });

  test('manifest blocks cleartext HTTP and excludes app data from backups', () async {
    final manifest = await File('android/app/src/main/AndroidManifest.xml').readAsString();

    // Ek bhi http:// call na chale — token/customer data MITM se bache.
    expect(manifest, contains('android:usesCleartextTraffic="false"'));
    expect(manifest, contains('android:networkSecurityConfig="@xml/network_security_config"'));
    // SharedPreferences me login token hota hai — ADB/cloud backup se bahar na jaye.
    expect(manifest, contains('android:allowBackup="false"'));
    expect(manifest, contains('android:dataExtractionRules="@xml/data_extraction_rules"'));

    final network = await File('android/app/src/main/res/xml/network_security_config.xml').readAsString();
    expect(network, contains('cleartextTrafficPermitted="false"'));
    expect(network, contains('src="system"'));

    final rules = await File('android/app/src/main/res/xml/data_extraction_rules.xml').readAsString();
    expect(RegExp(r'<cloud-backup>[\s\S]*?</cloud-backup>').firstMatch(rules)?.group(0),
        contains('<exclude domain="sharedpref" path="." />'));
    expect(RegExp(r'<device-transfer>[\s\S]*?</device-transfer>').firstMatch(rules)?.group(0),
        contains('<exclude domain="sharedpref" path="." />'));
  });
}
