// Material 3 Expressive motion tokens: springs first, tweens only for enter/exit/ambient.
import 'package:flutter/widgets.dart';

abstract final class Springs {
  static SpringDescription _s(double ratio, double stiffness) =>
      SpringDescription.withDampingRatio(mass: 1, stiffness: stiffness, ratio: ratio);
  static final micro = _s(.85, 900); // icons, ripple, small state
  static final standard = _s(.80, 380); // cards, sheets, tabs (default)
  static final emphasis = _s(.72, 320); // morph, slight overshoot
  static final slow = _s(.75, 180); // hero, large surfaces
}

abstract final class Durations2 {
  static const enter = Duration(milliseconds: 320);
  static const exit = Duration(milliseconds: 200); // always shorter than enter
  static const fadeOut = Duration(milliseconds: 140); // fade-through out
  static const fadeIn = Duration(milliseconds: 240); // fade-through in
  static const toggleTrack = Duration(milliseconds: 160);
  static const shake = Duration(milliseconds: 240);
  static const iconDraw = Duration(milliseconds: 280);
  static const confetti = Duration(milliseconds: 900);
  static const shimmer = Duration(milliseconds: 1400);
  static const crossfadeImage = Duration(milliseconds: 200);
  static const stagger = Duration(milliseconds: 45);
  static const maxSequence = Duration(milliseconds: 600);
  static const ambient = Duration(milliseconds: 22000);
  static const ambientMin = Duration(milliseconds: 18000), ambientMax = Duration(milliseconds: 26000);
}

abstract final class Curves2 {
  static const enter = Curves.fastOutSlowIn;
  static const exit = Curves.linearToEaseOut; // LinearOutSlowIn equivalent
  static const ambient = Curves.easeInOutSine;
}

abstract final class MotionValues {
  static const pressScaleButton = .96, pressScaleCard = .98;
  static const cardBorderRest = .22, cardBorderPressed = .34;
  static const iconPop = 1.12;
  static const thumbSquashX = 1.15, thumbSquashY = .90;
  static const sharedAxisOffset = 30.0; // dp
  static const shakeOffset = 6.0; // dp, ×2
  static const parallax = .5;
  static const topBarBlurTrigger = 40.0; // dp scrolled
  static const topBarMaxBlur = 24.0, topBarMaxFill = .10;
}

/// Reduced motion: Android ANIMATOR_DURATION_SCALE == 0 maps to
/// MediaQuery.disableAnimations. Everything reads through this.
class Motion {
  final bool reduced;
  const Motion._(this.reduced);
  static Motion of(BuildContext c) => Motion._(MediaQuery.maybeDisableAnimationsOf(c) ?? false);

  Duration d(Duration x) => reduced ? Duration.zero : x;
  /// Stagger delay for list index i, capped to the 600ms max sequence.
  Duration staggerFor(int i) {
    if (reduced) return Duration.zero;
    final ms = Durations2.stagger.inMilliseconds * i;
    return Duration(milliseconds: ms.clamp(0, Durations2.maxSequence.inMilliseconds - Durations2.enter.inMilliseconds));
  }
  bool get ambientEnabled => !reduced;
}
