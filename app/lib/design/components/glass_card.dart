// GlassCard: pressable GlassSurface. Press = scale .98 + border .22→.34 (Standard spring).
import 'package:flutter/material.dart';
import '../design.dart';
import 'glass_surface.dart';
import 'spring.dart';

class GlassCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool blur, scrim;
  final String? semanticLabel;
  const GlassCard({
    super.key, required this.child, this.onTap, this.onLongPress, this.padding = const EdgeInsets.all(Space.card),
    this.radius = Radii.card, this.blur = true, this.scrim = false, this.semanticLabel,
  });
  @override
  State<GlassCard> createState() => _GlassCardState();
}

class _GlassCardState extends State<GlassCard> with SingleTickerProviderStateMixin {
  late final _press = AnimationController.unbounded(vsync: this);
  void _set(bool down) => _press.springTo(down ? 1 : 0, Springs.standard, Motion.of(context));
  @override
  void dispose() { _press.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final interactive = widget.onTap != null || widget.onLongPress != null;
    final boostMax = MotionValues.cardBorderPressed / MotionValues.cardBorderRest;
    return Semantics(
      button: interactive, label: widget.semanticLabel,
      child: AnimatedBuilder(
        animation: _press,
        builder: (context, child) {
          final p = _press.value;
          return Transform.scale(
            scale: 1 - (1 - MotionValues.pressScaleCard) * p,
            child: GlassSurface(
              radius: widget.radius, blur: widget.blur, scrim: widget.scrim,
              borderBoost: 1 + (boostMax - 1) * p, child: child!),
          );
        },
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: widget.onTap == null ? null : () { Haptics.tap(); widget.onTap!(); },
            onLongPress: widget.onLongPress == null ? null : () { Haptics.select(); widget.onLongPress!(); },
            onHighlightChanged: interactive ? _set : null,
            borderRadius: BorderRadius.circular(widget.radius),
            child: Padding(padding: widget.padding, child: widget.child),
          ),
        ),
      ),
    );
  }
}
