import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateChecker {
  // Replace this URL with your raw version.json GitHub URL
  static const String versionJsonUrl = 'https://raw.githubusercontent.com/kaushalp8095/Vktrixmobile/main/app/version.json';

  static Future<void> checkForUpdate(BuildContext context) async {
    try {
      final response = await http.get(Uri.parse(versionJsonUrl));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final latestVersionCode = data['versionCode'] as int;
        final latestVersionName = data['versionName'] as String;
        final downloadUrl = data['downloadUrl'] as String;
        final releaseNotes = data['releaseNotes'] as String;
        final forceUpdate = data['forceUpdate'] as bool;

        final packageInfo = await PackageInfo.fromPlatform();
        // Fallback to 0 if we can't parse the version code
        final currentVersionCode = int.tryParse(packageInfo.buildNumber) ?? 0;

        if (latestVersionCode > currentVersionCode) {
          if (context.mounted) {
            _showUpdateDialog(
              context,
              latestVersionName,
              releaseNotes,
              downloadUrl,
              forceUpdate,
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Error checking for updates: $e');
    }
  }

  static void _showUpdateDialog(
    BuildContext context,
    String versionName,
    String releaseNotes,
    String downloadUrl,
    bool forceUpdate,
  ) {
    showDialog(
      context: context,
      barrierDismissible: !forceUpdate,
      builder: (BuildContext context) {
        return PopScope(
          canPop: !forceUpdate,
          child: AlertDialog(
            title: const Text('Update Available ✨', style: TextStyle(fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('A new version ($versionName) is available!'),
                const SizedBox(height: 12),
                const Text('What\'s new:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(releaseNotes),
              ],
            ),
            actions: [
              if (!forceUpdate)
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Later', style: TextStyle(color: Colors.grey)),
                ),
              ElevatedButton(
                onPressed: () async {
                  final Uri url = Uri.parse(downloadUrl);
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Update Now'),
              ),
            ],
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        );
      },
    );
  }
}
