// SHOP LOGO AVATAR — app ke har jagah ek hi tarah ka logo (Oct 2026 style).
//
// Kahin circle, kahin square, kahin contain me chhota floating — teen tarah ke
// logo dikh rahe the. Ab har jagah ek hi shape: **rounded square** (modern app
// icon / squircle ratio ~26%), aur andar wahi image jo server upload par
// auto-adjust karke banti hai (margin trim + centre + square tile). Isliye 2:1
// ya transparent logo bhi box ko poora bharta hai.
//
// Poora logo (base64, 100-700 KB) list me nahi jaata; server har logo ka 128px
// thumbnail (`logo_thumb`, ~2-6 KB) bhejta hai. Wo na ho (purana PNG logo,
// upload se pehle) to brand initial ya store icon dikhta hai — kabhi crash nahi.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../design/design.dart';

/// Data URL (ya seedha base64) → bytes. Kharab data par `null`.
Uint8List? decodeLogoThumb(dynamic value) {
  final raw = '${value ?? ''}'.trim();
  if (raw.isEmpty || raw == 'null') return null;
  final comma = raw.indexOf(',');
  final data = comma >= 0 ? raw.substring(comma + 1) : raw;
  if (data.isEmpty) return null;
  try { return base64Decode(data); } catch (_) { return null; }
}

/// Squircle radius — app-icon grids (iOS/Android 2026) 22–26% use karte hain.
double logoRadius(double size) => size * .26;

class ShopLogoAvatar extends StatelessWidget {
  /// `logo_thumb` (data URL) — null/khaali/kharaab ho to fallback.
  final String? thumb;
  final bool active;
  final double size;
  /// Logo na ho to jagah ek letter (shop/owner ke naam ka pehla akshar)
  /// dikhana hai ya store ka icon.
  final String? fallbackLetter;
  /// Hero-style tile (Dashboard top bar, Profile card): brand tint background
  /// aur halka border, taaki chhote size par bhi logo "set" lage.
  final bool elevated;
  final bool circle;

  const ShopLogoAvatar({
    super.key,
    this.thumb,
    required this.active,
    this.size = 44,
    this.fallbackLetter,
    this.elevated = true,
    this.circle = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors, t = context.type;
    final bytes = decodeLogoThumb(thumb);
    final tone = active ? c.brandInk : c.textSecondary;
    final radius = circle ? size : logoRadius(size);
    final letter = (fallbackLetter ?? '').trim().characters.isEmpty
        ? null
        : (fallbackLetter ?? '').trim().characters.first.toUpperCase();

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        // Logo ho to safed canvas (server tile bhi safed hai) — dono theme me
        // same, isliye image ke kinare tile ke kinare se mil jaate hain.
        color: bytes == null ? tone.withValues(alpha: .12) : Colors.white,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: c.textPrimary.withValues(alpha: bytes == null ? (elevated ? .10 : 0) : .12),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: bytes == null
          ? Center(
              child: letter == null
                  ? Icon(Icons.store_outlined, color: tone, size: size * .5)
                  // 200% text scale par bhi letter box se bahar na jaye.
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Padding(
                        padding: EdgeInsets.all(size * .2),
                        child: Text(letter, style: (size >= 40 ? t.titleMedium : t.titleSmall)
                            ?.copyWith(color: tone, fontWeight: FontWeight.w600)),
                      ),
                    ),
            )
          : Image.memory(
              bytes,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => Center(
                child: Icon(Icons.store_outlined, color: c.textSecondary, size: size * .5),
              ),
            ),
    );
  }
}
