// GlassTextField: themed field on glass fill, accent 2dp focus ring, error shake,
// multiline-safe at 200% font scale (no fixed heights).
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../design.dart';
import 'spring.dart';

class GlassTextField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final IconData? prefixIcon;
  final Widget? suffix;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final Iterable<String>? autofillHints;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final int? maxLength;
  final bool obscure, required, enabled;
  final String? helper;
  final Color? helperColor;
  const GlassTextField({
    super.key, required this.controller, required this.label, this.hint, this.prefixIcon, this.suffix,
    this.keyboardType, this.textInputAction, this.inputFormatters, this.autofillHints, this.validator,
    this.onChanged, this.onSubmitted, this.maxLength, this.obscure = false, this.required = false,
    this.enabled = true, this.helper, this.helperColor,
  });
  @override
  State<GlassTextField> createState() => _GlassTextFieldState();
}

class _GlassTextFieldState extends State<GlassTextField> with SingleTickerProviderStateMixin {
  late final _shake = AnimationController(vsync: this, duration: Durations2.shake);
  @override
  void dispose() { _shake.dispose(); super.dispose(); }

  String? _validate(String? v) {
    String? err;
    if (widget.required && (v == null || v.trim().isEmpty)) err = '${widget.label} is required';
    err ??= widget.validator?.call(v);
    if (err != null) {
      final m = Motion.of(context);
      _shake.duration = m.d(Durations2.shake);
      _shake.forward(from: 0);
      Haptics.error();
    }
    return err;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AnimatedBuilder(
      animation: _shake,
      builder: (context, child) => Transform.translate(
        offset: Offset(math.sin(_shake.value * math.pi * 4) * MotionValues.shakeOffset * (1 - _shake.value), 0), child: child),
      child: TextFormField(
        controller: widget.controller, enabled: widget.enabled, obscureText: widget.obscure,
        keyboardType: widget.keyboardType, textInputAction: widget.textInputAction,
        inputFormatters: widget.inputFormatters, autofillHints: widget.autofillHints,
        maxLength: widget.maxLength, onChanged: widget.onChanged, onFieldSubmitted: widget.onSubmitted,
        validator: _validate, style: AppType.bodyLarge.copyWith(color: c.textPrimary),
        cursorColor: c.brandInk,
        decoration: InputDecoration(
          labelText: widget.required ? '${widget.label} *' : widget.label,
          hintText: widget.hint, counterText: '',
          helperText: widget.helper, helperMaxLines: 3,
          helperStyle: widget.helper == null ? null : AppType.labelSmall.copyWith(color: widget.helperColor ?? c.textSecondary),
          errorMaxLines: 3,
          prefixIcon: widget.prefixIcon == null ? null : Icon(widget.prefixIcon, color: c.textSecondary, semanticLabel: null),
          suffixIcon: widget.suffix,
        ),
      ),
    );
  }
}
