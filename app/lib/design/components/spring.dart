// Shared motion plumbing: spring driver + haptics. Used by every interactive component.
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import '../motion.dart';

extension SpringDrive on AnimationController {
  /// Animate to [target] with a spring token; instant when reduced motion is on.
  TickerFuture springTo(double target, SpringDescription spec, Motion m, {double velocity = 0}) {
    if (m.reduced) { value = target; return TickerFuture.complete(); }
    return animateWith(SpringSimulation(spec, value, target, velocity));
  }
}

/// Haptic vocabulary mapped onto Flutter's Android constants:
/// lightImpact=VIRTUAL_KEY, vibrate=LONG_PRESS, selectionClick=CLOCK_TICK,
/// heavyImpact=CONTEXT_CLICK (closest available to REJECT). Never call on scroll.
abstract final class Haptics {
  static void tap() => HapticFeedback.lightImpact();
  static void select() => HapticFeedback.vibrate();
  static void tick() => HapticFeedback.selectionClick();
  static Future<void> success() async {
    await HapticFeedback.selectionClick();
    await Future<void>.delayed(const Duration(milliseconds: 70));
    await HapticFeedback.selectionClick();
  }
  static void error() => HapticFeedback.heavyImpact();
}
