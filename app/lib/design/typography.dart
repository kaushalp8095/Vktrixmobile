// Type scale: Manrope (bundled, offline). Single family; numbers use tabular figures.
import 'package:flutter/material.dart';

abstract final class AppType {
  static const family = 'Manrope';
  static const _tabular = [FontFeature.tabularFigures()];

  static const display = TextStyle(fontFamily: family, fontSize: 36, fontWeight: FontWeight.w800, height: 1.15, letterSpacing: -0.6, fontFeatures: _tabular);
  static const headline = TextStyle(fontFamily: family, fontSize: 28, fontWeight: FontWeight.w600, height: 1.22, letterSpacing: -0.3);
  static const title = TextStyle(fontFamily: family, fontSize: 21, fontWeight: FontWeight.w600, height: 1.30, letterSpacing: -0.1);
  static const bodyLarge = TextStyle(fontFamily: family, fontSize: 16, fontWeight: FontWeight.w400, height: 1.45);
  static const bodyMedium = TextStyle(fontFamily: family, fontSize: 15, fontWeight: FontWeight.w400, height: 1.40);
  static const labelLarge = TextStyle(fontFamily: family, fontSize: 15, fontWeight: FontWeight.w600, height: 1.20, letterSpacing: 0.1);
  static const labelSmall = TextStyle(fontFamily: family, fontSize: 12, fontWeight: FontWeight.w500, height: 1.30, letterSpacing: 0.2);

  /// Maps the 7 locked styles onto Material's TextTheme; unused M3 slots
  /// alias to the nearest locked style (no new sizes invented).
  static TextTheme textTheme(Color primary, Color secondary) {
    TextStyle p(TextStyle s) => s.copyWith(color: primary);
    return TextTheme(
      displayLarge: p(display), displayMedium: p(display), displaySmall: p(display),
      headlineLarge: p(headline), headlineMedium: p(headline), headlineSmall: p(title),
      titleLarge: p(title), titleMedium: p(labelLarge), titleSmall: p(labelLarge),
      bodyLarge: p(bodyLarge), bodyMedium: p(bodyMedium), bodySmall: labelSmall.copyWith(color: secondary, fontWeight: FontWeight.w400),
      labelLarge: p(labelLarge), labelMedium: p(labelSmall), labelSmall: labelSmall.copyWith(color: secondary),
    );
  }
}
