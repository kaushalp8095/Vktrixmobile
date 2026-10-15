// SUPER ADMIN: overview stats + shops list (open as shop, edit, reset pass, toggle, delete)
// + TAC catalog screen (free community IMEI model sync).
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
    Api.viewShopId = null;
    setState(() { loading = true; _error = null; });
    try {
      final r = await Future.wait([Api.get('/admin/dashboard'), Api.get('/admin/shops')]);
      if (!mounted) return;
      setState(() { dash = r[0] as Map; shops = r[1] as List; });
    } catch (e) { if (mounted) setState(() => _error = e); }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _logout() async {
    await Api.logout();
    if (mounted) SharedAxisRoute.replace(context, (_) => const LoginScreen());
  }

  Future<void> _shopForm([Map? shop]) async {
    final name = TextEditingController(text: shop?['name']), owner = TextEditingController(text: shop?['owner_name']),
        phone = TextEditingController(text: shop?['phone']), addr = TextEditingController(text: shop?['address']),
        gst = TextEditingController(text: shop?['gst_no']), user = TextEditingController(), pass = TextEditingController();
    String? logoData = '${shop?['logo_data'] ?? ''}'.trim();
    if (logoData.isEmpty) logoData = null;
    Uint8List? logoBytes;
    try {
      if (logoData != null) logoBytes = base64Decode(logoData.substring(logoData.indexOf(',') + 1));
    } catch (_) { logoData = null; }
    final key = GlobalKey<FormState>();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setDialogState) => AlertDialog(
      title: Text(shop == null ? 'New shop' : 'Edit shop'),
      content: Form(key: key, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextFormField(controller: name, decoration: const InputDecoration(labelText: 'Shop name *'), validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null),
        const SizedBox(height: 8),
        TextFormField(controller: owner, decoration: const InputDecoration(labelText: 'Owner name')),
        const SizedBox(height: 8),
        TextFormField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Mobile')),
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
                logoBytes = null; logoData = null;
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
      final body = {'name': name.text, 'owner_name': owner.text, 'phone': phone.text, 'address': addr.text,
        'gst_no': gst.text, 'logo_data': logoData ?? ''};
      if (shop == null) {
        await Api.post('/admin/shops', {...body, 'username': user.text.trim(), 'password': pass.text});
        if (mounted) toast(context, '${name.text} created — login: ${user.text.trim()}');
      } else {
        await Api.put('/admin/shops/${shop['id']}', {...body, 'active': _on(shop['active'])});
      }
      _load();
    } catch (e) { if (mounted) toast(context, '$e', err: true); }
  }

  Future<void> _resetPass(Map shop) async {
    final p = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(
      title: Text('Reset password'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(shop['name'], style: Theme.of(d).textTheme.bodyMedium),
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
    final act = _on(s['active']);
    final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(
      title: Text(act ? 'Deactivate ${s['name']}?' : 'Activate ${s['name']}?'),
      content: Text(act ? 'The shop will not be able to sign in until re-activated. Data is kept.' : 'The shop can sign in again.'),
      actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Back')),
        FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(act ? 'Deactivate' : 'Activate'))],
    ));
    if (ok != true) return;
    await Api.put('/admin/shops/${s['id']}', {...s, 'active': !act}..remove('login')..remove('stock_count')..remove('id')..remove('created_at'));
    _load();
  }

  Future<void> _delete(Map s) async {
    final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(
      title: const Text('Delete shop permanently?'),
      content: Text('${s['name']} — all stock and sales data will be deleted forever. This cannot be undone.'),
      actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
        FilledButton(style: FilledButton.styleFrom(backgroundColor: Theme.of(d).colorScheme.error),
            onPressed: () => Navigator.pop(d, true), child: const Text('Delete forever'))],
    ));
    if (ok == true) { await Api.delete('/admin/shops/${s['id']}'); _load(); }
  }

  void _open(Map s) async {
    Api.viewShopId = s['id'];
    await SharedAxisRoute.push(context, (_) => ShopHome(adminShopName: s['name']));
    Api.viewShopId = null;
    _load();
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
                // ---- Overview ----
                Row(children: [
                  Expanded(child: _OvTile(icon: Icons.store_outlined, value: '${dash!['shops']}', label: 'Shops')),
                  const SizedBox(width: Space.x8),
                  Expanded(child: _OvTile(icon: Icons.inventory_2_outlined, value: '${dash!['stock_count']}', label: 'In stock')),
                  const SizedBox(width: Space.x8),
                  Expanded(child: _OvTile(icon: Icons.currency_rupee, value: rs(dash!['sales_value']), label: 'Sales value')),
                ]),
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
                      _ShopRow(s: shops[i], active: _on(shops[i]['active']), onOpen: () => _open(shops[i]),
                          onEdit: () => _shopForm(shops[i]), onPass: () => _resetPass(shops[i]),
                          onToggle: () => _toggle(shops[i]), onDelete: () => _delete(shops[i])),
                    ],
                  ])),
              ],
            ],
          ),
        ),
        Positioned(top: 0, left: 0, right: 0, child: GlassTopBar(title: 'Super Admin', scroll: _scroll,
            leading: const SizedBox(width: Space.x12),
            actions: [
              GlassIconButton(icon: Icons.manage_search, semanticLabel: 'TAC catalog (IMEI models)',
                  onPressed: () => SharedAxisRoute.push(context, (_) => const TacCatalogScreen())),
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
  final Map s; final bool active;
  final VoidCallback onOpen, onEdit, onPass, onToggle, onDelete;
  const _ShopRow({required this.s, required this.active, required this.onOpen, required this.onEdit,
      required this.onPass, required this.onToggle, required this.onDelete});
  @override
  Widget build(BuildContext context) {
    final c = context.colors, t = context.type;
    return Semantics(
      button: true, label: '${s['name']}, ${s['stock_count']} phones in stock${active ? '' : ', deactivated'}',
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.x16, Space.x12, Space.x4, Space.x12),
          child: Row(children: [
            Container(width: 44, height: 44,
              decoration: BoxDecoration(color: (active ? c.brandInk : c.textSecondary).withValues(alpha: .12), borderRadius: BorderRadius.circular(Radii.md)),
              child: Icon(Icons.store_outlined, color: active ? c.brandInk : c.textSecondary, size: 22)),
            const SizedBox(width: Space.x12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${s['name']}', style: t.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text([
                'login: ${s['login']?['username'] ?? '—'}',
                '${s['stock_count']} in stock',
                if (!active) 'deactivated',
              ].join(' · '), style: t.bodySmall?.copyWith(color: c.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
            ])),
            PopupMenuButton<String>(
              tooltip: 'Shop actions',
              onSelected: (v) => switch (v) { 'edit' => onEdit(), 'pass' => onPass(), 'toggle' => onToggle(), _ => onDelete() },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('Edit details')),
                const PopupMenuItem(value: 'pass', child: Text('Reset password')),
                PopupMenuItem(value: 'toggle', child: Text(active ? 'Deactivate' : 'Activate')),
                PopupMenuItem(value: 'del', child: Text('Delete', style: TextStyle(color: c.errorInk))),
              ],
            ),
          ]),
        ),
      ),
    );
  }
}
