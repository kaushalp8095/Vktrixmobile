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
}
