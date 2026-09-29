// DesignSystemShowcase: renders every token, light + dark, on one scrollable screen.
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'design.dart';

double contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + .05) / (math.min(la, lb) + .05);
}

class DesignSystemShowcase extends StatelessWidget {
  const DesignSystemShowcase({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        body: CustomScrollView(slivers: [
          SliverSafeArea(
            bottom: false,
            sliver: SliverToBoxAdapter(child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.screen, Space.x16, Space.screen, Space.x8),
              child: Text('Indigo Mint · Design System', style: AppType.headline.copyWith(color: context.colors.textPrimary)),
            )),
          ),
          SliverToBoxAdapter(child: Theme(data: AppTheme.build(AppTheme.lightScheme), child: const _ThemePanel(label: 'Light'))),
          SliverToBoxAdapter(child: Theme(data: AppTheme.build(AppTheme.darkScheme), child: const _ThemePanel(label: 'Dark'))),
          SliverToBoxAdapter(child: SizedBox(height: MediaQuery.paddingOf(context).bottom + Space.x24)),
        ]),
      );
}

class _ThemePanel extends StatelessWidget {
  final String label;
  const _ThemePanel({required this.label});
  @override
  Widget build(BuildContext context) {
    final s = context.scheme, c = context.colors;
    return ColoredBox(
      color: s.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.screen, vertical: Space.section),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('$label theme', style: context.type.displayMedium),
          const SizedBox(height: Space.section),
          const _Header('Brand'),
          _Swatches([
            ('Primary', s.primary, s.onPrimary), ('Primary ink', c.brandInk, s.onPrimary),
            ('Primary container', s.primaryContainer, s.onPrimaryContainer), ('Accent', c.accent, s.onSecondary),
          ]),
          const _Header('Neutrals'),
          _Swatches([
            ('Background', s.surface, c.textPrimary), ('Surface raised', s.surfaceContainer, c.textPrimary),
            ('Surface variant', s.surfaceContainerHighest, c.textPrimary), ('Outline', s.outline, c.textPrimary),
          ]),
          _TextOn(bg: s.surface),
          const _Header('Semantic · status chips'),
          Wrap(spacing: Space.x8, runSpacing: Space.x8, children: [
            _Chip('Success', Icons.check_circle_outline, c.success, c.successInk),
            _Chip('Warning', Icons.error_outline, c.warning, c.warningInk),
            _Chip('Error', Icons.cancel_outlined, c.error, c.errorInk),
          ]),
          const _Header('Glass · over brand backdrop'),
          const _GlassDemo(),
          const _Header('Gradient (2 stops, one hero number only)'),
          ShaderMask(
            shaderCallback: (r) => AppColors.brandGradient.createShader(r),
            child: Text('₹1,24,500', style: AppType.display.copyWith(color: IndigoMint.glassWhite)),
          ),
          const _Header('Type · Manrope'),
          for (final t in [
            ('Display 36 / ExtraBold', context.type.displayMedium), ('Headline 28 / SemiBold', context.type.headlineMedium),
            ('Title 21 / SemiBold', context.type.titleLarge), ('Body large 16', context.type.bodyLarge),
            ('Body medium 15', context.type.bodyMedium), ('Label large 15 / SemiBold', context.type.labelLarge),
            ('Label small 12 / Medium', context.type.labelSmall),
          ]) Padding(padding: const EdgeInsets.only(bottom: Space.x8), child: Text(t.$1, style: t.$2)),
          const _Header('Radius'),
          Wrap(spacing: Space.x12, runSpacing: Space.x12, children: [
            for (final r in [('xs 8', Radii.xs), ('sm 12', Radii.sm), ('md 16', Radii.md), ('lg 24', Radii.lg), ('xl 32', Radii.xl), ('full', Radii.full)])
              Column(children: [
                Container(width: 64, height: 64, decoration: BoxDecoration(color: s.primaryContainer,
                    borderRadius: BorderRadius.circular(math.min(r.$2, 32)), border: Border.all(color: s.outline))),
                const SizedBox(height: Space.x4),
                Text(r.$1, style: context.type.labelSmall),
              ]),
          ]),
          const _Header('Spacing · 8dp grid'),
          for (final v in [Space.x4, Space.x8, Space.x12, Space.x16, Space.x20, Space.x24, Space.x32, Space.x48])
            Padding(padding: const EdgeInsets.only(bottom: Space.x4), child: Row(children: [
              SizedBox(width: 40, child: Text('${v.toInt()}', style: context.type.labelSmall)),
              Container(width: v * 3, height: Space.x8, decoration: BoxDecoration(color: s.primary, borderRadius: Shapes.pill)),
            ])),
          const _Header('Motion · tap to play'),
          const _SpringDemo(),
        ]),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String text;
  const _Header(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: Space.section, bottom: Space.x12),
        child: Semantics(header: true, child: Text(text.toUpperCase(), style: context.type.labelSmall)),
      );
}

class _Swatches extends StatelessWidget {
  final List<(String, Color, Color)> items;
  const _Swatches(this.items);
  String _hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final w = (box.maxWidth - Space.x12) / 2;
        return Wrap(spacing: Space.x12, runSpacing: Space.x12, children: [
          for (final (name, bg, fg) in items)
            Container(
              width: w, constraints: const BoxConstraints(minHeight: 88),
              padding: const EdgeInsets.all(Space.x12),
              decoration: BoxDecoration(color: bg, borderRadius: Shapes.md, border: Border.all(color: context.scheme.outline)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: AppType.labelLarge.copyWith(color: fg)),
                const SizedBox(height: Space.x4),
                Text('${_hex(bg)} · ${contrast(fg, bg).toStringAsFixed(2)}:1', style: AppType.labelSmall.copyWith(color: fg)),
              ]),
            ),
        ]);
      });
}

class _TextOn extends StatelessWidget {
  final Color bg;
  const _TextOn({required this.bg});
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final secondaryFlat = Color.alphaBlend(c.textSecondary, bg);
    return Padding(
      padding: const EdgeInsets.only(top: Space.x12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Text primary · ${contrast(c.textPrimary, bg).toStringAsFixed(2)}:1', style: AppType.bodyMedium.copyWith(color: c.textPrimary)),
        Text('Text secondary · ${contrast(secondaryFlat, bg).toStringAsFixed(2)}:1', style: AppType.bodyMedium.copyWith(color: c.textSecondary)),
        Text('Primary ink as text · ${contrast(c.brandInk, bg).toStringAsFixed(2)}:1', style: AppType.bodyMedium.copyWith(color: c.brandInk)),
      ]),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label; final IconData icon; final Color tint, ink;
  const _Chip(this.label, this.icon, this.tint, this.ink);
  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minHeight: 32),
        padding: const EdgeInsets.symmetric(horizontal: Space.x12, vertical: Space.x4),
        decoration: BoxDecoration(
          color: tint.withValues(alpha: .12), borderRadius: Shapes.pill,
          border: Border.all(color: tint.withValues(alpha: .24))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: ink, semanticLabel: label),
          const SizedBox(width: Space.x4),
          Text(label, style: AppType.labelSmall.copyWith(color: ink)),
        ]),
      );
}

class _GlassDemo extends StatelessWidget {
  const _GlassDemo();
  @override
  Widget build(BuildContext context) {
    final g = context.glass, c = context.colors, s = context.scheme;
    return SizedBox(
      height: 184,
      child: Stack(children: [
        // Backdrop: two brand blobs so the glass has something to blur.
        Positioned(left: -20, top: -10, child: _Blob(color: s.primary.withValues(alpha: .55), size: 150)),
        Positioned(right: -10, bottom: -20, child: _Blob(color: c.accent.withValues(alpha: .45), size: 130)),
        Positioned.fill(child: Padding(
          padding: const EdgeInsets.all(Space.x20),
          child: DecoratedBox(
            decoration: BoxDecoration(borderRadius: Shapes.lg, boxShadow: g.elevation),
            child: ClipRRect(
              borderRadius: Shapes.lg,
              child: BackdropFilter(
                filter: g.filter,
                child: DecoratedBox(
                  decoration: BoxDecoration(gradient: g.fill, borderRadius: Shapes.lg, border: Border.all(color: g.border)),
                  child: Padding(
                    padding: const EdgeInsets.all(Space.x16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      DecoratedBox(
                        decoration: BoxDecoration(color: g.scrim, borderRadius: Shapes.sm),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: Space.x8, vertical: Space.x4),
                          child: Text('Text on glass (scrim ${(g.scrimAlpha * 100).round()}%)',
                              style: AppType.labelLarge.copyWith(color: c.textPrimary)),
                        ),
                      ),
                      const Spacer(),
                      Text('blur ${g.blurSigma.toInt()}dp · fill ${(g.fillTop * 100).round()}→${(g.fillBottom * 100).round()}% · border ${(g.borderAlpha * 100).round()}%',
                          style: AppType.labelSmall.copyWith(color: c.textPrimary)),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        )),
      ]),
    );
  }
}

class _Blob extends StatelessWidget {
  final Color color; final double size;
  const _Blob({required this.color, required this.size});
  @override
  Widget build(BuildContext context) => Container(width: size, height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)])));
}

/// Plays each spring token on a dot so the feel can be compared side by side.
class _SpringDemo extends StatefulWidget {
  const _SpringDemo();
  @override
  State<_SpringDemo> createState() => _SpringDemoState();
}

class _SpringDemoState extends State<_SpringDemo> with TickerProviderStateMixin {
  static final specs = {'Micro .85/900': Springs.micro, 'Standard .80/380': Springs.standard,
    'Emphasis .72/320': Springs.emphasis, 'Slow .75/180': Springs.slow};
  late final ctrls = {for (final k in specs.keys) k: AnimationController.unbounded(vsync: this)};
  bool out = false;

  void _play() {
    out = !out;
    final m = Motion.of(context);
    for (final e in specs.entries) {
      final ctrl = ctrls[e.key]!;
      if (m.reduced) { ctrl.value = out ? 1 : 0; continue; }
      ctrl.animateWith(SpringSimulation(e.value, ctrl.value, out ? 1 : 0, 0));
    }
  }

  @override
  void dispose() { for (final c in ctrls.values) { c.dispose(); } super.dispose(); }

  @override
  Widget build(BuildContext context) => Semantics(
        button: true, label: 'Play spring motion demo',
        child: InkWell(
          onTap: _play, borderRadius: Shapes.md,
          child: Padding(
            padding: const EdgeInsets.all(Space.x8),
            child: Column(children: [
              for (final k in specs.keys)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: Space.x8),
                  child: LayoutBuilder(builder: (context, box) => AnimatedBuilder(
                    animation: ctrls[k]!,
                    builder: (context, _) => Stack(children: [
                      SizedBox(height: 28, width: box.maxWidth),
                      Positioned(left: 0, top: 0, child: Text(k, style: context.type.labelSmall)),
                      Positioned(
                        left: ctrls[k]!.value * (box.maxWidth - 16), top: 16,
                        child: Container(width: 12, height: 12, decoration: BoxDecoration(color: context.scheme.primary, shape: BoxShape.circle)),
                      ),
                    ]),
                  )),
                ),
            ]),
          ),
        ),
      );
}
