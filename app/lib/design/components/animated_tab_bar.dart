// AnimatedTabBar: floating glass pill bar, 16dp above the nav-bar inset.
// Indicator slides on the Emphasis spring and stretches while travelling (morph);
// active icon switches outline→filled with a 1→1.12→1 pop. Gains blur/fill when [elevated].
import 'package:flutter/material.dart';
import '../design.dart';
import 'glass_surface.dart';
import 'spring.dart';

@immutable
class TabItem {
  final IconData icon, activeIcon;
  final String label;
  const TabItem({required this.icon, required this.activeIcon, required this.label});
}

class AnimatedTabBar extends StatefulWidget {
  final List<TabItem> items;
  final int index;
  final ValueChanged<int> onChanged;
  final bool elevated; // true when content is scrolled underneath
  const AnimatedTabBar({super.key, required this.items, required this.index, required this.onChanged, this.elevated = false});
  @override
  State<AnimatedTabBar> createState() => _AnimatedTabBarState();
}

class _AnimatedTabBarState extends State<AnimatedTabBar> with TickerProviderStateMixin {
  late final _pos = AnimationController.unbounded(vsync: this, value: widget.index.toDouble());
  late final _elev = AnimationController.unbounded(vsync: this, value: widget.elevated ? 1 : 0);

  @override
  void didUpdateWidget(AnimatedTabBar old) {
    super.didUpdateWidget(old);
    final m = Motion.of(context);
    if (old.index != widget.index) _pos.springTo(widget.index.toDouble(), Springs.emphasis, m);
    if (old.elevated != widget.elevated) _elev.springTo(widget.elevated ? 1 : 0, Springs.standard, m);
  }

  @override
  void dispose() { _pos.dispose(); _elev.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final c = context.colors, s = context.scheme;
    final bottom = MediaQuery.viewPaddingOf(context).bottom + Space.tabBarLift;
    return Padding(
      padding: EdgeInsets.fromLTRB(Space.screen, 0, Space.screen, bottom),
      child: AnimatedBuilder(
        animation: _elev,
        builder: (context, child) => GlassSurface(
          radius: Radii.full, scrim: true,
          fillFactor: 1 + _elev.value.clamp(0.0, 1.0), // more frost when content scrolls under
          blurOverride: context.glass.blurSigma * (.6 + .4 * _elev.value.clamp(0.0, 1.0)),
          child: child!,
        ),
        child: Padding(
          padding: const EdgeInsets.all(Space.x4),
          child: LayoutBuilder(builder: (context, box) {
            final n = widget.items.length, w = box.maxWidth / n;
            return Stack(children: [
              // Indicator: stretches by the remaining travel distance → liquid morph.
              AnimatedBuilder(
                animation: _pos,
                builder: (context, _) {
                  final travel = (_pos.value - widget.index).abs().clamp(0.0, 1.0);
                  final iw = w * (1 + .35 * travel);
                  final left = (_pos.value * w - (iw - w) / 2).clamp(0.0, box.maxWidth - iw);
                  return Positioned(left: left, top: 0, bottom: 0, width: iw,
                      child: DecoratedBox(decoration: BoxDecoration(
                          color: s.primary.withValues(alpha: .16), borderRadius: Shapes.pill,
                          border: Border.all(color: s.primary.withValues(alpha: .32)))));
                },
              ),
              Row(children: [
                for (var i = 0; i < n; i++)
                  Expanded(child: _TabButton(
                    item: widget.items[i], active: i == widget.index, activeColor: c.brandInk, idleColor: c.textSecondary,
                    onTap: () { if (i != widget.index) { Haptics.select(); widget.onChanged(i); } },
                    semanticIndex: '${i + 1} of $n',
                  )),
              ]),
            ]);
          }),
        ),
      ),
    );
  }
}

class _TabButton extends StatefulWidget {
  final TabItem item; final bool active; final Color activeColor, idleColor; final VoidCallback onTap; final String semanticIndex;
  const _TabButton({required this.item, required this.active, required this.activeColor, required this.idleColor, required this.onTap, required this.semanticIndex});
  @override
  State<_TabButton> createState() => _TabButtonState();
}

class _TabButtonState extends State<_TabButton> with SingleTickerProviderStateMixin {
  late final _pop = AnimationController.unbounded(vsync: this, value: 1);
  @override
  void didUpdateWidget(_TabButton old) {
    super.didUpdateWidget(old);
    final m = Motion.of(context);
    if (widget.active && !old.active && !m.reduced) { _pop.value = MotionValues.iconPop; _pop.springTo(1, Springs.micro, m, velocity: -2); }
  }
  @override
  void dispose() { _pop.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final color = widget.active ? widget.activeColor : widget.idleColor;
    return Semantics(
      button: true, selected: widget.active, label: '${widget.item.label}, tab ${widget.semanticIndex}', excludeSemantics: true,
      child: InkResponse(
        onTap: widget.onTap, containedInkWell: true, customBorder: Shapes.stadium,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.x4),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
              ScaleTransition(scale: _pop, child: Icon(widget.active ? widget.item.activeIcon : widget.item.icon, color: color)),
              const SizedBox(height: 2),
              Text(widget.item.label, maxLines: 1, overflow: TextOverflow.fade, softWrap: false,
                  style: AppType.labelSmall.copyWith(color: color, fontWeight: widget.active ? FontWeight.w700 : FontWeight.w500)),
            ]),
          ),
        ),
      ),
    );
  }
}
