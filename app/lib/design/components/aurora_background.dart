// AuroraBackground: base colour → 3 drifting brand blobs → 3% grain. Ambient loop
// runs only while the app is RESUMED and is frozen under reduced motion.
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
    return Stack(fit: StackFit.expand, children: [
      RepaintBoundary(child: CustomPaint(painter: _AuroraPainter(
        time: _time, base: s.surface, primary: s.primary, accent: c.accent,
        grain: _grain, grainOpacity: s.brightness == Brightness.dark ? .04 : .03))),
      widget.child,
    ]);
  }
}

class _AuroraPainter extends CustomPainter {
  final ValueNotifier<double> time;
  final Color base, primary, accent;
  final ui.Image? grain;
  final double grainOpacity;
  _AuroraPainter({required this.time, required this.base, required this.primary, required this.accent, required this.grain, required this.grainOpacity})
      : super(repaint: time);

  // (colour alpha, diameter dp, period s, anchor x/y as fraction, drift radius dp)
  List<(Color, double, double, Offset, double)> get _blobs => [
        (primary.withValues(alpha: .55), 340, 22, const Offset(.15, .10), 48),
        (accent.withValues(alpha: .45), 280, 18, const Offset(.95, .40), 40),
        (primary.withValues(alpha: .30), 220, 26, const Offset(.30, .85), 56),
      ];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = base);
    final t = time.value;
    for (final (color, d, period, anchor, drift) in _blobs) {
      final a = t / period * 2 * math.pi;
      final center = Offset(anchor.dx * size.width + math.cos(a) * drift, anchor.dy * size.height + math.sin(a * 1.3) * drift);
      // Soft radial falloff = visually equivalent to a 120–180dp gaussian blur, zero blur cost.
      final r = d / 2 + 90;
      canvas.drawCircle(center, r, Paint()
        ..shader = ui.Gradient.radial(center, r, [color, color.withValues(alpha: color.a * .45), color.withValues(alpha: 0)], [0, .45, 1]));
    }
    final g = grain;
    if (g != null) {
      canvas.drawRect(Offset.zero & size, Paint()
        ..shader = ImageShader(g, TileMode.repeated, TileMode.repeated, Matrix4.identity().storage)
        ..color = Color.fromRGBO(0, 0, 0, grainOpacity)
        ..blendMode = BlendMode.overlay);
    }
  }

  @override
  bool shouldRepaint(_AuroraPainter o) => o.base != base || o.primary != primary || o.accent != accent || o.grain != grain;
}
