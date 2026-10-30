// AuroraBackground — app ka base wash (Oct 2026 "aurora glass" look).
//
// Layering, neeche se upar:
//   1. vertical base wash (cool aqua-grey → green-leaning bottom)
//   2. brand radial gradients — exactly the requested shape:
//        circle at 50% 70%  rgba(41,171,226,0.20) → transparent 50%
//        circle at 30% 30%  rgba(57,181,74, 0.20) → transparent 50%
//   3. do chhote ambient bodies jo dheere dheere drift karte hain (glass ko
//      hamesha kuch "peeche" chahiye warna blur nazar hi nahi aata)
//   4. 3% grain — flat digital gradient ko photographic texture deta hai
//
// Drift sirf tab chalta hai jab app RESUMED ho aur reduced-motion off ho.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../design.dart';

class AuroraBackground extends StatefulWidget {
  final Widget child;
  const AuroraBackground({super.key, required this.child});
  @override
  State<AuroraBackground> createState() => _AuroraBackgroundState();
}

class _AuroraBackgroundState extends State<AuroraBackground> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final Ticker _ticker = createTicker(_onTick);
  final _time = ValueNotifier<double>(0); // seconds
  Duration _base = Duration.zero, _last = Duration.zero;
  static ui.Image? _grain; // shared, generated once

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _makeGrain();
  }

  void _onTick(Duration e) { _last = e; _time.value = (_base + e).inMicroseconds / 1e6; }

  @override
  void didChangeDependencies() { super.didChangeDependencies(); _syncTicker(); }

  void _syncTicker() {
    final resumed = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    final run = resumed && Motion.of(context).ambientEnabled && TickerMode.valuesOf(context).enabled;
    if (run && !_ticker.isActive) { _ticker.start(); }
    else if (!run && _ticker.isActive) { _base += _last; _ticker.stop(); }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _syncTicker();

  Future<void> _makeGrain() async {
    if (_grain != null) return;
    const n = 128;
    final rnd = math.Random(7), px = Uint8List(n * n * 4);
    for (var i = 0; i < n * n; i++) {
      final v = rnd.nextInt(256);
      px[i * 4] = v; px[i * 4 + 1] = v; px[i * 4 + 2] = v; px[i * 4 + 3] = 255;
    }
    ui.decodeImageFromPixels(px, n, n, ui.PixelFormat.rgba8888, (img) { _grain = img; if (mounted) setState(() {}); });
  }

  @override
  void dispose() { WidgetsBinding.instance.removeObserver(this); _ticker.dispose(); _time.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final s = context.scheme, c = context.colors;
    final dark = s.brightness == Brightness.dark;
    return Stack(fit: StackFit.expand, children: [
      RepaintBoundary(child: CustomPaint(painter: _AuroraPainter(
        time: _time, start: c.backgroundStart, end: c.backgroundEnd,
        aqua: AquaEmerald.aqua,
        emerald: AquaEmerald.emerald,
        // Dark theme needs a bit more pigment to register at all on near-black.
        strength: dark ? 1.45 : 1.0,
        grain: _grain, grainOpacity: dark ? .045 : .03))),
      widget.child,
    ]);
  }
}

class _AuroraPainter extends CustomPainter {
  final ValueNotifier<double> time;
  final Color start, end, aqua, emerald;
  final double strength;
  final ui.Image? grain;
  final double grainOpacity;
  _AuroraPainter({required this.time, required this.start, required this.end, required this.aqua,
      required this.emerald, required this.strength, required this.grain, required this.grainOpacity})
      : super(repaint: time);

  // Brand fields: (colour, alpha, centre x/y as fraction, radius as fraction of
  // the long edge, drift radius dp, period s)
  List<(Color, double, Offset, double, double, double)> get _fields => [
        (aqua, .20, const Offset(.50, .70), .50, 0, 0),      // requested: circle 50% 70%
        (emerald, .20, const Offset(.30, .30), .50, 0, 0),   // requested: circle 30% 30%
        (aqua, .16, const Offset(.92, .06), .34, 26, 24),    // ambient accent
        (emerald, .14, const Offset(.05, .95), .32, 30, 30), // ambient accent
      ];

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    // 1. base wash — aurora ke neeche ek saaf, thanda canvas
    canvas.drawRect(rect, Paint()
      ..shader = ui.Gradient.linear(rect.topCenter, rect.bottomCenter, [start, end]));

    // 2. + 3. brand fields
    final t = time.value;
    final long = math.max(size.width, size.height);
    for (final (color, alpha, anchor, radiusFrac, drift, period) in _fields) {
      var center = Offset(anchor.dx * size.width, anchor.dy * size.height);
      if (drift > 0) {
        final a = t / period * 2 * math.pi;
        center = center.translate(math.cos(a) * drift, math.sin(a * 1.27) * drift);
      }
      final r = long * radiusFrac;
      // Radial falloff to fully transparent at 50% (0.45 stop keeps the core
      // solid so the colour still reads as a field, not a haze).
      canvas.drawCircle(center, r, Paint()
        ..shader = ui.Gradient.radial(center, r, [
          color.withValues(alpha: (alpha * strength).clamp(0, 1)),
          color.withValues(alpha: (alpha * strength * .45).clamp(0, 1)),
          color.withValues(alpha: 0),
        ], [0, .45, 1]));
    }

    // 4. grain
    final g = grain;
    if (g != null) {
      canvas.drawRect(rect, Paint()
        ..shader = ImageShader(g, TileMode.repeated, TileMode.repeated, Matrix4.identity().storage)
        ..color = Color.fromRGBO(0, 0, 0, grainOpacity)
        ..blendMode = BlendMode.overlay);
    }
  }

  @override
  bool shouldRepaint(_AuroraPainter o) =>
      o.start != start || o.end != end || o.aqua != aqua || o.emerald != emerald ||
      o.grain != grain || o.strength != strength;
}
