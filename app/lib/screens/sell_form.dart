import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api.dart';
import 'common.dart';

class SellForm extends StatefulWidget {
  final Map phone;
  const SellForm({super.key, required this.phone});
  @override
  State<SellForm> createState() => _SellFormState();
}

class _SellFormState extends State<SellForm> {
  final key = GlobalKey<FormState>();
  final price = TextEditingController(), name = TextEditingController(), mob = TextEditingController(),
      addr = TextEditingController(), warranty = TextEditingController(), notes = TextEditingController();
  String pay = 'cash'; DateTime date = DateTime.now(); bool saving = false;

  num get profit => (num.tryParse(price.text) ?? 0) - (num.tryParse('${widget.phone['buy_price']}') ?? 0);

  Future<void> _save() async {
    if (!key.currentState!.validate()) return;
    setState(() => saving = true);
    try {
      await Api.post('/sell', {
        'phone_id': widget.phone['id'], 'sell_price': price.text, 'sell_date': DateFormat('yyyy-MM-dd').format(date),
        'customer_name': name.text, 'customer_phone': mob.text, 'customer_address': addr.text,
        'payment_mode': pay, 'warranty': warranty.text, 'notes': notes.text,
      });
      if (!mounted) return;
      toast(context, 'Phone bik gaya ✓');
      Navigator.pop(context, true);
    } catch (e) { toast(context, '$e', err: true); }
    if (mounted) setState(() => saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.phone;
    return Scaffold(
      appBar: AppBar(title: const Text('Phone Becho')),
      body: Form(key: key, child: ListView(padding: const EdgeInsets.all(14), children: [
        Card(color: Colors.indigo.shade50, child: ListTile(
          title: Text('${p['brand']} ${p['model']}', style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text('${p['ram'] ?? ''} ${p['storage'] ?? ''}\nIMEI: ${p['imei']}'),
          trailing: Text('Kharid\n${rs(p['buy_price'])}', textAlign: TextAlign.right),
        )),
        const SizedBox(height: 12),
        field(price, 'Bechne ka Price ₹', type: TextInputType.number, required: true, onChanged: (_) => setState(() {})),
        if (price.text.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(
            profit >= 0 ? 'Profit: ${rs(profit)}' : 'Loss: ${rs(-profit)}',
            style: TextStyle(color: profit >= 0 ? Colors.green : Colors.red, fontWeight: FontWeight.bold))),
        field(name, 'Customer Naam', required: true),
        field(mob, 'Customer Mobile', type: TextInputType.phone),
        field(addr, 'Address'),
        DropdownButtonFormField(value: pay, decoration: const InputDecoration(labelText: 'Payment'),
            items: const [DropdownMenuItem(value: 'cash', child: Text('Cash')), DropdownMenuItem(value: 'upi', child: Text('UPI')),
              DropdownMenuItem(value: 'card', child: Text('Card')), DropdownMenuItem(value: 'credit', child: Text('Udhaar'))],
            onChanged: (v) => pay = v!),
        const SizedBox(height: 12),
        field(warranty, 'Warranty (e.g. 7 din)'),
        OutlinedButton.icon(icon: const Icon(Icons.calendar_month), label: Text('Date: ${DateFormat('dd-MM-yyyy').format(date)}'),
            onPressed: () async {
              final d = await showDatePicker(context: context, initialDate: date, firstDate: DateTime(2020), lastDate: DateTime.now());
              if (d != null) setState(() => date = d);
            }),
        const SizedBox(height: 12),
        field(notes, 'Notes'),
        SizedBox(height: 50, child: FilledButton.icon(onPressed: saving ? null : _save, icon: const Icon(Icons.check),
            label: Text(saving ? 'Saving...' : 'Sale Complete karo'))),
      ])),
    );
  }
}
