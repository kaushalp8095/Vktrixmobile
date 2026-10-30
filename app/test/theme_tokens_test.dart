// Aqua Emerald theme — locked palette + contrast contract.
//
// Theme ka "pro" hone ka matlab sirf sundar dikhna nahi: har wo colour jo text
// ban kar padha jaata hai WCAG AA (4.5:1) cross karna chahiye. Ye test wahi
// contract lock karta hai, taaki aage koi token "thoda brighter" karne ke
// chakkar me readability na tode. Numbers yahin likhe hain — design doc ki
// zaroorat nahi.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_shop/design/components/components.dart';
import 'package:mobile_shop/design/design.dart';

/// WCAG contrast. Foreground me alpha ho to pehle background par composite
/// karte hain — warna `computeLuminance()` translucent ink ko galat aanka leta hai.
double contrast(Color fg, Color bg) {
  final solid = fg.a < 1 ? Color.alphaBlend(fg, bg) : fg;
  final a = solid.computeLuminance(), b = bg.computeLuminance();
  return (math.max(a, b) + .05) / (math.min(a, b) + .05);
}

void main() {
  group('brand hues', () {
    test('the requested aqua and emerald are the source of truth', () {
      expect(AquaEmerald.aqua, const Color(0xFF29ABE2));
      expect(AquaEmerald.emerald, const Color(0xFF39B54A));
      // Aurora isi do hues se banta hai (50% 70% aqua, 30% 30% emerald).
      expect(AppColors.brandGradient.colors, [AquaEmerald.aqua, AquaEmerald.emerald]);
    });

    test('CTA gradient is the deep pair, so a white label still reads', () {
      for (final stop in AppColors.ctaGradient.colors) {
        expect(contrast(Colors.white, stop), greaterThanOrEqualTo(4.5),
            reason: '$stop must carry white 15px text');
      }
    });
  });

  group('light theme contrast', () {
    final c = AppColors.light;
    final bg = c.backgroundStart;

    test('text tokens clear AA on the aurora wash', () {
      expect(contrast(c.textPrimary, bg), greaterThanOrEqualTo(7));
      expect(contrast(c.textSecondary, bg), greaterThanOrEqualTo(4.5));
      // brandInk hi buttons/chips/icons ka text colour hai.
      expect(contrast(c.brandInk, bg), greaterThanOrEqualTo(4.5));
    });

    test('status inks stay readable on their own 12% tint', () {
      // StatusChip: brand 12% tint *over the page*, phir uske upar ink text.
      // Full-strength tint par nahi — warna test asli UI se zyada sakht ho jata.
      for (final (tint, ink) in [
        (c.success, c.successInk),
        (c.warning, c.warningInk),
        (c.error, c.errorInk),
      ]) {
        final chipBg = Color.alphaBlend(tint.withValues(alpha: .12), bg);
        expect(contrast(ink, chipBg), greaterThanOrEqualTo(4.5), reason: 'on $chipBg');
      }
    });

    test('the primary colour is the deep aqua (white onPrimary)', () {
      expect(AppTheme.lightScheme.primary, AquaEmerald.primaryLight);
      expect(contrast(Colors.white, AppTheme.lightScheme.primary), greaterThanOrEqualTo(4.5));
    });
  });

  group('dark theme contrast', () {
    final c = AppColors.dark;
    final bg = c.backgroundStart;

    test('text tokens clear AA on the dark aurora', () {
      expect(contrast(c.textPrimary, bg), greaterThanOrEqualTo(7));
      expect(contrast(c.textSecondary, bg), greaterThanOrEqualTo(4.5));
      expect(contrast(c.brandInk, bg), greaterThanOrEqualTo(4.5));
    });

    test('hero gradient text clears large-text AA (3:1) at every stop', () {
      // display 36px = large text. Bright brand hues yahan fail hote hain,
      // isliye text ke liye alag `textGradient` token hai.
      for (final (label, c) in [('light', AppColors.light), ('dark', AppColors.dark)]) {
        for (final stop in c.textGradient.colors) {
          expect(contrast(stop, c.backgroundStart), greaterThanOrEqualTo(3.0),
              reason: '$label hero stop $stop');
        }
      }
    });

    test('dark CTA carries the dark onPrimary ink', () {
      final onPrimary = AppTheme.darkScheme.onPrimary;
      for (final stop in [AquaEmerald.primaryDark, AquaEmerald.emeraldLight]) {
        expect(contrast(onPrimary, stop), greaterThanOrEqualTo(4.5), reason: '$stop');
      }
    });

    test('saturated semantics survive on near-black', () {
      for (final ink in [c.success, c.warning, c.error]) {
        expect(contrast(ink, bg), greaterThanOrEqualTo(4.5), reason: '$ink');
      }
    });
  });

  group('theme wiring', () {
    test('both extensions are installed and the scaffold matches the wash', () {
      for (final (scheme, colors) in [
        (AppTheme.lightScheme, AppColors.light),
        (AppTheme.darkScheme, AppColors.dark),
      ]) {
        final t = AppTheme.build(scheme);
        expect(t.extension<AppColors>(), isNotNull);
        expect(t.extension<GlassTokens>(), isNotNull);
        expect(t.scaffoldBackgroundColor, colors.backgroundStart,
            reason: 'first frame must not flash a different colour');
      }
    });

    test('glass is tinted, rim-lit and shadowed (not a flat white card)', () {
      for (final g in [GlassTokens.light, GlassTokens.dark]) {
        expect(g.borderHighlightStart, greaterThan(g.borderHighlightEnd), reason: 'top-left light source');
        expect(g.sheenAlpha, greaterThan(0));
        expect(g.fillTop, greaterThan(g.fillBottom));
      }
      expect(GlassTokens.light.elevation, isNotEmpty);
      expect(GlassTokens.dark.glowAlpha, greaterThan(0));
      // Blur-free devices get a denser fill instead of a ghost card.
      expect(GlassTokens.light.withFallback(false).fillTop, greaterThan(GlassTokens.light.fillTop));
    });
  });

  group('widgets', () {
    testWidgets('GradientText paints the brand gradient over its label', (t) async {
      await t.pumpWidget(const MaterialApp(
        home: Scaffold(body: Center(child: GradientText('₹1,24,500', style: AppType.display))),
      ));
      expect(find.text('₹1,24,500'), findsOneWidget);
      expect(find.byType(ShaderMask), findsOneWidget);
    });

    testWidgets('aurora background hosts content without exceptions', (t) async {
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.build(AppTheme.lightScheme),
        home: const AuroraBackground(child: Center(child: Text('Workshop'))),
      ));
      await t.pump(const Duration(milliseconds: 120));
      expect(find.text('Workshop'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });
}
