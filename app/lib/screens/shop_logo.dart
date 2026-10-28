// SHOP LOGO AVATAR — app ke har jagah ek hi tarah ka logo (Oct 2026 style).
//
// Kahin circle, kahin square, kahin contain me chhota floating — teen tarah ke
// logo dikh rahe the. Ab har jagah ek hi shape: **rounded square** (modern app
// icon / squircle ratio ~26%), aur andar wahi image jo server upload par
// auto-adjust karke banti hai: 512px **full-bleed** tile (margin trim + centre
// square crop). Image box ko chaaron taraf se bharti hai — na upar-neeche khaali
// patti, na safed box, na logo ke aas-paas alag frame. Sirf ek patli border,
// jo image ke *upar* draw hoti hai, aur corners box ke radius par cut hote hain.
//
// Server har logo ka 128px thumbnail (`logo_thumb`, ~2-6 KB) bhejta hai; poora
// base64 (100-700 KB) list me nahi jaata. Thumb na ho (purana PNG logo, upload
// se pehle) to shop/owner ke naam ka pehla akshar — kabhi crash nahi.
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
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Image ke upar ek hairline — box ka kinara saaf dikhe, par logo ke andar
    // koi alag frame na bane. Dark theme par halka safed, light par halka kaala.
    final hairline = dark ? Colors.white.withValues(alpha: .16) : Colors.black.withValues(alpha: .12);
    final border = BorderRadius.circular(radius);

    // Screen reader ke liye row/sheet ka apna label hi kaafi hai (shop ka naam);
    // andar ka logo dobara "logo, logo" nahi bolna chahiye.
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          // Sirf fallback par tinted plate. Logo ho to plate ki zaroorat nahi —
          // tile khud box bharta hai (isliye koi safed/glass patti nahi dikhti).
          color: bytes == null ? tone.withValues(alpha: .12) : null,
          borderRadius: border,
          border: bytes == null
              ? Border.all(color: c.textPrimary.withValues(alpha: elevated ? .10 : 0))
              : null,
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
            // Full-bleed: image box ko poora bharti hai, corners box ke radius se
            // clip hote hain. Border image ke upar, warna logo ke andar gap dikhta.
            : Stack(fit: StackFit.expand, children: [
                Image.memory(
                  bytes,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, __, ___) => Center(
                    child: Icon(Icons.store_outlined, color: c.textSecondary, size: size * .5),
                  ),
                ),
                IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: border,
                      border: Border.all(color: hairline),
                    ),
                  ),
                ),
              ]),
      ),
    );
  }
}
