// REPAIR FORM: customer + device + complaint + paisa (estimate, charge, advance,
// internal parts cost). Naya job aur edit — dono ek hi form se.
//
// Do cheezein jaan-boojh kar alag rakhi gayi hain:
//   * "Internal" section (parts cost, diagnosis, lock note) — ye customer ke PDF
//     par kabhi nahi jaata.
//   * "My own stock phone" link — shop ke faulty phone ka repair (case B), jisse
//     repair cost us phone ke cost basis me jud jaye.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api.dart';
import '../design/components/components.dart';
import '../design/design.dart';
import 'common.dart';

class RepairForm extends StatefulWidget {
  /// Maujood job (edit). `null` = naya job.
  final Map<String, dynamic>? job;
  /// Test hook: data inject karne par network nahi chalta.
  final List<dynamic>? testStock;
  final Future<void> Function(Map<String, dynamic> body)? testSave;
  const RepairForm({super.key, this.job, this.testStock, this.testSave});
  @override
  State<RepairForm> createState() => _RepairFormState();
}

class _RepairFormState extends State<RepairForm> {
  final _form = GlobalKey<FormState>();
  final _scroll = ScrollController();
  final name = TextEditingController(), phone = TextEditingController(), address = TextEditingController(),
      brand = TextEditingController(), model = TextEditingController(), imei = TextEditingController(),
      imei2 = TextEditingController(), serial = TextEditingController(), color = TextEditingController(),
      accessories = TextEditingController(), complaint = TextEditingController(), diagnosis = TextEditingController(),
      lockNote = TextEditingController(), estimate = TextEditingController(), charge = TextEditingController(),
      parts = TextEditingController(), partsNote = TextEditingController(), warranty = TextEditingController(),
      advance = TextEditingController();

  DateTime receivedAt = DateTime.now();
  DateTime? promisedDate;
  int? phoneId;
  List<dynamic> stock = [];
  bool _internalOpen = false;
  ButtonPhase _phase = ButtonPhase.idle;

  bool get _edit => widget.job != null;
  bool get _saving => _phase == ButtonPhase.loading || _phase == ButtonPhase.success;

  @override
  void initState() {
    super.initState();
    final job = widget.job;
    if (job != null) {
      name.text = '${job['customer_name'] ?? ''}';
      phone.text = '${job['customer_phone'] ?? ''}';
      address.text = '${job['customer_address'] ?? ''}';
      brand.text = '${job['brand'] ?? ''}';
      model.text = '${job['model'] ?? ''}';
      imei.text = '${job['imei'] ?? ''}';
      imei2.text = '${job['imei2'] ?? ''}';
      serial.text = '${job['serial_number'] ?? ''}';
      color.text = '${job['color'] ?? ''}';
      accessories.text = '${job['accessories'] ?? ''}';
      complaint.text = '${job['complaint'] ?? ''}';
      diagnosis.text = '${job['diagnosis'] ?? ''}';
      lockNote.text = '${job['device_lock_note'] ?? ''}';
      estimate.text = _plain(job['estimate']);
      charge.text = _plain(job['service_charge']);
      parts.text = _plain(job['parts_cost']);
      partsNote.text = '${job['parts_note'] ?? ''}';
      warranty.text = job['warranty_days'] == null ? '' : '${job['warranty_days']}';
      phoneId = job['phone_id'] == null ? null : int.tryParse('${job['phone_id']}');
      receivedAt = DateTime.tryParse(dateOnly(job['received_at'])) ?? DateTime.now();
      promisedDate = job['promised_date'] == null ? null : DateTime.tryParse(dateOnly(job['promised_date']));
      _internalOpen = diagnosis.text.isNotEmpty || parts.text.isNotEmpty && parts.text != '0' || partsNote.text.isNotEmpty;
    }
    if (!_edit && !Api.supportReadOnly) _loadStock();
  }

  static String _plain(dynamic v) {
    final n = num.tryParse('$v');
    if (n == null || n == 0) return '';
    return n == n.roundToDouble() ? '${n.round()}' : '$n';
  }

  Future<void> _loadStock() async {
    try {
      final rows = widget.testStock ?? await Api.get('/stock');
      if (mounted) setState(() => stock = rows as List);
    } catch (_) {
      // Stock list sirf optional link ke liye hai — fail ho to job banne se na roke.
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    for (final c in [name, phone, address, brand, model, imei, imei2, serial, color, accessories,
      complaint, diagnosis, lockNote, estimate, charge, parts, partsNote, warranty, advance]) { c.dispose(); }
    super.dispose();
  }

  static String _money(TextEditingController c) {
    final v = c.text.trim();
    return v.isEmpty ? '0' : v;
  }

  static String _moneyText(TextEditingController c) => c.text.trim().isEmpty ? '0' : c.text.trim();

  String? _imeiValidator(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return null;
    if (s.length != 15 || !RegExp(r'^\d{15}$').hasMatch(s)) return 'IMEI must be 15 digits';
    if (!validImei(s)) return 'IMEI check digit is not valid';
    return null;
  }

  String? _moneyValidator(String? v, {String label = 'amount', bool required = false}) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return required ? 'Enter $label' : null;
    if (!RegExp(r'^\d{1,8}(\.\d{1,2})?$').hasMatch(s)) return 'Enter $label in rupees (max 2 decimals)';
    return null;
  }

  String? _warrantyValidator(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return null;
    final n = int.tryParse(s);
    if (n == null || n < 0 || n > 3650) return 'Enter 0-3650 days';
    return null;
  }

  Future<void> _pickDate({required bool promised}) async {
    final now = DateTime.now();
    final initial = promised ? (promisedDate ?? receivedAt) : receivedAt;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isAfter(now) && !promised ? now : initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 2),
    );
    if (picked == null) return;
    setState(() {
      if (promised) {
        promisedDate = picked;
      } else {
        receivedAt = picked;
        if (promisedDate != null && promisedDate!.isBefore(picked)) promisedDate = null;
      }
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    if (supportReadOnlyBlock(context, _edit ? 'editing a repair job' : 'adding a repair job')) return;
    FocusScope.of(context).unfocus();
    if (!_form.currentState!.validate()) return;
    // Backend bhi ye rokta hai — form me pehle hi saaf message.
    if (phone.text.trim().isEmpty && address.text.trim().isEmpty && phoneId == null) {
      toast(context, 'Add a mobile number or address so you can contact the customer', err: true);
      return;
    }
    if (promisedDate != null && promisedDate!.isBefore(receivedAt)) {
      toast(context, 'Promised date cannot be before the received date', err: true);
      return;
    }
    setState(() => _phase = ButtonPhase.loading);
    final body = <String, dynamic>{
      'customer_name': name.text.trim(),
      'customer_phone': phone.text.trim(),
      'customer_address': address.text.trim(),
      'brand': brand.text.trim(),
      'model': model.text.trim(),
      'imei': imei.text.trim(),
      'imei2': imei2.text.trim(),
      'serial_number': serial.text.trim(),
      'color': color.text.trim(),
      'accessories': accessories.text.trim(),
      'complaint': complaint.text.trim(),
      'diagnosis': diagnosis.text.trim(),
      'device_lock_note': lockNote.text.trim(),
      'estimate': _moneyText(estimate),
      'service_charge': _money(charge),
      'parts_cost': _money(parts),
      'parts_note': partsNote.text.trim(),
      'promised_date': promisedDate == null ? null : DateFormat('yyyy-MM-dd').format(promisedDate!),
      'warranty_days': warranty.text.trim().isEmpty ? null : int.parse(warranty.text.trim()),
      'phone_id': phoneId,
      if (!_edit) 'received_at': DateFormat('yyyy-MM-dd').format(receivedAt),
      if (!_edit) 'advance': _money(advance),
    };
    try {
      if (widget.testSave != null) {
        await widget.testSave!(body);
      } else if (_edit) {
        await Api.put('/repairs/${widget.job!['id']}', body);
      } else {
        await Api.post('/repairs', body);
      }
      if (!mounted) return;
      setState(() => _phase = ButtonPhase.success);
      Haptics.success();
      await Future<void>.delayed(Motion.of(context).d(const Duration(milliseconds: 450)));
      if (mounted) Navigator.of(context).pop(true);
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
    final top = MediaQuery.viewPaddingOf(context).top;
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: AuroraBackground(child: Stack(children: [
        Form(key: _form, child: ListView(
          controller: _scroll,
          padding: EdgeInsets.fromLTRB(Space.screen, top + 64 + Space.x8, Space.screen, Space.x24 + MediaQuery.viewInsetsOf(context).bottom),
          children: [
            SectionHeader(title: 'Customer'),
            GlassCard(blur: false, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              GlassTextField(controller: name, label: 'Customer name', required: true,
                prefixIcon: Icons.person_outline, textInputAction: TextInputAction.next),
              const SizedBox(height: Space.x12),
              GlassTextField(controller: phone, label: 'Mobile', prefixIcon: Icons.phone_outlined,
                keyboardType: TextInputType.phone, maxLength: 15, textInputAction: TextInputAction.next,
                helper: 'Mobile or address — kam se kam ek zaroori hai, taaki delivery par contact ho sake.'),
              const SizedBox(height: Space.x12),
              GlassTextField(controller: address, label: 'Address (optional)', textInputAction: TextInputAction.next),
              if (!_edit && stock.isNotEmpty) ...[
                const SizedBox(height: Space.x12),
                _StockPicker(
                  stock: stock, value: phoneId,
                  onChanged: (id) {
                    setState(() {
                      phoneId = id;
                      final p = id == null ? null : stock.firstWhere((e) => int.tryParse('${e['id']}') == id,
                          orElse: () => null);
                      if (p is Map) {
                        if (brand.text.trim().isEmpty) brand.text = '${p['brand'] ?? ''}';
                        if (model.text.trim().isEmpty) model.text = '${p['model'] ?? ''}';
                        if (imei.text.trim().isEmpty) imei.text = '${p['imei'] ?? ''}';
                        if (color.text.trim().isEmpty) color.text = '${p['color'] ?? ''}';
                      }
                    });
                  },
                ),
              ],
            ])),
            SectionHeader(title: 'Device & problem'),
            GlassCard(blur: false, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: GlassTextField(controller: brand, label: 'Brand', textInputAction: TextInputAction.next)),
                const SizedBox(width: Space.x12),
                Expanded(child: GlassTextField(controller: model, label: 'Model', textInputAction: TextInputAction.next)),
              ]),
              const SizedBox(height: Space.x12),
              Row(children: [
                Expanded(child: GlassTextField(controller: imei, label: 'IMEI (optional)',
                  keyboardType: TextInputType.number, maxLength: 15, textInputAction: TextInputAction.next,
                  validator: _imeiValidator)),
                const SizedBox(width: Space.x12),
                Expanded(child: GlassTextField(controller: imei2, label: 'IMEI 2 (optional)',
                  keyboardType: TextInputType.number, maxLength: 15, textInputAction: TextInputAction.next,
                  validator: _imeiValidator)),
              ]),
              const SizedBox(height: Space.x12),
              Row(children: [
                Expanded(child: GlassTextField(controller: color, label: 'Colour', textInputAction: TextInputAction.next)),
                const SizedBox(width: Space.x12),
                Expanded(child: GlassTextField(controller: serial, label: 'Serial (optional)', textInputAction: TextInputAction.next)),
              ]),
              const SizedBox(height: Space.x12),
              GlassTextField(controller: accessories, label: 'Accessories left with device',
                hint: 'Cover, charger, SIM tray…', textInputAction: TextInputAction.next),
              const SizedBox(height: Space.x12),
              GlassTextField(controller: complaint, label: 'Complaint', required: true,
                keyboardType: TextInputType.multiline, hint: 'What is wrong with the phone?'),
            ])),
            SectionHeader(title: 'Money'),
            GlassCard(blur: false, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: GlassTextField(controller: estimate, label: 'Estimate (₹)',
                  keyboardType: const TextInputType.numberWithOptions(decimal: true), textInputAction: TextInputAction.next,
                  validator: (v) => _moneyValidator(v, label: 'estimate'))),
                const SizedBox(width: Space.x12),
                Expanded(child: GlassTextField(controller: charge, label: 'Service charge (₹)',
                  keyboardType: const TextInputType.numberWithOptions(decimal: true), textInputAction: TextInputAction.next,
                  helper: 'Final bill. 0 allowed for a free check-up.',
                  validator: (v) => _moneyValidator(v, label: 'service charge'))),
              ]),
              if (!_edit) ...[
                const SizedBox(height: Space.x12),
                GlassTextField(controller: advance, label: 'Advance received (₹)',
                  keyboardType: const TextInputType.numberWithOptions(decimal: true), textInputAction: TextInputAction.next,
                  prefixIcon: Icons.payments_outlined,
                  helper: 'Optional. Advance ek alag payment row banti hai — baaki balance ledger me rahega.',
                  validator: (v) => _moneyValidator(v, label: 'advance')),
              ],
              const SizedBox(height: Space.x12),
              Row(children: [
                Expanded(child: GlassTextField(controller: warranty, label: 'Warranty days',
                  keyboardType: TextInputType.number, textInputAction: TextInputAction.next,
                  validator: _warrantyValidator)),
              ]),
            ])),
            SectionHeader(title: 'Timeline'),
            GlassCard(blur: false, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _DateRow(
                label: 'Received on', value: dateOnly(DateFormat('yyyy-MM-dd').format(receivedAt)),
                enabled: !_edit, onTap: () => _pickDate(promised: false),
              ),
              const SizedBox(height: Space.x12),
              _DateRow(
                label: 'Promised delivery', value: promisedDate == null ? 'Not set' : dateOnly(DateFormat('yyyy-MM-dd').format(promisedDate!)),
                onTap: () => _pickDate(promised: true),
                trailing: promisedDate == null ? null : IconButton(
                  tooltip: 'Clear promised date',
                  onPressed: () => setState(() => promisedDate = null),
                  icon: const Icon(Icons.close, size: 18)),
              ),
            ])),
            const SizedBox(height: Space.x12),
            GlassCard(blur: false, padding: EdgeInsets.zero, child: ExpansionTile(
              initiallyExpanded: _internalOpen,
              onExpansionChanged: (v) => setState(() => _internalOpen = v),
              leading: Icon(Icons.lock_outline, color: c.textSecondary),
              title: Text('Internal — never printed', style: t.titleSmall),
              subtitle: Text('Parts cost, diagnosis and device lock stay with the shop.', style: t.bodySmall?.copyWith(color: c.textSecondary)),
              childrenPadding: const EdgeInsets.fromLTRB(Space.x16, 0, Space.x16, Space.x16),
              children: [
                Row(children: [
                  Expanded(child: GlassTextField(controller: parts, label: 'Parts cost (₹)',
                    keyboardType: const TextInputType.numberWithOptions(decimal: true), textInputAction: TextInputAction.next,
                    helper: 'Aapka kharch — profit nikalne ke liye.',
                    validator: (v) => _moneyValidator(v, label: 'parts cost'))),
                ]),
                const SizedBox(height: Space.x12),
                GlassTextField(controller: partsNote, label: 'Parts note', hint: 'Where the part came from, warranty…',
                  textInputAction: TextInputAction.next),
                const SizedBox(height: Space.x12),
                GlassTextField(controller: diagnosis, label: 'Diagnosis', keyboardType: TextInputType.multiline),
                const SizedBox(height: Space.x12),
                GlassTextField(controller: lockNote, label: 'Device lock note',
                  hint: 'PIN / pattern — customer ke saamne hi likhein',
                  helper: 'This is never printed on any customer document.', textInputAction: TextInputAction.done),
              ],
            )),
            const SizedBox(height: Space.section),
            PrimaryButton(label: _edit ? 'Save changes' : 'Create repair job', icon: Icons.check,
              phase: _phase, onPressed: _save),
          ],
        )),
        Positioned(top: 0, left: 0, right: 0, child: GlassTopBar(
          title: _edit ? 'Edit job ${widget.job!['job_no'] ?? ''}'.trim() : 'New repair job',
          scroll: _scroll, leading: const BackButton())),
      ])),
    );
  }
}

class _StockPicker extends StatelessWidget {
  final List<dynamic> stock;
  final int? value;
  final ValueChanged<int?> onChanged;
  const _StockPicker({required this.stock, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ids = stock.map((e) => int.tryParse('${(e as Map)['id']}')).whereType<int>().toSet();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.inventory_2_outlined, size: 20, color: c.brandInk),
        const SizedBox(width: Space.x8),
        Expanded(child: Text('Repairing my own stock phone?', style: context.type.titleSmall)),
      ]),
      const SizedBox(height: Space.x4),
      Text('Link the phone so its repair cost is added to the cost price — profit stays correct.',
        style: context.type.bodySmall?.copyWith(color: c.textSecondary)),
      const SizedBox(height: Space.x8),
      Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: Space.x16),
        decoration: BoxDecoration(borderRadius: Shapes.md, color: c.textPrimary.withValues(alpha: .05),
          border: Border.all(color: c.textPrimary.withValues(alpha: .10))),
        child: DropdownButtonHideUnderline(child: DropdownButton<int?>(
          value: ids.contains(value) ? value : null,
          isExpanded: true, dropdownColor: context.scheme.surface,
          style: context.type.bodyLarge?.copyWith(color: c.textPrimary),
          hint: Text('Not linked — customer device', style: context.type.bodyMedium?.copyWith(color: c.textSecondary)),
          items: [
            const DropdownMenuItem<int?>(value: null, child: Text('Not linked — customer device')),
            for (final p in stock.cast<Map>())
              DropdownMenuItem<int?>(value: int.tryParse('${p['id']}'),
                child: Text('${p['brand']} ${p['model']} · ${p['imei']}',
                  maxLines: 1, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) { Haptics.tick(); onChanged(v); },
        )),
      ),
    ]);
  }
}

class _DateRow extends StatelessWidget {
  final String label, value;
  final VoidCallback onTap;
  final bool enabled;
  final Widget? trailing;
  const _DateRow({required this.label, required this.value, required this.onTap, this.enabled = true, this.trailing});

  @override
  Widget build(BuildContext context) {
    final c = context.colors, t = context.type;
    return InkWell(
      borderRadius: Shapes.md,
      onTap: enabled ? onTap : null,
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: Space.x16),
        decoration: BoxDecoration(borderRadius: Shapes.md,
          color: c.textPrimary.withValues(alpha: enabled ? .05 : .03),
          border: Border.all(color: c.textPrimary.withValues(alpha: .10))),
        child: Row(children: [
          Icon(Icons.calendar_month_outlined, size: 20, color: c.textSecondary),
          const SizedBox(width: Space.x12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(label, style: t.labelSmall?.copyWith(color: c.textSecondary)),
            Text(value, style: t.bodyLarge?.copyWith(color: enabled ? c.textPrimary : c.textSecondary),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          ])),
          if (trailing != null) trailing!,
        ]),
      ),
    );
  }
}
