// LOGIN: aurora → Display greeting → one blurred GlassCard (fields + server) → PrimaryButton.
import 'package:flutter/material.dart';
import '../api.dart';
import '../design/components/components.dart';
import '../design/design.dart';
import 'admin_home.dart';
import 'shop_home.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _user = TextEditingController(), _pass = TextEditingController();
  late final _server = TextEditingController(text: baseUrl);
  ButtonPhase _phase = ButtonPhase.idle;
  bool _showPass = false, _showServer = false;
  String? _error;

  @override
  void dispose() { _user.dispose(); _pass.dispose(); _server.dispose(); super.dispose(); }

  Future<void> _login() async {
    FocusScope.of(context).unfocus();
    if (!_form.currentState!.validate()) return;
    setState(() { _phase = ButtonPhase.loading; _error = null; });
    try {
      await Api.setServer(_server.text);
      await Api.login(_user.text.trim(), _pass.text);
      if (!mounted) return;
      setState(() => _phase = ButtonPhase.success);
      await Future<void>.delayed(Motion.of(context).d(const Duration(milliseconds: 450)));
      if (!mounted) return;
      SharedAxisRoute.replace(context, (_) => Api.isSuperAdmin ? const AdminHome() : const ShopHome());
    } catch (e) {
      if (!mounted) return;
      final msg = '$e'.replaceFirst('Exception: ', '');
      setState(() {
        _phase = ButtonPhase.error;
        _error = msg.contains('SocketException') || msg.contains('Failed host') || msg.contains('ClientException')
            ? "Can't reach the server. Check your internet or server address."
            : msg;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final insets = MediaQuery.viewPaddingOf(context);
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: AuroraBackground(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(Space.screen, insets.top + Space.x48, Space.screen, insets.bottom + Space.x32),
          child: AutofillGroup(
            child: Form(
              key: _form,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const BrandMark(size: 64),
                const SizedBox(height: Space.x32),
                Semantics(header: true, child: Text('Welcome back', style: context.type.displayMedium)),
                const SizedBox(height: Space.x8),
                Text('Sign in to manage your shop’s buying, selling and stock.',
                    style: context.type.bodyLarge?.copyWith(color: c.textSecondary)),
                const SizedBox(height: Space.x32),
                GlassCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    GlassTextField(
                      controller: _user, label: 'Username', required: true, prefixIcon: Icons.person_outline,
                      textInputAction: TextInputAction.next, autofillHints: const [AutofillHints.username],
                    ),
                    const SizedBox(height: Space.x12),
                    GlassTextField(
                      controller: _pass, label: 'Password', required: true, prefixIcon: Icons.lock_outline,
                      obscure: !_showPass, textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.password], onSubmitted: (_) => _login(),
                      suffix: IconButton(
                        tooltip: _showPass ? 'Hide password' : 'Show password',
                        icon: Icon(_showPass ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: c.textSecondary),
                        onPressed: () => setState(() => _showPass = !_showPass),
                      ),
                    ),
                    AnimatedSize(
                      duration: Motion.of(context).d(Durations2.enter), curve: Curves2.enter,
                      alignment: Alignment.topCenter,
                      child: _error == null ? const SizedBox(width: double.infinity) : Padding(
                        padding: const EdgeInsets.only(top: Space.x12),
                        child: Semantics(liveRegion: true, child: Align(alignment: Alignment.centerLeft,
                            child: StatusChip(label: _error!, tone: ChipTone.error))),
                      ),
                    ),
                    const SizedBox(height: Space.x8),
                    // Server setting: collapsible, hidden by default (preset to production).
                    Semantics(
                      button: true, expanded: _showServer, label: 'Server settings',
                      child: InkWell(
                        borderRadius: Shapes.md,
                        onTap: () { Haptics.tap(); setState(() => _showServer = !_showServer); },
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: Space.minTouch),
                          child: Row(children: [
                            Icon(Icons.dns_outlined, size: 20, color: c.textSecondary),
                            const SizedBox(width: Space.x8),
                            Expanded(child: Text('Server settings', style: context.type.labelLarge?.copyWith(color: c.textSecondary))),
                            AnimatedRotation(
                              turns: _showServer ? .5 : 0, duration: Motion.of(context).d(Durations2.enter),
                              child: Icon(Icons.expand_more, color: c.textSecondary),
                            ),
                          ]),
                        ),
                      ),
                    ),
                    AnimatedSize(
                      duration: Motion.of(context).d(Durations2.enter), curve: Curves2.enter, alignment: Alignment.topCenter,
                      child: !_showServer ? const SizedBox(width: double.infinity) : Padding(
                        padding: const EdgeInsets.only(top: Space.x8),
                        child: GlassTextField(controller: _server, label: 'Server URL', prefixIcon: Icons.link,
                            keyboardType: TextInputType.url, required: true,
                            validator: (v) => (v ?? '').startsWith('http') ? null : 'Must start with https://'),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: Space.section),
                PrimaryButton(label: 'Sign in', icon: Icons.arrow_forward, phase: _phase, onPressed: _login),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
