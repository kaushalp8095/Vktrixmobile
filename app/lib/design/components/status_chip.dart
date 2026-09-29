// StatusChip: 12% tinted fill + 1dp 24% tinted border + ink text + icon (never colour alone).
import 'package:flutter/material.dart';
import '../design.dart';

enum ChipTone { success, warning, error, brand, neutral }

class StatusChip extends StatelessWidget {
  final String label;
  final ChipTone tone;
  final IconData? icon;
  const StatusChip({super.key, required this.label, required this.tone, this.icon});

  @override
  Widget build(BuildContext context) {
    final c = context.colors, s = context.scheme;
    final (tint, ink, fallbackIcon) = switch (tone) {
      ChipTone.success => (c.success, c.successInk, Icons.check_circle_outline),
      ChipTone.warning => (c.warning, c.warningInk, Icons.error_outline),
      ChipTone.error => (c.error, c.errorInk, Icons.cancel_outlined),
      ChipTone.brand => (s.primary, c.brandInk, Icons.circle_outlined),
      ChipTone.neutral => (c.textPrimary, c.textSecondary, Icons.circle_outlined),
    };
    return Semantics(
      label: label, excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: 28),
        padding: const EdgeInsets.symmetric(horizontal: Space.x12, vertical: Space.x4),
        decoration: BoxDecoration(
          color: tint.withValues(alpha: .12), borderRadius: Shapes.pill, border: Border.all(color: tint.withValues(alpha: .24))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon ?? fallbackIcon, size: 16, color: ink),
          const SizedBox(width: Space.x4),
          Flexible(child: Text(label, style: AppType.labelSmall.copyWith(color: ink))),
        ]),
      ),
    );
  }
}
