// ComponentsGallery: every Deliverable-2 component, live, over the aurora.
import 'package:flutter/material.dart';
import 'components/components.dart';
import 'design.dart';

class ComponentsGallery extends StatefulWidget {
  const ComponentsGallery({super.key});
  @override
  State<ComponentsGallery> createState() => _ComponentsGalleryState();
}

class _ComponentsGalleryState extends State<ComponentsGallery> {
  final _scroll = ScrollController();
  final _imei = TextEditingController(text: '353328111234561');
  final _formKey = GlobalKey<FormState>();
  int _tab = 0;
  bool _fav = false;
  ButtonPhase _phase = ButtonPhase.idle;

  static const _tabs = [
    TabItem(icon: Icons.space_dashboard_outlined, activeIcon: Icons.space_dashboard, label: 'Home'),
    TabItem(icon: Icons.add_circle_outline, activeIcon: Icons.add_circle, label: 'Buy'),
    TabItem(icon: Icons.inventory_2_outlined, activeIcon: Icons.inventory_2, label: 'Stock'),
    TabItem(icon: Icons.sell_outlined, activeIcon: Icons.sell, label: 'Sales'),
    TabItem(icon: Icons.insights_outlined, activeIcon: Icons.insights, label: 'Reports'),
  ];

  @override
  void dispose() { _scroll.dispose(); _imei.dispose(); super.dispose(); }

  Future<void> _runButton() async {
    setState(() => _phase = ButtonPhase.loading);
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;
    setState(() => _phase = ButtonPhase.success);
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    if (mounted) setState(() => _phase = ButtonPhase.idle);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      extendBodyBehindAppBar: true,
      extendBody: true,
      appBar: GlassTopBar(title: 'Components', scroll: _scroll, actions: [
        GlassIconButton(icon: Icons.favorite_border, selectedIcon: Icons.favorite, selected: _fav,
            semanticLabel: 'Favourite', onPressed: () => setState(() => _fav = !_fav)),
      ]),
      body: AuroraBackground(
        child: ListView(
          controller: _scroll,
          padding: EdgeInsets.fromLTRB(Space.screen, MediaQuery.viewPaddingOf(context).top + 64, Space.screen, 140),
          children: [
            // 1 · Hero glass card with the single gradient number
            GlassCard(
              onTap: () {},
              semanticLabel: 'Stock value 1,24,500 rupees, 18 phones',
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Stock value', style: context.type.labelLarge?.copyWith(color: c.textSecondary)),
                const SizedBox(height: Space.x8),
                ShaderMask(shaderCallback: (r) => AppColors.brandGradient.createShader(r),
                    child: Text('₹1,24,500', style: AppType.display.copyWith(color: IndigoMint.glassWhite))),
                const SizedBox(height: Space.x12),
                const Wrap(spacing: Space.x8, runSpacing: Space.x8, children: [
                  StatusChip(label: '18 in stock', tone: ChipTone.brand, icon: Icons.inventory_2_outlined),
                  StatusChip(label: '+12% this week', tone: ChipTone.success, icon: Icons.trending_up),
                ]),
              ]),
            ),
            const SectionHeader(title: 'Buttons', actionLabel: 'See all'),
            PrimaryButton(label: 'Save & add to stock', icon: Icons.check, phase: _phase, onPressed: _runButton),
            const SizedBox(height: Space.x12),
            PrimaryButton(label: 'Retry payment', phase: ButtonPhase.error, onPressed: () {}),
            const SectionHeader(title: 'Input'),
            GlassCard(
              blur: false,
              child: Form(key: _formKey, child: Column(children: [
                GlassTextField(controller: _imei, label: 'IMEI 1', required: true, prefixIcon: Icons.qr_code_2,
                    keyboardType: TextInputType.number, maxLength: 15,
                    helper: 'Apple iPhone 13 · details auto-filled', helperColor: c.successInk),
                const SizedBox(height: Space.x12),
                GlassTextField(controller: TextEditingController(), label: 'Seller name', required: true, prefixIcon: Icons.person_outline),
              ])),
            ),
            const SectionHeader(title: 'Status'),
            const Wrap(spacing: Space.x8, runSpacing: Space.x8, children: [
              StatusChip(label: 'In stock', tone: ChipTone.success),
              StatusChip(label: 'Low margin', tone: ChipTone.warning),
              StatusChip(label: 'Invalid IMEI', tone: ChipTone.error),
              StatusChip(label: 'Sold', tone: ChipTone.neutral, icon: Icons.sell_outlined),
            ]),
            const SectionHeader(title: 'Loading'),
            GlassCard(blur: false, child: Shimmer(child: Column(children: List.generate(3, (_) => const SkeletonListTile())))),
            const SectionHeader(title: 'Empty & error'),
            GlassCard(blur: false, padding: EdgeInsets.zero, child: EmptyState(icon: Icons.inventory_2_outlined,
                title: 'No phones in stock', message: 'Buy a phone and it will appear here, ready to sell.',
                actionLabel: 'Buy phone', onAction: () {})),
            const SizedBox(height: Space.x12),
            GlassCard(blur: false, padding: EdgeInsets.zero,
                child: ErrorState(message: "Couldn't reach the server. Check your internet.", onRetry: () {})),
          ],
        ),
      ),
      bottomNavigationBar: AnimatedTabBar(items: _tabs, index: _tab, elevated: true, onChanged: (i) => setState(() => _tab = i)),
    );
  }
}
