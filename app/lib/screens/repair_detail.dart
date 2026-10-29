// REPAIR DETAIL: ek job ka poora hisaab — status, payments (advance + baaki),
// customer-safe PDF, edit/delete aur "customer ka phone khareed liya → stock".
//
// Internal cheezein (parts cost, diagnosis, lock note) alag section me hain aur
// unke saath saaf likha hai ki ye kisi customer document par nahi jaati.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../api.dart';
import '../billing/pdf_actions.dart';
import '../billing/repair_document.dart';
import '../design/components/components.dart';
import '../design/design.dart';
import 'common.dart';
import 'repair_form.dart';

class RepairDetailScreen extends StatefulWidget {
  final int id;
  /// Test hook — diya to network nahi chalta.
  final Map<String, dynamic>? testJob;
  const RepairDetailScreen({super.key, required this.id, this.testJob});
  @override
  State<RepairDetailScreen> createState() => _RepairDetailScreenState();
}

class _RepairDetailScreenState extends State<RepairDetailScreen> {
  final _scroll = ScrollController();
  Map<String, dynamic>? _job;
  bool _loading = true;
  bool _actionBusy = false;
  Object? _error;

  static const _statusLabels = {
    'received': 'Received', 'repairing': 'Repairing', 'ready': 'Ready',
    'hold': 'On hold', 'delivered': 'Delivered', 'cancelled': 'Cancelled',
  };

  String get _status => '${_job?['status'] ?? 'received'}';
  bool get _closed => _status == 'delivered' || _status == 'cancelled';
  num get _due => num.tryParse('${_job?['balance_due'] ?? 0}') ?? 0;
  num get _paid => num.tryParse('${_job?['paid_amount'] ?? 0}') ?? 0;
  num get _charge => num.tryParse('${_job?['service_charge'] ?? 0}') ?? 0;

  @override
  void initState() {
    super.initState();
    if (widget.testJob != null) {
      _job = widget.testJob;
      _loading = false;
    } else {
      _load();
    }
  }

  @override
  void dispose() { _scroll.dispose(); super.dispose(); }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });
    try {
      final raw = await Api.get('/repairs/${widget.id}');
      if (!mounted) return;
      setState(() => _job = Map<String, dynamic>.from(raw as Map));
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
    if (mounted) setState(() => _loading = false);
  }

  /// Deliver karte waqt balance ho to backend 409 `balance_due` deta hai — yahan
  /// saaf confirm dikhata hai, phir `confirm_due` ke saath dobara bhejta hai.
  Future<void> _setStatus(String next, {bool confirmDue = false}) async {
    if (_actionBusy) return;
    if (supportReadOnlyBlock(context, 'changing a repair status')) return;
    setState(() => _actionBusy = true);
    try {
      await Api.post('/repairs/${widget.id}/status', {
        'status': next,
        if (confirmDue) 'confirm_due': true,
        if (next == 'delivered') 'delivered_at': dateOnly(DateTime.now().toIso8601String()),
      });
      if (!mounted) return;
      Haptics.success();
      toast(context, next == 'delivered'
          ? 'Delivered — ${_due > 0 ? '${rs(_due)} due stays in the ledger' : 'payment complete'}'
          : 'Status: ${_statusLabels[next] ?? next}');
      await _load();
    } on ApiException catch (e) {
      if (e.code == 'balance_due' && !confirmDue && mounted) {
        final ok = await showConfirmDialog(context,
          title: 'Balance pending',
          message: '${rs(_due)} is still due on this job. Deliver the phone anyway? The balance will stay in the repair ledger.',
          confirmLabel: 'Deliver with due',
          cancelLabel: 'Collect first',
          icon: Icons.account_balance_wallet_outlined);
        if (ok && mounted) {
          setState(() => _actionBusy = false);
          return _setStatus(next, confirmDue: true);
        }
      } else if (mounted) {
        toast(context, '$e', err: true);
      }
    } catch (e) {
      if (mounted) toast(context, '$e', err: true);
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _collectPayment() async {
    if (_actionBusy || _status == 'cancelled') return;
    if (supportReadOnlyBlock(context, 'collecting a repair payment')) return;
    final body = await showModalBottomSheet<Map<String, dynamic>>(
      context: context, isScrollControlled: true, showDragHandle: true,
      builder: (_) => _PaymentSheet(due: _due),
    );
    if (body == null || !mounted) return;
    setState(() => _actionBusy = true);
    try {
      await Api.post('/repairs/${widget.id}/payments', body);
      if (!mounted) return;
      Haptics.success();
      toast(context, 'Payment recorded');
      await _load();
    } catch (e) {
      if (mounted) toast(context, '$e', err: true);
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _edit() async {
    final job = _job;
    if (job == null) return;
    final saved = await SharedAxisRoute.push<bool>(context, (_) => RepairForm(job: job));
    if (saved == true && mounted) { toast(context, 'Job updated'); _load(); }
  }

  Future<void> _delete() async {
    if (supportReadOnlyBlock(context, 'deleting a repair job')) return;
    final ok = await showConfirmDialog(context,
      title: 'Delete this job?', message: 'The job sheet and any record of this device will be removed.',
      confirmLabel: 'Delete job', cancelLabel: 'Keep job', icon: Icons.delete_outline, destructive: true);
    if (!ok || !mounted) return;
    try {
      await Api.delete('/repairs/${widget.id}');
      if (!mounted) return;
      toast(context, 'Repair job deleted');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) toast(context, '$e', err: true);
    }
  }

  /// Customer ka phone shop ne khareed liya (case C): phone stock me, job band.
  Future<void> _convertToStock() async {
    if (supportReadOnlyBlock(context, 'purchasing a customer device')) return;
    final body = await showModalBottomSheet<Map<String, dynamic>>(
      context: context, isScrollControlled: true, showDragHandle: true,
      builder: (_) => _ConvertSheet(job: _job ?? const {}),
    );
    if (body == null || !mounted) return;
    setState(() => _actionBusy = true);
    try {
      await Api.post('/repairs/${widget.id}/convert-to-stock', body);
      if (!mounted) return;
      Haptics.success();
      toast(context, 'Device purchased — added to stock');
      await _load();
    } catch (e) {
      if (mounted) toast(context, '$e', err: true);
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _openPdf() async {
    if (_job == null) return;
    Haptics.tap();
    await SharedAxisRoute.push(context, (_) => RepairPdfScreen(id: widget.id));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors, t = context.type;
    final top = MediaQuery.viewPaddingOf(context).top;
    final job = _job;
    return Scaffold(
      body: AuroraBackground(child: Stack(children: [
        if (_loading)
          const Center(child: CircularProgressIndicator())
        else if (_error != null)
          Center(child: Padding(padding: const EdgeInsets.all(Space.screen),
            child: ErrorState(title: "Couldn't load this job",
              message: 'Check your internet connection and try again.', onRetry: _load)))
        else if (job != null)
          ListView(
            controller: _scroll,
            padding: EdgeInsets.fromLTRB(Space.screen, top + 64 + Space.x8, Space.screen, Space.x32),
            children: [
              _HeaderCard(job: job, statusLabel: _statusLabels[_status] ?? _status,
                tone: _tone(_status)),
              const SizedBox(height: Space.x12),
              _MoneyCard(amount: _charge, paid: _paid, due: _due, estimate: job['estimate'],
                onCollect: _closed || Api.supportReadOnly ? null : _collectPayment),
              SectionHeader(title: 'Status'),
              GlassCard(blur: false, child: _StatusActions(
                status: _status, busy: _actionBusy, readOnly: Api.supportReadOnly,
                onNext: _setStatus, onDeliver: () => _setStatus('delivered'))),
              const SizedBox(height: Space.x12),
              GlassCard(blur: false, padding: EdgeInsets.zero, onTap: _openPdf,
                child: ListTile(
                  leading: Icon(Icons.picture_as_pdf_outlined, color: c.brandInk),
                  title: Text(_status == 'delivered' ? 'Delivery receipt PDF' : 'Job sheet PDF'),
                  subtitle: Text('Customer copy · no internal cost', style: t.bodySmall?.copyWith(color: c.textSecondary)),
                  trailing: const Icon(Icons.chevron_right),
                )),
              if ((job['payments'] as List?)?.isNotEmpty == true) ...[
                SectionHeader(title: 'Payments'),
                GlassCard(blur: false, padding: const EdgeInsets.all(Space.x12), child: Column(
                  children: [
                    for (final p in (job['payments'] as List).cast<Map>())
                      Padding(padding: const EdgeInsets.symmetric(vertical: Space.x4), child: Row(children: [
                        Icon(num.tryParse('${p['amount']}')! < 0 ? Icons.undo : Icons.payments_outlined,
                          size: 18, color: num.tryParse('${p['amount']}')! < 0 ? c.errorInk : c.successInk),
                        const SizedBox(width: Space.x8),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(rs(p['amount']), style: t.titleSmall),
                          Text('${dateOnly(p['payment_date'])} · ${p['payment_mode']} · ${p['kind']}',
                            style: t.bodySmall?.copyWith(color: c.textSecondary)),
                        ])),
                      ])),
                  ],
                )),
              ],
              const SizedBox(height: Space.x12),
              _InternalCard(job: job),
              if (!_closed && !Api.supportReadOnly) ...[
                const SizedBox(height: Space.x12),
                if (_status != 'delivered')
                  _DangerAction(icon: Icons.inventory_2_outlined, label: 'Buy this device into stock',
                    note: 'Customer ne phone bech diya? Ye job band ho jayegi aur device stock me chala jayega.',
                    onTap: _convertToStock),
                const SizedBox(height: Space.x8),
                _DangerAction(icon: Icons.edit_outlined, label: 'Edit job details', onTap: _edit),
                const SizedBox(height: Space.x8),
                _DangerAction(icon: Icons.delete_outline, label: 'Delete job', destructive: true,
                  enabled: _status == 'received' && _paid == 0, onTap: _delete),
              ],
            ],
          ),
        Positioned(top: 0, left: 0, right: 0, child: GlassTopBar(
          title: '${job?['job_no'] ?? 'Repair job'}', scroll: _scroll, leading: const BackButton(),
          actions: [
            if (!Api.supportReadOnly && job != null)
              GlassIconButton(icon: Icons.edit_outlined, semanticLabel: 'Edit repair job',
                onPressed: _closed ? null : _edit),
          ])),
      ])),
    );
  }

  static ChipTone _tone(String status) => switch (status) {
        'ready' => ChipTone.success,
        'hold' => ChipTone.warning,
        'cancelled' => ChipTone.error,
        'delivered' => ChipTone.neutral,
        _ => ChipTone.brand,
      };
}

class _HeaderCard extends StatelessWidget {
  final Map<String, dynamic> job;
  final String statusLabel;
  final ChipTone tone;
  const _HeaderCard({required this.job, required this.statusLabel, required this.tone});

  @override
  Widget build(BuildContext context) {
    final c = context.colors, t = context.type;
    final device = [job['brand'], job['model']].where((e) => e != null && '$e'.trim().isNotEmpty).join(' ');
    final promised = dateOnly(job['promised_date']);
    return GlassCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text('${job['customer_name'] ?? 'Customer'}', style: t.titleLarge,
          maxLines: 1, overflow: TextOverflow.ellipsis)),
        const SizedBox(width: Space.x8),
        StatusChip(label: statusLabel.toUpperCase(), tone: tone),
      ]),
      const SizedBox(height: Space.x4),
      Text([device, if (job['color'] != null) '${job['color']}'].where((e) => '$e'.trim().isNotEmpty).join(' · '),
        style: t.bodyMedium?.copyWith(color: c.textSecondary)),
      const SizedBox(height: Space.x8),
      Wrap(spacing: Space.x12, runSpacing: Space.x4, children: [
        if (job['customer_phone'] != null && '${job['customer_phone']}'.isNotEmpty)
          IconLabel(icon: Icons.phone_outlined, label: '${job['customer_phone']}', color: c.textSecondary),
        if (job['imei'] != null && '${job['imei']}'.isNotEmpty)
          IconLabel(icon: Icons.qr_code_2_outlined, label: 'IMEI ${job['imei']}', color: c.textSecondary),
        if (promised != '—')
          IconLabel(icon: Icons.event_outlined, label: 'Promised $promised', color: c.textSecondary),
      ]),
      const SizedBox(height: Space.x12),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(Space.x12),
        decoration: BoxDecoration(color: c.brandInk.withValues(alpha: .07), borderRadius: Shapes.sm),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Complaint', style: t.labelSmall?.copyWith(color: c.textSecondary)),
          const SizedBox(height: 2),
          Text('${job['complaint'] ?? '—'}', style: t.bodyMedium),
        ]),
      ),
    ]));
  }
}

class _MoneyCard extends StatelessWidget {
  final num amount, paid, due;
  final dynamic estimate;
  final VoidCallback? onCollect;
  const _MoneyCard({required this.amount, required this.paid, required this.due, this.estimate, this.onCollect});

  @override
  Widget build(BuildContext context) {
    final c = context.colors, t = context.type;
    final clear = due <= 0;
    return GlassCard(blur: false, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Service charge', style: t.labelLarge?.copyWith(color: c.textSecondary)),
          const SizedBox(height: 2),
          Text(rs(amount), style: t.headlineSmall?.copyWith(color: c.brandInk)),
        ])),
        StatusChip(label: clear ? 'PAID' : '${rs(due)} DUE', tone: clear ? ChipTone.success : ChipTone.warning),
      ]),
      const SizedBox(height: Space.x12),
      Row(children: [
        Expanded(child: _MoneyStat(label: 'Estimate', value: rs(estimate))),
        Expanded(child: _MoneyStat(label: 'Received', value: rs(paid))),
        Expanded(child: _MoneyStat(label: 'Balance', value: rs(due), strong: true)),
      ]),
      if (onCollect != null) ...[
        const SizedBox(height: Space.x12),
        OutlinedButton.icon(
          onPressed: onCollect,
          icon: const Icon(Icons.add_card_outlined, size: 18),
          label: Text(due > 0 ? 'Collect payment' : 'Add payment / refund'),
        ),
      ],
    ]));
  }
}

class _MoneyStat extends StatelessWidget {
  final String label, value;
  final bool strong;
  const _MoneyStat({required this.label, required this.value, this.strong = false});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: context.type.labelSmall?.copyWith(color: context.colors.textSecondary)),
    const SizedBox(height: 2),
    FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
      child: Text(value, style: (strong ? context.type.titleSmall : context.type.bodyMedium)?.copyWith(
        color: strong ? context.colors.brandInk : context.colors.textPrimary))),
  ]);
}

class _StatusActions extends StatelessWidget {
  final String status;
  final bool busy, readOnly;
  final ValueChanged<String> onNext;
  final VoidCallback onDeliver;
  const _StatusActions({required this.status, required this.busy, required this.readOnly,
    required this.onNext, required this.onDeliver});

  @override
  Widget build(BuildContext context) {
    final c = context.colors, t = context.type;
    if (readOnly) {
      return Text('Support mode is read-only. The shop owner must change this job.',
        style: t.bodySmall?.copyWith(color: c.textSecondary));
    }
    if (status == 'delivered') {
      return Row(children: [
        Icon(Icons.check_circle_outline, color: c.successInk, size: 20),
        const SizedBox(width: Space.x8),
        Expanded(child: Text('Delivered — this job is closed.', style: t.bodyMedium)),
      ]);
    }
    if (status == 'cancelled') {
      return Row(children: [
        Icon(Icons.cancel_outlined, color: c.errorInk, size: 20),
        const SizedBox(width: Space.x8),
        Expanded(child: Text('Cancelled — reopen to work on it again.', style: t.bodyMedium)),
        TextButton(onPressed: busy ? null : () => onNext('received'), child: const Text('Reopen')),
      ]);
    }
    final buttons = <(String, String, IconData)>[
      if (status != 'repairing') ('repairing', 'Repairing', Icons.handyman_outlined),
      if (status != 'ready') ('ready', 'Ready', Icons.notifications_active_outlined),
      if (status != 'hold') ('hold', 'Hold', Icons.pause_circle_outline),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: Space.x8, runSpacing: Space.x8, children: [
        for (final b in buttons)
          OutlinedButton.icon(
            onPressed: busy ? null : () => onNext(b.$1),
            icon: Icon(b.$3, size: 18), label: Text(b.$2)),
      ]),
      const SizedBox(height: Space.x12),
      FilledButton.icon(
        onPressed: busy ? null : onDeliver,
        icon: const Icon(Icons.check_circle_outline, size: 18),
        label: const Text('Mark delivered'),
      ),
      const SizedBox(height: Space.x8),
      TextButton(
        onPressed: busy ? null : () => onNext('cancelled'),
        child: Text('Cancel this job', style: TextStyle(color: c.errorInk)),
      ),
    ]);
  }
}

class _InternalCard extends StatelessWidget {
  final Map<String, dynamic> job;
  const _InternalCard({required this.job});
  @override
  Widget build(BuildContext context) {
    final c = context.colors, t = context.type;
    final parts = num.tryParse('${job['parts_cost'] ?? 0}') ?? 0;
    final charge = num.tryParse('${job['service_charge'] ?? 0}') ?? 0;
    final margin = charge - parts;
    return GlassCard(blur: false, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.lock_outline, size: 18, color: c.textSecondary),
        const SizedBox(width: Space.x8),
        Expanded(child: Text('Internal — never printed', style: t.titleSmall)),
        Text(rs(margin), style: t.titleSmall?.copyWith(color: margin >= 0 ? c.successInk : c.errorInk)),
      ]),
      const SizedBox(height: Space.x8),
      Wrap(spacing: Space.x16, runSpacing: Space.x8, children: [
        _MoneyStat(label: 'Parts cost', value: rs(parts)),
        _MoneyStat(label: 'Margin', value: rs(margin)),
      ]),
      if ('${job['parts_note'] ?? ''}'.trim().isNotEmpty) ...[
        const SizedBox(height: Space.x8),
        Text('Parts: ${job['parts_note']}', style: t.bodySmall?.copyWith(color: c.textSecondary)),
      ],
      if ('${job['diagnosis'] ?? ''}'.trim().isNotEmpty) ...[
        const SizedBox(height: Space.x8),
        Text('Diagnosis: ${job['diagnosis']}', style: t.bodySmall?.copyWith(color: c.textSecondary)),
      ],
      if ('${job['device_lock_note'] ?? ''}'.trim().isNotEmpty) ...[
        const SizedBox(height: Space.x8),
        Text('Lock note: ${job['device_lock_note']}', style: t.bodySmall?.copyWith(color: c.textSecondary)),
      ],
      if (job['phone'] is Map) ...[
        const SizedBox(height: Space.x8),
        Text('Linked stock phone #${(job['phone'] as Map)['id']} · repair cost already counted in its cost price',
          style: t.bodySmall?.copyWith(color: c.textSecondary)),
      ],
    ]));
  }
}

class _DangerAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? note;
  final VoidCallback onTap;
  final bool destructive;
  final bool enabled;
  const _DangerAction({required this.icon, required this.label, this.note, required this.onTap,
    this.destructive = false, this.enabled = true});

  @override
  Widget build(BuildContext context) {
    final c = context.colors, t = context.type;
    final color = destructive ? c.errorInk : c.textPrimary;
    return Opacity(
      opacity: enabled ? 1 : .45,
      child: GlassCard(blur: false, padding: EdgeInsets.zero,
        onTap: enabled ? onTap : null,
        child: ListTile(
          leading: Icon(icon, color: color),
          title: Text(label, style: t.bodyLarge?.copyWith(color: color)),
          subtitle: note == null ? null : Text(note!, style: t.bodySmall?.copyWith(color: c.textSecondary)),
          trailing: const Icon(Icons.chevron_right),
        )),
    );
  }
}

/// Payment sheet — advance/baaki dono yahin se. Refund negative amount ke roop me
/// nahi, alag `kind` se jata hai (backend `-` laga kar row banata hai).
class _PaymentSheet extends StatefulWidget {
  final num due;
  const _PaymentSheet({required this.due});
  @override
  State<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<_PaymentSheet> {
  final _form = GlobalKey<FormState>();
  final amount = TextEditingController();
  final note = TextEditingController();
  String mode = 'cash';
  String kind = 'payment';
  DateTime date = DateTime.now();

  @override
  void initState() {
    super.initState();
    if (widget.due > 0) amount.text = widget.due == widget.due.roundToDouble() ? '${widget.due.round()}' : '${widget.due}';
  }

  @override
  void dispose() { amount.dispose(); note.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(child: Form(key: _form, child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Space.screen, 0, Space.screen, Space.x24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Record payment', style: context.type.titleLarge),
          const SizedBox(height: Space.x4),
          Text('${rs(widget.due)} due on this job', style: context.type.bodySmall?.copyWith(color: c.textSecondary)),
          const SizedBox(height: Space.x16),
          GlassTextField(controller: amount, label: 'Amount (₹)', required: true,
            prefixIcon: Icons.currency_rupee, keyboardType: const TextInputType.numberWithOptions(decimal: true),
            validator: (v) {
              final s = (v ?? '').trim();
              if (!RegExp(r'^\d{1,8}(\.\d{1,2})?$').hasMatch(s)) return 'Enter a valid amount';
              if (kind != 'refund' && num.parse(s) > widget.due) return 'More than the balance due (${rs(widget.due)})';
              return null;
            }),
          const SizedBox(height: Space.x12),
          Row(children: [
            Expanded(child: DropdownButtonFormField<String>(
              initialValue: mode, decoration: const InputDecoration(labelText: 'Mode'),
              items: const ['cash', 'upi', 'card', 'bank', 'other']
                .map((v) => DropdownMenuItem(value: v, child: Text(v.toUpperCase()))).toList(),
              onChanged: (v) => setState(() => mode = v ?? 'cash'),
            )),
            const SizedBox(width: Space.x12),
            Expanded(child: DropdownButtonFormField<String>(
              initialValue: kind, decoration: const InputDecoration(labelText: 'Type'),
              items: const ['payment', 'advance', 'refund']
                .map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
              onChanged: (v) => setState(() => kind = v ?? 'payment'),
            )),
          ]),
          const SizedBox(height: Space.x12),
          InkWell(
            borderRadius: Shapes.md,
            onTap: () async {
              final d = await showDatePicker(context: context, initialDate: date,
                firstDate: DateTime(2020), lastDate: DateTime.now());
              if (d != null) setState(() => date = d);
            },
            child: Container(constraints: const BoxConstraints(minHeight: 56),
              padding: const EdgeInsets.symmetric(horizontal: Space.x16),
              decoration: BoxDecoration(borderRadius: Shapes.md, color: c.textPrimary.withValues(alpha: .05),
                border: Border.all(color: c.textPrimary.withValues(alpha: .10))),
              child: Row(children: [
                Icon(Icons.calendar_month_outlined, size: 20, color: c.textSecondary),
                const SizedBox(width: Space.x12),
                Text(dateOnly(date.toIso8601String()), style: context.type.bodyLarge),
              ])),
          ),
          const SizedBox(height: Space.x12),
          GlassTextField(controller: note, label: 'Note (optional)', textInputAction: TextInputAction.done),
          const SizedBox(height: Space.x16),
          PrimaryButton(label: 'Save payment', icon: Icons.check, onPressed: () {
            if (!_form.currentState!.validate()) return;
            Navigator.pop(context, {
              'amount': amount.text.trim(),
              'payment_mode': mode,
              'kind': kind,
              'payment_date': dateOnly(date.toIso8601String()),
              'note': note.text.trim(),
            });
          }),
        ]),
      ))),
    );
  }
}

/// "Buy this device into stock" — customer ka phone shop khareed le to poore
/// buy-form ki zaroorat nahi: price, date aur condition kaafi hai. Customer
/// details job se hi chali jaati hain (ledger me wahi dikhega jo Buy me dikhta).
class _ConvertSheet extends StatefulWidget {
  final Map<String, dynamic> job;
  const _ConvertSheet({required this.job});
  @override
  State<_ConvertSheet> createState() => _ConvertSheetState();
}

class _ConvertSheetState extends State<_ConvertSheet> {
  final _form = GlobalKey<FormState>();
  final price = TextEditingController(), ram = TextEditingController(), storage = TextEditingController();
  String condition = 'Good';
  DateTime date = DateTime.now();

  @override
  void dispose() { price.dispose(); ram.dispose(); storage.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(child: Form(key: _form, child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Space.screen, 0, Space.screen, Space.x24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Buy this device', style: context.type.titleLarge),
          const SizedBox(height: Space.x4),
          Text('Device stock me chala jayega aur job band ho jayegi. Customer: ${widget.job['customer_name'] ?? '—'}',
            style: context.type.bodySmall?.copyWith(color: c.textSecondary)),
          const SizedBox(height: Space.x16),
          GlassTextField(controller: price, label: 'Buy price (₹)', required: true,
            prefixIcon: Icons.currency_rupee, keyboardType: const TextInputType.numberWithOptions(decimal: true),
            validator: (v) => RegExp(r'^\d{1,8}(\.\d{1,2})?$').hasMatch((v ?? '').trim())
              && num.parse(v!.trim()) > 0 ? null : 'Enter a valid buy price'),
          const SizedBox(height: Space.x12),
          Row(children: [
            Expanded(child: GlassTextField(controller: ram, label: 'RAM (optional)', textInputAction: TextInputAction.next)),
            const SizedBox(width: Space.x12),
            Expanded(child: GlassTextField(controller: storage, label: 'Storage (optional)', textInputAction: TextInputAction.next)),
          ]),
          const SizedBox(height: Space.x12),
          DropdownButtonFormField<String>(
            initialValue: condition, decoration: const InputDecoration(labelText: 'Condition'),
            items: const ['Excellent', 'Good', 'Fair', 'Faulty']
              .map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
            onChanged: (v) => setState(() => condition = v ?? 'Good'),
          ),
          const SizedBox(height: Space.x12),
          InkWell(
            borderRadius: Shapes.md,
            onTap: () async {
              final d = await showDatePicker(context: context, initialDate: date,
                firstDate: DateTime(2020), lastDate: DateTime.now());
              if (d != null) setState(() => date = d);
            },
            child: Container(constraints: const BoxConstraints(minHeight: 56),
              padding: const EdgeInsets.symmetric(horizontal: Space.x16),
              decoration: BoxDecoration(borderRadius: Shapes.md, color: c.textPrimary.withValues(alpha: .05),
                border: Border.all(color: c.textPrimary.withValues(alpha: .10))),
              child: Row(children: [
                Icon(Icons.calendar_month_outlined, size: 20, color: c.textSecondary),
                const SizedBox(width: Space.x12),
                Text(dateOnly(date.toIso8601String()), style: context.type.bodyLarge),
              ])),
          ),
          const SizedBox(height: Space.x16),
          PrimaryButton(label: 'Add to stock', icon: Icons.inventory_2_outlined, onPressed: () {
            if (!_form.currentState!.validate()) return;
            Navigator.pop(context, {
              'buy_price': price.text.trim(),
              'buy_date': dateOnly(date.toIso8601String()),
              'condition': condition,
              'ram': ram.text.trim(),
              'storage': storage.text.trim(),
            });
          }),
        ]),
      ))),
    );
  }
}

/// Repair PDF screen — job sheet / delivery receipt ko preview, save aur share.
class RepairPdfScreen extends StatefulWidget {
  final int id;
  final Map<String, dynamic>? testData;
  const RepairPdfScreen({super.key, required this.id, this.testData});
  @override
  State<RepairPdfScreen> createState() => _RepairPdfScreenState();
}

class _RepairPdfScreenState extends State<RepairPdfScreen> {
  Map<String, dynamic>? _data;
  Uint8List? _pdf;
  Object? _error;
  bool _busy = false;

  String get _fileName {
    final raw = '${_data?['number'] ?? 'repair-${widget.id}'}';
    return '${raw.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}.pdf';
  }

  bool get _delivery => _data?['type'] == 'delivery';
  String get _title => _delivery ? 'Delivery receipt' : 'Job sheet';

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() { _error = null; _data = null; _pdf = null; });
    try {
      final raw = widget.testData ?? await Api.get('/repairs/${widget.id}/job-sheet');
      final data = Map<String, dynamic>.from(raw as Map);
      final bytes = await RepairDocument.build(data);
      if (!mounted) return;
      setState(() { _data = data; _pdf = bytes; });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  String get _caption {
    final shop = _data?['shop'] as Map? ?? const {};
    return '${_title} ${_data?['number'] ?? ''} · ${shop['name'] ?? 'Vktrix Mobile'} · ${rs(_data?['amount'])}';
  }

  Future<void> _save() async {
    if (_pdf == null || _busy) return;
    setState(() => _busy = true);
    try {
      final result = await PdfActions.savePdf(_pdf!, _fileName);
      if (mounted && result != 'cancelled') toast(context, result == 'shared' ? 'Choose a save location' : 'PDF saved');
    } catch (e) {
      if (mounted) toast(context, 'Could not save the PDF: $e', err: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share({required bool whatsapp}) async {
    if (_pdf == null || _busy) return;
    setState(() => _busy = true);
    try {
      final result = await PdfActions.sharePdf(_pdf!, _fileName, whatsapp: whatsapp, caption: _caption);
      if (!mounted) return;
      if (result == 'whatsapp_not_installed') {
        final fallback = await showConfirmDialog(context,
          title: 'WhatsApp is not available',
          message: 'Would you like to share the PDF using another app?',
          confirmLabel: 'Share PDF', cancelLabel: 'Cancel', icon: Icons.share_outlined);
        if (fallback) await PdfActions.sharePdf(_pdf!, _fileName, whatsapp: false, caption: _caption);
      }
    } catch (e) {
      if (mounted) toast(context, 'Could not share: $e', err: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors, t = context.type;
    final top = MediaQuery.viewPaddingOf(context).top;
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    return Scaffold(
      body: AuroraBackground(child: Stack(children: [
        Positioned.fill(child: Padding(
          padding: EdgeInsets.fromLTRB(Space.screen, top + 64 + Space.x8, Space.screen, bottom + Space.x16),
          child: _error != null
            ? Center(child: ErrorState(title: "Couldn't build the PDF",
                message: 'Check your internet connection and try again.', onRetry: _load))
            : _pdf == null || _data == null
              ? const Center(child: CircularProgressIndicator())
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  GlassCard(padding: const EdgeInsets.all(Space.x16), child: Row(children: [
                    Container(width: 48, height: 48,
                      decoration: BoxDecoration(color: context.scheme.primary.withValues(alpha: .12), borderRadius: Shapes.md),
                      child: Icon(_delivery ? Icons.verified_outlined : Icons.build_outlined, color: c.brandInk, size: 24)),
                    const SizedBox(width: Space.x12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('$_title ready', style: t.titleMedium),
                      const SizedBox(height: 2),
                      Text('${_data!['number']} · ${rs(_data!['amount'])}',
                        style: t.bodySmall?.copyWith(color: c.textSecondary)),
                    ])),
                    StatusChip(label: num.tryParse('${_data!['balance_due'] ?? 0}')! > 0 ? 'DUE' : 'PAID',
                      tone: num.tryParse('${_data!['balance_due'] ?? 0}')! > 0 ? ChipTone.warning : ChipTone.success),
                  ])),
                  const SizedBox(height: Space.x12),
                  Expanded(child: GlassCard(blur: false, padding: EdgeInsets.zero,
                    child: ClipRRect(borderRadius: Shapes.lg, child: PdfPreview(
                      build: (_) async => _pdf!,
                      initialPageFormat: PdfPageFormat.a4,
                      pdfFileName: _fileName,
                      useActions: false, allowPrinting: false, allowSharing: false,
                      canChangeOrientation: false, canChangePageFormat: false, canDebug: false,
                      dynamicLayout: false, maxPageWidth: 420, padding: const EdgeInsets.all(8),
                      scrollViewDecoration: BoxDecoration(color: c.textPrimary.withValues(alpha: .05)),
                      loadingWidget: const Center(child: CircularProgressIndicator()),
                    )))),
                  const SizedBox(height: Space.x12),
                  if (_busy) const LinearProgressIndicator(minHeight: 2),
                  if (_busy) const SizedBox(height: Space.x8),
                  LayoutBuilder(builder: (context, box) {
                    final width = (box.maxWidth - Space.x8) / 2;
                    return Wrap(spacing: Space.x8, runSpacing: Space.x8, children: [
                      SizedBox(width: width, child: OutlinedButton.icon(onPressed: _save,
                        icon: const Icon(Icons.download_outlined, size: 18), label: const Text('Save PDF'))),
                      SizedBox(width: width, child: FilledButton.icon(onPressed: () => _share(whatsapp: true),
                        icon: const Icon(Icons.chat_outlined, size: 18), label: const Text('WhatsApp'))),
                      SizedBox(width: width, child: OutlinedButton.icon(onPressed: () => _share(whatsapp: false),
                        icon: const Icon(Icons.share_outlined, size: 18), label: const Text('Other apps'))),
                    ]);
                  }),
                ]),
        )),
        Positioned(top: 0, left: 0, right: 0, child: GlassTopBar(title: _title, leading: const BackButton())),
      ])),
    );
  }
}
