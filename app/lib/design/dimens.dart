// Spacing (strict 8dp grid with 4/12/20 half-steps), shapes, sizes.
import 'package:flutter/material.dart';

abstract final class Space {
  static const x4 = 4.0, x8 = 8.0, x12 = 12.0, x16 = 16.0, x20 = 20.0, x24 = 24.0, x32 = 32.0, x48 = 48.0;
  static const screen = x16; // screen horizontal padding
  static const section = x24; // gap between sections
  static const card = x20; // card inner padding (16–20)
  static const item = x12; // list item gap
  static const minTouch = x48; // min hit target
  static const icon = 24.0;
  static const tabBarLift = x16; // floating tab bar above nav inset
}

abstract final class Radii {
  static const xs = 8.0, sm = 12.0, md = 16.0, lg = 24.0, xl = 32.0, full = 999.0;
  static const card = lg, sheet = xl, inner = md;
  /// Nested rule: inner = outer − padding (never below xs).
  static double nested(double outer, double padding) => (outer - padding).clamp(xs, outer);
}

abstract final class Shapes {
  static BorderRadius r(double v) => BorderRadius.circular(v);
  static final xs = r(Radii.xs), sm = r(Radii.sm), md = r(Radii.md), lg = r(Radii.lg), xl = r(Radii.xl), pill = r(Radii.full);
  static final card = RoundedRectangleBorder(borderRadius: lg);
  static final sheet = RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.xl)));
  static const stadium = StadiumBorder();
}
