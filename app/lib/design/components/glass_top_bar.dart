// GlassTopBar: transparent at rest → frosted glass after 40dp of scroll
// (blur 0→24dp, fill 0→10%). Only this subtree rebuilds on scroll.
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import '../design.dart';

class GlassTopBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final ScrollController? scroll;
  final Widget? leading;
  final List<Widget> actions;
  const GlassTopBar({super.key, required this.title, this.scroll, this.leading, this.actions = const []});

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.viewPaddingOf(context).top;
    final bar = Padding(
      padding: EdgeInsets.only(top: top),
      child: SizedBox(
        height: preferredSize.height,
        child: Row(children: [
          const SizedBox(width: Space.x4),
          leading ?? (Navigator.canPop(context) ? const BackButton() : const SizedBox(width: Space.x12)),
          Expanded(child: Semantics(header: true, child: Text(title, style: context.type.titleLarge, maxLines: 1, overflow: TextOverflow.ellipsis))),
          ...actions,
          const SizedBox(width: Space.x4),
        ]),
      ),
    );
    final s = scroll;
    if (s == null) return bar;
    return ListenableBuilder(
      listenable: s,
      child: bar,
      builder: (context, child) {
        final off = s.hasClients ? s.offset : 0.0;
        final t = (off / MotionValues.topBarBlurTrigger).clamp(0.0, 1.0);
        final sigma = MotionValues.topBarMaxBlur * t;
        final g = context.glass;
        Widget content = DecoratedBox(
          decoration: BoxDecoration(
            color: IndigoMint.glassWhite.withValues(alpha: MotionValues.topBarMaxFill * t),
            border: Border(bottom: BorderSide(color: g.border.withValues(alpha: g.borderAlpha * t))),
          ),
          child: child,
        );
        if (sigma > .5 && g.blurSupported) {
          content = ClipRect(child: BackdropFilter(filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma), child: content));
        }
        return content;
      },
    );
  }
}
