// SHOP LOGO AVATAR — list/detail ke liye chhota logo.
//
// Poora logo (base64, 100-700 KB) list me nahi jaata; server har logo ka 96px
// thumbnail (`logo_thumb`, ~2 KB) bhejta hai. Wo na ho (purana PNG logo, upload
// ke bina) to pehle jaisa store icon dikhta hai — kabhi crash nahi.
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

class ShopLogoAvatar extends StatelessWidget {
  /// `logo_thumb` (data URL) — null/khaali/kharaab ho to icon.
  final String? thumb;
  final bool active;
  final double size;
  /// Shop row 44, bottom sheet 56 — dono same design language.
  const ShopLogoAvatar({super.key, this.thumb, required this.active, this.size = 44});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bytes = decodeLogoThumb(thumb);
    final tone = active ? c.brandInk : c.textSecondary;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bytes == null ? tone.withValues(alpha: .12) : Colors.white,
        borderRadius: BorderRadius.circular(Radii.md),
        border: bytes == null ? null : Border.all(color: c.textPrimary.withValues(alpha: .10)),
      ),
      clipBehavior: Clip.antiAlias,
      padding: EdgeInsets.all(bytes == null ? 0 : size * .06),
      child: bytes == null
          ? Icon(Icons.store_outlined, color: tone, size: size * .5)
          : Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true,
              errorBuilder: (_, __, ___) => Icon(Icons.store_outlined, color: c.textSecondary, size: size * .5)),
    );
  }
}
