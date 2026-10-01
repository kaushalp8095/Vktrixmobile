// SPLASH: aurora → glass brand mark (Slow spring scale-in) → wordmark fade → route.
import 'package:flutter/material.dart';
import '../api.dart';
import '../design/components/components.dart';
import '../design/design.dart';
import 'admin_home.dart';
import 'onboarding.dart';
import 'login.dart';
import 'shop_home.dart';

class SplashScreen extends StatefulWidget {
  /// Injected for previews/tests; production resolves from saved session.
  final bool autoRoute;
  const SplashScreen({super.key, this.autoRoute = true});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late final _mark = AnimationController.unbounded(vsync: this, value: .6);
  late final _word = AnimationController(vsync: this, duration: Durations2.enter);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_word.status == AnimationStatus.dismissed && !_word.isAnimating) _start();
  }

  Future<void> _start() async {
    final m = Motion.of(context);
    _mark.springTo(1, Springs.slow, m);
    await Future<void>.delayed(m.d(const Duration(milliseconds: 120)));
    if (!mounted) return;
    _word.duration = m.d(Durations2.enter);
    await _word.forward();
    if (!widget.autoRoute || !mounted) return;
    await Future<void>.delayed(m.d(const Duration(milliseconds: 250)));
    if (!mounted) return;
    final seen = await Api.onboardingSeen();
    if (!mounted) return;
    SharedAxisRoute.replace(context, (_) => !seen
        ? OnboardingScreen(onDone: () => _routeNext())
        : (Api.token == null ? const LoginScreen() : (Api.isSuperAdmin ? const AdminHome() : const ShopHome())));
  }

  void _routeNext() {
    if (!mounted) return;
    SharedAxisRoute.replace(context, (_) =>
        Api.token == null ? const LoginScreen() : (Api.isSuperAdmin ? const AdminHome() : const ShopHome()));
  }

  @override
  void dispose() { _mark.dispose(); _word.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      body: AuroraBackground(
        child: SafeArea(
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ScaleTransition(scale: _mark, child: const BrandMark(size: 112)),
              const SizedBox(height: Space.x24),
              FadeTransition(
                opacity: _word,
                child: SlideTransition(
                  position: Tween(begin: const Offset(0, .25), end: Offset.zero).animate(CurvedAnimation(parent: _word, curve: Curves2.enter)),
                  child: Column(children: [
                    Text('Vktrix Mobile', style: context.type.headlineMedium, textAlign: TextAlign.center),
                    const SizedBox(height: Space.x4),
                    Text('Buy · Sell · Stock', style: context.type.bodyMedium?.copyWith(color: c.textSecondary)),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
