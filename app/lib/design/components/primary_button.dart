// PrimaryButton: pill CTA that morphs. Press = scale .96 + corners 100%→24% (Emphasis
// spring) + haptic. Loading = collapses to a circle with spinner. Success = check drawn
// in 280ms. Error = 240ms ±6dp ×2 shake. Every state is announced to TalkBack.
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../design.dart';
import 'spring.dart';

enum ButtonPhase { idle, loading, success, error }

class PrimaryButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final ButtonPhase phase;
  final IconData? icon;
  final bool expand;
  const PrimaryButton({super.key, required this.label, required this.onPressed, this.phase = ButtonPhase.idle, this.icon, this.expand = true});
  @override
  State<PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<PrimaryButton> with TickerProviderStateMixin {
  static const _h = 56.0;
  late final _press = AnimationController.unbounded(vsync: this);
  late final _collapse = AnimationController.unbounded(vsync: this);
  late final _check = AnimationController(vsync: this, duration: Durations2.iconDraw);
  late final _shake = AnimationController(vsync: this, duration: Durations2.shake);

  @override
  void didUpdateWidget(PrimaryButton old) {
    super.didUpdateWidget(old);
    if (old.phase == widget.phase) return;
    final m = Motion.of(context);
    final collapsed = widget.phase == ButtonPhase.loading || widget.phase == ButtonPhase.success;
    _collapse.springTo(collapsed ? 1 : 0, Springs.emphasis, m);
    if (widget.phase == ButtonPhase.success) {
      _check.duration = m.d(Durations2.iconDraw);
      _check.forward(from: 0);
      Haptics.success();
    } else {
      _check.value = 0;
    }
    if (widget.phase == ButtonPhase.error) {
      Haptics.error();
      _shake.duration = m.d(Durations2.shake);
      _shake.forward(from: 0);
    }
  }

  @override
  void dispose() { _press.dispose(); _collapse.dispose(); _check.dispose(); _shake.dispose(); super.dispose(); }

  bool get _enabled => widget.onPressed != null && widget.phase != ButtonPhase.loading && widget.phase != ButtonPhase.success;

  String get _announce => switch (widget.phase) {
        ButtonPhase.loading => '${widget.label}, loading', ButtonPhase.success => '${widget.label}, done',
        ButtonPhase.error => '${widget.label}, failed, try again', ButtonPhase.idle => widget.label };

  /// Gradient CTA — brand ke do stops, aur label ka colour theme se:
  ///   light: deep aqua/emerald (white label par 5.7:1 / 5.1:1)
  ///   dark : light aqua/emerald (dark label par 8.5:1 / 9.5:1)
  /// Dono case me AA se upar. Gradient sirf primary action par — ek screen par
  /// ek hi hota hai, isliye "hero" treatment spill nahi karta.
  LinearGradient get _ctaGradient {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return dark
        ? const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [AquaEmerald.primaryDark, AquaEmerald.emeraldLight])
        : AppColors.ctaGradient;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors, s = context.scheme;
    final fg = s.onPrimary;
    final success = widget.phase == ButtonPhase.success;
    final disabled = widget.onPressed == null;
    return Semantics(
      button: true, enabled: _enabled, liveRegion: widget.phase != ButtonPhase.idle, label: _announce,
      excludeSemantics: true,
      child: LayoutBuilder(builder: (context, box) {
        final full = widget.expand && box.maxWidth.isFinite ? box.maxWidth : null;
        return AnimatedBuilder(
          animation: Listenable.merge([_press, _collapse, _check, _shake]),
          builder: (context, _) {
            final p = _press.value, k = _collapse.value.clamp(0.0, 1.0);
            final w = full == null ? null : _h + (full - _h) * (1 - k);
            final radius = _h / 2 * (1 - p * .76); // 100% → 24%
            final dx = math.sin(_shake.value * math.pi * 4) * MotionValues.shakeOffset * (1 - _shake.value);
            return Transform.translate(
              offset: Offset(dx, 0),
              child: Center(
                child: Transform.scale(
                  scale: 1 - (1 - MotionValues.pressScaleButton) * p,
                  // Fixed height nahi: 200% text scale par label do line leta hai,
                  // to button utna hi ooncha ho jata hai (clip/overflow nahi).
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: w ?? 0, minHeight: _h),
                    child: Material(
                      // Gradient Material ke andar DecoratedBox se aata hai; Material
                      // khud transparent rehta hai warna gradient chhup jata.
                      color: disabled
                          ? s.onSurface.withValues(alpha: .12)
                          : (success ? c.success : Colors.transparent),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
                      clipBehavior: Clip.antiAlias,
                      // `Ink` (DecoratedBox nahi) — gradient Material ki apni
                      // surface par paint hota hai, isliye InkWell ka splash
                      // gradient ke **upar** dikhta hai (warna ripple chhup jata).
                      child: Ink(
                        decoration: BoxDecoration(
                          gradient: disabled || success ? null : _ctaGradient,
                          borderRadius: BorderRadius.circular(radius)),
                        child: InkWell(
                          onTap: _enabled ? () { Haptics.tap(); widget.onPressed!(); } : null,
                          onHighlightChanged: _enabled ? (d) => _press.springTo(d ? 1 : 0, Springs.emphasis, Motion.of(context)) : null,
                          child: Center(child: _content(fg, k)),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      }),
    );
  }

  Widget _content(Color fg, double k) {
    if (widget.phase == ButtonPhase.success) {
      return CustomPaint(size: const Size(24, 24), painter: _CheckPainter(_check.value, fg));
    }
    if (widget.phase == ButtonPhase.loading) {
      return SizedBox(width: 22, height: 22, child: Motion.of(context).reduced
          ? Icon(Icons.hourglass_empty, color: fg, size: 20)
          : CircularProgressIndicator(strokeWidth: 2.5, color: fg));
    }
    return Opacity(
      opacity: (1 - k * 2).clamp(0.0, 1.0),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.x24),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (widget.icon != null) ...[Icon(widget.icon, color: fg, size: 20), const SizedBox(width: Space.x8)],
          Flexible(child: Text(
            widget.phase == ButtonPhase.error ? 'Try again' : widget.label,
            style: AppType.labelLarge.copyWith(color: fg), textAlign: TextAlign.center, softWrap: true)),
        ]),
      ),
    );
  }
}

class _CheckPainter extends CustomPainter {
  final double t; final Color color;
  _CheckPainter(this.t, this.color);
  @override
  void paint(Canvas canvas, Size s) {
    final path = Path()..moveTo(s.width * .18, s.height * .54)..lineTo(s.width * .42, s.height * .76)..lineTo(s.width * .84, s.height * .28);
    final m = path.computeMetrics().first;
    canvas.drawPath(m.extractPath(0, m.length * t), Paint()
      ..color = color..style = PaintingStyle.stroke..strokeWidth = 2.5..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round);
  }
  @override
  bool shouldRepaint(_CheckPainter o) => o.t != t || o.color != color;
}
