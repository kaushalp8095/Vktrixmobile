// GradientText: brand gradient (aqua → emerald) se bhara hua text.
//
// Rule: ek screen par **ek hi** gradient number/headline. Gradient text 15px se
// chhota ho to antialiasing se edges gandhe dikhte hain, isliye yahan min 24px
// ka style pass karein (display/headline/title). Chhote labels ke liye
// `context.colors.brandInk` hi use karein.
import 'package:flutter/material.dart';
import '../design.dart';

class GradientText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  /// `null` = theme ka `textGradient` (light: deep pair, dark: bright pair).
  final Gradient? gradient;
  final TextAlign textAlign;
  final int? maxLines;
  final bool softWrap;

  const GradientText(
    this.text, {
    super.key,
    this.style,
    this.gradient,
    this.textAlign = TextAlign.start,
    this.maxLines,
    this.softWrap = true,
  });

  @override
  Widget build(BuildContext context) {
    // Theme extension missing ho (preview/test widget bina AppTheme.build) to
    // crash na ho — brand gradient par gir jao.
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>();
    final base = style ?? theme.textTheme.titleLarge ?? AppType.title;
    final paint = gradient ?? colors?.textGradient ?? AppColors.brandGradient;
    return ShaderMask(
      // srcIn: sirf text ke andar gradient dikhe, baaki transparent.
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => paint.createShader(Offset.zero & bounds.size),
      child: Text(
        text,
        textAlign: textAlign,
        maxLines: maxLines,
        softWrap: softWrap,
        // ShaderMask mask ke roop me kaam karta hai — text ka apna colour safed
        // (opaque) hona zaroori hai, warna gradient fade ho jata hai.
        style: base.copyWith(color: Colors.white),
      ),
    );
  }
}
