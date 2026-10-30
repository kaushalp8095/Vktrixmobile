// GradientFab — primary screen action ("New shop" type) ka floating pill.
//
// Kyun alag component: Material ka `FloatingActionButton` default surface se
// paint hota hai, aur uske default elevation shadow ka rang pure black hota
// hai. Light aurora par wo ek moti **kaali ring** jaisa dikhta tha (admin_home
// golden me saaf nazar aata tha) — gradient CTA wale app me sabse zyada
// attention maangne wala control hi sabse off-brand tha.
//
// Yahan wahi recipe hai jo `PrimaryButton` use karta hai, taaki poore app me
// "action" ka ek hi roop ho:
//   • gradient theme se (`AppColors.cta`) — light me deep pair, dark me bright
//   • label/icon `scheme.onPrimary` — dono themes me AA
//   • shadow brand-tinted (pure black nahi), do layer (wide + tight)
//   • Ink + InkWell, taaki ripple gradient ke *upar* aaye
import 'package:flutter/material.dart';
import '../design.dart';
import 'spring.dart';

class GradientFab extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final String? heroTag;
  const GradientFab({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.heroTag,
  });

  @override
  State<GradientFab> createState() => _GradientFabState();
}

class _GradientFabState extends State<GradientFab> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors, s = context.scheme;
    final fg = s.onPrimary;
    final pill = Semantics(
      button: true,
      label: widget.label,
      excludeSemantics: true,
      child: AnimatedScale(
        scale: _down ? MotionValues.pressScaleButton : 1,
        duration: Durations2.toggleTrack,
        curve: Curves2.exit,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: Shapes.pill,
            gradient: c.cta,
            boxShadow: [
              // Wide, soft, brand-tinted: coloured aurora par black shadow maila
              // dikhta hai aur "grey ledge" jaisa band bana deta hai.
              BoxShadow(color: c.brandInk.withValues(alpha: .26), blurRadius: 28, offset: const Offset(0, 10)),
              BoxShadow(color: c.brandInk.withValues(alpha: .16), blurRadius: 6, offset: const Offset(0, 2)),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            shape: Shapes.stadium,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () { Haptics.tap(); widget.onPressed(); },
              onHighlightChanged: (d) => setState(() => _down = d),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.x20, vertical: Space.x16),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(widget.icon, size: 22, color: fg),
                  const SizedBox(width: Space.x8),
                  Text(widget.label, style: AppType.labelLarge.copyWith(color: fg)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
    // Scaffold ke saath Hero flight bani rahe (FAB → full-screen form).
    return widget.heroTag == null ? pill : Hero(tag: widget.heroTag!, child: pill);
  }
}
