// Navigation transitions: shared-axis X (±30dp + fade) and fade-through.
// Enter 320ms FastOutSlowIn, exit 200ms. Instant under reduced motion.
import 'package:flutter/material.dart';
import '../design.dart';

class SharedAxisRoute<T> extends PageRouteBuilder<T> {
  SharedAxisRoute({required WidgetBuilder builder, bool reduced = false})
      : super(
          transitionDuration: reduced ? Duration.zero : Durations2.enter,
          reverseTransitionDuration: reduced ? Duration.zero : Durations2.exit,
          pageBuilder: (context, _, __) => builder(context),
          transitionsBuilder: (context, anim, secondary, child) {
            final inCurve = CurvedAnimation(parent: anim, curve: Curves2.enter, reverseCurve: Curves2.exit);
            final outCurve = CurvedAnimation(parent: secondary, curve: Curves2.enter, reverseCurve: Curves2.exit);
            const d = MotionValues.sharedAxisOffset;
            return AnimatedBuilder(
              animation: Listenable.merge([inCurve, outCurve]),
              child: child,
              builder: (context, child) => Transform.translate(
                offset: Offset(d * (1 - inCurve.value) - d * outCurve.value, 0),
                child: Opacity(opacity: (inCurve.value * (1 - outCurve.value)).clamp(0.0, 1.0), child: child),
              ),
            );
          },
        );

  static Future<T?> push<T>(BuildContext context, WidgetBuilder b) =>
      Navigator.of(context).push<T>(SharedAxisRoute<T>(builder: b, reduced: Motion.of(context).reduced));
  static Future<T?> replace<T>(BuildContext context, WidgetBuilder b) =>
      Navigator.of(context).pushReplacement<T, void>(SharedAxisRoute<T>(builder: b, reduced: Motion.of(context).reduced));
}

/// Fade-through for swapping content in place (out 140ms → in 240ms).
class FadeThrough extends StatelessWidget {
  final Widget child;
  const FadeThrough({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    final m = Motion.of(context);
    return AnimatedSwitcher(
      duration: m.d(Durations2.fadeIn), reverseDuration: m.d(Durations2.fadeOut),
      switchInCurve: Curves2.enter, switchOutCurve: Curves2.exit,
      transitionBuilder: (c, a) => FadeTransition(opacity: a, child: ScaleTransition(scale: Tween(begin: .98, end: 1.0).animate(a), child: c)),
      child: child,
    );
  }
}
