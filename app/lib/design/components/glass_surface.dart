// GlassSurface: the single glass recipe (blur → white gradient fill → optional scrim →
import 'dart:ui' show ImageFilter;
// top-lit gradient border → dark-mode inner highlight). Light: bottom-right shadow; dark: glow.
import 'package:flutter/material.dart';
import '../design.dart';

class GlassSurface extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  /// Real backdrop blur. Keep ≤3 blurred nodes per screen; set false for nested glass.
  final bool blur;
  /// Adds the theme text scrim (black 10% / 38%) for guaranteed text contrast.
  final bool scrim;
  final bool elevated;
  /// Multiplies border alpha (1 = rest .22, ~1.55 = pressed .34).
  final double borderBoost;
  /// Extra white fill (0..1 of max) used by scroll-linked bars.
  final double fillFactor;
  final double? blurOverride;

  const GlassSurface({
    super.key, required this.child, this.radius = Radii.card, this.padding = EdgeInsets.zero,
    this.blur = true, this.scrim = false, this.elevated = true, this.borderBoost = 1, this.fillFactor = 1, this.blurOverride,
  });

  @override
  Widget build(BuildContext context) {
    final g = context.glass;
    final br = BorderRadius.circular(radius);
    final sigma = (blurOverride ?? g.blurSigma).clamp(0.0, GlassTokens.maxBlur);
    Widget body = CustomPaint(
      foregroundPainter: _GlassEdgePainter(radius: radius, tokens: g, boost: borderBoost),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: br,
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [
            IndigoMint.glassWhite.withValues(alpha: g.fillTop * fillFactor),
            IndigoMint.glassWhite.withValues(alpha: g.fillBottom * fillFactor),
          ]),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(borderRadius: br, color: scrim ? g.scrim : Colors.transparent),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
    if (blur && g.blurSupported && sigma > 0) {
      body = BackdropFilter(filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma), child: body);
    }
    body = ClipRRect(borderRadius: br, child: body);
    // Shadow/glow painted OUTSIDE the shape only, so it never muddies translucent glass.
    return elevated && g.elevation.isNotEmpty
        ? CustomPaint(painter: _OuterShadowPainter(radius: radius, shadows: g.elevation), child: body)
        : body;
  }
}

class _GlassEdgePainter extends CustomPainter {
  final double radius, boost;
  final GlassTokens tokens;
  _GlassEdgePainter({required this.radius, required this.tokens, required this.boost});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rr = RRect.fromRectAndRadius(rect.deflate(.5), Radius.circular(radius));
    final k = boost * tokens.borderAlpha / GlassTokens.light.borderAlpha;
    canvas.drawRRect(rr, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [
        IndigoMint.glassWhite.withValues(alpha: (tokens.borderHighlightStart * k).clamp(0, 1)),
        IndigoMint.glassWhite.withValues(alpha: (tokens.borderHighlightEnd * k).clamp(0, 1)),
      ]).createShader(rect));
    if (tokens.innerHighlightAlpha > 0) {
      // 1dp inner top highlight (dark theme), fading out toward the sides.
      final y = 1.5, inset = radius * .6;
      canvas.drawLine(Offset(inset, y), Offset(size.width - inset, y), Paint()
        ..strokeWidth = 1
        ..shader = LinearGradient(colors: [
          IndigoMint.glassWhite.withValues(alpha: 0),
          IndigoMint.glassWhite.withValues(alpha: tokens.innerHighlightAlpha),
          IndigoMint.glassWhite.withValues(alpha: 0),
        ]).createShader(Rect.fromLTWH(inset, 0, size.width - inset * 2, 2)));
    }
  }

  @override
  bool shouldRepaint(_GlassEdgePainter o) => o.boost != boost || o.tokens != tokens || o.radius != radius;
}

class _OuterShadowPainter extends CustomPainter {
  final double radius;
  final List<BoxShadow> shadows;
  _OuterShadowPainter({required this.radius, required this.shadows});

  @override
  void paint(Canvas canvas, Size size) {
    final rr = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius));
    canvas.save();
    canvas.clipPath(Path()
      ..fillType = PathFillType.evenOdd
      ..addRect((Offset.zero & size).inflate(80))
      ..addRRect(rr));
    for (final s in shadows) {
      canvas.drawRRect(rr.shift(s.offset).inflate(s.spreadRadius), s.toPaint());
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OuterShadowPainter o) => o.radius != radius || o.shadows != shadows;
}
