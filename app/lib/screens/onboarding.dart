// ONBOARDING: 1st launch only — 3 aurora slides (Buy → Sell → Reports), skip + next.
import 'package:flutter/material.dart';
import '../api.dart';
import '../design/components/components.dart';
import '../design/design.dart';

class OnboardingScreen extends StatefulWidget {
  final VoidCallback? onDone; // injection for tests/prod routing
  const OnboardingScreen({super.key, this.onDone});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pager = PageController();
  int _page = 0;

  static const _slides = [
    (Icons.add_shopping_cart, 'Buy in seconds',
     'Type the IMEI — brand, model, RAM and storage fill themselves. The phone lands straight into your stock.'),
    (Icons.sell_outlined, 'Sell with profit in view',
     'Pick a phone from stock, see the profit before you confirm, and every sale is recorded with customer details.'),
    (Icons.bar_chart_outlined, 'Know your shop',
     'Daily sales charts, cash/UPI splits and top-selling models — your whole business on one screen.'),
  ];

  Future<void> _finish() async {
    await Api.setOnboardingSeen();
    widget.onDone?.call();
  }

  void _next() {
    if (_page == 2) { _finish(); return; }
    Haptics.tick();
    _pager.nextPage(duration: Motion.of(context).d(Durations2.enter), curve: Curves2.enter);
  }

  @override
  void dispose() { _pager.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final c = context.colors, t = context.type;
    final last = _page == 2;
    return Scaffold(
      body: AuroraBackground(child: SafeArea(child: Padding(
        padding: const EdgeInsets.all(Space.screen),
        child: Column(children: [
          Align(alignment: Alignment.centerRight, child: TextButton(
            onPressed: _finish,
            child: Text('Skip', style: t.labelLarge?.copyWith(color: c.textSecondary)),
          )),
          Expanded(child: PageView.builder(
            controller: _pager,
            onPageChanged: (i) { setState(() => _page = i); Haptics.tick(); },
            itemCount: 3,
            itemBuilder: (_, i) {
              final s = _slides[i];
              return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                SizedBox.square(dimension: 120, child: GlassSurface(radius: Radii.full,
                    child: Center(child: Icon(s.$1, size: 52, color: c.brandInk)))),
                const SizedBox(height: Space.x32),
                Semantics(header: true, child: Text(s.$2, style: t.headlineMedium, textAlign: TextAlign.center)),
                const SizedBox(height: Space.x12),
                Text(s.$3, style: t.bodyLarge?.copyWith(color: c.textSecondary), textAlign: TextAlign.center),
              ]);
            },
          )),
          // ---- Dots + CTA ----
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < 3; i++)
              AnimatedContainer(
                duration: Motion.of(context).d(Durations2.enter), curve: Curves2.enter,
                margin: const EdgeInsets.symmetric(horizontal: Space.x4),
                width: _page == i ? 24 : 8, height: 8,
                decoration: BoxDecoration(
                  color: _page == i ? c.brandInk : c.textPrimary.withValues(alpha: .20),
                  borderRadius: BorderRadius.circular(4)),
              ),
          ]),
          const SizedBox(height: Space.x24),
          PrimaryButton(label: last ? 'Get started' : 'Next', icon: last ? Icons.check : Icons.arrow_forward, onPressed: _next),
          const SizedBox(height: Space.x16),
        ]),
      ))),
    );
  }
}
