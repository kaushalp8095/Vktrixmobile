// SELL FORM: phone summary → live profit calc → customer + payment → confirm.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api.dart';
import '../design/components/components.dart';
import '../design/design.dart';
import 'common.dart';
import 'receipt.dart';

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
  final price = TextEditingController(), received = TextEditingController(), name = TextEditingController(),
      mob = TextEditingController(), addr = TextEditingController(), warranty = TextEditingController(), notes = TextEditingController();
  String pay = 'Cash';
  DateTime date = DateTime.now();
  ButtonPhase _phase = ButtonPhase.idle;
  bool _receivedEdited = false;

  num get _saleAmount => num.tryParse(price.text) ?? 0;
  num get _receivedAmount => num.tryParse(received.text) ?? 0;
  num get _balance => (_saleAmount - _receivedAmount).clamp(0, double.infinity);
  num get _profit => _saleAmount - (num.tryParse('${widget.phone['buy_price']}') ?? 0);

  @override
  void initState() {
    super.initState();
    price.addListener(() {
      if (!_receivedEdited) received.text = price.text;
      if (mounted) setState(() {});
    });
    received.addListener(() { if (mounted) setState(() {}); });
  }

  @override
  void dispose() { for (final c in [price, received, name, mob, addr, warranty, notes]) { c.dispose(); } _scroll.dispose(); super.dispose(); }

  Future<void> _save() async {
    if (supportReadOnlyBlock(context, 'Selling a phone')) return;
    FocusScope.of(context).unfocus();
    if (!_form.currentState!.validate()) return;
    setState(() => _phase = ButtonPhase.loading);
    final paymentCode = switch (pay) {
      'UPI' => 'upi', 'Card' => 'card', 'Bank' => 'bank', 'Udhaar' => 'credit', _ => 'cash',
    };
    final body = {
      'phone_id': widget.phone['id'], 'sell_price': price.text, 'sell_date': DateFormat('yyyy-MM-dd').format(date),
      'customer_name': name.text, 'customer_phone': mob.text, 'customer_address': addr.text,
      'payment_mode': paymentCode, 'amount_received': received.text.isEmpty ? '0' : received.text,
      'warranty': warranty.text, 'notes': notes.text,
    };
    try {
      int? saleId;
      if (widget.testSave != null) {
        await widget.testSave!(body);
      } else {
        final saved = await Api.post('/sell', body);
        saleId = saved is Map ? int.tryParse('${saved['id']}') : null;
      }
      if (!mounted) return;
      setState(() => _phase = ButtonPhase.success);
      Haptics.success();
      await Future<void>.delayed(Motion.of(context).d(const Duration(milliseconds: 500)));
      if (!mounted) return;
      if (saleId != null) {
        await SharedAxisRoute.push(context, (_) => ReceiptScreen(type: 'sale', id: saleId!));
        if (!mounted) return;
      }
      Navigator.pop(context, true);
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
                  Expanded(child: _PayDropdown(value: pay, onChanged: (v) {
                    if (v == null) return;
                    setState(() {
                      pay = v;
                      if (v == 'Udhaar') {
                        _receivedEdited = true;
                        received.text = '0';
                      }
                    });
                  })),
                ]),
                const SizedBox(height: Space.x12),
                GlassTextField(
                  controller: received,
                  label: 'Amount received now (₹)',
                  prefixIcon: Icons.payments_outlined,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => _receivedEdited = true,
                  helper: 'Full, partial ya 0 — baki amount Udhaar ledger mein rahega.',
                  validator: (v) {
                    final amount = num.tryParse(v ?? '');
                    if (amount == null || amount < 0) return 'Enter 0 or a valid received amount';
                    if (amount > _saleAmount) return 'Received amount cannot exceed sell price';
                    return null;
                  },
                ),
                const SizedBox(height: Space.x12),
                _PaymentSummary(total: _saleAmount, received: _receivedAmount, balance: _balance),
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

class _PaymentSummary extends StatelessWidget {
  final num total, received, balance;
  const _PaymentSummary({required this.total, required this.received, required this.balance});

  @override
  Widget build(BuildContext context) {
    final c = context.colors, t = context.type;
    final paid = total > 0 && balance <= 0;
    final partial = received > 0 && balance > 0;
    return AnimatedContainer(
      duration: Motion.of(context).d(Durations2.enter),
      padding: const EdgeInsets.all(Space.x12),
      decoration: BoxDecoration(
        color: (paid ? c.success : balance > 0 ? c.warning : c.brandInk).withValues(alpha: .09),
        borderRadius: Shapes.md,
        border: Border.all(color: (paid ? c.success : balance > 0 ? c.warning : c.brandInk).withValues(alpha: .24)),
      ),
      child: Column(children: [
        Row(children: [
          Icon(paid ? Icons.check_circle_outline : Icons.account_balance_wallet_outlined,
            size: 20, color: paid ? c.successInk : balance > 0 ? c.warningInk : c.brandInk),
          const SizedBox(width: Space.x8),
          Expanded(child: Text(paid ? 'Payment complete' : partial ? 'Partial payment' : 'Udhaar / payment pending',
            style: t.titleSmall)),
          StatusChip(label: paid ? 'PAID' : '${rs(balance)} DUE', tone: paid ? ChipTone.success : ChipTone.warning),
        ]),
        const SizedBox(height: Space.x12),
        Row(children: [
          Expanded(child: _MoneyStat(label: 'Bill', value: total)),
          Expanded(child: _MoneyStat(label: 'Received', value: received)),
          Expanded(child: _MoneyStat(label: 'Balance', value: balance, strong: true)),
        ]),
      ]),
    );
  }
}

class _MoneyStat extends StatelessWidget {
  final String label;
  final num value;
  final bool strong;
  const _MoneyStat({required this.label, required this.value, this.strong = false});

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: context.type.labelSmall?.copyWith(color: context.colors.textSecondary)),
    const SizedBox(height: 2),
    FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
      child: Text(rs(value), style: (strong ? context.type.titleSmall : context.type.bodyMedium)?.copyWith(
        color: strong ? context.colors.brandInk : context.colors.textPrimary))),
  ]);
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
        items: const ['Cash', 'UPI', 'Card', 'Bank', 'Udhaar'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
        onChanged: (v) { Haptics.tick(); onChanged(v); },
      )),
    );
  }
}
