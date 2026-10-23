// CONFIRM DIALOG: ek hi reusable, Indigo/Mint se matched confirmation popup.
// Shop side aur Super Admin side — dono yahi use karte hain (logout, shop
// deactivate, delete, support access). Buttons: safe action pehle, confirm baad me.
//
// Structure: brand hairline → icon disc + title → message → identity chip → note
// → [Cancel] [Confirm]. Enter: fade + scale .94→1 (320ms FastOutSlowIn), reduced
// motion par instant.
import 'package:flutter/material.dart';
import '../design.dart';
import 'glass_dialog.dart';

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

/// Confirmation popup — chrome `GlassDialogCard` se aata hai, isliye form
/// dialogs aur confirms bilkul ek jaise dikhte hain.
class ConfirmDialogCard extends StatelessWidget {
  final String title, message, confirmLabel, cancelLabel;
  final IconData icon, identityIcon;
  final bool destructive;
  final String? identity, note;
  const ConfirmDialogCard({super.key, required this.title, required this.message,
    required this.confirmLabel, required this.cancelLabel, this.icon = Icons.help_outline,
    this.destructive = false, this.identity, this.identityIcon = Icons.storefront_outlined, this.note});

  @override
  Widget build(BuildContext context) => GlassDialogCard(
        title: title, icon: icon, message: message, identity: identity,
        identityIcon: identityIcon, note: note, destructive: destructive,
        footer: GlassDialogActions(
          cancelLabel: cancelLabel, confirmLabel: confirmLabel, destructive: destructive,
          onCancel: () => Navigator.pop(context, false),
          onConfirm: () => Navigator.pop(context, true),
        ),
      );
}
