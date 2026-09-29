// ShimmerSkeleton: layout-matched placeholders with a 1400ms linear sweep (soft 24dp band).
// Reduced motion → static skeleton. Announces "Loading" once via live region.
import 'package:flutter/material.dart';
import '../design.dart';

class Shimmer extends StatefulWidget {
  final Widget child;
  const Shimmer({super.key, required this.child});
  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: Durations2.shimmer);
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    Motion.of(context).reduced ? _c.stop() : (_c.isAnimating ? null : _c.repeat());
  }
  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final base = context.colors.textPrimary.withValues(alpha: .08);
    final hi = context.colors.textPrimary.withValues(alpha: .16);
    return Semantics(
      liveRegion: true, label: 'Loading',
      child: ExcludeSemantics(child: AnimatedBuilder(
        animation: _c,
        child: widget.child,
        builder: (context, child) => ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (r) {
            final x = -1.0 + _c.value * 3; // sweep from left to right
            return LinearGradient(
              begin: Alignment(x - 1, 0), end: Alignment(x + 1, 0),
              colors: [base, hi, base], stops: const [.35, .5, .65]).createShader(r);
          },
          child: child,
        ),
      )),
    );
  }
}

class SkeletonBox extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;
  const SkeletonBox({super.key, this.width, required this.height, this.radius = Radii.sm});
  @override
  Widget build(BuildContext context) => Container(
        width: width, height: height,
        decoration: BoxDecoration(color: context.colors.textPrimary.withValues(alpha: .08), borderRadius: BorderRadius.circular(radius)));
}

/// Ready-made list-row skeleton matching the app's phone rows (avatar + 2 lines + price).
class SkeletonListTile extends StatelessWidget {
  const SkeletonListTile({super.key});
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: Space.x8),
        child: Row(children: [
          SkeletonBox(width: 44, height: 44, radius: Radii.md),
          SizedBox(width: Space.x12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SkeletonBox(width: 160, height: 14), SizedBox(height: Space.x8), SkeletonBox(width: 110, height: 12)])),
          SizedBox(width: Space.x12),
          SkeletonBox(width: 64, height: 16),
        ]),
      );
}
