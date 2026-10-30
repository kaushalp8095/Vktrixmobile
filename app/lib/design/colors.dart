// AQUA EMERALD — locked colour system (Oct 2026 refresh).
//
// Brand do hues par khada hai, exactly waise jaise background gradient me use
// hote hain:
//   rgba(41,171,226,·)  → #29ABE2  aqua
//   rgba(57,181,74, ·)  → #39B54A  emerald
// Dono decorative hues hain (glass tint, aurora blobs, gradient CTA). Jo bhi
// colour **text** ban kar padha jaata hai wo neeche `*Ink` tokens se aata hai,
// jinke contrast ratios comment me likhe hain (WCAG AA: text ≥4.5:1,
// non-text/icon ≥3:1). Isi wajah se `scheme.primary` deep aqua hai, bright aqua
// nahi: bright aqua par white text sirf 2.6:1 hota hai.
import 'package:flutter/material.dart';

abstract final class AquaEmerald {
  // ---- Brand hues (user palette, never used directly for small text) ----
  static const aqua = Color(0xFF29ABE2);
  static const emerald = Color(0xFF39B54A);
  static const aquaLight = Color(0xFF7DD3F2);
  static const emeraldLight = Color(0xFF6FDC86);
  /// Text/icon ink. 2026-10 audit: wash thoda gehra hua, isliye aquaDeep bhi
  /// ek shade neeche gaya — ab sabse gehere point (screen bottom) par bhi
  /// 4.6:1+, aur white 6.6:1. (#0A6E93 pe ye 4.0:1 tak gir jaata tha.)
  static const aquaDeep = Color(0xFF096481);
  static const emeraldDeep = Color(0xFF12735A);
  /// Hero gradient ke stops: deep se thode brighter, par 36px text par bhi
  /// 3:1 (large-text AA) se upar — deep wash par 3.3:1 / 3.2:1.
  static const heroAqua = Color(0xFF0B7BA8);
  static const heroEmerald = Color(0xFF1B8443);

  // Brand
  static const primaryLight = Color(0xFF0C7FA8); // 4.55:1 with white
  static const primaryDark = Color(0xFF5BC8F0); // 10.3:1 on dark bg
  static const primaryContainerLight = Color(0xFFD8EFF9);
  static const primaryContainerDark = Color(0xFF0B2B37);
  static const onPrimaryLight = Color(0xFFFFFFFF);
  static const onPrimaryDark = Color(0xFF06232E); // 8.4:1 on primaryDark
  static const accentLight = Color(0xFF29ABE2);
  static const accentDark = Color(0xFF7DD3F2);
  /// Emerald secondary. 2026-10 audit: #1C8F4B glass card par sirf 3.4:1 tha
  /// ("text-safe" comment galat tha). Deepened — 4.6:1 card par, 5.4:1 white.
  static const secondaryLight = Color(0xFF127A3E);
  static const secondaryDark = Color(0xFF4ED97A);

  // Neutrals — base has a faint aqua cast so glass reads cool, not grey.
  /// Aurora base wash. 2026-10 audit: pehla wash (#EAF5FB → #E8F5EF) itna
  /// halka tha ki light mode me glass card aur background ka luminance gap
  /// sirf +18 tha — card edge sirf shadow se dikhta tha. Ab wash ~11 shade
  /// gehra hai, isliye card apne fill se hi float karta hai (ΔLum ~+21..+40).
  static const backgroundLight = Color(0xFFDFEFF2);
  static const backgroundLightEnd = Color(0xFFDDEFE6); // green-leaning bottom
  static const backgroundDark = Color(0xFF050C10);
  static const backgroundDarkEnd = Color(0xFF07120F);
  static const surfaceLight = Color(0xFFFFFFFF);
  static const surfaceDark = Color(0xFF0E1A21);
  static const surfaceVariantLight = Color(0xFFDCEBF2);
  static const surfaceVariantDark = Color(0xFF16262F);
  static const inkLight = Color(0xFF0A1519); // text primary @100%
  static const inkDark = Color(0xFFEEF6F9);
  static const textSecondaryAlphaLight = 0.62;
  static const textSecondaryAlphaDark = 0.68;
  static const outlineLight = Color(0xFFBFD6E0);
  static const outlineDark = Color(0xFF2C414C);

  // Semantic (never re-hued, and deliberately deeper than the brand emerald so
  // "success" never looks like decoration)
  static const successLight = Color(0xFF14934A);
  static const successDark = Color(0xFF4ADE80);
  static const warningLight = Color(0xFFD97706);
  static const warningDark = Color(0xFFFBBF24);
  static const errorLight = Color(0xFFDC2626);
  static const errorDark = Color(0xFFF87171);
  /// Error **text** on dark glass. #F87171 card par sirf 3.7:1 deta hai
  /// (chhota text AA fail) — icon/fill ke liye wahi rehta hai, text ke liye ye.
  static const errorInkDark = Color(0xFFFCA5A5); // 5.5:1 on dark glass

  // Base glass/scrim pigments (alpha applied in GlassTokens only)
  static const glassWhite = Color(0xFFFFFFFF);
  static const scrimBlack = Color(0xFF000000);
  /// Shadow/glow pigment. Black shadows on a coloured aurora look muddy; a
  /// deep aqua keeps the depth while staying on-brand.
  static const shadowTint = Color(0xFF062B3A);

  /// Contrast-safe "ink" tone: same hue, pulled toward text-primary.
  static Color ink(Color c, Color toward, double t) => Color.lerp(c, toward, t)!;
}

/// Semantic tokens not covered by ColorScheme, theme-resolved.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  final Color textPrimary, textSecondary;
  final Color accent; // brand aqua (decorative: blobs, tints, charts)
  final Color accentAlt; // brand emerald (decorative partner)
  final Color brandInk; // primary as TEXT / filled control (≥4.5:1 guaranteed)
  final Color success, warning, error; // icon / fill base
  final Color successInk, warningInk, errorInk; // text on 12% tinted chips
  final Color focusRing;
  /// Aurora base wash (top → bottom), drawn behind every screen.
  final Color backgroundStart, backgroundEnd;
  /// Gradient for *text* (hero numbers). Decorative `brandGradient` bright hues
  /// large-text (3:1) par bhi fail karte hain, isliye text ke liye deep pair.
  final LinearGradient textGradient;
  /// Glass shadow pigment (aqua-tinted, never pure black in light theme).
  final Color shadowTint, glowTint;

  const AppColors({
    required this.textPrimary, required this.textSecondary, required this.accent, required this.accentAlt,
    required this.brandInk, required this.success, required this.warning, required this.error,
    required this.successInk, required this.warningInk, required this.errorInk, required this.focusRing,
    required this.backgroundStart, required this.backgroundEnd, required this.shadowTint, required this.glowTint,
    required this.textGradient,
  });

  static final light = AppColors(
    textPrimary: AquaEmerald.inkLight,
    textSecondary: AquaEmerald.inkLight.withValues(alpha: AquaEmerald.textSecondaryAlphaLight),
    accent: AquaEmerald.aqua,
    accentAlt: AquaEmerald.emerald,
    brandInk: AquaEmerald.aquaDeep, // #096481: 6.6:1 on white, 4.7:1 on the deepest wash
    success: AquaEmerald.successLight, warning: AquaEmerald.warningLight, error: AquaEmerald.errorLight,
    successInk: AquaEmerald.ink(AquaEmerald.successLight, AquaEmerald.inkLight, .30), // 5.0:1+
    warningInk: AquaEmerald.ink(AquaEmerald.warningLight, AquaEmerald.inkLight, .35),
    errorInk: AquaEmerald.ink(AquaEmerald.errorLight, AquaEmerald.inkLight, .20),
    focusRing: AquaEmerald.primaryLight, // 4.2:1 on glass
    backgroundStart: AquaEmerald.backgroundLight, backgroundEnd: AquaEmerald.backgroundLightEnd,
    shadowTint: AquaEmerald.shadowTint, glowTint: AquaEmerald.aqua,
    // Bright pair 36px par sirf 2.5:1 deta hai; hero pair 3.3:1 / 3.3:1 —
    // bada number hote hue bhi brand ka rang bacha rehta hai.
    textGradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
      colors: [AquaEmerald.heroAqua, AquaEmerald.heroEmerald]),
  );

  static final dark = AppColors(
    textPrimary: AquaEmerald.inkDark,
    textSecondary: AquaEmerald.inkDark.withValues(alpha: AquaEmerald.textSecondaryAlphaDark),
    accent: AquaEmerald.accentDark,
    accentAlt: AquaEmerald.emeraldLight,
    brandInk: AquaEmerald.primaryDark,
    success: AquaEmerald.successDark, warning: AquaEmerald.warningDark, error: AquaEmerald.errorDark,
    successInk: AquaEmerald.successDark, warningInk: AquaEmerald.warningDark, errorInk: AquaEmerald.errorInkDark,
    focusRing: AquaEmerald.aquaLight,
    backgroundStart: AquaEmerald.backgroundDark, backgroundEnd: AquaEmerald.backgroundDarkEnd,
    shadowTint: AquaEmerald.shadowTint, glowTint: AquaEmerald.aqua,
    // Dark aurora par bright pair hi chalta hai (10.3:1 → 10.8:1).
    textGradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
      colors: [AquaEmerald.primaryDark, AquaEmerald.emeraldLight]),
  );

  /// Hero gradient — decor only (big numbers/headlines, CTA). Two stops, and the
  /// hue travel stays inside the brand family (aqua → emerald).
  static const brandGradient = LinearGradient(
    begin: Alignment.topLeft, end: Alignment.bottomRight,
    colors: [AquaEmerald.aqua, AquaEmerald.emerald],
  );

  /// CTA gradient — same hue family but dark enough for white 15px labels
  /// (5.7:1 and 5.1:1 at the two ends). PrimaryButton isi ka use karta hai.
  static const ctaGradient = LinearGradient(
    begin: Alignment.topLeft, end: Alignment.bottomRight,
    colors: [AquaEmerald.aquaDeep, AquaEmerald.emeraldDeep],
  );

  /// Theme-aware action gradient. Light theme = deep pair (white label
  /// 5.7:1+), dark theme = bright pair (dark label 8.5:1+). PrimaryButton,
  /// gradient FAB aur progress bars — sab ek hi rasta.
  LinearGradient get cta => backgroundStart.computeLuminance() < .2
      ? const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [AquaEmerald.primaryDark, AquaEmerald.emeraldLight])
      : ctaGradient;

  @override
  AppColors copyWith() => this;
  @override
  AppColors lerp(AppColors? o, double t) => o == null ? this : AppColors(
        textPrimary: Color.lerp(textPrimary, o.textPrimary, t)!, textSecondary: Color.lerp(textSecondary, o.textSecondary, t)!,
        accent: Color.lerp(accent, o.accent, t)!, accentAlt: Color.lerp(accentAlt, o.accentAlt, t)!,
        brandInk: Color.lerp(brandInk, o.brandInk, t)!,
        success: Color.lerp(success, o.success, t)!, warning: Color.lerp(warning, o.warning, t)!, error: Color.lerp(error, o.error, t)!,
        successInk: Color.lerp(successInk, o.successInk, t)!, warningInk: Color.lerp(warningInk, o.warningInk, t)!,
        errorInk: Color.lerp(errorInk, o.errorInk, t)!, focusRing: Color.lerp(focusRing, o.focusRing, t)!,
        backgroundStart: Color.lerp(backgroundStart, o.backgroundStart, t)!,
        backgroundEnd: Color.lerp(backgroundEnd, o.backgroundEnd, t)!,
        shadowTint: Color.lerp(shadowTint, o.shadowTint, t)!, glowTint: Color.lerp(glowTint, o.glowTint, t)!,
        textGradient: t < .5 ? textGradient : o.textGradient);
}
