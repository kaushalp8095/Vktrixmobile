import 'package:flutter/material.dart';
import '../api.dart';
import 'common.dart';

class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});
  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  List items = []; bool loading = true;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    setState(() => loading = true);
    try { items = await Api.get('/sales'); } catch (e) { if (mounted) toast(context, '$e', err: true); }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _cancel(Map s) async {
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: const Text('Sale cancel karein?'), content: const Text('Phone wapas stock me aa jayega.'),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Nahi')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Haan'))]));
    if (ok == true) { await Api.delete('/sales/${s['id']}'); _load(); }
  }

  @override
  Widget build(BuildContext context) => loading ? const Center(child: CircularProgressIndicator()) : RefreshIndicator(
        onRefresh: _load,
        child: items.isEmpty ? ListView(children: const [SizedBox(height: 100), Center(child: Text('Abhi koi sale nahi'))]) :
        ListView.builder(itemCount: items.length, itemBuilder: (_, i) {
          final s = items[i];
          final profit = (num.tryParse('${s['sell_price']}') ?? 0) - (num.tryParse('${s['buy_price']}') ?? 0);
          return Card(margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), child: ListTile(
            leading: const CircleAvatar(backgroundColor: Colors.green, child: Icon(Icons.sell, color: Colors.white)),
            title: Text('${s['brand']} ${s['model']}'),
            subtitle: Text('${s['customer_name'] ?? ''} • ${s['sell_date']} • ${'${s['payment_mode']}'.toUpperCase()}\nIMEI: ${s['imei']}'),
            isThreeLine: true,
            trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(rs(s['sell_price']), style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(profit >= 0 ? '+${rs(profit)}' : '-${rs(-profit)}', style: TextStyle(color: profit >= 0 ? Colors.green : Colors.red)),
            ]),
            onLongPress: () => _cancel(s),
          ));
        }),
      );
}
