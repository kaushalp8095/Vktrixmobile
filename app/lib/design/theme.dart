// Theme: Light/Dark schemes, brand-clamped dynamic colour, glass + semantic extensions.
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'colors.dart';
import 'dimens.dart';
import 'glass.dart';
import 'typography.dart';

abstract final class AppTheme {
  static const lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: IndigoMint.primaryLight, onPrimary: IndigoMint.onPrimaryLight,
    primaryContainer: IndigoMint.primaryContainerLight, onPrimaryContainer: IndigoMint.primaryContainerDark,
    secondary: IndigoMint.accentLight, onSecondary: IndigoMint.inkLight,
    secondaryContainer: IndigoMint.surfaceVariantLight, onSecondaryContainer: IndigoMint.inkLight,
    tertiary: IndigoMint.accentLight, onTertiary: IndigoMint.inkLight,
    error: IndigoMint.errorLight, onError: IndigoMint.onPrimaryLight,
    surface: IndigoMint.backgroundLight, onSurface: IndigoMint.inkLight,
    surfaceContainerLowest: IndigoMint.surfaceLight, surfaceContainerLow: IndigoMint.surfaceLight,
    surfaceContainer: IndigoMint.surfaceLight, surfaceContainerHigh: IndigoMint.surfaceVariantLight,
    surfaceContainerHighest: IndigoMint.surfaceVariantLight,
    onSurfaceVariant: Color(0x9E0E1116), // ink @62%
    outline: IndigoMint.outlineLight, outlineVariant: IndigoMint.surfaceVariantLight,
    inverseSurface: IndigoMint.surfaceDark, onInverseSurface: IndigoMint.inkDark, inversePrimary: IndigoMint.primaryDark,
    shadow: IndigoMint.scrimBlack, scrim: IndigoMint.scrimBlack, surfaceTint: Colors.transparent,
  );

  static const darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: IndigoMint.primaryDark, onPrimary: IndigoMint.onPrimaryDark,
    primaryContainer: IndigoMint.primaryContainerDark, onPrimaryContainer: IndigoMint.primaryContainerLight,
    secondary: IndigoMint.accentDark, onSecondary: IndigoMint.backgroundDark,
    secondaryContainer: IndigoMint.surfaceVariantDark, onSecondaryContainer: IndigoMint.inkDark,
    tertiary: IndigoMint.accentDark, onTertiary: IndigoMint.backgroundDark,
    error: IndigoMint.errorDark, onError: IndigoMint.backgroundDark,
    surface: IndigoMint.backgroundDark, onSurface: IndigoMint.inkDark,
    surfaceContainerLowest: IndigoMint.backgroundDark, surfaceContainerLow: IndigoMint.surfaceDark,
    surfaceContainer: IndigoMint.surfaceDark, surfaceContainerHigh: IndigoMint.surfaceVariantDark,
    surfaceContainerHighest: IndigoMint.surfaceVariantDark,
    onSurfaceVariant: Color(0xADF2F5F9), // ink @68%
    outline: IndigoMint.outlineDark, outlineVariant: IndigoMint.surfaceVariantDark,
    inverseSurface: IndigoMint.surfaceLight, onInverseSurface: IndigoMint.inkLight, inversePrimary: IndigoMint.primaryLight,
    shadow: IndigoMint.scrimBlack, scrim: IndigoMint.scrimBlack, surfaceTint: Colors.transparent,
  );

  /// Brand-clamp: take ONLY background/surface/outline from the system (Android 12+),
  /// keep primary/accent/semantic as Indigo Mint.
  static ColorScheme clamp(ColorScheme brand, ColorScheme? system) => system == null ? brand : brand.copyWith(
        surface: system.surface, surfaceContainerLowest: system.surfaceContainerLowest,
        surfaceContainerLow: system.surfaceContainerLow, surfaceContainer: system.surfaceContainer,
        surfaceContainerHigh: system.surfaceContainerHigh, surfaceContainerHighest: system.surfaceContainerHighest,
        outline: system.outline, outlineVariant: system.outlineVariant);

  static ThemeData build(ColorScheme scheme, {bool blur = true}) {
    final dark = scheme.brightness == Brightness.dark;
    final c = dark ? AppColors.dark : AppColors.light;
    final glass = (dark ? GlassTokens.dark : GlassTokens.light).withFallback(blur);
    final text = AppType.textTheme(c.textPrimary, c.textSecondary);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      fontFamily: AppType.family,
      textTheme: text,
      extensions: [c, glass],
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded, // ≥48dp
      iconTheme: IconThemeData(size: Space.icon, color: c.textPrimary),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent, surfaceTintColor: Colors.transparent, elevation: 0,
        foregroundColor: c.textPrimary, titleTextStyle: text.titleLarge, centerTitle: false,
        systemOverlayStyle: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(
            statusBarColor: Colors.transparent, systemNavigationBarColor: Colors.transparent,
            systemNavigationBarContrastEnforced: false),
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: false,
        filled: true,
        fillColor: IndigoMint.glassWhite.withValues(alpha: glass.fillTop),
        contentPadding: const EdgeInsets.symmetric(horizontal: Space.x16, vertical: Space.x16),
        labelStyle: text.bodyMedium?.copyWith(color: c.textSecondary),
        floatingLabelStyle: text.labelSmall?.copyWith(color: c.brandInk),
        border: OutlineInputBorder(borderRadius: Shapes.md, borderSide: BorderSide(color: scheme.outline)),
        enabledBorder: OutlineInputBorder(borderRadius: Shapes.md, borderSide: BorderSide(color: scheme.outline)),
        focusedBorder: OutlineInputBorder(borderRadius: Shapes.md, borderSide: BorderSide(color: c.focusRing, width: 2)),
        errorBorder: OutlineInputBorder(borderRadius: Shapes.md, borderSide: BorderSide(color: c.error)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: Shapes.md, borderSide: BorderSide(color: c.error, width: 2)),
      ),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
        backgroundColor: c.brandInk, foregroundColor: scheme.onPrimary, minimumSize: const Size(Space.minTouch, 52),
        shape: Shapes.stadium, textStyle: AppType.labelLarge, padding: const EdgeInsets.symmetric(horizontal: Space.x24))),
      outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(
        foregroundColor: c.textPrimary, minimumSize: const Size(Space.minTouch, 52), shape: Shapes.stadium,
        side: BorderSide(color: scheme.outline), textStyle: AppType.labelLarge)),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(
        foregroundColor: c.brandInk, minimumSize: const Size(Space.minTouch, Space.minTouch), textStyle: AppType.labelLarge)),
      iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(minimumSize: const Size(Space.minTouch, Space.minTouch))),
      cardTheme: CardThemeData(color: scheme.surfaceContainer, elevation: 0, shape: Shapes.card, margin: EdgeInsets.zero),
      dialogTheme: DialogThemeData(shape: RoundedRectangleBorder(borderRadius: Shapes.xl), backgroundColor: scheme.surfaceContainer),
      bottomSheetTheme: BottomSheetThemeData(shape: Shapes.sheet, backgroundColor: scheme.surfaceContainer, showDragHandle: true),
      snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: Shapes.md),
          contentTextStyle: AppType.bodyMedium.copyWith(color: scheme.onInverseSurface)),
      dividerTheme: DividerThemeData(color: scheme.outline.withValues(alpha: .5), thickness: 1, space: Space.x24),
      focusColor: c.focusRing.withValues(alpha: .24),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: PredictiveBackPageTransitionsBuilder(), // Android 14+ predictive back
      }),
    );
  }
}

/// Wrap MaterialApp with this: resolves dynamic colour (API 31+) with static fallback.
class IndigoMintTheme extends StatelessWidget {
  final Widget Function(ThemeData light, ThemeData dark) builder;
  final bool blur;
  const IndigoMintTheme({super.key, required this.builder, this.blur = true});
  @override
  Widget build(BuildContext context) => DynamicColorBuilder(
        builder: (sysLight, sysDark) => builder(
          AppTheme.build(AppTheme.clamp(AppTheme.lightScheme, sysLight), blur: blur),
          AppTheme.build(AppTheme.clamp(AppTheme.darkScheme, sysDark), blur: blur),
        ),
      );
}

/// Ergonomic accessors (the Flutter equivalent of LocalGlass.current).
extension DesignX on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
  GlassTokens get glass => Theme.of(this).extension<GlassTokens>()!;
  TextTheme get type => Theme.of(this).textTheme;
  ColorScheme get scheme => Theme.of(this).colorScheme;
}
