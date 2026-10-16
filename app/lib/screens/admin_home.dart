// SUPER ADMIN: overview + shops list (create, edit, activate, reset password,
// delete). Shop ke **business data** (stock, IMEI, sales, profit, ledger,
// customer/ID) yahan nahi dikhta — uske liye reason ke saath temporary,
// read-only support access lena padta hai (dekhein support_access.dart).
// "Open as shop" hata diya gaya hai; shop screen sirf chalu support session me khulti hai.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../api.dart';
import '../design/components/components.dart';
import '../design/design.dart';
import '../documents/document_photo.dart';
import 'common.dart';
import 'login.dart';
import 'shop_home.dart';
import 'support_access.dart';
import 'tac_catalog.dart';
import 'update_checker.dart';

class AdminHome extends StatefulWidget {
  final Map<String, dynamic>? testDash; // test hooks
  final List<dynamic>? testShops;
  const AdminHome({super.key, this.testDash, this.testShops});
  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  Map? dash;
  List shops = [];
  bool loading = true;
  Object? _error;
  final _scroll = ScrollController();
  Timer? _updateTimer;

  bool _on(v) => v == true || v == 1;

  @override
  void initState() {
    super.initState();
    if (widget.testDash != null) { dash = widget.testDash; shops = widget.testShops ?? []; loading = false; }
    else _load();

    _updateTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) UpdateChecker.checkForUpdate(context);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _updateTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { loading = true; _error = null; });
    try {
      final r = await Future.wait([Api.get('/admin/dashboard'), Api.get('/admin/shops')]);
      if (!mounted) return;
      setState(() { dash = r[0] as Map; shops = r[1] as List; });
      _syncSupport();
    } catch (e) { if (mounted) setState(() => _error = e); }
    if (mounted) setState(() => loading = false);
  }

  /// Server hi sach hai: list me jo support session chalu dikh raha hai, wahi
  /// local state ban jata hai (aur koi nahi to local session hata dete hain).
  void _syncSupport() {
    final viewing = Api.viewShopId;
    for (final s in shops) {
      final support = (s['support'] as Map?) ?? const {};
      final ms = (support['expires_in_ms'] as num?)?.toInt() ?? 0;
      if (ms > 0 && (viewing == null || viewing == s['id'])) {
        Api.beginSupport(shopId: s['id'] as int, reason: '${support['reason'] ?? ''}', expiresInMs: ms);
        return;
      }
    }
    Api.endSupport();
  }

  String get _identity {
    final u = Api.user ?? const {};
    return 'Super Admin · @${u['username'] ?? ''}';
  }

  Future<void> _logout() async {
    final ok = await showLogoutDialog(context, identity: _identity,
        note: 'Support sessions aapke logout ke baad bhi shop ke log me rehti hain.');
    if (ok != true || !mounted) return;
    await Api.logout();
    if (mounted) SharedAxisRoute.replace(context, (_) => const LoginScreen());
  }

  Future<void> _shopForm([Map? shop]) async {
    final name = TextEditingController(text: shop?['name']), owner = TextEditingController(text: shop?['owner_name']),
        phone = TextEditingController(), addr = TextEditingController(text: shop?['address']),
        gst = TextEditingController(text: shop?['gst_no']), user = TextEditingController(), pass = TextEditingController();
    final masked = '${shop?['phone_masked'] ?? ''}';
    // Shop list me logo nahi aata (bhaari base64). Isliye purana logo tab tak
    // chhedte nahi jab tak admin khud Add/Change/Remove na kare.
    String? logoData;
    bool logoChanged = false;
    Uint8List? logoBytes;
    final key = GlobalKey<FormState>();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setDialogState) => AlertDialog(
      title: Text(shop == null ? 'New shop' : 'Edit shop'),
      content: Form(key: key, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextFormField(controller: name, decoration: const InputDecoration(labelText: 'Shop name *'), validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null),
        const SizedBox(height: 8),
        TextFormField(controller: owner, decoration: const InputDecoration(labelText: 'Owner name')),
        const SizedBox(height: 8),
        TextFormField(controller: phone, keyboardType: TextInputType.phone,
          decoration: InputDecoration(labelText: shop == null ? 'Mobile' : 'Mobile (naya number, optional)',
            hintText: shop == null ? null : 'current: ${masked.isEmpty ? '—' : masked}',
            helperText: shop == null ? null : 'Khali chhodein to purana number waisa hi rahega.')),
        const SizedBox(height: 8),
        TextFormField(controller: addr, decoration: const InputDecoration(labelText: 'Address')),
        const SizedBox(height: 8),
        TextFormField(controller: gst, decoration: const InputDecoration(labelText: 'GST no (optional)')),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(Space.x12),
          decoration: BoxDecoration(color: context.colors.textPrimary.withValues(alpha: .04),
            borderRadius: Shapes.md, border: Border.all(color: context.colors.textPrimary.withValues(alpha: .10))),
          child: Row(children: [
            Container(width: 54, height: 54,
              decoration: BoxDecoration(color: context.scheme.primary.withValues(alpha: .10), borderRadius: Shapes.md),
              clipBehavior: Clip.antiAlias,
              child: logoBytes == null
                ? Icon(Icons.storefront_outlined, color: context.colors.brandInk)
                : Image.memory(logoBytes!, fit: BoxFit.contain)),
            const SizedBox(width: Space.x12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Bill logo', style: context.type.titleSmall),
              Text('PDF bill par shop logo', style: context.type.bodySmall?.copyWith(color: context.colors.textSecondary)),
            ])),
            TextButton(
              onPressed: () async {
                try {
                  final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1200,
                    maxHeight: 1200, imageQuality: 100, requestFullMetadata: false);
                  if (picked == null) return;
                  final prepared = await prepareDocumentPhoto(await picked.readAsBytes());
                  if (!ctx.mounted) return;
                  setDialogState(() {
                    logoBytes = prepared;
                    logoChanged = true;
                    logoData = 'data:image/jpeg;base64,${base64Encode(prepared)}';
                  });
                } catch (_) {
                  if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Logo process nahi hua. Dobara try karein.')));
                }
              },
              child: Text(logoBytes == null ? 'Add' : 'Change'),
            ),
            if (logoBytes != null)
              IconButton(tooltip: 'Remove logo', icon: const Icon(Icons.close), onPressed: () => setDialogState(() {
                logoBytes = null; logoData = null; logoChanged = true;
              })),
          ]),
        ),
        if (shop == null) ...[
          const SizedBox(height: 16),
          Align(alignment: Alignment.centerLeft, child: Text('Shop login', style: Theme.of(ctx).textTheme.titleSmall)),
          const SizedBox(height: 8),
          TextFormField(controller: user, decoration: const InputDecoration(labelText: 'Username *'),
              validator: (v) => (v ?? '').trim().length >= 3 ? null : 'Min 3 characters'),
          const SizedBox(height: 8),
          TextFormField(controller: pass, obscureText: true, decoration: const InputDecoration(labelText: 'Password *'),
              validator: (v) => (v ?? '').length >= 6 ? null : 'Min 6 characters'),
        ],
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () { if (key.currentState!.validate()) Navigator.pop(ctx, true); },
            child: Text(shop == null ? 'Create shop' : 'Save')),
      ],
    )));
    if (ok != true) return;
    try {
      final body = <String, dynamic>{'name': name.text, 'owner_name': owner.text, 'address': addr.text,
        'gst_no': gst.text};
      if (shop == null || logoChanged) body['logo_data'] = logoData ?? '';
      // Phone sirf tab bhejte hain jab admin ne poora naya number likha ho:
      // masked ("98•••••210") value kabhi save nahi hoti.
      if (phone.text.trim().isNotEmpty) body['phone'] = phone.text.trim();
      if (shop == null) {
        await Api.post('/admin/shops', {...body, 'username': user.text.trim(), 'password': pass.text});
        if (mounted) toast(context, '${name.text} created — login: ${user.text.trim()}');
      } else {
        await Api.put('/admin/shops/${shop['id']}', body);
        if (mounted) toast(context, '${name.text} updated');
      }
      _load();
    } catch (e) { if (mounted) toast(context, '$e', err: true); }
  }

  Future<void> _resetPass(Map shop) async {
    final p = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(
      title: const Text('Reset password'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${shop['name']}', style: Theme.of(d).textTheme.bodyMedium),
        const SizedBox(height: 8),
        TextFormField(controller: p, obscureText: true, decoration: const InputDecoration(labelText: 'New password *')),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Reset'))],
    ));
    if (ok != true || p.text.length < 6) { if (ok == true && mounted) toast(context, 'Password min 6 characters', err: true); return; }
    try { await Api.post('/admin/shops/${shop['id']}/reset-password', {'password': p.text}); if (mounted) toast(context, 'Password changed'); }
    catch (e) { if (mounted) toast(context, '$e', err: true); }
  }

  Future<void> _toggle(Map s) async {
    final active = _on(s['active']);
    final ok = await showConfirmDialog(context,
      title: active ? 'Deactivate ${s['name']}?' : 'Activate ${s['name']}?',
      message: active ? 'The shop will not be able to sign in until you activate it again. No data is deleted.'
        : 'The shop can sign in again with its own password.',
      confirmLabel: active ? 'Deactivate' : 'Activate',
      cancelLabel: 'Back',
      icon: active ? Icons.pause_circle_outline : Icons.play_circle_outline,
      identity: '@${s['login']?['username'] ?? '—'}',
      destructive: active);
    if (ok != true || !mounted) return;
    try {
      await Api.put('/admin/shops/${s['id']}', {'active': !active});
      if (mounted) toast(context, active ? '${s['name']} deactivated' : '${s['name']} activated');
      _load();
    } catch (e) { if (mounted) toast(context, '$e', err: true); }
  }

  Future<void> _delete(Map s) async {
    final ok = await showConfirmDialog(context,
      title: 'Delete shop permanently?',
      message: '${s['name']} — all stock, sales and payment history will be deleted forever. This cannot be undone.',
      confirmLabel: 'Delete forever',
      cancelLabel: 'Cancel',
      icon: Icons.delete_forever_outlined,
      destructive: true,
      identity: '@${s['login']?['username'] ?? '—'} · ${s['phone_masked'] ?? 'no contact'}');
    if (ok != true || !mounted) return;
    try {
      await Api.delete('/admin/shops/${s['id']}');
      if (mounted) toast(context, '${s['name']} deleted');
      _load();
    } catch (e) { if (mounted) toast(context, '$e', err: true); }
  }

  // ---- Temporary support access (reason + time limit + read-only + log) ----
  Future<void> _startSupport(Map s) async {
    final req = await showStartSupportDialog(context, shopName: '${s['name']}');
    if (req == null || !mounted) return;
    try {
      final r = await Api.post('/admin/shops/${s['id']}/support-access', req);
      final session = (r is Map ? r['session'] : null) as Map? ?? const {};
      if (!mounted) return;
      Haptics.success();
      Api.beginSupport(shopId: s['id'] as int, reason: '${req['reason']}',
          expiresInMs: (session['expires_in_ms'] as num?)?.toInt() ?? 0);
      toast(context, 'Support access open — read-only, ${session['minutes'] ?? req['minutes']} min');
      await _openShop(s);
    } catch (e) { if (mounted) toast(context, '$e', err: true); }
  }

  Future<void> _endSupport(Map s) async {
    final ok = await showConfirmDialog(context,
      title: 'End support access?',
      message: 'Shop ka data turant lock ho jayega. Session log me "ended" likha jayega.',
      confirmLabel: 'End access',
      cancelLabel: 'Keep open',
      icon: Icons.lock_outline);
    if (ok != true || !mounted) return;
    try {
      await Api.delete('/admin/shops/${s['id']}/support-access');
      Api.endSupport();
      if (mounted) toast(context, 'Support access ended');
      _load();
    } catch (e) { if (mounted) toast(context, '$e', err: true); }
  }

  Future<void> _revealContact(Map s) async {
    try {
      final r = await Api.post('/admin/shops/${s['id']}/reveal-contact', {});
      if (!mounted) return;
      Haptics.select();
      await showRevealedContactSheet(context, shopName: '${s['name']}',
          phone: r is Map ? '${r['phone']}' : null, ownerName: r is Map ? '${r['owner_name'] ?? ''}' : null);
      if (mounted) _load();   // reveal log me gin liya gaya
    } catch (e) { if (mounted) toast(context, '$e', err: true); }
  }

  Future<void> _openShop(Map s) async {
    // Session backend par chalu rehta hai — wapas aane par list usse sync kar leti hai.
    await SharedAxisRoute.push(context, (_) => ShopHome(adminShopName: '${s['name']}'));
    if (mounted) _load();
  }

  void _openLog(Map s) => SharedAxisRoute.push(context,
      (_) => SupportAccessLogScreen(shopId: s['id'] as int, shopName: '${s['name']}'));

  Future<void> _shopSheet(Map s) async {
    Haptics.tap();
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (c) => _ShopSheet(shop: Map<String, dynamic>.from(s), onOpen: () => Navigator.pop(c, 'open')),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'open': await _openShop(s);
      case 'support': await _startSupport(s);
      case 'end': await _endSupport(s);
      case 'contact': await _revealContact(s);
      case 'log': _openLog(s);
      case 'edit': await _shopForm(s);
      case 'pass': await _resetPass(s);
      case 'toggle': await _toggle(s);
      case 'delete': await _delete(s);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final top = MediaQuery.viewPaddingOf(context).top;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'new-shop', onPressed: () => _shopForm(),
        icon: const Icon(Icons.add), label: const Text('New shop'),
      ),
      body: AuroraBackground(child: Stack(children: [
        RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(Space.screen, top + 64 + Space.x8, Space.screen, 120),
            children: [
              if (loading)
                GlassCard(blur: false, child: Shimmer(child: Column(children: List.generate(4, (_) => const SkeletonListTile()))))
              else if (_error != null)
                ErrorState(title: "Couldn't load shops", message: 'Check your internet and pull to retry.', onRetry: _load)
              else ...[
                // ---- Overview (operational counts only, no shop business data) ----
                Row(children: [
                  Expanded(child: _OvTile(icon: Icons.store_outlined, value: '${dash!['shops'] ?? shops.length}', label: 'Shops')),
                  const SizedBox(width: Space.x8),
                  Expanded(child: _OvTile(icon: Icons.verified_outlined, value: '${dash!['active_shops'] ?? 0}', label: 'Active')),
                  const SizedBox(width: Space.x8),
                  Expanded(child: _OvTile(icon: Icons.shield_outlined, value: '${dash!['support_active'] ?? 0}', label: 'Support open')),
                ]),
                const SizedBox(height: Space.x12),
                GlassCard(blur: false, child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.lock_outline, size: 18, color: c.textSecondary),
                  const SizedBox(width: Space.x12),
                  Expanded(child: Text(
                      'Shop ka stock, IMEI, sales, profit aur customer details aapko yahan nahi dikhte. Zaroorat par reason ke saath temporary, read-only support access lein — wo shop ke log me dikhega.',
                      style: context.type.bodySmall?.copyWith(color: c.textSecondary))),
                ])),
                const SizedBox(height: Space.section),
                SectionHeader(title: 'Shops'),
                const SizedBox(height: Space.x12),
                if (shops.isEmpty)
                  GlassCard(blur: false, child: EmptyState(icon: Icons.store_outlined, title: 'No shops yet',
                      message: 'Create a shop to give it its own login and data.', actionLabel: 'New shop', onAction: () => _shopForm()))
                else
                  GlassCard(blur: false, padding: EdgeInsets.zero, child: Column(children: [
                    for (var i = 0; i < shops.length; i++) ...[
                      if (i > 0) Divider(height: 1, indent: 68, color: c.textPrimary.withValues(alpha: .08)),
                      _ShopRow(s: shops[i], active: _on(shops[i]['active']), onTap: () => _shopSheet(shops[i])),
                    ],
                  ])),
                const SizedBox(height: Space.x12),
                Center(child: TextButton.icon(
                  onPressed: () => SharedAxisRoute.push(context, (_) => const SupportAccessLogScreen()),
                  icon: const Icon(Icons.receipt_long_outlined, size: 18),
                  label: const Text('Support access log'),
                )),
              ],
            ],
          ),
        ),
        Positioned(top: 0, left: 0, right: 0, child: GlassTopBar(title: 'Super Admin', scroll: _scroll,
            leading: const SizedBox(width: Space.x12),
            actions: [
              GlassIconButton(icon: Icons.manage_search, semanticLabel: 'TAC catalog (IMEI models)',
                  onPressed: () => SharedAxisRoute.push(context, (_) => const TacCatalogScreen())),
              GlassIconButton(icon: Icons.shield_outlined, semanticLabel: 'Support access log',
                  onPressed: () => SharedAxisRoute.push(context, (_) => const SupportAccessLogScreen())),
              GlassIconButton(icon: Icons.logout, semanticLabel: 'Log out', onPressed: _logout),
            ])),
      ])),
    );
  }
}

class _OvTile extends StatelessWidget {
  final IconData icon; final String value, label;
  const _OvTile({required this.icon, required this.value, required this.label});
  @override
  Widget build(BuildContext context) {
    final c = context.colors, t = context.type;
    return GlassCard(blur: false, padding: const EdgeInsets.all(Space.x12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 20, color: c.brandInk),
        const SizedBox(height: Space.x8),
        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: t.titleLarge, maxLines: 1)),
        Text(label, style: t.labelSmall?.copyWith(color: c.textSecondary)),
      ]));
  }
}

class _ShopRow extends StatelessWidget {
  final Map s; final bool active; final VoidCallback onTap;
  const _ShopRow({required this.s, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors, t = context.type;
    final support = (s['support'] as Map?) ?? const {};
    final supportMs = (support['expires_in_ms'] as num?)?.toInt() ?? 0;
    final inSupport = supportMs > 0;
    final masked = '${s['phone_masked'] ?? ''}';
    return Semantics(
      button: true,
      label: '${s['name']}, ${active ? 'active' : 'deactivated'}${inSupport ? ', support access open' : ''}, manage shop',
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.x16, Space.x12, Space.x12, Space.x12),
          child: Row(children: [
            Container(width: 44, height: 44,
              decoration: BoxDecoration(color: (active ? c.brandInk : c.textSecondary).withValues(alpha: .12), borderRadius: BorderRadius.circular(Radii.md)),
              child: Icon(Icons.store_outlined, color: active ? c.brandInk : c.textSecondary, size: 22)),
            const SizedBox(width: Space.x12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text('${s['name']}', style: t.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis)),
                const SizedBox(width: Space.x8),
                StatusChip(label: active ? 'ACTIVE' : 'OFF', tone: active ? ChipTone.success : ChipTone.neutral),
              ]),
              const SizedBox(height: 2),
              Text([
                '@${s['login']?['username'] ?? '—'}',
                if (masked.isNotEmpty && masked != 'null') masked,
                if (!active) 'sign-in blocked',
              ].join(' · '), style: t.bodySmall?.copyWith(color: c.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
              if (inSupport) ...[
                const SizedBox(height: Space.x4),
                StatusChip(label: 'SUPPORT ${clock(Duration(milliseconds: supportMs))}', tone: ChipTone.brand, icon: Icons.shield_outlined),
              ],
            ])),
            const SizedBox(width: Space.x4),
            Icon(Icons.chevron_right, size: 20, color: c.textSecondary),
          ]),
        ),
      ),
    );
  }
}

/// Shop management sheet: yahan sirf manage karne layak basic details + actions.
class _ShopSheet extends StatelessWidget {
  final Map<String, dynamic> shop;
  final VoidCallback onOpen;
  const _ShopSheet({required this.shop, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final c = context.colors, t = context.type;
    final active = shop['active'] == true || shop['active'] == 1;
    final support = (shop['support'] as Map?) ?? const {};
    final supportMs = (support['expires_in_ms'] as num?)?.toInt() ?? 0;
    final inSupport = supportMs > 0;
    final masked = '${shop['phone_masked'] ?? ''}';
    final rows = <(String, String)>[
      ('Login', '@${shop['login']?['username'] ?? '—'}${active ? '' : ' · sign-in blocked'}'),
      ('Contact', masked.isEmpty || masked == 'null' ? 'No number saved' : masked),
      if ('${shop['owner_name'] ?? ''}'.isNotEmpty) ('Owner', '${shop['owner_name']}'),
      if ('${shop['address'] ?? ''}'.isNotEmpty) ('Address', '${shop['address']}'),
      if ('${shop['gst_no'] ?? ''}'.isNotEmpty) ('GST', '${shop['gst_no']}'),
      ('Shop since', dateOnly(shop['created_at'])),
      ('Support sessions', '${shop['support_sessions'] ?? 0}'),
    ];
    return Padding(
      padding: EdgeInsets.fromLTRB(Space.x16, 0, Space.x16, MediaQuery.viewPaddingOf(context).bottom + Space.x16),
      child: GlassSurface(child: SafeArea(top: false, child: SingleChildScrollView(
        padding: const EdgeInsets.all(Space.x20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: c.textPrimary.withValues(alpha: .20), borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: Space.x16),
          Semantics(header: true, child: Text('${shop['name']}', style: t.headlineSmall, maxLines: 2, overflow: TextOverflow.ellipsis)),
          const SizedBox(height: Space.x4),
          Wrap(spacing: Space.x8, runSpacing: Space.x4, children: [
            StatusChip(label: active ? 'Active' : 'Deactivated', tone: active ? ChipTone.success : ChipTone.neutral),
            if (inSupport) StatusChip(label: 'Support open · ${clock(Duration(milliseconds: supportMs))}', tone: ChipTone.brand, icon: Icons.shield_outlined),
          ]),
          const SizedBox(height: Space.x16),
          for (final r in rows) Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 120, child: Text(r.$1, style: t.bodyMedium?.copyWith(color: c.textSecondary))),
              Expanded(child: Text(r.$2, style: t.bodyMedium)),
            ])),
          if (inSupport) ...[
            const SizedBox(height: Space.x8),
            Container(
              padding: const EdgeInsets.all(Space.x12),
              decoration: BoxDecoration(color: c.brandInk.withValues(alpha: .08), borderRadius: Shapes.md,
                  border: Border.all(color: c.brandInk.withValues(alpha: .20))),
              child: Text('Reason: ${support['reason'] ?? '—'}', style: t.bodySmall?.copyWith(color: c.textSecondary)),
            ),
          ],
          const SizedBox(height: Space.x20),
          if (inSupport) ...[
            FilledButton.icon(
              onPressed: onOpen,
              icon: const Icon(Icons.visibility_outlined, size: 20),
              label: const Text('Open shop data · read-only'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            ),
            const SizedBox(height: Space.x8),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(context, 'contact'),
              icon: const Icon(Icons.call_outlined, size: 20),
              label: const Text('Show full contact number'),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            ),
            const SizedBox(height: Space.x8),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(context, 'end'),
              icon: const Icon(Icons.lock_outline, size: 20),
              label: const Text('End support access'),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            ),
          ] else ...[
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, 'support'),
              icon: const Icon(Icons.shield_outlined, size: 20),
              label: const Text('Start support access'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            ),
            const SizedBox(height: Space.x8),
            Row(children: [
              Icon(Icons.lock_outline, size: 16, color: c.textSecondary),
              const SizedBox(width: Space.x8),
              Expanded(child: Text('Shop data aur full contact ke liye support access zaroori hai.',
                  style: t.bodySmall?.copyWith(color: c.textSecondary))),
            ]),
          ],
          const SizedBox(height: Space.x12),
          OutlinedButton.icon(
            onPressed: () => Navigator.pop(context, 'log'),
            icon: const Icon(Icons.receipt_long_outlined, size: 20),
            label: const Text('Access log'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
          const SizedBox(height: Space.x8),
          OutlinedButton.icon(
            onPressed: () => Navigator.pop(context, 'edit'),
            icon: const Icon(Icons.edit_outlined, size: 20),
            label: const Text('Edit details'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
          const SizedBox(height: Space.x8),
          OutlinedButton.icon(
            onPressed: () => Navigator.pop(context, 'pass'),
            icon: const Icon(Icons.password_outlined, size: 20),
            label: const Text('Reset password'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
          const SizedBox(height: Space.x8),
          OutlinedButton.icon(
            onPressed: () => Navigator.pop(context, 'toggle'),
            icon: Icon(active ? Icons.pause_circle_outline : Icons.play_circle_outline, size: 20),
            label: Text(active ? 'Deactivate shop' : 'Activate shop'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
          const SizedBox(height: Space.x12),
          Center(child: TextButton(
            onPressed: () => Navigator.pop(context, 'delete'),
            child: Text('Delete shop', style: t.labelLarge?.copyWith(color: c.errorInk)),
          )),
        ]),
      ))),
    );
  }
}
