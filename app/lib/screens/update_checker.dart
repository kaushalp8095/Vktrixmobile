import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../design/components/components.dart';
import '../design/design.dart';
import '../update/apk_updater.dart';

class UpdateChecker {
  static const String versionJsonUrl =
      'https://raw.githubusercontent.com/kaushalp8095/Vktrixmobile/main/app/version.json';

  static bool _dialogOpen = false;

  static Future<void> checkForUpdate(BuildContext context) async {
    if (_dialogOpen) return;
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
    _dialogOpen = true;
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
            child: UpdateDialog(
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
    ).whenComplete(() { _dialogOpen = false; });
  }
}

/// Update popup: release notes → in-app download with live progress → system installer.
class UpdateDialog extends StatefulWidget {
  final String versionName;
  final String releaseNotes;
  final String downloadUrl;
  final bool forceUpdate;
  final ApkUpdater? updater; // test hook; defaults to the app-wide updater

  const UpdateDialog({
    super.key,
    required this.versionName,
    required this.releaseNotes,
    required this.downloadUrl,
    required this.forceUpdate,
    this.updater,
  });

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _openingBrowser = false;
  String? _browserMessage;

  ApkUpdater get _u => widget.updater ?? ApkUpdater.instance;

  /// Phase for *this* version (an older failed download is shown as fresh).
  UpdatePhase get _phase => _u.versionName == widget.versionName ? _u.phase : UpdatePhase.idle;

  Future<void> _update() async {
    if (!_u.platform.supported) return _openInBrowser();
    await _u.start(url: widget.downloadUrl, versionName: widget.versionName);
  }

  Future<void> _openInBrowser() async {
    final uri = Uri.tryParse(widget.downloadUrl);
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
      setState(() => _browserMessage = 'The update link is invalid. Please try again later.');
      return;
    }
    setState(() { _openingBrowser = true; _browserMessage = null; });
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) throw StateError('No external app handled the update URL.');
      if (mounted) setState(() => _browserMessage = 'Download opened in your browser. Tap the APK when it finishes.');
    } catch (e) {
      debugPrint('Could not open update URL: $e');
      if (mounted) setState(() => _browserMessage = 'Could not open the download. Check your internet and try again.');
    }
    if (mounted) setState(() => _openingBrowser = false);
  }

  void _hide() => Navigator.of(context).maybePop();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(listenable: _u, builder: (context, _) => _card(context));
  }

  Widget _card(BuildContext context) {
    final c = context.colors;
    final t = context.type;
    final motion = Motion.of(context);
    final phase = _phase;
    final releaseNotes = widget.releaseNotes.trim();
    final notes = releaseNotes.isEmpty || releaseNotes.toLowerCase().startsWith('auto-generated release')
        ? 'The latest Vktrix Mobile release is ready to install.'
        : releaseNotes;

    final (title, subtitle) = switch (phase) {
      UpdatePhase.downloading => ('Downloading update', 'Keep using the app — we\'ll open the installer when it\'s ready.'),
      UpdatePhase.installing || UpdatePhase.ready => ('Ready to install', 'Download complete. Tap Install on the next screen.'),
      UpdatePhase.needsPermission => ('One quick permission', 'Allow Vktrix Mobile to install updates, then come back.'),
      UpdatePhase.failed => ('Update paused', 'Something went wrong, but nothing was changed on your phone.'),
      UpdatePhase.idle => ('Update available', 'A fresh update is ready for your shop.'),
    };

    final Widget body = switch (phase) {
      UpdatePhase.downloading => _DownloadPanel(updater: _u, key: const ValueKey('downloading')),
      UpdatePhase.installing || UpdatePhase.ready => _StatusPanel(
          key: const ValueKey('ready'),
          icon: Icons.verified_rounded, color: c.successInk,
          title: 'Download complete',
          message: 'The Android installer opens automatically. Your data stays safe — only the app is updated.'),
      UpdatePhase.needsPermission => _StatusPanel(
          key: const ValueKey('permission'),
          icon: Icons.admin_panel_settings_outlined, color: c.warningInk,
          title: 'Allow installs from Vktrix Mobile',
          message: 'In Settings, turn on "Allow from this source". When you come back, installation continues automatically.'),
      UpdatePhase.failed => _StatusPanel(
          key: const ValueKey('failed'),
          icon: Icons.wifi_off_rounded, color: c.errorInk,
          title: 'Download failed', message: _u.error ?? 'Please try again.'),
      UpdatePhase.idle => _NotesPanel(notes: notes, key: const ValueKey('notes')),
    };

    return GlassSurface(
      radius: Radii.xl,
      scrim: true,
      child: Stack(children: [
        Positioned(
          top: -76, right: -58,
          child: IgnorePointer(child: Container(
            width: 210, height: 210,
            decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(
              colors: [c.brandInk.withValues(alpha: .22), c.brandInk.withValues(alpha: 0)])),
          )),
        ),
        SingleChildScrollView(
          padding: const EdgeInsets.all(Space.x24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              _AppBadge(phase: phase, progress: phase == UpdatePhase.downloading ? _u.progress : null),
              const SizedBox(width: Space.x16),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Vktrix Mobile', style: t.labelLarge?.copyWith(color: c.textSecondary)),
                const SizedBox(height: Space.x4),
                Semantics(header: true, liveRegion: true, child: Text(title, style: t.headlineSmall)),
              ])),
            ]),
            const SizedBox(height: Space.x16),
            Wrap(spacing: Space.x8, runSpacing: Space.x8, children: [
              StatusChip(label: 'v${widget.versionName}', tone: ChipTone.brand, icon: Icons.new_releases_outlined),
              if (widget.forceUpdate)
                const StatusChip(label: 'Required', tone: ChipTone.warning, icon: Icons.priority_high_rounded),
            ]),
            const SizedBox(height: Space.x16),
            Text(subtitle, style: t.bodyLarge?.copyWith(color: c.textSecondary)),
            const SizedBox(height: Space.x20),
            AnimatedSwitcher(
              duration: motion.d(const Duration(milliseconds: 280)),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, a) => FadeTransition(opacity: a, child: SizeTransition(sizeFactor: a, alignment: Alignment.topCenter, child: child)),
              child: body,
            ),
            if (_browserMessage != null) ...[
              const SizedBox(height: Space.x12),
              _UpdateMessage(message: _browserMessage!, color: c.brandInk, icon: Icons.open_in_new_rounded),
            ],
            const SizedBox(height: Space.x24),
            _actions(context, phase),
          ]),
        ),
      ]),
    );
  }

  Widget _actions(BuildContext context, UpdatePhase phase) {
    final canLater = !widget.forceUpdate;
    Widget withSecondary(Widget primary, {String? label, VoidCallback? onTap}) {
      if (label == null) return primary;
      return Row(children: [
        Expanded(child: TextButton(onPressed: onTap, child: Text(label))),
        const SizedBox(width: Space.x8),
        Expanded(flex: 2, child: primary),
      ]);
    }

    switch (phase) {
      case UpdatePhase.downloading:
        // "Hide" keeps downloading in the background; "Cancel" stops and deletes it.
        return Row(children: [
          Expanded(child: TextButton(onPressed: _u.cancel, child: const Text('Cancel'))),
          if (canLater) ...[
            const SizedBox(width: Space.x8),
            Expanded(flex: 2, child: FilledButton.tonalIcon(
              onPressed: _hide,
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
              label: const Text('Hide'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52), shape: Shapes.stadium),
            )),
          ],
        ]);
      case UpdatePhase.installing:
      case UpdatePhase.ready:
        return withSecondary(
          PrimaryButton(label: 'Install now', icon: Icons.install_mobile_rounded,
              phase: phase == UpdatePhase.installing ? ButtonPhase.loading : ButtonPhase.idle,
              onPressed: phase == UpdatePhase.installing ? null : _u.install),
          label: canLater ? 'Later' : null, onTap: _hide);
      case UpdatePhase.needsPermission:
        return withSecondary(
          PrimaryButton(label: 'Open settings', icon: Icons.settings_outlined, onPressed: _u.openInstallSettings),
          label: 'Install', onTap: _u.install);
      case UpdatePhase.failed:
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          withSecondary(
            PrimaryButton(label: 'Retry', icon: Icons.refresh_rounded, onPressed: _update),
            label: canLater ? 'Later' : null, onTap: _hide),
          const SizedBox(height: Space.x8),
          TextButton.icon(
            onPressed: _openingBrowser ? null : _openInBrowser,
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: const Text('Download in browser instead'),
          ),
        ]);
      case UpdatePhase.idle:
        return withSecondary(
          PrimaryButton(label: 'Update now', icon: Icons.download_rounded,
              phase: _openingBrowser ? ButtonPhase.loading : ButtonPhase.idle,
              onPressed: _openingBrowser ? null : _update),
          label: canLater ? 'Later' : null, onTap: _hide);
    }
  }
}

/// Gradient app badge; while downloading, a progress ring wraps it.
class _AppBadge extends StatelessWidget {
  final UpdatePhase phase;
  final double? progress;
  const _AppBadge({required this.phase, required this.progress});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final icon = switch (phase) {
      UpdatePhase.downloading => Icons.downloading_rounded,
      UpdatePhase.installing || UpdatePhase.ready => Icons.install_mobile_rounded,
      UpdatePhase.needsPermission => Icons.lock_open_rounded,
      UpdatePhase.failed => Icons.refresh_rounded,
      UpdatePhase.idle => Icons.system_update_alt_rounded,
    };
    final badge = Container(
      width: 56, height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.md),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [c.brandInk, c.accent]),
        boxShadow: [BoxShadow(color: c.brandInk.withValues(alpha: .28), blurRadius: 24, offset: const Offset(0, 8))],
      ),
      child: Icon(icon, size: 28, color: Colors.white),
    );
    if (phase != UpdatePhase.downloading) return badge;
    return SizedBox(width: 64, height: 64, child: Stack(alignment: Alignment.center, children: [
      SizedBox.expand(child: CircularProgressIndicator(
        value: progress, strokeWidth: 3, strokeCap: StrokeCap.round,
        color: c.accent, backgroundColor: c.textPrimary.withValues(alpha: .08))),
      Transform.scale(scale: .82, child: badge),
    ]));
  }
}

class _NotesPanel extends StatelessWidget {
  final String notes;
  const _NotesPanel({super.key, required this.notes});

  @override
  Widget build(BuildContext context) {
    final c = context.colors, t = context.type;
    return _Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.auto_awesome_rounded, size: 16, color: c.brandInk),
        const SizedBox(width: Space.x8),
        Text("WHAT'S NEW", style: t.labelSmall?.copyWith(color: c.brandInk, letterSpacing: 1.1)),
      ]),
      const SizedBox(height: Space.x8),
      Text(notes, style: t.bodyMedium),
    ]));
  }
}

/// Live download progress: big gradient percentage, animated bar, size, speed and time left.
class _DownloadPanel extends StatelessWidget {
  final ApkUpdater updater;
  const _DownloadPanel({super.key, required this.updater});

  static String _size(int bytes) => bytes >= 1048576
      ? '${(bytes / 1048576).toStringAsFixed(1)} MB'
      : '${(bytes / 1024).toStringAsFixed(0)} KB';

  static String _eta(Duration d) => d.inSeconds < 60
      ? '${d.inSeconds}s left'
      : '${d.inMinutes} min ${(d.inSeconds % 60).toString().padLeft(2, '0')}s left';

  @override
  Widget build(BuildContext context) {
    final c = context.colors, t = context.type;
    final p = updater.progress;
    final total = updater.total;
    final speed = updater.bytesPerSecond;
    final eta = updater.eta;
    final duration = Motion.of(context).d(const Duration(milliseconds: 260));
    return _Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(child: Padding(
          padding: const EdgeInsets.only(bottom: Space.x8),
          child: Row(children: [
            Icon(Icons.cloud_download_outlined, size: 16, color: c.brandInk),
            const SizedBox(width: Space.x8),
            Flexible(child: Text('DOWNLOADING', style: t.labelSmall?.copyWith(color: c.brandInk, letterSpacing: 1.1))),
          ]),
        )),
        TweenAnimationBuilder<double>(
          tween: Tween(end: (p ?? 0) * 100),
          duration: duration,
          builder: (context, v, _) {
            final pct = (v + 1e-6).floor().clamp(0, 100); // 0.29*100 = 28.999… must still read 29%
            return ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (r) => LinearGradient(colors: [c.brandInk, c.accent]).createShader(r),
            child: Text(p == null ? '…' : '$pct%',
                semanticsLabel: p == null ? 'Downloading' : '$pct percent downloaded',
                style: t.displaySmall?.copyWith(fontWeight: FontWeight.w800, height: 1, color: Colors.white)),
            );
          },
        ),
      ]),
      const SizedBox(height: Space.x12),
      TweenAnimationBuilder<double>(
        tween: Tween(end: p ?? 0),
        duration: duration,
        builder: (context, v, _) => _GradientProgressBar(value: p == null ? null : v),
      ),
      const SizedBox(height: Space.x12),
      Row(children: [
        Expanded(child: Text(
          total == null ? '${_size(updater.received)} downloaded' : '${_size(updater.received)} of ${_size(total)}',
          style: t.bodySmall?.copyWith(color: c.textSecondary))),
        if (speed > 0)
          Text([
            '${_size(speed.round())}/s',
            if (eta != null) _eta(eta),
          ].join(' · '), style: t.bodySmall?.copyWith(color: c.textSecondary)),
      ]),
    ]));
  }
}

/// Rounded brand-gradient bar with a soft moving shine (indeterminate when value is null).
class _GradientProgressBar extends StatefulWidget {
  final double? value;
  const _GradientProgressBar({required this.value});
  @override
  State<_GradientProgressBar> createState() => _GradientProgressBarState();
}

class _GradientProgressBarState extends State<_GradientProgressBar> with SingleTickerProviderStateMixin {
  late final AnimationController _shine = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.of(context).reduced) {
      _shine.stop();
    } else if (!_shine.isAnimating) {
      _shine.repeat();
    }
  }

  @override
  void dispose() { _shine.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final value = widget.value;
    return Semantics(
      label: 'Download progress',
      value: value == null ? 'in progress' : '${(value * 100).round()} percent',
      child: SizedBox(
        height: 12,
        child: ClipRRect(
          borderRadius: Shapes.pill,
          child: LayoutBuilder(builder: (context, box) {
            final w = box.maxWidth;
            return AnimatedBuilder(
              animation: _shine,
              builder: (context, _) {
                final s = _shine.value;
                final fillW = value == null ? w * .35 : w * value;
                final left = value == null ? (w + fillW) * s - fillW : 0.0;
                return Stack(children: [
                  Positioned.fill(child: ColoredBox(color: c.textPrimary.withValues(alpha: .08))),
                  Positioned(
                    left: left, top: 0, bottom: 0, width: fillW,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: Shapes.pill,
                        gradient: LinearGradient(colors: [c.brandInk, c.accent]),
                        boxShadow: [BoxShadow(color: c.accent.withValues(alpha: .45), blurRadius: 10)],
                      ),
                      child: value == null || fillW < 24 ? null : ClipRRect(
                        borderRadius: Shapes.pill,
                        child: FractionalTranslation(
                          translation: Offset(s * 2.4 - 1.2, 0),
                          child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(colors: [
                            Colors.white.withValues(alpha: 0),
                            Colors.white.withValues(alpha: .38),
                            Colors.white.withValues(alpha: 0),
                          ]))),
                        ),
                      ),
                    ),
                  ),
                ]);
              },
            );
          }),
        ),
      ),
    );
  }
}

class _StatusPanel extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String message;
  const _StatusPanel({super.key, required this.icon, required this.color, required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    return _Panel(tint: color, child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 36, height: 36,
        decoration: BoxDecoration(color: color.withValues(alpha: .14), shape: BoxShape.circle),
        child: Icon(icon, size: 20, color: color),
      ),
      const SizedBox(width: Space.x12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: t.titleSmall),
        const SizedBox(height: Space.x4),
        Text(message, style: t.bodySmall?.copyWith(color: context.colors.textSecondary)),
      ])),
    ]));
  }
}

class _Panel extends StatelessWidget {
  final Widget child;
  final Color? tint;
  const _Panel({required this.child, this.tint});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Space.x16),
      decoration: BoxDecoration(
        color: (tint ?? c.textPrimary).withValues(alpha: tint == null ? .045 : .07),
        borderRadius: Shapes.md,
        border: Border.all(color: tint?.withValues(alpha: .28) ?? context.scheme.outline.withValues(alpha: .35)),
      ),
      child: child,
    );
  }
}

class _UpdateMessage extends StatelessWidget {
  final String message;
  final Color color;
  final IconData icon;

  const _UpdateMessage({required this.message, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(Space.x12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .10),
          borderRadius: Shapes.sm,
          border: Border.all(color: color.withValues(alpha: .28)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: Space.x8),
          Expanded(child: Text(message, style: context.type.bodySmall?.copyWith(color: context.colors.textPrimary))),
        ]),
      );
}
