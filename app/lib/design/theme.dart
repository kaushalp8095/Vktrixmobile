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
    primary: AquaEmerald.primaryLight, onPrimary: AquaEmerald.onPrimaryLight,
    primaryContainer: AquaEmerald.primaryContainerLight, onPrimaryContainer: AquaEmerald.primaryContainerDark,
    secondary: AquaEmerald.secondaryLight, onSecondary: AquaEmerald.onPrimaryLight,
    secondaryContainer: AquaEmerald.primaryContainerLight, onSecondaryContainer: AquaEmerald.emeraldDeep,
    tertiary: AquaEmerald.accentLight, onTertiary: AquaEmerald.inkLight,
    error: AquaEmerald.errorLight, onError: AquaEmerald.onPrimaryLight,
    surface: AquaEmerald.backgroundLight, onSurface: AquaEmerald.inkLight,
    surfaceContainerLowest: AquaEmerald.surfaceLight, surfaceContainerLow: AquaEmerald.surfaceLight,
    surfaceContainer: AquaEmerald.surfaceLight, surfaceContainerHigh: AquaEmerald.surfaceVariantLight,
    surfaceContainerHighest: AquaEmerald.surfaceVariantLight,
    onSurfaceVariant: Color(0x9E0A1519), // ink @62%
    outline: AquaEmerald.outlineLight, outlineVariant: AquaEmerald.surfaceVariantLight,
    inverseSurface: AquaEmerald.surfaceDark, onInverseSurface: AquaEmerald.inkDark, inversePrimary: AquaEmerald.primaryDark,
    shadow: AquaEmerald.shadowTint, scrim: AquaEmerald.scrimBlack, surfaceTint: Colors.transparent,
  );

  static const darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: AquaEmerald.primaryDark, onPrimary: AquaEmerald.onPrimaryDark,
    primaryContainer: AquaEmerald.primaryContainerDark, onPrimaryContainer: AquaEmerald.primaryContainerLight,
    secondary: AquaEmerald.secondaryDark, onSecondary: AquaEmerald.backgroundDark,
    secondaryContainer: AquaEmerald.surfaceVariantDark, onSecondaryContainer: AquaEmerald.inkDark,
    tertiary: AquaEmerald.accentDark, onTertiary: AquaEmerald.backgroundDark,
    error: AquaEmerald.errorDark, onError: AquaEmerald.backgroundDark,
    surface: AquaEmerald.backgroundDark, onSurface: AquaEmerald.inkDark,
    surfaceContainerLowest: AquaEmerald.backgroundDark, surfaceContainerLow: AquaEmerald.surfaceDark,
    surfaceContainer: AquaEmerald.surfaceDark, surfaceContainerHigh: AquaEmerald.surfaceVariantDark,
    surfaceContainerHighest: AquaEmerald.surfaceVariantDark,
    onSurfaceVariant: Color(0xADEEF6F9), // ink @68%
    outline: AquaEmerald.outlineDark, outlineVariant: AquaEmerald.surfaceVariantDark,
    inverseSurface: AquaEmerald.surfaceLight, onInverseSurface: AquaEmerald.inkLight, inversePrimary: AquaEmerald.primaryLight,
    shadow: AquaEmerald.shadowTint, scrim: AquaEmerald.scrimBlack, surfaceTint: Colors.transparent,
  );

  /// Brand-lock. Pehle yahan Material You (Android 12+) ke surfaces adopt karte the.
  /// Aqua/Emerald theme ke saath wo galat lagta hai: system ka wallpaper se aaya
  /// grey/purple surface aur brand ka aqua/emerald aurora aapas me ladte hain aur
  /// glass ka tint bhi badal jata hai. Isliye ab **poore app ka palette locked**
  /// hai (backend/PDF/logo tiles se match karta hua) — sirf `outline` system se
  /// aata hai taaki high-contrast accessibility settings respect hon.
  static ColorScheme clamp(ColorScheme brand, ColorScheme? system) =>
      system == null ? brand : brand.copyWith(outline: system.outline);

  static ThemeData build(ColorScheme scheme, {bool blur = true}) {
    final dark = scheme.brightness == Brightness.dark;
    final c = dark ? AppColors.dark : AppColors.light;
    final glass = (dark ? GlassTokens.dark : GlassTokens.light).withFallback(blur);
    final text = AppType.textTheme(c.textPrimary, c.textSecondary);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      // Pehla frame aurora se pehle paint hota hai — base wash ka start colour
      // hi scaffold rakho, warna ek frame ke liye grey flash dikhta hai.
      scaffoldBackgroundColor: c.backgroundStart,
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
        fillColor: AquaEmerald.glassWhite.withValues(alpha: glass.fillTop),
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
class AquaEmeraldTheme extends StatelessWidget {
  final Widget Function(ThemeData light, ThemeData dark) builder;
  final bool blur;
  const AquaEmeraldTheme({super.key, required this.builder, this.blur = true});
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
