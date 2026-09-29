// EmptyState / ErrorState: glass icon disc + title + message + optional action.
// ErrorState is a live region so TalkBack announces it.
import 'package:flutter/material.dart';
import '../design.dart';
import 'glass_surface.dart';
import 'primary_button.dart';

class _StateView extends StatelessWidget {
  final IconData icon; final Color iconColor; final String title, message;
  final String? actionLabel; final VoidCallback? onAction; final bool live;
  const _StateView({required this.icon, required this.iconColor, required this.title, required this.message,
    this.actionLabel, this.onAction, this.live = false});
  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: live, container: true,
        child: Padding(
          padding: const EdgeInsets.all(Space.x32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox.square(dimension: 88, child: GlassSurface(radius: Radii.full, blur: false,
                child: Center(child: Icon(icon, size: 36, color: iconColor)))),
            const SizedBox(height: Space.x24),
            Text(title, style: context.type.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: Space.x8),
            Text(message, style: context.type.bodyMedium?.copyWith(color: context.colors.textSecondary), textAlign: TextAlign.center),
            if (actionLabel != null) ...[
              const SizedBox(height: Space.x24),
              PrimaryButton(label: actionLabel!, onPressed: onAction, expand: false),
            ],
          ]),
        ),
      );
}

class EmptyState extends StatelessWidget {
  final IconData icon; final String title, message; final String? actionLabel; final VoidCallback? onAction;
  const EmptyState({super.key, required this.icon, required this.title, required this.message, this.actionLabel, this.onAction});
  @override
  Widget build(BuildContext context) => _StateView(icon: icon, iconColor: context.colors.brandInk, title: title,
      message: message, actionLabel: actionLabel, onAction: onAction);
}

class ErrorState extends StatelessWidget {
  final String title, message; final VoidCallback? onRetry;
  const ErrorState({super.key, this.title = 'Something went wrong', required this.message, this.onRetry});
  @override
  Widget build(BuildContext context) => _StateView(icon: Icons.cloud_off_outlined, iconColor: context.colors.errorInk,
      title: title, message: message, actionLabel: onRetry == null ? null : 'Retry', onAction: onRetry, live: true);
}
