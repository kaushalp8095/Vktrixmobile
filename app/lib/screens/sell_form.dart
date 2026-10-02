// SELL FORM: phone summary → live profit calc → customer + payment → confirm.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api.dart';
import '../design/components/components.dart';
import '../design/design.dart';
import 'common.dart';

class SellForm extends StatefulWidget {
  final Map<String, dynamic> phone;
  final Future<void> Function(Map<String, dynamic> body)? testSave;
  const SellForm({super.key, required this.phone, this.testSave});
  @override
  State<SellForm> createState() => _SellFormState();
}

class _SellFormState extends State<SellForm> {
  final _form = GlobalKey<FormState>();
  final _scroll = ScrollController();
  final price = TextEditingController(), name = TextEditingController(), mob = TextEditingController(),
      addr = TextEditingController(), warranty = TextEditingController(), notes = TextEditingController();
  String pay = 'Cash';
  DateTime date = DateTime.now();
  ButtonPhase _phase = ButtonPhase.idle;

  num get _profit => (num.tryParse(price.text) ?? 0) -
      (num.tryParse('${widget.phone['buy_price']}') ?? 0);

  @override
  void initState() {
    super.initState();
    price.addListener(() => setState(() {}));
  }

  @override
  void dispose() { for (final c in [price, name, mob, addr, warranty, notes]) { c.dispose(); } _scroll.dispose(); super.dispose(); }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!_form.currentState!.validate()) return;
    setState(() => _phase = ButtonPhase.loading);
    final body = {
      'phone_id': widget.phone['id'], 'sell_price': price.text, 'sell_date': DateFormat('yyyy-MM-dd').format(date),
      'customer_name': name.text, 'customer_phone': mob.text, 'customer_address': addr.text,
      'payment_mode': pay.toLowerCase(), 'warranty': warranty.text, 'notes': notes.text,
    };
    try {
      if (widget.testSave != null) { await widget.testSave!(body); } else { await Api.post('/sell', body); }
      if (!mounted) return;
      setState(() => _phase = ButtonPhase.success);
      Haptics.success();
      await Future<void>.delayed(Motion.of(context).d(const Duration(milliseconds: 500)));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _phase = ButtonPhase.error);
      Haptics.error();
      toast(context, '$e', err: true);
      await Future<void>.delayed(const Duration(seconds: 2));
      if (mounted && _phase == ButtonPhase.error) setState(() => _phase = ButtonPhase.idle);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors, t = context.type;
    final p = widget.phone;
    final profit = _profit;
    final top = MediaQuery.viewPaddingOf(context).top;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: AuroraBackground(child: Stack(children: [
        Form(
          key: _form,
          child: ListView(
            controller: _scroll,
            padding: EdgeInsets.fromLTRB(Space.screen, top + 64 + Space.x8, Space.screen, Space.x32),
            children: [
              // ---- Phone summary ----
              GlassCard(child: Row(children: [
                Container(width: 52, height: 52,
                  decoration: BoxDecoration(color: context.scheme.primary.withValues(alpha: .12), borderRadius: BorderRadius.circular(Radii.md)),
                  child: Icon(Icons.smartphone_outlined, color: context.scheme.primary, size: 26)),
                const SizedBox(width: Space.x12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${p['brand']} ${p['model']}', style: t.titleMedium),
                  const SizedBox(height: 2),
                  Text('${p['ram'] ?? '—'} · ${p['storage'] ?? '—'} · IMEI ${p['imei']}', style: t.bodySmall?.copyWith(color: c.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
                ])),
              ])),
              const SizedBox(height: Space.x16),
              // ---- Price + profit ----
              GlassCard(blur: false, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                GlassTextField(controller: price, label: 'Sell price (₹)', required: true, prefixIcon: Icons.currency_rupee,
                    keyboardType: TextInputType.number, textInputAction: TextInputAction.next,
                    validator: (v) => (num.tryParse(v ?? '') ?? 0) > 0 ? null : 'Enter the sell price'),
                const SizedBox(height: Space.x12),
                Row(children: [
                  Expanded(child: Text('Bought at ${rs(p['buy_price'])}', style: t.bodyMedium?.copyWith(color: c.textSecondary))),
                  AnimatedSwitcher(
                    duration: Motion.of(context).d(Durations2.enter),
                    child: StatusChip(key: ValueKey(profit),
                      label: profit >= 0 ? '+${rs(profit)} profit' : '${rs(profit)} loss',
                      tone: profit >= 0 ? ChipTone.success : ChipTone.error),
                  ),
                ]),
                const SizedBox(height: Space.x12),
                InkWell(
                  borderRadius: Shapes.md,
                  onTap: () async {
                    final d = await showDatePicker(context: context, initialDate: date, firstDate: DateTime(2020), lastDate: DateTime.now());
                    if (d != null) setState(() => date = d);
                  },
                  child: Container(height: 56, padding: const EdgeInsets.symmetric(horizontal: Space.x16),
                    decoration: BoxDecoration(borderRadius: Shapes.md, color: c.textPrimary.withValues(alpha: .05),
                        border: Border.all(color: c.textPrimary.withValues(alpha: .10))),
                    child: Row(children: [
                      Icon(Icons.calendar_month_outlined, size: 20, color: c.textSecondary),
                      const SizedBox(width: Space.x12),
                      Text(DateFormat('d MMMM yyyy').format(date), style: t.bodyLarge),
                    ])),
                ),
              ])),
              const SizedBox(height: Space.section),
              SectionHeader(title: 'Customer & payment'),
              const SizedBox(height: Space.x12),
              GlassCard(blur: false, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                GlassTextField(controller: name, label: 'Customer name', required: true, prefixIcon: Icons.person_outline, textInputAction: TextInputAction.next),
                const SizedBox(height: Space.x12),
                Row(children: [
                  Expanded(child: GlassTextField(controller: mob, label: 'Mobile', prefixIcon: Icons.phone_outlined, keyboardType: TextInputType.phone, maxLength: 10, textInputAction: TextInputAction.next)),
                  const SizedBox(width: Space.x12),
                  Expanded(child: _PayDropdown(value: pay, onChanged: (v) => setState(() => pay = v!))),
                ]),
                const SizedBox(height: Space.x12),
                GlassTextField(controller: addr, label: 'Address (optional)'),
                const SizedBox(height: Space.x12),
                Row(children: [
                  Expanded(child: GlassTextField(controller: warranty, label: 'Warranty (e.g. 7 days)', textInputAction: TextInputAction.next)),
                  const SizedBox(width: Space.x12),
                  Expanded(child: GlassTextField(controller: notes, label: 'Notes (optional)', textInputAction: TextInputAction.done)),
                ]),
              ])),
              const SizedBox(height: Space.section),
              PrimaryButton(label: 'Confirm sale', icon: Icons.check, phase: _phase, onPressed: _save),
            ],
          ),
        ),
        Positioned(top: 0, left: 0, right: 0, child: GlassTopBar(title: 'Sell phone', scroll: _scroll)),
      ])),
    );
  }
}

class _PayDropdown extends StatelessWidget {
  final String value; final ValueChanged<String?> onChanged;
  const _PayDropdown({required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(height: 56, padding: const EdgeInsets.symmetric(horizontal: Space.x16),
      decoration: BoxDecoration(borderRadius: Shapes.md, color: c.textPrimary.withValues(alpha: .05),
          border: Border.all(color: c.textPrimary.withValues(alpha: .10))),
      child: DropdownButtonHideUnderline(child: DropdownButton<String>(
        value: value, isExpanded: true, dropdownColor: context.scheme.surface,
        style: context.type.bodyLarge?.copyWith(color: c.textPrimary),
        items: const ['Cash', 'UPI', 'Card', 'EMI'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
        onChanged: (v) { Haptics.tick(); onChanged(v); },
      )),
    );
  }
}
