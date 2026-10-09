// BUY FORM: IMEI 15 digits → auto-lookup fills brand/model/RAM/storage/color.
// Catalog (tac_models) first; if it misses, this shop's own last entry for the same
// IMEI fills it. Status shown as live StatusChip; save adds to stock. Test hook: testLookup/testSave.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api.dart';
import '../design/components/components.dart';
import '../design/design.dart';
import 'common.dart';
import 'scanner.dart';

class BuyForm extends StatefulWidget {
  final VoidCallback onSaved;
  final Future<Map<String, dynamic>> Function(String imei)? testLookup;
  final Future<void> Function(Map<String, dynamic> body)? testSave;
  const BuyForm({super.key, required this.onSaved, this.testLookup, this.testSave});
  @override
  State<BuyForm> createState() => _BuyFormState();
}

enum _ImeiState { none, looking, found, community, fromHistory, newModel, invalid, duplicate }

class _BuyFormState extends State<BuyForm> {
  final _form = GlobalKey<FormState>();
  final _scroll = ScrollController();
  final imei = TextEditingController(), imei2 = TextEditingController(), brand = TextEditingController(),
      model = TextEditingController(), ram = TextEditingController(), storage = TextEditingController(),
      color = TextEditingController(), accessories = TextEditingController(), price = TextEditingController(),
      sName = TextEditingController(), sPhone = TextEditingController(), sIdNo = TextEditingController(),
      sAddr = TextEditingController(), notes = TextEditingController();
  String condition = 'Good', idType = 'Aadhaar';
  DateTime date = DateTime.now();
  ButtonPhase _phase = ButtonPhase.idle;
  _ImeiState _imeiState = _ImeiState.none;
  String _imeiLabel = '';
  int _timesBought = 0;

  @override
  void dispose() { _scroll.dispose(); for (final c in [imei, imei2, brand, model, ram, storage, color, accessories, price, sName, sPhone, sIdNo, sAddr, notes]) { c.dispose(); } super.dispose(); }

  Future<void> _lookup(String v) async {
    if (v.length != 15) { setState(() => _imeiState = _ImeiState.none); return; }
    if (!validImei(v)) { setState(() { _imeiState = _ImeiState.invalid; _imeiLabel = 'Invalid IMEI — please check the number'; }); return; }
    setState(() => _imeiState = _ImeiState.looking);
    try {
      final r = widget.testLookup != null ? await widget.testLookup!(v) : (await Api.get('/imei/$v')) as Map<String, dynamic>;
      if (!mounted) return;
      final history = (r['history'] as List?) ?? const [];
      _timesBought = history.length;
      // Newest first: this shop's own last entry for the same IMEI/IMEI 2 — the most
      // trustworthy source we have, because the shop typed it itself.
      final Map<String, dynamic>? prev = history.isEmpty ? null : Map<String, dynamic>.from(history.first as Map);
      if (r['already_in_stock'] == true) { _imeiState = _ImeiState.duplicate; _imeiLabel = 'This phone is already in stock'; }
      else if (r['found'] == true) {
        final i = r['info'];
        brand.text = '${i['brand'] ?? ''}'; model.text = '${i['model'] ?? ''}';
        ram.text = '${i['ram'] ?? ''}'; storage.text = '${i['storage'] ?? ''}';
        if (i['color'] != null && color.text.isEmpty) color.text = '${i['color']}';
        // Community catalog rows are unverified and have no RAM/storage: plug those gaps
        // from the shop's earlier entry and say so, instead of claiming "auto-filled".
        final community = i['source'] == 'osmocom';
        final plugged = _fillFrom(prev, onlyEmpty: true);
        final name = _deviceName(i);
        _imeiState = community ? _ImeiState.community : _ImeiState.found;
        _imeiLabel = community
            ? (plugged > 0
                ? '$name · community data, verify model — RAM/storage from your earlier entry'
                : '$name · community data, verify model & fill RAM/storage')
            : '$name · details auto-filled';
      } else if (prev != null) {
        _fillFrom(prev, onlyEmpty: true);
        final name = _deviceName(prev);
        _imeiState = _ImeiState.fromHistory;
        _imeiLabel = name.isEmpty ? 'Filled from your earlier entry' : '$name · filled from your earlier entry';
      } else { _imeiState = _ImeiState.newModel; _imeiLabel = 'New model — fill brand & model once, next time they auto-fill'; }
      Haptics.tick();
    } catch (e) { _imeiState = _ImeiState.invalid; _imeiLabel = 'Lookup failed — you can still enter details manually'; }
    if (mounted) setState(() {});
  }

  /// "Samsung Galaxy S21" from a catalog or history row; skips whatever is missing
  /// instead of printing "null".
  String _deviceName(Map src) =>
      [src['brand'], src['model']].map((e) => '${e ?? ''}'.trim()).where((e) => e.isNotEmpty).join(' ');

  /// Copies brand/model/RAM/storage/color off [src]. Never overwrites a value the shop
  /// has already typed when [onlyEmpty] is set. Returns how many fields were filled.
  int _fillFrom(Map<String, dynamic>? src, {required bool onlyEmpty}) {
    if (src == null) return 0;
    var filled = 0;
    void into(TextEditingController c, String key) {
      final v = '${src[key] ?? ''}'.trim();
      if (v.isEmpty || (onlyEmpty && c.text.trim().isNotEmpty)) return;
      c.text = v; filled++;
    }
    into(brand, 'brand'); into(model, 'model'); into(ram, 'ram'); into(storage, 'storage'); into(color, 'color');
    return filled;
  }

  Future<void> _scan() async {
    final v = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const ImeiScanner()));
    if (v != null) { imei.text = v; _lookup(v); }
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!_form.currentState!.validate()) return;
    setState(() => _phase = ButtonPhase.loading);
    final body = {
      'imei': imei.text, 'imei2': imei2.text, 'brand': brand.text, 'model': model.text, 'ram': ram.text,
      'storage': storage.text, 'color': color.text, 'condition': condition, 'accessories': accessories.text,
      'buy_price': price.text, 'buy_date': DateFormat('yyyy-MM-dd').format(date),
      'seller_name': sName.text, 'seller_phone': sPhone.text, 'seller_id_type': idType, 'seller_id_no': sIdNo.text,
      'seller_address': sAddr.text, 'notes': notes.text,
    };
    try {
      if (widget.testSave != null) { await widget.testSave!(body); } else { await Api.post('/buy', body); }
      if (!mounted) return;
      setState(() => _phase = ButtonPhase.success);
      Haptics.success();
      await Future<void>.delayed(Motion.of(context).d(const Duration(milliseconds: 500)));
      if (!mounted) return;
      widget.onSaved();
    } catch (e) {
      if (!mounted) return;
      setState(() => _phase = ButtonPhase.error);
      Haptics.error();
      toast(context, '$e', err: true);
      await Future<void>.delayed(const Duration(seconds: 2));
      if (mounted && _phase == ButtonPhase.error) setState(() => _phase = ButtonPhase.idle);
    }
  }

  (ChipTone, IconData, String) get _imeiChip => switch (_imeiState) {
        _ImeiState.found => (ChipTone.success, Icons.check_circle_outline, _imeiLabel),
        _ImeiState.fromHistory => (ChipTone.success, Icons.history, _imeiLabel),
        _ImeiState.newModel => (ChipTone.warning, Icons.info_outline, _imeiLabel),
        _ImeiState.community => (ChipTone.warning, Icons.fact_check_outlined, _imeiLabel),
        _ImeiState.invalid || _ImeiState.duplicate => (ChipTone.error, Icons.cancel_outlined, _imeiLabel),
        _ => (ChipTone.neutral, Icons.search, _imeiLabel),
      };

  @override
  Widget build(BuildContext context) {
    final c = context.colors, t = context.type;
    final top = MediaQuery.viewPaddingOf(context).top;
    return Stack(children: [
      Form(
        key: _form,
        child: ListView(
          controller: _scroll,
          padding: EdgeInsets.fromLTRB(Space.screen, top + 64 + Space.x8, Space.screen, Space.x32),
          children: [
            // ---- Phone identity ----
            SectionHeader(title: 'Phone details'),
            const SizedBox(height: Space.x12),
            GlassCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              GlassTextField(
                controller: imei, label: 'IMEI 1', required: true, prefixIcon: Icons.dialpad,
                keyboardType: TextInputType.number, maxLength: 15, onChanged: _lookup,
                textInputAction: TextInputAction.next,
                suffix: _imeiState == _ImeiState.looking
                    ? const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                    : IconButton(tooltip: 'Scan IMEI barcode', icon: Icon(Icons.qr_code_scanner, color: c.brandInk), onPressed: _scan),
                validator: (v) => validImei(v ?? '') ? null : 'Enter a valid 15-digit IMEI',
              ),
              if (_imeiState != _ImeiState.none && _imeiState != _ImeiState.looking) ...[
                const SizedBox(height: Space.x8),
                Align(alignment: Alignment.centerLeft,
                  child: StatusChip(label: _imeiChip.$3 + (_timesBought > 0 ? ' · bought $_timesBought× before' : ''),
                      tone: _imeiChip.$1, icon: _imeiChip.$2)),
              ],
              const SizedBox(height: Space.x12),
              GlassTextField(controller: imei2, label: 'IMEI 2 (optional)', prefixIcon: Icons.dialpad,
                  keyboardType: TextInputType.number, maxLength: 15, textInputAction: TextInputAction.next),
            ])),
            const SizedBox(height: Space.x16),
            // ---- Device ----
            GlassCard(blur: false, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: GlassTextField(controller: brand, label: 'Brand', required: true, textInputAction: TextInputAction.next)),
                const SizedBox(width: Space.x12),
                Expanded(child: GlassTextField(controller: model, label: 'Model', required: true, textInputAction: TextInputAction.next)),
              ]),
              const SizedBox(height: Space.x12),
              Row(children: [
                Expanded(child: GlassTextField(controller: ram, label: 'RAM (e.g. 8GB)', textInputAction: TextInputAction.next)),
                const SizedBox(width: Space.x12),
                Expanded(child: GlassTextField(controller: storage, label: 'Storage (e.g. 128GB)', textInputAction: TextInputAction.next)),
              ]),
              const SizedBox(height: Space.x12),
              Row(children: [
                Expanded(child: GlassTextField(controller: color, label: 'Color', textInputAction: TextInputAction.next)),
                const SizedBox(width: Space.x12),
                Expanded(child: _GlassDropdown(label: 'Condition', value: condition,
                    items: const ['Excellent', 'Good', 'Fair', 'Faulty'], onChanged: (v) => setState(() => condition = v!))),
              ]),
              const SizedBox(height: Space.x12),
              GlassTextField(controller: accessories, label: 'Accessories (box, charger, bill)'),
            ])),
            const SizedBox(height: Space.x16),
            // ---- Price & date ----
            GlassCard(blur: false, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              GlassTextField(controller: price, label: 'Buy price (₹)', required: true, prefixIcon: Icons.currency_rupee,
                  keyboardType: TextInputType.number,
                  validator: (v) => (num.tryParse(v ?? '') ?? 0) > 0 ? null : 'Enter the buy price'),
              const SizedBox(height: Space.x12),
              Semantics(button: true, label: 'Buy date: ${DateFormat('d MMMM yyyy').format(date)}. Double tap to change.',
                child: InkWell(
                  borderRadius: Shapes.md,
                  onTap: () async {
                    final d = await showDatePicker(context: context, initialDate: date, firstDate: DateTime(2020), lastDate: DateTime.now());
                    if (d != null) setState(() => date = d);
                  },
                  child: Container(
                    height: 56, padding: const EdgeInsets.symmetric(horizontal: Space.x16),
                    decoration: BoxDecoration(borderRadius: Shapes.md, color: c.textPrimary.withValues(alpha: .05),
                        border: Border.all(color: c.textPrimary.withValues(alpha: .10))),
                    child: Row(children: [
                      Icon(Icons.calendar_month_outlined, size: 20, color: c.textSecondary),
                      const SizedBox(width: Space.x12),
                      Text(DateFormat('d MMMM yyyy').format(date), style: t.bodyLarge),
                      const Spacer(),
                      Text('Change', style: t.labelLarge?.copyWith(color: c.brandInk)),
                    ]),
                  ),
                )),
            ])),
            const SizedBox(height: Space.section),
            // ---- Seller ----
            SectionHeader(title: 'Seller details'),
            const SizedBox(height: Space.x12),
            GlassCard(blur: false, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: GlassTextField(controller: sName, label: 'Seller name', required: true, prefixIcon: Icons.person_outline, textInputAction: TextInputAction.next)),
                const SizedBox(width: Space.x12),
                Expanded(child: GlassTextField(controller: sPhone, label: 'Mobile', prefixIcon: Icons.phone_outlined, keyboardType: TextInputType.phone, maxLength: 10, textInputAction: TextInputAction.next)),
              ]),
              const SizedBox(height: Space.x12),
              Row(children: [
                Expanded(child: _GlassDropdown(label: 'ID proof', value: idType,
                    items: const ['Aadhaar', 'PAN', 'Voter ID', 'Driving Licence'], onChanged: (v) => setState(() => idType = v!))),
                const SizedBox(width: Space.x12),
                Expanded(child: GlassTextField(controller: sIdNo, label: 'ID number', textInputAction: TextInputAction.next)),
              ]),
              const SizedBox(height: Space.x12),
              GlassTextField(controller: sAddr, label: 'Address (optional)'),
              const SizedBox(height: Space.x12),
              GlassTextField(controller: notes, label: 'Notes (optional)'),
            ])),
            const SizedBox(height: Space.section),
            PrimaryButton(label: 'Save & add to stock', icon: Icons.add, phase: _phase, onPressed: _save),
          ],
        ),
      ),
      Positioned(top: 0, left: 0, right: 0, child: GlassTopBar(title: 'Buy phone', scroll: _scroll, leading: const SizedBox(width: Space.x12))),
    ]);
  }
}

/// Dropdown styled like GlassTextField.
class _GlassDropdown extends StatelessWidget {
  final String label, value;
  final List<String> items;
  final ValueChanged<String?> onChanged;
  const _GlassDropdown({required this.label, required this.value, required this.items, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      height: 56, padding: const EdgeInsets.symmetric(horizontal: Space.x16),
      decoration: BoxDecoration(borderRadius: Shapes.md, color: c.textPrimary.withValues(alpha: .05),
          border: Border.all(color: c.textPrimary.withValues(alpha: .10))),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value, isExpanded: true, dropdownColor: context.scheme.surface,
          style: context.type.bodyLarge?.copyWith(color: c.textPrimary),
          hint: Text(label, style: context.type.bodyLarge?.copyWith(color: c.textSecondary)),
          items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
          onChanged: (v) { Haptics.tick(); onChanged(v); },
        ),
      ),
    );
  }
}
