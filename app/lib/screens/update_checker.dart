import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../design/components/components.dart';
import '../design/design.dart';

class UpdateChecker {
  static const String versionJsonUrl =
      'https://raw.githubusercontent.com/kaushalp8095/Vktrixmobile/main/app/version.json';

  static Future<void> checkForUpdate(BuildContext context) async {
    try {
      final response = await http
          .get(Uri.parse(versionJsonUrl))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return;

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return;

      final latestVersionCode = int.tryParse('${decoded['versionCode']}');
      final latestVersionName = decoded['versionName'];
      final downloadUrl = decoded['downloadUrl'];
      final releaseNotes = decoded['releaseNotes'];
      final forceUpdate = decoded['forceUpdate'] == true;
      if (latestVersionCode == null ||
          latestVersionName is! String ||
          downloadUrl is! String ||
          releaseNotes is! String) {
        return;
      }

      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersionCode = int.tryParse(packageInfo.buildNumber) ?? 0;
      if (latestVersionCode > currentVersionCode && context.mounted) {
        _showUpdateDialog(
          context,
          versionName: latestVersionName,
          releaseNotes: releaseNotes,
          downloadUrl: downloadUrl,
          forceUpdate: forceUpdate,
        );
      }
    } catch (e) {
      debugPrint('Error checking for updates: $e');
    }
  }

  static void _showUpdateDialog(
    BuildContext context, {
    required String versionName,
    required String releaseNotes,
    required String downloadUrl,
    required bool forceUpdate,
  }) {
    final motion = Motion.of(context);
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: !forceUpdate,
      barrierLabel: 'Dismiss update dialog',
      barrierColor: Colors.black.withValues(alpha: .62),
      transitionDuration: motion.d(const Duration(milliseconds: 420)),
      pageBuilder: (dialogContext, _, __) => PopScope(
        canPop: !forceUpdate,
        child: Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: Space.screen,
            vertical: Space.x24,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 440,
              maxHeight: MediaQuery.sizeOf(dialogContext).height * .84,
            ),
            child: _UpdateDialog(
              versionName: versionName,
              releaseNotes: releaseNotes,
              downloadUrl: downloadUrl,
              forceUpdate: forceUpdate,
            ),
          ),
        ),
      ),
      transitionBuilder: (_, animation, __, child) {
        final fade = animation.drive(CurveTween(curve: Curves.easeOutCubic));
        final scale = animation.drive(Tween<double>(begin: .94, end: 1).chain(
          CurveTween(curve: Curves.easeOutBack),
        ));
        final slide = animation.drive(Tween<Offset>(
          begin: const Offset(0, .035),
          end: Offset.zero,
        ).chain(CurveTween(curve: Curves.easeOutCubic)));
        return FadeTransition(
          opacity: fade,
          child: SlideTransition(
            position: slide,
            child: ScaleTransition(scale: scale, child: child),
          ),
        );
      },
    );
  }
}

class _UpdateDialog extends StatefulWidget {
  final String versionName;
  final String releaseNotes;
  final String downloadUrl;
  final bool forceUpdate;

  const _UpdateDialog({
    required this.versionName,
    required this.releaseNotes,
    required this.downloadUrl,
    required this.forceUpdate,
  });

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _opening = false;
  String? _error;
  String? _info;

  Future<void> _openDownload() async {
    if (_opening) return;

    final uri = Uri.tryParse(widget.downloadUrl);
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
      setState(() => _error = 'The update link is invalid. Please try again later.');
      return;
    }

    setState(() {
      _opening = true;
      _error = null;
      _info = null;
    });

    try {
      // Launch directly: canLaunchUrl can return false on Android 11+ when
      // package visibility queries are not declared, even for a valid browser.
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        throw StateError('No external app handled the update URL.');
      }

      if (!mounted) return;
      setState(() {
        _opening = false;
        _info = 'The download opened in your browser. When it finishes, tap the APK to install.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _opening = false;
        _error = 'Could not open the download. Check your internet and try again.';
      });
      debugPrint('Could not open update URL: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;
    final releaseNotes = widget.releaseNotes.trim();
    final notes = releaseNotes.isEmpty ||
            releaseNotes.toLowerCase().startsWith('auto-generated release')
        ? 'The latest Vktrix Mobile release is ready to install.'
        : releaseNotes;

    return GlassSurface(
      radius: Radii.xl,
      scrim: true,
      child: Stack(
        children: [
          Positioned(
            top: -76,
            right: -58,
            child: IgnorePointer(
              child: Container(
                width: 210,
                height: 210,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      c.brandInk.withValues(alpha: .22),
                      c.brandInk.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SingleChildScrollView(
            padding: const EdgeInsets.all(Space.x24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(Radii.md),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [c.brandInk, c.accent],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: c.brandInk.withValues(alpha: .28),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.system_update_alt_rounded,
                        size: 28,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: Space.x16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Vktrix Mobile',
                            style: t.labelLarge?.copyWith(color: c.textSecondary),
                          ),
                          const SizedBox(height: Space.x4),
                          Semantics(
                            header: true,
                            child: Text(
                              'Update available',
                              style: t.headlineSmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Space.x16),
                Wrap(
                  spacing: Space.x8,
                  runSpacing: Space.x8,
                  children: [
                    StatusChip(
                      label: 'v${widget.versionName}',
                      tone: ChipTone.brand,
                      icon: Icons.new_releases_outlined,
                    ),
                    if (widget.forceUpdate)
                      const StatusChip(
                        label: 'Required',
                        tone: ChipTone.warning,
                        icon: Icons.priority_high_rounded,
                      ),
                  ],
                ),
                const SizedBox(height: Space.x16),
                Text(
                  'A fresh update is ready for your shop.',
                  style: t.bodyLarge?.copyWith(color: c.textSecondary),
                ),
                const SizedBox(height: Space.x20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(Space.x16),
                  decoration: BoxDecoration(
                    color: c.textPrimary.withValues(alpha: .045),
                    borderRadius: Shapes.md,
                    border: Border.all(
                      color: context.scheme.outline.withValues(alpha: .35),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.auto_awesome_rounded, size: 16, color: c.brandInk),
                          const SizedBox(width: Space.x8),
                          Text(
                            "WHAT'S NEW",
                            style: t.labelSmall?.copyWith(
                              color: c.brandInk,
                              letterSpacing: 1.1,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: Space.x8),
                      Text(notes, style: t.bodyMedium),
                    ],
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: Space.x12),
                  _UpdateMessage(message: _error!, color: c.error, icon: Icons.error_outline_rounded),
                ],
                if (_info != null) ...[
                  const SizedBox(height: Space.x12),
                  _UpdateMessage(message: _info!, color: c.successInk, icon: Icons.check_circle_outline_rounded),
                ],
                const SizedBox(height: Space.x24),
                if (widget.forceUpdate)
                  PrimaryButton(
                    label: 'Update now',
                    icon: Icons.download_rounded,
                    phase: _opening ? ButtonPhase.loading : ButtonPhase.idle,
                    onPressed: _opening ? null : _openDownload,
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Later'),
                        ),
                      ),
                      const SizedBox(width: Space.x8),
                      Expanded(
                        flex: 2,
                        child: PrimaryButton(
                          label: 'Update now',
                          icon: Icons.download_rounded,
                          phase: _opening ? ButtonPhase.loading : ButtonPhase.idle,
                          onPressed: _opening ? null : _openDownload,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UpdateMessage extends StatelessWidget {
  final String message;
  final Color color;
  final IconData icon;

  const _UpdateMessage({
    required this.message,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(Space.x12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .10),
          borderRadius: Shapes.sm,
          border: Border.all(color: color.withValues(alpha: .28)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: Space.x8),
            Expanded(
              child: Text(
                message,
                style: context.type.bodySmall?.copyWith(color: context.colors.textPrimary),
              ),
            ),
          ],
        ),
      );
}
