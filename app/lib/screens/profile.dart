// PROFILE & SETTINGS: shop card → theme → account (change password, logout) → app info.
import 'package:flutter/material.dart';
import '../api.dart';
import '../design/components/components.dart';
import '../design/design.dart';
import '../main.dart' show themeMode;
import 'common.dart';
import 'login.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _scroll = ScrollController();
  String _theme = 'system';
  ButtonPhase _passPhase = ButtonPhase.idle;

  @override
  void initState() {
    super.initState();
    Api.themeMode().then((m) { if (mounted) setState(() => _theme = m); });
  }

  @override
  void dispose() { _scroll.dispose(); super.dispose(); }

  Future<void> _setTheme(String m) async {
    Haptics.tick();
    setState(() => _theme = m);
    themeMode.value = switch (m) { 'light' => ThemeMode.light, 'dark' => ThemeMode.dark, _ => ThemeMode.system };
    await Api.setThemeMode(m);
  }

  Future<void> _changePassword() async {
    final old = TextEditingController(), nw = TextEditingController(), cf = TextEditingController();
    final key = GlobalKey<FormState>();
    final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(
      title: const Text('Change password'),
      content: Form(key: key, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextFormField(controller: old, obscureText: true, decoration: const InputDecoration(labelText: 'Current password *'),
            autofillHints: const [AutofillHints.password], validator: (v) => (v ?? '').isEmpty ? 'Required' : null),
        const SizedBox(height: 12),
        TextFormField(controller: nw, obscureText: true, decoration: const InputDecoration(labelText: 'New password *'),
            autofillHints: const [AutofillHints.newPassword], validator: (v) => (v ?? '').length >= 6 ? null : 'Min 6 characters'),
        const SizedBox(height: 12),
        TextFormField(controller: cf, obscureText: true, decoration: const InputDecoration(labelText: 'Confirm new password *'),
            autofillHints: const [AutofillHints.newPassword], validator: (v) => v == nw.text ? null : "Doesn't match"),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
        FilledButton(onPressed: () { if (key.currentState!.validate()) Navigator.pop(d, true); }, child: const Text('Change'))],
    ));
    if (ok != true || !mounted) return;
    setState(() => _passPhase = ButtonPhase.loading);
    try {
      await Api.changePassword(old.text, nw.text);
      if (!mounted) return;
      setState(() => _passPhase = ButtonPhase.success);
      Haptics.success();
      await Api.logout();
      if (!mounted) return;
      toast(context, 'Password changed. Please log in again.');
      SharedAxisRoute.replace(context, (_) => const LoginScreen());
    } catch (e) {
      if (!mounted) return;
      setState(() => _passPhase = ButtonPhase.error);
      Haptics.error();
      toast(context, '$e', err: true);
      await Future<void>.delayed(const Duration(seconds: 2));
      if (mounted && _passPhase == ButtonPhase.error) setState(() => _passPhase = ButtonPhase.idle);
    }
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(
      title: const Text('Log out?'),
      content: const Text('You will need your username and password to sign back in.'),
      actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Log out'))],
    ));
    if (ok != true) return;
    await Api.logout();
    if (mounted) SharedAxisRoute.replace(context, (_) => const LoginScreen());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors, t = context.type;
    final u = Api.user ?? const {};
    final shop = (u['shop'] as Map?) ?? const {};
    final top = MediaQuery.viewPaddingOf(context).top;
    return Scaffold(
      body: AuroraBackground(child: Stack(children: [
        ListView(
          controller: _scroll,
          padding: EdgeInsets.fromLTRB(Space.screen, top + 64 + Space.x8, Space.screen, Space.x32),
          children: [
            // ---- Shop card ----
            GlassCard(child: Row(children: [
              SizedBox.square(dimension: 56, child: GlassSurface(radius: Radii.full, blur: false,
                  child: Center(child: Text(
                      ('${shop['name'] ?? u['name'] ?? 'S'}').trim().characters.first.toUpperCase(),
                      style: t.headlineSmall?.copyWith(color: c.brandInk)))),
              ),
              const SizedBox(width: Space.x12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${shop['name'] ?? u['name'] ?? 'My Shop'}', style: t.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text('@${u['username'] ?? ''} · ${u['role'] == 'superadmin' ? 'Super Admin' : 'Shop owner'}',
                    style: t.bodySmall?.copyWith(color: c.textSecondary)),
              ])),
            ])),
            const SizedBox(height: Space.section),
            // ---- Appearance ----
            SectionHeader(title: 'Appearance'),
            const SizedBox(height: Space.x12),
            GlassCard(blur: false, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Theme', style: t.labelLarge?.copyWith(color: c.textSecondary)),
              const SizedBox(height: Space.x12),
              Semantics(
                label: 'Theme',
                child: Row(children: [
                  for (final m in [('system', 'System', Icons.settings_brightness_outlined), ('light', 'Light', Icons.light_mode_outlined), ('dark', 'Dark', Icons.dark_mode_outlined)])
                    Expanded(child: Padding(
                      padding: EdgeInsets.only(left: m.$1 == 'system' ? 0 : Space.x8),
                      child: _ThemeTile(key: ValueKey('theme-${m.$1}'), mode: m.$1, label: m.$2, icon: m.$3,
                          selected: _theme == m.$1, onTap: () => _setTheme(m.$1)),
                    )),
                ]),
              ),
            ])),
            const SizedBox(height: Space.section),
            // ---- Account ----
            SectionHeader(title: 'Account'),
            const SizedBox(height: Space.x12),
            GlassCard(blur: false, padding: EdgeInsets.zero, child: Column(children: [
              _RowTap(icon: Icons.lock_reset, title: 'Change password', onTap: _changePassword,
                  trailing: _passPhase == ButtonPhase.loading
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : _passPhase == ButtonPhase.success ? Icon(Icons.check_circle, color: c.success, size: 20) : null),
              Divider(height: 1, indent: 56, color: c.textPrimary.withValues(alpha: .08)),
              _RowTap(icon: Icons.dns_outlined, title: 'Server', subtitle: baseUrl, onTap: () async {
                final ctrl = TextEditingController(text: baseUrl);
                final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(
                  title: const Text('Server address'),
                  content: TextFormField(controller: ctrl, decoration: const InputDecoration(labelText: 'URL', hintText: 'https://…'),
                      keyboardType: TextInputType.url),
                  actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
                    FilledButton(onPressed: () => Navigator.pop(d, ctrl.text.startsWith('http')), child: const Text('Save'))],
                ));
                if (ok == true) { await Api.setServer(ctrl.text); if (mounted) { setState(() {}); toast(context, 'Server saved'); } }
              }),
              Divider(height: 1, indent: 56, color: c.textPrimary.withValues(alpha: .08)),
              _RowTap(icon: Icons.logout, title: 'Log out', destructive: true, onTap: _logout),
            ])),
            const SizedBox(height: Space.section),
            Center(child: Text('Vktrix Mobile · v1.0\nBuy, sell and stock for mobile shops',
                style: t.bodySmall?.copyWith(color: c.textSecondary), textAlign: TextAlign.center)),
          ],
        ),
        Positioned(top: 0, left: 0, right: 0, child: GlassTopBar(title: 'Profile', scroll: _scroll)),
      ])),
    );
  }
}

class _ThemeTile extends StatelessWidget {
  final String mode, label; final IconData icon; final bool selected; final VoidCallback onTap;
  const _ThemeTile({super.key, required this.mode, required this.label, required this.icon, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final c = context.colors, t = context.type;
    return Semantics(
      button: true, selected: selected, label: '$label theme',
      child: InkWell(
        borderRadius: Shapes.md, onTap: onTap,
        child: AnimatedContainer(
          duration: Motion.of(context).d(Durations2.enter), curve: Curves2.enter,
          height: 64,
          decoration: BoxDecoration(
            color: selected ? c.brandInk.withValues(alpha: .12) : c.textPrimary.withValues(alpha: .04),
            borderRadius: Shapes.md,
            border: Border.all(color: selected ? c.brandInk : c.textPrimary.withValues(alpha: .10), width: selected ? 1.5 : 1),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 20, color: selected ? c.brandInk : c.textSecondary),
            const SizedBox(height: Space.x4),
            Text(label, style: t.labelMedium?.copyWith(color: selected ? c.brandInk : c.textPrimary)),
          ]),
        ),
      ),
    );
  }
}

class _RowTap extends StatelessWidget {
  final IconData icon; final String title; final String? subtitle; final bool destructive; final VoidCallback onTap; final Widget? trailing;
  const _RowTap({required this.icon, required this.title, this.subtitle, this.destructive = false, required this.onTap, this.trailing});
  @override
  Widget build(BuildContext context) {
    final c = context.colors, t = context.type;
    final col = destructive ? c.errorInk : c.textPrimary;
    return Semantics(
      button: true, label: title,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Space.minTouch),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.x16, vertical: Space.x8),
            child: Row(children: [
              Icon(icon, size: 22, color: destructive ? c.errorInk : c.textSecondary),
              const SizedBox(width: Space.x12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: t.titleSmall?.copyWith(color: col)),
                if (subtitle != null) Text(subtitle!, style: t.bodySmall?.copyWith(color: c.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
              ])),
              trailing ?? Icon(Icons.chevron_right, size: 20, color: c.textSecondary),
            ]),
          ),
        ),
      ),
    );
  }
}
