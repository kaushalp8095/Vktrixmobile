// GlassTokens: alpha-based, theme-driven frosted-glass recipe (Flutter's LocalGlass).
//
// 2026 refresh — glass ab "white 16% card" nahi, balki **tinted, top-lit glass**
// hai: brand hue ka halka tint, ek diagonal specular sheen, hairline rim jo
// top-left par chamakta hai, aur aqua-tinted soft shadow (black shadow coloured
// aurora par maila dikhta tha).
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'colors.dart';

@immutable
class GlassTokens extends ThemeExtension<GlassTokens> {
  final double fillTop, fillBottom; // white alpha, diagonal gradient
  final Color tint; // brand hue mixed into the bottom half of the fill
  final double tintAlpha;
  final double borderAlpha; // 1dp white
  final double borderHighlightStart, borderHighlightEnd; // top-lit TL→BR
  final double sheenAlpha; // diagonal specular sweep inside the card
  final double scrimAlpha; // black behind text on glass
  final double blurSigma; // dp
  final double shadowBlur, shadowAlpha; // light only
  final double shadowBlurTight, shadowAlphaTight; // second, tighter light shadow
  final double glowBlur, glowAlpha; // dark only (brand glow)
  final double innerHighlightAlpha; // 1dp inner top highlight
  final Color glowColor;
  /// No-blur fallback (<API 31 or blur disabled): fill +6%, border +4%.
  final bool blurSupported;

  const GlassTokens({
    required this.fillTop, required this.fillBottom, required this.tint, required this.tintAlpha,
    required this.borderAlpha, required this.borderHighlightStart, required this.borderHighlightEnd,
    required this.sheenAlpha, required this.scrimAlpha, required this.blurSigma,
    required this.shadowBlur, required this.shadowAlpha, required this.shadowBlurTight, required this.shadowAlphaTight,
    required this.glowBlur, required this.glowAlpha, required this.innerHighlightAlpha,
    required this.glowColor, this.blurSupported = true,
  });

  /// 2026-10 audit tuning. Pehle card ka fill .42/.16 tha aur shadow .13/.07 —
  /// matlab card background se alag *shadow* se dikhta tha, apne glass se nahi:
  /// golden me card ke neeche ~-47 luminance ka grey-blue band ban raha tha
  /// ("grey ledge" look) jabki card khud sirf +18 upar tha. Ab hierarchy
  /// palat gayi hai — glass sabse loud cue hai (bada, soft, low-alpha shadow).
  static const light = GlassTokens(
    fillTop: .54, fillBottom: .22, tint: AquaEmerald.emerald, tintAlpha: .05,
    borderAlpha: .28, borderHighlightStart: .52, borderHighlightEnd: .09, sheenAlpha: .14,
    scrimAlpha: .03, blurSigma: 28,
    shadowBlur: 40, shadowAlpha: .075, shadowBlurTight: 12, shadowAlphaTight: .045,
    glowBlur: 0, glowAlpha: 0, innerHighlightAlpha: 0, glowColor: AquaEmerald.aqua,
  );
  static const dark = GlassTokens(
    fillTop: .12, fillBottom: .03, tint: AquaEmerald.aqua, tintAlpha: .06,
    borderAlpha: .18, borderHighlightStart: .40, borderHighlightEnd: .06, sheenAlpha: .06,
    scrimAlpha: .30, blurSigma: 22,
    shadowBlur: 0, shadowAlpha: 0, shadowBlurTight: 0, shadowAlphaTight: 0,
    glowBlur: 30, glowAlpha: .14, innerHighlightAlpha: .18, glowColor: AquaEmerald.aqua,
  );

  static const maxBlur = 32.0;
  static const maxStackedLayers = 3;

  GlassTokens withFallback(bool supported) => supported ? this : GlassTokens(
        fillTop: (fillTop + .06).clamp(0, 1), fillBottom: (fillBottom + .06).clamp(0, 1),
        tint: tint, tintAlpha: tintAlpha,
        borderAlpha: borderAlpha + .04,
        borderHighlightStart: (borderHighlightStart + .04).clamp(0, 1), borderHighlightEnd: borderHighlightEnd + .04,
        sheenAlpha: sheenAlpha, scrimAlpha: scrimAlpha,
        blurSigma: 0, shadowBlur: shadowBlur, shadowAlpha: shadowAlpha,
        shadowBlurTight: shadowBlurTight, shadowAlphaTight: shadowAlphaTight,
        glowBlur: glowBlur, glowAlpha: glowAlpha, innerHighlightAlpha: innerHighlightAlpha,
        glowColor: glowColor, blurSupported: false);

  // ---- Derived paint helpers (single source for every glass surface) ----
  /// Diagonal white → brand-tinted fade. Diagonal (not vertical) is what makes
  /// a rectangle read as a sheet of glass rather than a gradient panel.
  LinearGradient get fill => LinearGradient(
        begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: [
          AquaEmerald.glassWhite.withValues(alpha: fillTop),
          Color.alphaBlend(tint.withValues(alpha: tintAlpha), AquaEmerald.glassWhite.withValues(alpha: fillBottom)),
        ],
      );

  /// Specular sweep: a soft white wedge falling from the top-left corner.
  LinearGradient get sheen => LinearGradient(
        begin: Alignment.topLeft, end: Alignment.center,
        colors: [AquaEmerald.glassWhite.withValues(alpha: sheenAlpha), AquaEmerald.glassWhite.withValues(alpha: 0)],
      );

  LinearGradient get borderGradient => LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [
        AquaEmerald.glassWhite.withValues(alpha: borderHighlightStart),
        AquaEmerald.glassWhite.withValues(alpha: borderHighlightEnd),
      ]);
  Color get border => AquaEmerald.glassWhite.withValues(alpha: borderAlpha);
  Color get scrim => AquaEmerald.scrimBlack.withValues(alpha: scrimAlpha);
  ImageFilter get filter => ImageFilter.blur(sigmaX: blurSigma.clamp(0, maxBlur), sigmaY: blurSigma.clamp(0, maxBlur));

  /// Light: two-layer aqua-tinted drop shadow (wide + tight). Dark: brand glow.
  List<BoxShadow> get elevation => [
        if (shadowAlpha > 0)
          BoxShadow(color: AquaEmerald.shadowTint.withValues(alpha: shadowAlpha),
            blurRadius: shadowBlur, offset: const Offset(0, 10)),
        if (shadowAlphaTight > 0)
          BoxShadow(color: AquaEmerald.shadowTint.withValues(alpha: shadowAlphaTight),
            blurRadius: shadowBlurTight, offset: const Offset(0, 2)),
        if (glowAlpha > 0)
          BoxShadow(color: glowColor.withValues(alpha: glowAlpha), blurRadius: glowBlur, spreadRadius: 1),
      ];

  @override
  GlassTokens copyWith() => this;
  @override
  GlassTokens lerp(GlassTokens? o, double t) => t < .5 ? this : (o ?? this);
}
