// CONFIRM DIALOG: ek hi reusable, Indigo/Mint se matched confirmation popup.
// Shop side aur Super Admin side — dono yahi use karte hain (logout, shop
// deactivate, delete, support access). Buttons: safe action pehle, confirm baad me.
//
// Structure: brand hairline → icon disc + title → message → identity chip → note
// → [Cancel] [Confirm]. Enter: fade + scale .94→1 (320ms FastOutSlowIn), reduced
// motion par instant.
import 'package:flutter/material.dart';
import '../colors.dart';
import '../design.dart';

Color _scrim(BuildContext context) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return IndigoMint.scrimBlack.withValues(alpha: dark ? .66 : .44);
}

/// Returns true only when the user chose the confirm action.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  IconData icon = Icons.help_outline,
  bool destructive = false,
  String? identity,
  IconData identityIcon = Icons.storefront_outlined,
  String? note,
}) async {
  final result = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: cancelLabel,
    barrierColor: _scrim(context),
    transitionDuration: Motion.of(context).d(Durations2.enter),
    pageBuilder: (ctx, _, __) => ConfirmDialogCard(
      title: title, message: message, confirmLabel: confirmLabel, cancelLabel: cancelLabel,
      icon: icon, destructive: destructive, identity: identity, identityIcon: identityIcon, note: note,
    ),
    transitionBuilder: (ctx, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves2.enter, reverseCurve: Curves2.exit);
      return FadeTransition(opacity: curved,
        child: ScaleTransition(scale: Tween<double>(begin: .94, end: 1).animate(curved), child: child));
    },
  );
  return result ?? false;
}

/// Logout confirmation — shop owner aur Super Admin, dono ke liye same popup.
/// Logout sirf yahan "Log out" dabane ke baad hi hota hai.
Future<bool> showLogoutDialog(BuildContext context, {String? identity, String? note}) => showConfirmDialog(
      context,
      title: 'Log out?',
      message: "You'll need your username and password to sign back in.",
      confirmLabel: 'Log out',
      cancelLabel: 'Stay logged in',
      icon: Icons.logout_rounded,
      identity: identity,
      identityIcon: Icons.storefront_outlined,
      note: note ?? 'Your data stays safe on the server — this only ends the session on this phone.',
    );

class ConfirmDialogCard extends StatelessWidget {
  final String title, message, confirmLabel, cancelLabel;
  final IconData icon, identityIcon;
  final bool destructive;
  final String? identity, note;
  const ConfirmDialogCard({super.key, required this.title, required this.message,
    required this.confirmLabel, required this.cancelLabel, this.icon = Icons.help_outline,
    this.destructive = false, this.identity, this.identityIcon = Icons.storefront_outlined, this.note});

  @override
  Widget build(BuildContext context) {
    final c = context.colors, t = context.type, s = context.scheme;
    final accent = destructive ? c.errorInk : c.brandInk;
    final fill = destructive ? c.error : c.brandInk;
    final onFill = destructive ? s.onError : s.onPrimary;
    return Semantics(
      container: true, explicitChildNodes: true, label: title,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: Space.x24, vertical: Space.x24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Material(
              color: s.surfaceContainer,
              elevation: 0,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(borderRadius: Shapes.xl,
                  side: BorderSide(color: c.textPrimary.withValues(alpha: .08))),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                // 4dp brand hairline: Indigo → Mint.
                Container(height: 4, decoration: const BoxDecoration(gradient: AppColors.brandGradient)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.x24, Space.x24, Space.x24, Space.x16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Container(
                        width: 52, height: 52,
                        decoration: BoxDecoration(color: accent.withValues(alpha: .12), borderRadius: Shapes.md,
                            border: Border.all(color: accent.withValues(alpha: .24))),
                        child: Icon(icon, size: 26, color: accent),
                      ),
                      const SizedBox(width: Space.x16),
                      Expanded(child: Text(title, style: t.titleLarge)),
                    ]),
                    const SizedBox(height: Space.x16),
                    Text(message, style: t.bodyMedium?.copyWith(color: c.textSecondary)),
                    if (identity != null) ...[
                      const SizedBox(height: Space.x16),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: Space.x12, vertical: Space.x8),
                        decoration: BoxDecoration(color: c.textPrimary.withValues(alpha: .04), borderRadius: Shapes.md,
                            border: Border.all(color: c.textPrimary.withValues(alpha: .08))),
                        child: Row(children: [
                          Icon(identityIcon, size: 18, color: c.textSecondary),
                          const SizedBox(width: Space.x8),
                          Expanded(child: Text(identity!, style: t.labelSmall?.copyWith(color: c.textSecondary),
                              maxLines: 1, overflow: TextOverflow.ellipsis)),
                        ]),
                      ),
                    ],
                    if (note != null) ...[
                      const SizedBox(height: Space.x12),
                      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Icon(Icons.info_outline, size: 16, color: c.textSecondary),
                        const SizedBox(width: Space.x8),
                        Expanded(child: Text(note!, style: t.bodySmall?.copyWith(color: c.textSecondary))),
                      ]),
                    ],
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.x24, 0, Space.x24, Space.x24),
                  child: Row(children: [
                    Expanded(child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(cancelLabel, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
                    )),
                    const SizedBox(width: Space.x12),
                    Expanded(child: FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: fill, foregroundColor: onFill),
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(confirmLabel, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
                    )),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
