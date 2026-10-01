// INDIGO MINT: locked colour system. Every colour in the app comes from here.
import 'package:flutter/material.dart';

abstract final class IndigoMint {
  // Brand
  static const primaryLight = Color(0xFF6366F1);
  static const primaryDark = Color(0xFF818CF8);
  static const primaryContainerLight = Color(0xFFE0E7FF);
  static const primaryContainerDark = Color(0xFF1E1B4B);
  static const onPrimaryLight = Color(0xFFFFFFFF);
  static const onPrimaryDark = Color(0xFF14163A);
  static const accentLight = Color(0xFF06B6D4);
  static const accentDark = Color(0xFF22D3EE);

  // Neutrals
  static const backgroundLight = Color(0xFFF4F6FA);
  static const backgroundDark = Color(0xFF0B0D12);
  static const surfaceLight = Color(0xFFFFFFFF);
  static const surfaceDark = Color(0xFF151A22);
  static const surfaceVariantLight = Color(0xFFE7EBF2);
  static const surfaceVariantDark = Color(0xFF1D242E);
  static const inkLight = Color(0xFF0E1116); // text primary @100%
  static const inkDark = Color(0xFFF2F5F9);
  static const textSecondaryAlphaLight = 0.62;
  static const textSecondaryAlphaDark = 0.68;
  static const outlineLight = Color(0xFFC6CEDA);
  static const outlineDark = Color(0xFF3A4453);

  // Semantic (never re-hued)
  static const successLight = Color(0xFF16A34A);
  static const successDark = Color(0xFF4ADE80);
  static const warningLight = Color(0xFFD97706);
  static const warningDark = Color(0xFFFBBF24);
  static const errorLight = Color(0xFFDC2626);
  static const errorDark = Color(0xFFF87171);

  // Base glass/scrim pigments (alpha applied in GlassTokens only)
  static const glassWhite = Color(0xFFFFFFFF);
  static const scrimBlack = Color(0xFF000000);

  /// Contrast-safe "ink" tone: same hue, pulled toward text-primary.
  /// Used only where the raw brand/semantic colour fails 4.5:1 as TEXT
  /// (measured: #6366F1 on white = 4.47, success-on-chip = 2.89).
  static Color ink(Color c, Color toward, double t) => Color.lerp(c, toward, t)!;
}

/// Semantic tokens not covered by ColorScheme, theme-resolved.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  final Color textPrimary, textSecondary;
  final Color accent;
  final Color brandInk; // primary as text / filled-button fill (≥4.5:1 guaranteed)
  final Color success, warning, error; // icon / fill base
  final Color successInk, warningInk, errorInk; // text on 12% tinted chips
  final Color focusRing;

  const AppColors({
    required this.textPrimary, required this.textSecondary, required this.accent, required this.brandInk,
    required this.success, required this.warning, required this.error,
    required this.successInk, required this.warningInk, required this.errorInk, required this.focusRing,
  });

  static final light = AppColors(
    textPrimary: IndigoMint.inkLight,
    textSecondary: IndigoMint.inkLight.withValues(alpha: IndigoMint.textSecondaryAlphaLight),
    accent: IndigoMint.accentLight,
    brandInk: IndigoMint.ink(IndigoMint.primaryLight, IndigoMint.inkLight, .10), // #5B5EDB: 5.16:1 w/ white
    success: IndigoMint.successLight, warning: IndigoMint.warningLight, error: IndigoMint.errorLight,
    successInk: IndigoMint.ink(IndigoMint.successLight, IndigoMint.inkLight, .35), // 5.0:1+
    warningInk: IndigoMint.ink(IndigoMint.warningLight, IndigoMint.inkLight, .35),
    errorInk: IndigoMint.ink(IndigoMint.errorLight, IndigoMint.inkLight, .20),
    focusRing: IndigoMint.ink(IndigoMint.accentLight, IndigoMint.inkLight, .32), // 3.2:1+ on glass (raw #06B6D4 = 2.27)
  );

  static final dark = AppColors(
    textPrimary: IndigoMint.inkDark,
    textSecondary: IndigoMint.inkDark.withValues(alpha: IndigoMint.textSecondaryAlphaDark),
    accent: IndigoMint.accentDark,
    brandInk: IndigoMint.primaryDark, // 6.5:1 on bg already
    success: IndigoMint.successDark, warning: IndigoMint.warningDark, error: IndigoMint.errorDark,
    successInk: IndigoMint.successDark, warningInk: IndigoMint.warningDark, errorInk: IndigoMint.errorDark,
    focusRing: IndigoMint.accentDark,
  );

  /// Brand gradient: exactly 2 stops, hue gap ≤45°. Only for ONE hero number/headline.
  static const brandGradient = LinearGradient(colors: [IndigoMint.primaryLight, IndigoMint.accentDark]);

  @override
  AppColors copyWith() => this;
  @override
  AppColors lerp(AppColors? o, double t) => o == null ? this : AppColors(
        textPrimary: Color.lerp(textPrimary, o.textPrimary, t)!, textSecondary: Color.lerp(textSecondary, o.textSecondary, t)!,
        accent: Color.lerp(accent, o.accent, t)!, brandInk: Color.lerp(brandInk, o.brandInk, t)!,
        success: Color.lerp(success, o.success, t)!, warning: Color.lerp(warning, o.warning, t)!, error: Color.lerp(error, o.error, t)!,
        successInk: Color.lerp(successInk, o.successInk, t)!, warningInk: Color.lerp(warningInk, o.warningInk, t)!,
        errorInk: Color.lerp(errorInk, o.errorInk, t)!, focusRing: Color.lerp(focusRing, o.focusRing, t)!);
}
