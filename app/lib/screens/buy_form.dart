import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api.dart';
import 'common.dart';
import 'scanner.dart';

/// BUY FORM: IMEI daalte hi model, RAM, storage auto-fill; save karte hi stock me add
class BuyForm extends StatefulWidget {
  final VoidCallback onSaved;
  const BuyForm({super.key, required this.onSaved});
  @override
  State<BuyForm> createState() => _BuyFormState();
}

class _BuyFormState extends State<BuyForm> {
  final key = GlobalKey<FormState>();
  final imei = TextEditingController(), imei2 = TextEditingController(), brand = TextEditingController(),
      model = TextEditingController(), ram = TextEditingController(), storage = TextEditingController(),
      color = TextEditingController(), accessories = TextEditingController(), price = TextEditingController(),
      sName = TextEditingController(), sPhone = TextEditingController(), sIdNo = TextEditingController(),
      sAddr = TextEditingController(), notes = TextEditingController();
  String condition = 'Good', idType = 'Aadhaar';
  DateTime date = DateTime.now();
  String? imeiMsg; Color imeiColor = Colors.grey;
  bool saving = false, looking = false;

  Future<void> _lookup(String v) async {
    if (v.length != 15) { setState(() => imeiMsg = null); return; }
    setState(() => looking = true);
    try {
      final r = await Api.get('/imei/$v');
      if (!mounted) return;
      if (r['valid'] != true) { imeiMsg = '⚠ IMEI valid nahi lag raha, dobara check karein'; imeiColor = Colors.red; }
      else if (r['already_in_stock'] == true) { imeiMsg = '⚠ Ye phone pehle se stock me hai'; imeiColor = Colors.red; }
      else if (r['found'] == true) {
        final i = r['info'];
        brand.text = i['brand'] ?? ''; model.text = i['model'] ?? '';
        ram.text = i['ram'] ?? ''; storage.text = i['storage'] ?? ''; color.text = i['color'] ?? color.text;
        imeiMsg = '✓ ${i['brand']} ${i['model']} — info auto-fill ho gayi'; imeiColor = Colors.green;
      } else { imeiMsg = 'Naya model — details bhar dein, agli baar auto-fill hoga'; imeiColor = Colors.orange; }
      if ((r['history'] as List).isNotEmpty) imeiMsg = '$imeiMsg\nℹ Ye phone pehle bhi ${(r['history'] as List).length} baar aaya tha';
    } catch (e) { imeiMsg = '$e'; imeiColor = Colors.red; }
    if (mounted) setState(() => looking = false);
  }

  Future<void> _scan() async {
    final v = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const ImeiScanner()));
    if (v != null) { imei.text = v; _lookup(v); }
  }

  Future<void> _save() async {
    if (!key.currentState!.validate()) return;
    if (!validImei(imei.text)) { toast(context, 'IMEI galat hai', err: true); return; }
    setState(() => saving = true);
    try {
      await Api.post('/buy', {
        'imei': imei.text, 'imei2': imei2.text, 'brand': brand.text, 'model': model.text, 'ram': ram.text,
        'storage': storage.text, 'color': color.text, 'condition': condition, 'accessories': accessories.text,
        'buy_price': price.text, 'buy_date': DateFormat('yyyy-MM-dd').format(date),
        'seller_name': sName.text, 'seller_phone': sPhone.text, 'seller_id_type': idType, 'seller_id_no': sIdNo.text,
        'seller_address': sAddr.text, 'notes': notes.text,
      });
      if (!mounted) return;
      toast(context, 'Phone stock me add ho gaya ✓');
      widget.onSaved();
    } catch (e) { toast(context, '$e', err: true); }
    if (mounted) setState(() => saving = false);
  }

  Widget _row(Widget a, Widget b) => Row(children: [Expanded(child: a), const SizedBox(width: 10), Expanded(child: b)]);

  @override
  Widget build(BuildContext context) => Form(
        key: key,
        child: ListView(padding: const EdgeInsets.all(14), children: [
          const Text('Phone Kharido', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          field(imei, 'IMEI 1', type: TextInputType.number, maxLength: 15, required: true, onChanged: _lookup,
              suffix: looking ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                  : IconButton(icon: const Icon(Icons.qr_code_scanner), onPressed: _scan)),
          if (imeiMsg != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(imeiMsg!, style: TextStyle(color: imeiColor))),
          field(imei2, 'IMEI 2 (optional)', type: TextInputType.number, maxLength: 15),
          _row(field(brand, 'Brand', required: true), field(model, 'Model', required: true)),
          _row(field(ram, 'RAM (e.g. 4GB)'), field(storage, 'Storage (e.g. 64GB)')),
          _row(field(color, 'Color'), Padding(padding: const EdgeInsets.only(bottom: 12), child: DropdownButtonFormField(
            value: condition, decoration: const InputDecoration(labelText: 'Condition'),
            items: ['Excellent', 'Good', 'Fair', 'Faulty'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
            onChanged: (v) => condition = v!))),
          field(accessories, 'Accessories (Box, Charger, Bill)'),
          _row(field(price, 'Kharid Price ₹', type: TextInputType.number, required: true),
            Padding(padding: const EdgeInsets.only(bottom: 12), child: OutlinedButton.icon(
              icon: const Icon(Icons.calendar_month), label: Text(DateFormat('dd-MM-yyyy').format(date)),
              onPressed: () async {
                final d = await showDatePicker(context: context, initialDate: date, firstDate: DateTime(2020), lastDate: DateTime.now());
                if (d != null) setState(() => date = d);
              }))),
          const Divider(), const Text('Bechne wale ki details', style: TextStyle(fontWeight: FontWeight.bold)), const SizedBox(height: 10),
          _row(field(sName, 'Naam', required: true), field(sPhone, 'Mobile', type: TextInputType.phone)),
          _row(Padding(padding: const EdgeInsets.only(bottom: 12), child: DropdownButtonFormField(
            value: idType, decoration: const InputDecoration(labelText: 'ID Proof'),
            items: ['Aadhaar', 'PAN', 'Voter ID', 'Driving Licence'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
            onChanged: (v) => idType = v!)), field(sIdNo, 'ID Number')),
          field(sAddr, 'Address'),
          field(notes, 'Notes'),
          SizedBox(height: 50, child: FilledButton.icon(onPressed: saving ? null : _save, icon: const Icon(Icons.save),
              label: Text(saving ? 'Saving...' : 'Save & Stock me Add karo'))),
        ]),
      );
}
