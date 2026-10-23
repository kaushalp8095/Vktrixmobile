// GLASS DIALOG: `AlertDialog` ki jagah ek hi Indigo/Mint shell — form aur
// message, dono ke liye. Chrome wahi hai jo `ConfirmDialogCard` ka hai: brand
// hairline → icon disc + title → message → body → footer. Confirm dialogs aur
// form dialogs ek hi tarah dikhein, isliye dono yahin se bante hain.
//
// Kyun: Material ka AlertDialog is glass/aurora theme ke beech flat lagta tha,
// uska fixed content box 200% text scale par overflow karta tha, aur keyboard
// khulne par fields ke upar aa jata tha. Yahan poora card scrollable hai,
// keyboard insets se upar uthta hai, aur buttons do line tak wrap karte hain.
import 'package:flutter/material.dart';
import '../design.dart';

Color _scrim(BuildContext context) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return IndigoMint.scrimBlack.withValues(alpha: dark ? .66 : .44);
}

/// Card ka dhaancha — header + optional body + footer. Footer caller banata hai
/// (2 ya 3 buttons), taaki confirm aur form dono same chrome share karein.
class GlassDialogCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final String? message, identity, note;
  final IconData identityIcon;
  final bool destructive;
  final Widget? child;
  final Widget footer;

  const GlassDialogCard({
    super.key, required this.title, required this.icon, required this.footer,
    this.message, this.identity, this.note, this.identityIcon = Icons.storefront_outlined,
    this.destructive = false, this.child,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors, t = context.type, s = context.scheme;
    final accent = destructive ? c.errorInk : c.brandInk;
    return Semantics(
      container: true, explicitChildNodes: true, label: title,
      child: Padding(
        // Keyboard khula ho to card uske upar rehta hai — fields chhup na jayein.
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
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
                    padding: const EdgeInsets.fromLTRB(Space.x24, Space.x24, Space.x24, 0),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Container(
                          width: 52, height: 52,
                          decoration: BoxDecoration(color: accent.withValues(alpha: .12), borderRadius: Shapes.md,
                              border: Border.all(color: accent.withValues(alpha: .24))),
                          child: Icon(icon, size: 26, color: accent),
                        ),
                        const SizedBox(width: Space.x16),
                        Expanded(child: Semantics(header: true, child: Text(title, style: t.titleLarge))),
                      ]),
                      if (message != null) ...[
                        const SizedBox(height: Space.x16),
                        Text(message!, style: t.bodyMedium?.copyWith(color: c.textSecondary)),
                      ],
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
                                maxLines: 2, overflow: TextOverflow.ellipsis)),
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
                  if (child != null)
                    Padding(padding: const EdgeInsets.fromLTRB(Space.x24, Space.x16, Space.x24, 0), child: child),
                  Padding(padding: const EdgeInsets.fromLTRB(Space.x24, Space.x16, Space.x24, Space.x24), child: footer),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Dialog footer: [Cancel] [Confirm] — barabar chaudai, 2 line tak label.
/// Labels wrap karte hain (ellipsis sirf 2 line ke baad), isliye 200% text scale
/// par bhi kuch bahar nahi nikalta.
class GlassDialogActions extends StatelessWidget {
  final String cancelLabel, confirmLabel;
  final VoidCallback onCancel, onConfirm;
  final bool destructive;
  /// Optional teesra action (e.g. "Use default") cancel aur confirm ke beech.
  final String? middleLabel;
  final VoidCallback? onMiddle;

  const GlassDialogActions({
    super.key, required this.cancelLabel, required this.confirmLabel,
    required this.onCancel, required this.onConfirm, this.destructive = false,
    this.middleLabel, this.onMiddle,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors, s = context.scheme;
    final fill = destructive ? c.error : c.brandInk;
    final onFill = destructive ? s.onError : s.onPrimary;
    Widget item(Widget w) => Expanded(child: w);
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        item(OutlinedButton(
          onPressed: onCancel,
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48), padding: const EdgeInsets.symmetric(horizontal: Space.x8)),
          child: Text(cancelLabel, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
        )),
        if (middleLabel != null) ...[
          const SizedBox(width: Space.x8),
          item(TextButton(
            onPressed: onMiddle,
            style: TextButton.styleFrom(minimumSize: const Size(0, 48), padding: const EdgeInsets.symmetric(horizontal: Space.x8)),
            child: Text(middleLabel!, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
          )),
        ],
        const SizedBox(width: Space.x12),
        item(FilledButton(
          style: FilledButton.styleFrom(backgroundColor: fill, foregroundColor: onFill,
              minimumSize: const Size(0, 48), padding: const EdgeInsets.symmetric(horizontal: Space.x8)),
          onPressed: onConfirm,
          child: Text(confirmLabel, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
        )),
      ]),
    );
  }
}

/// Low-level: koi bhi footer/content. Footer ko dialog ka apna context milta
/// hai, isliye `Navigator.pop(ctx, value)` seedha isi dialog ko band karta hai.
Future<T?> showGlassDialog<T>(
  BuildContext context, {
  required String title,
  required IconData icon,
  required Widget Function(BuildContext dialogContext) footer,
  String? message,
  String? note,
  String? identity,
  bool destructive = false,
  Widget? child,
}) =>
    showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close',
      barrierColor: _scrim(context),
      transitionDuration: Motion.of(context).d(Durations2.enter),
      pageBuilder: (ctx, _, __) => GlassDialogCard(
        title: title, icon: icon, message: message, note: note, identity: identity,
        destructive: destructive, footer: footer(ctx), child: child,
      ),
      transitionBuilder: (ctx, anim, _, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves2.enter, reverseCurve: Curves2.exit);
        return FadeTransition(opacity: curved,
          child: ScaleTransition(scale: Tween<double>(begin: .94, end: 1).animate(curved), child: child));
      },
    );

/// Form dialog: [Cancel] [Save]. `validate` false laute to dialog khula rehta
/// hai (form ke apne validators error dikha dete hain). Returns true sirf save
/// dabane par — caller apne controllers padh kar request bhejta hai.
Future<bool> showGlassFormDialog(
  BuildContext context, {
  required String title,
  required IconData icon,
  required WidgetBuilder body,
  String? message,
  String? note,
  String? identity,
  String confirmLabel = 'Save',
  String cancelLabel = 'Cancel',
  bool destructive = false,
  bool Function()? validate,
}) async {
  final ok = await showGlassDialog<bool>(
    context,
    title: title, icon: icon, message: message, note: note, identity: identity, destructive: destructive,
    child: Builder(builder: body),
    footer: (ctx) => GlassDialogActions(
      cancelLabel: cancelLabel, confirmLabel: confirmLabel, destructive: destructive,
      onCancel: () => Navigator.pop(ctx, false),
      onConfirm: () { if (validate == null || validate()) Navigator.pop(ctx, true); },
    ),
  );
  return ok == true;
}
