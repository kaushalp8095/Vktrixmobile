// GlassTokens: alpha-based, theme-driven frosted-glass recipe (Flutter's LocalGlass).
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'colors.dart';

@immutable
class GlassTokens extends ThemeExtension<GlassTokens> {
  final double fillTop, fillBottom; // white alpha, vertical gradient
  final double borderAlpha; // 1dp white
  final double borderHighlightStart, borderHighlightEnd; // top-lit TL→BR
  final double scrimAlpha; // black behind text on glass
  final double blurSigma; // dp
  final double shadowBlur, shadowAlpha; // light only
  final double glowBlur, glowAlpha; // dark only (primary glow)
  final double innerHighlightAlpha; // 1dp inner top highlight
  final Color glowColor;
  /// No-blur fallback (<API 31 or blur disabled): fill +6%, border +4%.
  final bool blurSupported;

  const GlassTokens({
    required this.fillTop, required this.fillBottom, required this.borderAlpha,
    required this.borderHighlightStart, required this.borderHighlightEnd, required this.scrimAlpha,
    required this.blurSigma, required this.shadowBlur, required this.shadowAlpha,
    required this.glowBlur, required this.glowAlpha, required this.innerHighlightAlpha,
    required this.glowColor, this.blurSupported = true,
  });

  static const light = GlassTokens(
    fillTop: .16, fillBottom: .06, borderAlpha: .22, borderHighlightStart: .34, borderHighlightEnd: .08,
    scrimAlpha: .10, blurSigma: 22, shadowBlur: 12, shadowAlpha: .10, glowBlur: 0, glowAlpha: 0,
    innerHighlightAlpha: 0, glowColor: IndigoMint.primaryLight,
  );
  static const dark = GlassTokens(
    fillTop: .10, fillBottom: .04, borderAlpha: .16, borderHighlightStart: .34, borderHighlightEnd: .08,
    scrimAlpha: .38, blurSigma: 18, shadowBlur: 0, shadowAlpha: 0, glowBlur: 24, glowAlpha: .10,
    innerHighlightAlpha: .16, glowColor: IndigoMint.primaryDark,
  );

  static const maxBlur = 28.0;
  static const maxStackedLayers = 3;

  GlassTokens withFallback(bool supported) => supported ? this : GlassTokens(
        fillTop: fillTop + .06, fillBottom: fillBottom + .06, borderAlpha: borderAlpha + .04,
        borderHighlightStart: borderHighlightStart + .04, borderHighlightEnd: borderHighlightEnd + .04,
        scrimAlpha: scrimAlpha, blurSigma: 0, shadowBlur: shadowBlur, shadowAlpha: shadowAlpha,
        glowBlur: glowBlur, glowAlpha: glowAlpha, innerHighlightAlpha: innerHighlightAlpha,
        glowColor: glowColor, blurSupported: false);

  // ---- Derived paint helpers (single source for every glass surface) ----
  LinearGradient get fill => LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [
        IndigoMint.glassWhite.withValues(alpha: fillTop), IndigoMint.glassWhite.withValues(alpha: fillBottom)]);
  LinearGradient get borderGradient => LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [
        IndigoMint.glassWhite.withValues(alpha: borderHighlightStart), IndigoMint.glassWhite.withValues(alpha: borderHighlightEnd)]);
  Color get border => IndigoMint.glassWhite.withValues(alpha: borderAlpha);
  Color get scrim => IndigoMint.scrimBlack.withValues(alpha: scrimAlpha);
  ImageFilter get filter => ImageFilter.blur(sigmaX: blurSigma.clamp(0, maxBlur), sigmaY: blurSigma.clamp(0, maxBlur));
  /// Light: bottom-right drop shadow (light source top-left). Dark: soft primary glow.
  List<BoxShadow> get elevation => [
        if (shadowAlpha > 0) BoxShadow(color: IndigoMint.scrimBlack.withValues(alpha: shadowAlpha), blurRadius: shadowBlur, offset: const Offset(4, 6)),
        if (glowAlpha > 0) BoxShadow(color: glowColor.withValues(alpha: glowAlpha), blurRadius: glowBlur),
      ];

  @override
  GlassTokens copyWith() => this;
  @override
  GlassTokens lerp(GlassTokens? o, double t) => t < .5 ? this : (o ?? this);
}
