// PROFILE & SETTINGS: shop card → theme → account (change password, logout) → app info.
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../api.dart';
import '../design/components/components.dart';
import '../design/design.dart';
import '../main.dart' show themeMode;
import 'common.dart';
import 'login.dart';
import 'support_access.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _scroll = ScrollController();
  String _theme = 'system';
  ButtonPhase _passPhase = ButtonPhase.idle;
  /// Asli build (e.g. "1.0.0 (20769)") — hardcoded "v1.0" se support ko pata nahi
  /// chalta tha ki shop kaun sa release chala rahi hai.
  String? _version;

  @override
  void initState() {
    super.initState();
    Api.themeMode().then((m) { if (mounted) setState(() => _theme = m); });
    PackageInfo.fromPlatform().then((info) {
      final build = info.buildNumber.trim();
      final label = info.version.isEmpty ? '' : '${info.version}${build.isEmpty ? '' : ' ($build)'}';
      if (mounted && label.isNotEmpty) setState(() => _version = label);
    }).catchError((Object _) {});
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
    final ok = await showGlassFormDialog(context,
      title: 'Change password',
      icon: Icons.lock_reset,
      message: "You'll be signed out and will log in again with the new password.",
      confirmLabel: 'Change',
      validate: () => key.currentState?.validate() ?? false,
      body: (_) => Form(key: key, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextFormField(controller: old, obscureText: true, decoration: const InputDecoration(labelText: 'Current password *'),
            autofillHints: const [AutofillHints.password], validator: (v) => (v ?? '').isEmpty ? 'Required' : null),
        const SizedBox(height: 12),
        TextFormField(controller: nw, obscureText: true, decoration: const InputDecoration(labelText: 'New password *'),
            autofillHints: const [AutofillHints.newPassword], validator: (v) => (v ?? '').length >= 6 ? null : 'Min 6 characters'),
        const SizedBox(height: 12),
        TextFormField(controller: cf, obscureText: true, decoration: const InputDecoration(labelText: 'Confirm new password *'),
            autofillHints: const [AutofillHints.newPassword], validator: (v) => v == nw.text ? null : "Doesn't match"),
      ])),
    );
    final oldValue = old.text, newValue = nw.text;
    // Dialog band hone par teeno controllers dispose — pehle leak hote the.
    old.dispose(); nw.dispose(); cf.dispose();
    if (!ok || !mounted) return;
    setState(() => _passPhase = ButtonPhase.loading);
    try {
      await Api.changePassword(oldValue, newValue);
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

  /// Server address: sirf valid https URL save hota hai, aur galti ho jaye to
  /// "Use default" se wapas. Pehle `https://` jaisa aadha address bhi save ho
  /// jata tha aur uske baad app ka har request fail hota tha.
  Future<void> _editServer() async {
    final ctrl = TextEditingController(text: baseUrl);
    final formKey = GlobalKey<FormState>();
    final action = await showGlassDialog<String>(context,
      title: 'Server address',
      icon: Icons.dns_outlined,
      message: 'The address this app talks to. Change it only if your server moved.',
      note: 'Default: $defaultBaseUrl',
      child: Form(key: formKey, child: TextFormField(
        controller: ctrl, autofocus: true,
        decoration: const InputDecoration(labelText: 'URL', hintText: 'https://…'),
        keyboardType: TextInputType.url,
        validator: (v) => Api.validateServer(v ?? ''),
      )),
      footer: (ctx) => GlassDialogActions(
        cancelLabel: 'Cancel', confirmLabel: 'Save',
        middleLabel: 'Use default',
        onCancel: () => Navigator.pop(ctx),
        onMiddle: () => Navigator.pop(ctx, 'reset'),
        onConfirm: () { if (formKey.currentState!.validate()) Navigator.pop(ctx, 'save'); },
      ),
    );
    final typed = ctrl.text;
    ctrl.dispose();
    if (action == null || !mounted) return;
    try {
      if (action == 'reset') {
        await Api.resetServer();
        if (mounted) { setState(() {}); toast(context, 'Server reset to $baseUrl'); }
      } else {
        await Api.setServer(typed);
        if (mounted) { setState(() {}); toast(context, 'Server saved'); }
      }
    } catch (e) {
      if (mounted) toast(context, '$e', err: true);
    }
  }

  Uint8List? _shopLogo(dynamic value) {
    try {
      final raw = '${value ?? ''}';
      final comma = raw.indexOf(',');
      return comma < 0 ? null : base64Decode(raw.substring(comma + 1));
    } catch (_) { return null; }
  }

  Future<void> _logout() async {
    final u = Api.user ?? const {};
    final shop = (u['shop'] as Map?) ?? const {};
    // Super Admin side bhi yahi popup use karta hai (admin_home.dart).
    final ok = await showLogoutDialog(context,
        identity: '${shop['name'] ?? u['name'] ?? 'My Shop'} · @${u['username'] ?? ''}');
    if (ok != true || !mounted) return;
    await Api.logout();
    if (mounted) SharedAxisRoute.replace(context, (_) => const LoginScreen());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors, t = context.type;
    final u = Api.user ?? const {};
    final shop = (u['shop'] as Map?) ?? const {};
    final logo = _shopLogo(shop['logo_data']);
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
                  child: logo == null
                    ? Center(child: Text(
                        ('${shop['name'] ?? u['name'] ?? 'S'}').trim().characters.first.toUpperCase(),
                        style: t.headlineSmall?.copyWith(color: c.brandInk)))
                    : Padding(padding: const EdgeInsets.all(6), child: ClipOval(child: Image.memory(logo, fit: BoxFit.contain)))),
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
              _RowTap(icon: Icons.shield_outlined, title: 'Support access',
                  subtitle: 'When, why, and how much data Vktrix Support viewed',
                  onTap: () => showSupportLogSheet(context, title: 'Support access')),
              Divider(height: 1, indent: 56, color: c.textPrimary.withValues(alpha: .08)),
              _RowTap(icon: Icons.dns_outlined, title: 'Server', subtitle: baseUrl, onTap: _editServer),
              Divider(height: 1, indent: 56, color: c.textPrimary.withValues(alpha: .08)),
              _RowTap(icon: Icons.logout, title: 'Log out', destructive: true, onTap: _logout),
            ])),
            const SizedBox(height: Space.section),
            Center(child: Text('Vktrix Mobile · v${_version ?? '1.0'}\nBuy, sell and stock for mobile shops',
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
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(vertical: Space.x8),
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
