import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api.dart';
import 'common.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final f = DateFormat('yyyy-MM-dd');
  late DateTimeRange range;
  String preset = 'month';
  Map? d; List daily = [];

  @override
  void initState() { super.initState(); _preset('month'); }

  void _preset(String p) {
    final n = DateTime.now();
    preset = p;
    range = switch (p) {
      'today' => DateTimeRange(start: n, end: n),
      'week' => DateTimeRange(start: n.subtract(const Duration(days: 6)), end: n),
      'year' => DateTimeRange(start: DateTime(n.year, 1, 1), end: n),
      _ => DateTimeRange(start: DateTime(n.year, n.month, 1), end: n),
    };
    _load();
  }

  Future<void> _load() async {
    final q = {'from': f.format(range.start), 'to': f.format(range.end)};
    try {
      d = await Api.get('/reports/summary', q);
      daily = await Api.get('/reports/daily', q);
    } catch (e) { if (mounted) toast(context, '$e', err: true); }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final maxSale = daily.fold<num>(1, (a, b) => b['sales'] > a ? b['sales'] : a);
    return ListView(padding: const EdgeInsets.all(12), children: [
      Wrap(spacing: 6, children: [
        for (final e in {'today': 'Aaj', 'week': '7 Din', 'month': 'Is Mahine', 'year': 'Is Saal'}.entries)
          ChoiceChip(label: Text(e.value), selected: preset == e.key, onSelected: (_) => _preset(e.key)),
        ActionChip(avatar: const Icon(Icons.date_range, size: 18), label: const Text('Custom'), onPressed: () async {
          final r = await showDateRangePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime.now(), initialDateRange: range);
          if (r != null) { range = r; preset = 'custom'; _load(); }
        }),
      ]),
      Text('${DateFormat('dd MMM yyyy').format(range.start)}  →  ${DateFormat('dd MMM yyyy').format(range.end)}', style: const TextStyle(color: Colors.grey)),
      const SizedBox(height: 8),
      if (d == null) const Center(child: CircularProgressIndicator()) else ...[
        statCard('Kharidi (Purchase)', '${d!['purchases']['count']} phones • ${rs(d!['purchases']['amount'])}', Icons.call_received, Colors.blue),
        statCard('Bikri (Sales)', '${d!['sales']['count']} phones • ${rs(d!['sales']['amount'])}', Icons.call_made, Colors.green),
        statCard('Net Profit', rs(d!['sales']['profit']), Icons.trending_up, d!['sales']['profit'] >= 0 ? Colors.teal : Colors.red),
        statCard('Current Stock', '${d!['stock']['count']} phones • ${rs(d!['stock']['value'])}', Icons.inventory, Colors.orange),
        if ((d!['by_payment'] as List).isNotEmpty) Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Payment Mode', style: TextStyle(fontWeight: FontWeight.bold)),
            for (final p in d!['by_payment']) Row(children: [Text('${p['mode']}'.toUpperCase()), const Spacer(), Text('${p['count']} • ${rs(p['total'])}')]),
          ]))),
        if ((d!['top_models'] as List).isNotEmpty) Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Sabse zyada bikne wale', style: TextStyle(fontWeight: FontWeight.bold)),
            for (final m in d!['top_models']) Row(children: [Text('${m['brand']} ${m['model']}'), const Spacer(), Text('${m['count']}')]),
          ]))),
        if (daily.isNotEmpty) Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Roz ki Sales', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            for (final x in daily) Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(children: [
              SizedBox(width: 80, child: Text('${x['date']}'.substring(5), style: const TextStyle(fontSize: 12))),
              Expanded(child: LinearProgressIndicator(value: x['sales'] / maxSale, minHeight: 14, borderRadius: BorderRadius.circular(4))),
              SizedBox(width: 90, child: Text(rs(x['sales']), textAlign: TextAlign.right, style: const TextStyle(fontSize: 12))),
            ])),
          ]))),
      ],
    ]);
  }
}
