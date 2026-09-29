import 'package:flutter/material.dart';
import '../api.dart';
import 'common.dart';

class Dashboard extends StatefulWidget {
  final void Function(int) onGo;
  const Dashboard({super.key, required this.onGo});
  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  Map? d;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    try { d = await Api.get('/reports/summary'); } catch (e) { if (mounted) toast(context, '$e', err: true); }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => d == null
      ? const Center(child: CircularProgressIndicator())
      : RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(12), children: [
          const Text('Aaj ka hisaab', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          statCard('Aaj Kharida', '${d!['purchases']['count']} • ${rs(d!['purchases']['amount'])}', Icons.call_received, Colors.blue),
          statCard('Aaj Becha', '${d!['sales']['count']} • ${rs(d!['sales']['amount'])}', Icons.call_made, Colors.green),
          statCard('Aaj ka Profit', rs(d!['sales']['profit']), Icons.trending_up, Colors.teal),
          statCard('Stock me', '${d!['stock']['count']} phones • ${rs(d!['stock']['value'])}', Icons.inventory, Colors.orange),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: FilledButton.icon(onPressed: () => widget.onGo(1), icon: const Icon(Icons.add), label: const Text('Phone Kharido'))),
            const SizedBox(width: 10),
            Expanded(child: FilledButton.tonalIcon(onPressed: () => widget.onGo(2), icon: const Icon(Icons.sell), label: const Text('Phone Becho'))),
          ]),
        ]));
}
