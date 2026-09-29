// SectionHeader: title (TalkBack header) + optional trailing text action (48dp target).
import 'package:flutter/material.dart';
import '../design.dart';

class SectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  const SectionHeader({super.key, required this.title, this.actionLabel, this.onAction});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: Space.section, bottom: Space.x8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Expanded(child: Semantics(header: true, child: Text(title, style: context.type.titleLarge))),
          if (actionLabel != null) TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ]),
      );
}
