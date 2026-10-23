// SELL FORM: phone summary → live profit calc → customer + payment → confirm.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../api.dart';
import '../documents/document_photo.dart';
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
  String pay = 'Cash', idType = 'Aadhaar';
  final List<Uint8List?> _idPhotos = [null, null];
  int? _pickingSide;
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

  String _photoDataUrl(int side) => _idPhotos[side] == null
      ? '' : 'data:image/jpeg;base64,${base64Encode(_idPhotos[side]!)}';

  Future<void> _pickIdPhoto(int side) async {
    if (_pickingSide != null || _phase == ButtonPhase.loading || _phase == ButtonPhase.success) return;
    FocusScope.of(context).unfocus();
    setState(() => _pickingSide = side);
    try {
      final source = await showModalBottomSheet<ImageSource>(
        context: context, showDragHandle: true,
        builder: (sheet) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${side == 0 ? 'Front' : 'Back'} photo', style: context.type.titleMedium),
          ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Choose from gallery'),
            onTap: () => Navigator.pop(sheet, ImageSource.gallery)),
          ListTile(leading: const Icon(Icons.photo_camera_outlined), title: const Text('Take a photo'),
            onTap: () => Navigator.pop(sheet, ImageSource.camera)),
          if (_idPhotos[side] != null) ListTile(leading: const Icon(Icons.delete_outline), title: const Text('Remove photo'),
            onTap: () { setState(() => _idPhotos[side] = null); Navigator.pop(sheet); }),
        ])),
      );
      if (source == null || !mounted) return;
      final picked = await ImagePicker().pickImage(source: source, maxWidth: 2000, maxHeight: 2000,
        imageQuality: 100, requestFullMetadata: false);
      if (picked == null || !mounted) return;
      if (await picked.length() > documentPhotoMaxInputBytes) {
        throw const FormatException('Choose a photo smaller than 20 MB.');
      }
      final bytes = await prepareDocumentPhoto(await picked.readAsBytes());
      if (mounted) setState(() => _idPhotos[side] = bytes);
    } catch (_) {
      if (mounted) toast(context, 'Could not process the photo. Please try a JPEG/PNG image or take a new photo.', err: true);
    } finally {
      if (mounted) setState(() => _pickingSide = null);
    }
  }

  Widget _idProofSection() {
    final c = context.colors, t = context.type;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _IdTypeDropdown(value: idType, onChanged: (value) {
        if (value != null) setState(() => idType = value);
      }),
      const SizedBox(height: Space.x12),
      Row(children: [
        Icon(Icons.verified_user_outlined, size: 20, color: c.brandInk),
        const SizedBox(width: Space.x8),
        Expanded(child: Text('Document photos', style: t.titleSmall)),
        Text('${_idPhotos.whereType<Uint8List>().length}/2', style: t.labelLarge?.copyWith(color: c.brandInk)),
      ]),
      const SizedBox(height: Space.x4),
      Text('Upload the front and back. One photo is also enough.', style: t.bodySmall?.copyWith(color: c.textSecondary)),
      const SizedBox(height: Space.x8),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: _idPhotoTile(0)), const SizedBox(width: Space.x12), Expanded(child: _idPhotoTile(1)),
      ]),
      const SizedBox(height: Space.x4),
      Text('Photos are compressed automatically to about 100 KB. Clear text may require a larger file.',
        style: t.bodySmall?.copyWith(color: c.textSecondary)),
    ]);
  }

  Widget _idPhotoTile(int side) {
    final c = context.colors, t = context.type, bytes = _idPhotos[side];
    final name = side == 0 ? 'Front' : 'Back';
    return Material(color: context.scheme.primary.withValues(alpha: .06),
      shape: RoundedRectangleBorder(borderRadius: Shapes.md,
        side: BorderSide(color: context.scheme.primary.withValues(alpha: bytes == null ? .2 : .5))),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: _pickingSide == null ? () => _pickIdPhoto(side) : null,
        child: Padding(padding: const EdgeInsets.all(Space.x12), child: Column(children: [
          SizedBox(height: 64, child: _pickingSide == side
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
            : bytes == null ? Icon(side == 0 ? Icons.badge_outlined : Icons.flip_to_back_rounded, color: c.brandInk, size: 30)
            : Image.memory(bytes, fit: BoxFit.contain)),
          const SizedBox(height: Space.x4),
          Text('$name photo', style: t.labelLarge),
          Text(bytes == null ? 'Tap to upload' : '${(bytes.length / 1024).ceil()} KB · Change',
            textAlign: TextAlign.center, style: t.bodySmall?.copyWith(color: c.brandInk)),
        ]))));
  }

  Future<void> _save() async {
    if (_pickingSide != null || supportReadOnlyBlock(context, 'Selling a phone')) return;
    FocusScope.of(context).unfocus();
    if (!_form.currentState!.validate()) return;
    setState(() => _phase = ButtonPhase.loading);
    final paymentCode = switch (pay) {
      'UPI' => 'upi', 'Card' => 'card', 'Bank' => 'bank', 'Credit' => 'credit', _ => 'cash',
    };
    final body = {
      'phone_id': widget.phone['id'], 'sell_price': price.text, 'sell_date': DateFormat('yyyy-MM-dd').format(date),
      'customer_name': name.text, 'customer_phone': mob.text, 'customer_address': addr.text,
      'payment_mode': paymentCode, 'amount_received': received.text.isEmpty ? '0' : received.text,
      'warranty': warranty.text, 'notes': notes.text, 'customer_id_type': idType,
      'customer_id_photo': _photoDataUrl(0), 'customer_id_photo_back': _photoDataUrl(1),
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
      // Keyboard ke liye body ko chhota hone dein (pehle false tha, isliye Notes/
      // Address field aur Confirm button keyboard ke neeche chhup jate the).
      resizeToAvoidBottomInset: true,
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
                  child: Container(constraints: const BoxConstraints(minHeight: 56),
                    padding: const EdgeInsets.symmetric(horizontal: Space.x16, vertical: Space.x4),
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
                      if (v == 'Credit') {
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
                  helper: 'Enter the full amount, a partial amount, or 0. Any balance will remain in the payment ledger.',
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
                _idProofSection(),
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

class _IdTypeDropdown extends StatelessWidget {
  final String value;
  final ValueChanged<String?> onChanged;
  const _IdTypeDropdown({required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    initialValue: value, decoration: const InputDecoration(labelText: 'ID proof'),
    items: const ['Aadhaar', 'PAN', 'Voter ID', 'Driving Licence', 'Visiting Card']
      .map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
    onChanged: onChanged,
  );
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
          Expanded(child: Text(paid ? 'Payment complete' : partial ? 'Partial payment' : 'Credit / payment pending',
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
    return Container(constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(horizontal: Space.x16, vertical: Space.x4),
      decoration: BoxDecoration(borderRadius: Shapes.md, color: c.textPrimary.withValues(alpha: .05),
          border: Border.all(color: c.textPrimary.withValues(alpha: .10))),
      child: DropdownButtonHideUnderline(child: DropdownButton<String>(
        value: value, isExpanded: true, dropdownColor: context.scheme.surface,
        style: context.type.bodyLarge?.copyWith(color: c.textPrimary),
        items: const ['Cash', 'UPI', 'Card', 'Bank', 'Credit'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
        onChanged: (v) { Haptics.tick(); onChanged(v); },
      )),
    );
  }
}
