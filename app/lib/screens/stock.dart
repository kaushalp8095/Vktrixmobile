import 'package:flutter/material.dart';
import '../api.dart';
import 'common.dart';
import 'sell_form.dart';

/// STOCK: jo phone kharide wo yahan dikhte hain, yahin se "Sell"
class StockScreen extends StatefulWidget {
  const StockScreen({super.key});
  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> {
  List items = []; bool loading = true;
  final search = TextEditingController();

  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    setState(() => loading = true);
    try { items = await Api.get('/stock', {'search': search.text}); } catch (e) { if (mounted) toast(context, '$e', err: true); }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _details(Map p) async {
    await showModalBottomSheet(context: context, isScrollControlled: true, builder: (c) => Padding(
      padding: const EdgeInsets.all(16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${p['brand']} ${p['model']}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        for (final e in {
          'IMEI': p['imei'], 'IMEI 2': p['imei2'], 'RAM / Storage': '${p['ram'] ?? '-'} / ${p['storage'] ?? '-'}',
          'Color': p['color'], 'Condition': p['condition'], 'Accessories': p['accessories'],
          'Kharid Price': rs(p['buy_price']), 'Kharid Date': p['buy_date'],
          'Seller': '${p['seller_name'] ?? ''} ${p['seller_phone'] ?? ''}', 'ID': '${p['seller_id_type'] ?? ''} ${p['seller_id_no'] ?? ''}',
          'Notes': p['notes'],
        }.entries)
          if (e.value != null && '${e.value}'.trim().isNotEmpty)
            Padding(padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [SizedBox(width: 120, child: Text(e.key, style: const TextStyle(color: Colors.grey))), Expanded(child: Text('${e.value}'))])),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: OutlinedButton.icon(style: OutlinedButton.styleFrom(foregroundColor: Colors.red), icon: const Icon(Icons.delete),
              label: const Text('Delete'), onPressed: () async {
                await Api.delete('/phones/${p['id']}'); if (c.mounted) Navigator.pop(c); _load();
              })),
          const SizedBox(width: 10),
          Expanded(child: FilledButton.icon(icon: const Icon(Icons.sell), label: const Text('Becho'), onPressed: () { Navigator.pop(c); _sell(p); })),
        ]),
      ]),
    ));
  }

  Future<void> _sell(Map p) async {
    final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => SellForm(phone: p)));
    if (ok == true) _load();
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        Padding(padding: const EdgeInsets.all(10), child: TextField(controller: search, onSubmitted: (_) => _load(),
            decoration: InputDecoration(hintText: 'IMEI / Model / Brand search', prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(icon: const Icon(Icons.clear), onPressed: () { search.clear(); _load(); })))),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [Text('${items.length} phones stock me'), const Spacer(),
              Text('Value: ${rs(items.fold<num>(0, (a, b) => a + (num.tryParse('${b['buy_price']}') ?? 0)))}')])),
        Expanded(child: loading ? const Center(child: CircularProgressIndicator()) : RefreshIndicator(onRefresh: _load,
          child: items.isEmpty ? ListView(children: const [SizedBox(height: 100), Center(child: Text('Stock khaali hai'))]) :
          ListView.builder(itemCount: items.length, itemBuilder: (_, i) {
            final p = items[i];
            return Card(margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.phone_android)),
              title: Text('${p['brand']} ${p['model']}'),
              subtitle: Text('${p['ram'] ?? ''} ${p['storage'] ?? ''} • ${p['condition'] ?? ''}\nIMEI: ${p['imei']}'),
              isThreeLine: true,
              trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(rs(p['buy_price']), style: const TextStyle(fontWeight: FontWeight.bold)),
                InkWell(onTap: () => _sell(p), child: const Text('BECHO', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold))),
              ]),
              onTap: () => _details(p),
            ));
          }))),
      ]);
}
