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
  final Gradient gradient;
  final TextAlign textAlign;
  final int? maxLines;
  final bool softWrap;

  const GradientText(
    this.text, {
    super.key,
    this.style,
    this.gradient = AppColors.brandGradient,
    this.textAlign = TextAlign.start,
    this.maxLines,
    this.softWrap = true,
  });

  @override
  Widget build(BuildContext context) {
    final base = style ?? context.type.titleLarge!;
    return ShaderMask(
      // srcIn: sirf text ke andar gradient dikhe, baaki transparent.
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => gradient.createShader(Offset.zero & bounds.size),
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
