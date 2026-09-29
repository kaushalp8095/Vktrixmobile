// BrandMark: glass disc + outlined phone glyph. Used on Splash and Login.
import 'package:flutter/material.dart';
import '../design.dart';
import 'glass_surface.dart';

class BrandMark extends StatelessWidget {
  final double size;
  const BrandMark({super.key, this.size = 96});
  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Vktrix Mobile logo', image: true,
        child: SizedBox.square(
          dimension: size,
          child: GlassSurface(radius: Radii.full, child: Center(
            child: Icon(Icons.smartphone_outlined, size: size * .46, color: context.colors.brandInk))),
        ),
      );
}
