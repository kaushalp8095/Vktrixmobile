// BRAND ART — har phone brand ka tile (logo jaisa mark) + brand naam.
//
// Stock screen brand-wise hona chahiye: har brand (Apple, Samsung, Vivo, …) ka
// ek tile jisme brand ka mark aur naam dikhe, aur tap karne par usi brand ka
// stock khule. Bahar se image download nahi karte (app offline chalti hai aur
// trademark images ship karna theek nahi) — har brand ka apna **vector mark**
// hai: brand ka colour + pehchana jane wala glyph (Apple ka A, Samsung ka S…),
// 44–48px par bhi saaf. Jo brand list me nahi, uska naam ka pehla akshar usi
// style me — kabhi khaali tile nahi.
import 'package:flutter/material.dart';

import '../design/design.dart';

/// Brand ka canonical roop. `Redmi`, `redmi`, `Mi`, `Xiaomi` — alag-alag
/// spelling hone par bhi stock me ek hi brand banta hai.
class BrandInfo {
  final String name;   // display name
  final Color color;   // brand ka rang
  final String mark;   // tile par glyph (1–2 akshar)

  const BrandInfo(this.name, this.color, this.mark);

  /// Grouping/filter key.
  String get key => name.toLowerCase();
}

// Brand tones — official-ish (Oct 2026), dark theme par bhi padhne layak.
const _brands = <String, BrandInfo>{
  'apple': BrandInfo('Apple', Color(0xFF3A3A3C), 'A'),
  'samsung': BrandInfo('Samsung', Color(0xFF1428A0), 'S'),
  'vivo': BrandInfo('Vivo', Color(0xFF415FFF), 'V'),
  'oppo': BrandInfo('Oppo', Color(0xFF1D7A46), 'O'),
  'oneplus': BrandInfo('OnePlus', Color(0xFFEB0028), '1+'),
  'xiaomi': BrandInfo('Xiaomi', Color(0xFFFF6900), 'MI'),
  'redmi': BrandInfo('Redmi', Color(0xFFE01B24), 'R'),
  'poco': BrandInfo('POCO', Color(0xFFB8860B), 'P'),
  'realme': BrandInfo('Realme', Color(0xFFB58A00), 'R'),
  'google': BrandInfo('Google', Color(0xFF4285F4), 'G'),
  'nothing': BrandInfo('Nothing', Color(0xFF4B4B4D), 'N'),
  'nokia': BrandInfo('Nokia', Color(0xFF124191), 'N'),
  'motorola': BrandInfo('Motorola', Color(0xFF5C6BC0), 'M'),
  'iqoo': BrandInfo('iQOO', Color(0xFFD98A00), 'iQ'),
  'infinix': BrandInfo('Infinix', Color(0xFF00A651), 'IN'),
  'tecno': BrandInfo('Tecno', Color(0xFF0B5FFF), 'T'),
  'lava': BrandInfo('Lava', Color(0xFFF26522), 'L'),
  'micromax': BrandInfo('Micromax', Color(0xFFE4002B), 'M'),
  'honor': BrandInfo('Honor', Color(0xFF0066FF), 'H'),
  'huawei': BrandInfo('Huawei', Color(0xFFC8102E), 'H'),
  'asus': BrandInfo('Asus', Color(0xFF0B3D91), 'AS'),
  'lenovo': BrandInfo('Lenovo', Color(0xFFE2231A), 'L'),
  'itel': BrandInfo('itel', Color(0xFF00A0E9), 'i'),
  'jio': BrandInfo('Jio', Color(0xFF0F3CC9), 'J'),
  'sony': BrandInfo('Sony', Color(0xFF3A3A3C), 'S'),
  'lg': BrandInfo('LG', Color(0xFFA50034), 'LG'),
  'htc': BrandInfo('HTC', Color(0xFF009933), 'H'),
  'blackberry': BrandInfo('BlackBerry', Color(0xFF3A3A3C), 'B'),
  'gionee': BrandInfo('Gionee', Color(0xFF00A0E9), 'G'),
  'coolpad': BrandInfo('Coolpad', Color(0xFF0B5FFF), 'C'),
  'karbonn': BrandInfo('Karbonn', Color(0xFFE4002B), 'K'),
  'wiko': BrandInfo('Wiko', Color(0xFF7C3AED), 'W'),
  'ulefone': BrandInfo('Ulefone', Color(0xFF0369A1), 'U'),
};

/// Common spellings (TAC catalog + shop entries) → canonical key.
const _aliases = <String, String>{
  'apple inc': 'apple', 'apple iphone': 'apple', 'iphone': 'apple', 'ipad': 'apple',
  'samsung electronics': 'samsung', 'samsung galaxy': 'samsung',
  'xiaomi inc': 'xiaomi', 'mi': 'xiaomi', 'mi phone': 'xiaomi',
  'oppo mobile': 'oppo', 'vivo mobile': 'vivo', 'bbk': 'vivo',
  'one plus': 'oneplus', 'one+': 'oneplus', 'one plus mobile': 'oneplus',
  'google pixel': 'google', 'pixel': 'google',
  'motorola mobility': 'motorola', 'moto': 'motorola',
  'nothing phone': 'nothing', 'realme mobile': 'realme',
  'iqoo mobile': 'iqoo', 'infinix mobile': 'infinix', 'tecno mobile': 'tecno',
  'red mi': 'redmi', 'poco phone': 'poco',
};

const _fallbackColors = [
  Color(0xFF4F46E5), Color(0xFF0E7490), Color(0xFF7C3AED), Color(0xFFB45309),
  Color(0xFF15803D), Color(0xFF9F1239), Color(0xFF0369A1), Color(0xFF6D28D9),
];

/// Kisi bhi brand string → canonical brand (naam, rang, mark).
BrandInfo brandInfo(String? raw) {
  final clean = (raw ?? '').trim();
  final key = clean.toLowerCase();
  final direct = _brands[key] ?? _brands[_aliases[key] ?? ''];
  if (direct != null) return direct;

  // "Samsung Galaxy S23" jaisa pura string: pehla shabd try karo.
  final first = key.split(RegExp(r'[\s/,-]+')).firstWhere((w) => w.isNotEmpty, orElse: () => '');
  if (first.isNotEmpty) {
    final byFirst = _brands[first] ?? _brands[_aliases[first] ?? ''];
    if (byFirst != null) return byFirst;
  }

  // Anjaan brand: naam + uske naam se tay rang aur initials — phir bhi tile.
  final colour = _fallbackColors[key.isEmpty ? 0 : _stableHash(key) % _fallbackColors.length];
  return BrandInfo(clean.isEmpty ? 'Unknown' : clean, colour, _initials(clean));
}

int _stableHash(String s) {
  var h = 0;
  for (final unit in s.codeUnits) {
    h = (h * 31 + unit) & 0x7fffffff;
  }
  return h;
}

String _initials(String raw) {
  final words = raw.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '?';
  final a = words.first[0].toUpperCase();
  if (words.length == 1) return a;
  return '$a${words[1][0].toUpperCase()}';
}

/// Brand ke tiles ke liye ek hi group key (Stock filter/list grouping).
String brandKey(String? raw) => brandInfo(raw).key;

/// Brand ka logo tile — default 44px. Brand colour ka tint + border, mark
/// andar. Dark theme par bahut gehre brand colours (Apple ka black) lighten
/// ho jate hain, warna tile khaali lagta.
class BrandLogo extends StatelessWidget {
  final String? brand;
  final double size;
  /// Disabled/inactive row (gray look).
  final bool muted;
  const BrandLogo({super.key, required this.brand, this.size = 44, this.muted = false});

  @override
  Widget build(BuildContext context) {
    final info = brandInfo(brand);
    final c = context.colors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    var colour = info.color;
    if (muted) {
      colour = c.textSecondary;
    } else if (dark && colour.computeLuminance() < .22) {
      // Gehra brand colour dark glass par doob jata hai — aadha white mila do.
      colour = Color.lerp(colour, Colors.white, .45)!;
    }
    return Semantics(
      label: '${info.name} logo',
      image: true,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: colour.withValues(alpha: muted ? .10 : .14),
          borderRadius: BorderRadius.circular(size * .28),
          border: Border.all(color: colour.withValues(alpha: muted ? .16 : .28)),
        ),
        clipBehavior: Clip.antiAlias,
        child: CustomPaint(painter: _MarkPainter(info.mark, colour)),
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  final String mark;
  final Color colour;
  _MarkPainter(this.mark, this.colour);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    // Monogram tile: brand ka rang + brand ka glyph (Apple → A, Samsung → S,
    // OnePlus → 1+, Xiaomi → MI). Font family app ka hi — warna test/golden me
    // glyph ki jagah box (Ahem) banta hai.
    final painter = TextPainter(
      text: TextSpan(
        text: mark,
        style: TextStyle(
          fontFamily: AppType.family,
          color: colour,
          fontSize: s * (mark.length > 1 ? .36 : .46),
          fontWeight: FontWeight.w800,
          letterSpacing: mark.length > 1 ? -.6 : -.4,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 1,
    )..layout(maxWidth: size.width * .92);
    // Optically centre (baseline ke saath exact centre thoda neeche lagta hai).
    painter.paint(canvas,
        Offset((size.width - painter.width) / 2, (size.height - painter.height) / 2));
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.mark != mark || old.colour != colour;
}

/// Stock screen ke upar brand tile: logo + naam + kitne phone stock me hain.
/// Tap karne par wahi brand filter ho jata hai (selected par ring).
class BrandTile extends StatelessWidget {
  final String brand;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  final double width;

  const BrandTile({
    super.key,
    required this.brand,
    required this.count,
    required this.selected,
    required this.onTap,
    this.width = 68,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors, t = context.type;
    final info = brandInfo(brand);
    return Semantics(
      // Ek hi saaf node: "Vivo, 3 in stock, button". Warna andar ka logo label
      // aur text labels merge hokar TalkBack par bakwaas padhta hai (aur tests me
      // exact label match nahi hota).
      container: true,
      excludeSemantics: true,
      button: true,
      selected: selected,
      label: '${info.name}, $count in stock',
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        borderRadius: Shapes.md,
        child: SizedBox(
          width: width,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            AnimatedContainer(
              duration: Durations2.toggleTrack,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(42 * .28 + 3),
                border: Border.all(
                  color: selected ? c.brandInk : Colors.transparent,
                  width: 2,
                ),
              ),
              child: BrandLogo(brand: brand, size: 42),
            ),
            const SizedBox(height: 4),
            Text(info.name,
                style: t.labelMedium?.copyWith(
                  color: selected ? c.brandInk : c.textPrimary,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                ),
                maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
            Text('$count in stock',
                style: t.labelSmall?.copyWith(color: c.textSecondary, fontSize: 10),
                maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
          ]),
        ),
      ),
    );
  }
}
