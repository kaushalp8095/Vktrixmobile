// GlassIconButton: 48dp hit target, 40dp glass disc. Selected = filled icon with
// scale pop 1→1.12→1 (Micro spring). Unselected icons are outlined.
import 'package:flutter/material.dart';
import '../design.dart';
import 'glass_surface.dart';
import 'spring.dart';

class GlassIconButton extends StatefulWidget {
  final IconData icon;
  final IconData? selectedIcon;
  final bool selected;
  final String semanticLabel;
  final VoidCallback? onPressed;
  final bool blur;
  const GlassIconButton({super.key, required this.icon, required this.semanticLabel, required this.onPressed,
    this.selectedIcon, this.selected = false, this.blur = false});
  @override
  State<GlassIconButton> createState() => _GlassIconButtonState();
}

class _GlassIconButtonState extends State<GlassIconButton> with SingleTickerProviderStateMixin {
  late final _pop = AnimationController.unbounded(vsync: this, value: 1);

  @override
  void didUpdateWidget(GlassIconButton old) {
    super.didUpdateWidget(old);
    if (old.selected != widget.selected) {
      final m = Motion.of(context);
      if (m.reduced) return;
      _pop.value = MotionValues.iconPop;
      _pop.springTo(1, Springs.micro, m, velocity: -2);
    }
  }

  @override
  void dispose() { _pop.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final icon = widget.selected ? (widget.selectedIcon ?? widget.icon) : widget.icon;
    return Semantics(
      button: true, selected: widget.selected, label: widget.semanticLabel, excludeSemantics: true,
      child: SizedBox.square(
        dimension: Space.minTouch,
        child: Material(
          type: MaterialType.transparency,
          child: InkResponse(
            onTap: widget.onPressed == null ? null : () { Haptics.tap(); widget.onPressed!(); },
            radius: Space.minTouch / 2,
            child: Center(
              child: SizedBox.square(
                dimension: 40,
                child: GlassSurface(
                  radius: Radii.full, blur: widget.blur, elevated: false,
                  child: Center(child: ScaleTransition(
                    scale: _pop,
                    child: Icon(icon, size: 22, color: widget.selected ? c.brandInk : c.textPrimary),
                  )),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
