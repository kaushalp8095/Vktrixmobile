import 'package:flutter/material.dart';
import '../api.dart';
import 'common.dart';
import 'login.dart';
import 'shop_home.dart';

/// SUPER ADMIN: sabhi shops manage karna
class AdminHome extends StatefulWidget {
  const AdminHome({super.key});
  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  Map? dash;
  List shops = [];
  bool loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    Api.viewShopId = null;
    setState(() => loading = true);
    try {
      dash = await Api.get('/admin/dashboard');
      shops = await Api.get('/admin/shops');
    } catch (e) { if (mounted) toast(context, '$e', err: true); }
    if (mounted) setState(() => loading = false);
  }

  bool _on(v) => v == true || v == 1;

  Future<void> _shopForm([Map? shop]) async {
    final name = TextEditingController(text: shop?['name']), owner = TextEditingController(text: shop?['owner_name']),
        phone = TextEditingController(text: shop?['phone']), addr = TextEditingController(text: shop?['address']),
        gst = TextEditingController(text: shop?['gst_no']), user = TextEditingController(), pass = TextEditingController();
    final key = GlobalKey<FormState>();
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: Text(shop == null ? 'Nayi Shop' : 'Shop Edit'),
      content: Form(key: key, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        field(name, 'Shop Name', required: true), field(owner, 'Owner Name'),
        field(phone, 'Mobile', type: TextInputType.phone), field(addr, 'Address'), field(gst, 'GST No'),
        if (shop == null) ...[
          const Divider(), const Text('Shop Login'),
          const SizedBox(height: 8),
          field(user, 'Username', required: true), field(pass, 'Password', required: true),
        ],
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(onPressed: () { if (key.currentState!.validate()) Navigator.pop(c, true); }, child: const Text('Save')),
      ],
    ));
    if (ok != true) return;
    try {
      final body = {'name': name.text, 'owner_name': owner.text, 'phone': phone.text, 'address': addr.text, 'gst_no': gst.text};
      if (shop == null) {
        await Api.post('/admin/shops', {...body, 'username': user.text.trim(), 'password': pass.text});
      } else {
        await Api.put('/admin/shops/${shop['id']}', {...body, 'active': _on(shop['active'])});
      }
      _load();
    } catch (e) { if (mounted) toast(context, '$e', err: true); }
  }

  Future<void> _resetPass(Map shop) async {
    final p = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: Text('Password reset: ${shop['name']}'),
      content: field(p, 'Naya Password'),
      actions: [FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Reset'))],
    ));
    if (ok != true) return;
    try { await Api.post('/admin/shops/${shop['id']}/reset-password', {'password': p.text}); toast(context, 'Password badal gaya'); }
    catch (e) { toast(context, '$e', err: true); }
  }

  Future<void> _toggle(Map s) async {
    await Api.put('/admin/shops/${s['id']}', {...s, 'active': !_on(s['active'])}..remove('login')..remove('stock_count')..remove('id')..remove('created_at'));
    _load();
  }

  Future<void> _delete(Map s) async {
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: const Text('Shop delete karein?'),
      content: Text('${s['name']} ka poora data (stock, sales) hamesha ke liye delete ho jayega.'),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Nahi')),
        FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(c, true), child: const Text('Delete'))],
    ));
    if (ok == true) { await Api.delete('/admin/shops/${s['id']}'); _load(); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Super Admin'), actions: [
          IconButton(icon: const Icon(Icons.logout), onPressed: () async {
            await Api.logout();
            if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
          }),
        ]),
        floatingActionButton: FloatingActionButton.extended(onPressed: () => _shopForm(), icon: const Icon(Icons.add), label: const Text('Nayi Shop')),
        body: loading ? const Center(child: CircularProgressIndicator()) : RefreshIndicator(
          onRefresh: _load,
          child: ListView(padding: const EdgeInsets.all(12), children: [
            if (dash != null) ...[
              statCard('Total Shops', '${dash!['shops']}', Icons.store, Colors.indigo),
              statCard('Total Stock', '${dash!['stock_count']} phones • ${rs(dash!['stock_value'])}', Icons.inventory, Colors.orange),
              statCard('Total Sales', '${dash!['sales_count']} • ${rs(dash!['sales_value'])}', Icons.currency_rupee, Colors.green),
            ],
            const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Shops', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
            ...shops.map((s) => Card(child: ListTile(
              leading: CircleAvatar(backgroundColor: _on(s['active']) ? Colors.green : Colors.grey, child: const Icon(Icons.store, color: Colors.white)),
              title: Text(s['name']),
              subtitle: Text('Login: ${s['login']?['username'] ?? '-'} • Stock: ${s['stock_count']}${_on(s['active']) ? '' : ' • BAND'}'),
              onTap: () { Api.viewShopId = s['id']; Navigator.push(context, MaterialPageRoute(builder: (_) => ShopHome(adminShopName: s['name']))).then((_) => _load()); },
              trailing: PopupMenuButton<String>(onSelected: (v) {
                if (v == 'edit') _shopForm(s);
                if (v == 'pass') _resetPass(s);
                if (v == 'toggle') _toggle(s);
                if (v == 'del') _delete(s);
              }, itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('Edit')),
                const PopupMenuItem(value: 'pass', child: Text('Password Reset')),
                PopupMenuItem(value: 'toggle', child: Text(_on(s['active']) ? 'Shop Band karo' : 'Shop Chalu karo')),
                const PopupMenuItem(value: 'del', child: Text('Delete', style: TextStyle(color: Colors.red))),
              ]),
            ))),
          ]),
        ),
      );
}
