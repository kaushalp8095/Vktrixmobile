import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api.dart';
import '../billing/pdf_actions.dart';
import '../design/components/components.dart';
import '../design/design.dart';
import 'common.dart';
import 'receipt.dart';

class LedgerScreen extends StatefulWidget {
  final Map<String, dynamic>? testData;
  const LedgerScreen({super.key, this.testData});

  @override
  State<LedgerScreen> createState() => _LedgerScreenState();
}

class _LedgerScreenState extends State<LedgerScreen> {
  Map<String, dynamic>? _data;
  Object? _error;
  String _status = 'pending';
  final _search = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    if (widget.testData != null) _data = widget.testData;
    else _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final raw = await Api.get('/ledger', {'status': _status, 'search': _search.text.trim()});
      if (mounted) setState(() => _data = Map<String, dynamic>.from(raw as Map));
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _searchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _load);
  }

  Future<void> _open(Map item) async {
    await SharedAxisRoute.push(context, (_) => LedgerDetailScreen(saleId: int.parse('${item['id']}')));
    if (mounted && widget.testData == null) _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors, t = context.type;
    final top = MediaQuery.viewPaddingOf(context).top;
    final data = _data;
    final summary = data?['summary'] as Map? ?? const {};
    final items = (data?['items'] as List?) ?? const [];
    return Scaffold(
      body: AuroraBackground(child: Stack(children: [
        RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(Space.screen, top + 64 + Space.x8, Space.screen, Space.x32),
            children: [
              _LedgerHero(summary: summary),
              const SizedBox(height: Space.x16),
              GlassTextField(controller: _search, label: 'Customer, mobile, model or IMEI',
                prefixIcon: Icons.search, onChanged: _searchChanged),
              const SizedBox(height: Space.x12),
              Wrap(spacing: Space.x8, children: [
                _FilterChip(label: 'Pending', selected: _status == 'pending', onTap: () => _setStatus('pending')),
                _FilterChip(label: 'Paid', selected: _status == 'paid', onTap: () => _setStatus('paid')),
                _FilterChip(label: 'All', selected: _status == 'all', onTap: () => _setStatus('all')),
              ]),
              const SizedBox(height: Space.section),
              SectionHeader(title: _status == 'pending' ? 'Payment pending' : _status == 'paid' ? 'Completed' : 'All sales'),
              const SizedBox(height: Space.x12),
              if (_error != null)
                ErrorState(title: "Couldn't load payment ledger", message: 'Internet check karke pull to retry karein.', onRetry: _load)
              else if (data == null)
                GlassCard(blur: false, child: Shimmer(child: Column(children: List.generate(4, (_) => const SkeletonListTile()))))
              else if (items.isEmpty)
                GlassCard(blur: false, child: EmptyState(
                  icon: _status == 'pending' ? Icons.verified_outlined : Icons.receipt_long_outlined,
                  title: _status == 'pending' ? 'No pending payments' : 'No payments here',
                  message: _status == 'pending'
                    ? 'Sab customer payments clear hain. Partial ya udhaar sale yahan automatically dikhegi.'
                    : 'Filter badal kar dusri entries dekhein.',
                ))
              else
                GlassCard(blur: false, padding: EdgeInsets.zero, child: Column(children: [
                  for (var i = 0; i < items.length; i++) ...[
                    if (i > 0) Divider(height: 1, indent: 68, color: c.textPrimary.withValues(alpha: .08)),
                    _LedgerRow(item: items[i] as Map, onTap: () => _open(items[i] as Map)),
                  ],
                ])),
              if (items.isNotEmpty) ...[
                const SizedBox(height: Space.x12),
                Text('Sale kholkar partial payment add karein, history dekhein ya WhatsApp reminder bhejein.',
                  style: t.bodySmall?.copyWith(color: c.textSecondary), textAlign: TextAlign.center),
              ],
            ],
          ),
        ),
        Positioned(top: 0, left: 0, right: 0, child: GlassTopBar(title: 'Udhaar ledger', scroll: _scroll,
          actions: [GlassIconButton(icon: Icons.refresh, semanticLabel: 'Refresh ledger', onPressed: _load)])),
      ])),
    );
  }

  void _setStatus(String value) {
    if (_status == value) return;
    Haptics.tick();
    setState(() { _status = value; _data = null; });
    if (widget.testData == null) _load();
  }
}

class _LedgerHero extends StatelessWidget {
  final Map summary;
  const _LedgerHero({required this.summary});

  @override
  Widget build(BuildContext context) {
    final c = context.colors, t = context.type;
    return GlassCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(width: 44, height: 44,
          decoration: BoxDecoration(color: c.warning.withValues(alpha: .13), borderRadius: Shapes.md),
          child: Icon(Icons.account_balance_wallet_outlined, color: c.warningInk)),
        const SizedBox(width: Space.x12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Total payment baki', style: t.labelLarge?.copyWith(color: c.textSecondary)),
          Text(rs(summary['outstanding']), style: t.headlineMedium?.copyWith(color: c.warningInk)),
        ])),
        StatusChip(label: '${summary['pending_count'] ?? 0} pending', tone: ChipTone.warning),
      ]),
      const SizedBox(height: Space.x16),
      Row(children: [
        Expanded(child: _HeroStat(label: 'Received', value: rs(summary['received']))),
        Container(width: 1, height: 30, color: c.textPrimary.withValues(alpha: .10)),
        const SizedBox(width: Space.x16),
        Expanded(child: _HeroStat(label: 'Sales total', value: rs(summary['sales_total']))),
      ]),
    ]));
  }
}

class _HeroStat extends StatelessWidget {
  final String label, value;
  const _HeroStat({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: context.type.labelSmall?.copyWith(color: context.colors.textSecondary)),
    const SizedBox(height: 2),
    Text(value, style: context.type.titleSmall),
  ]);
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => ChoiceChip(
    label: Text(label), selected: selected, onSelected: (_) => onTap(),
    avatar: selected ? const Icon(Icons.check, size: 16) : null,
  );
}

class _LedgerRow extends StatelessWidget {
  final Map item;
  final VoidCallback onTap;
  const _LedgerRow({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors, t = context.type;
    final total = num.tryParse('${item['sell_price']}') ?? 0;
    final paid = num.tryParse('${item['paid_amount']}') ?? 0;
    final due = num.tryParse('${item['balance_due']}') ?? 0;
    final progress = total <= 0 ? 0.0 : (paid / total).clamp(0, 1).toDouble();
    final paidOff = due <= 0;
    final name = '${item['customer_name'] ?? ''}'.trim();
    return Semantics(
      button: true,
      label: '${item['brand']} ${item['model']}, ${rs(due)} payment due',
      child: InkWell(onTap: onTap, child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.x16, vertical: Space.x12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: 44, height: 44,
            decoration: BoxDecoration(color: (paidOff ? c.success : c.warning).withValues(alpha: .12), borderRadius: Shapes.md),
            child: Icon(paidOff ? Icons.check_rounded : Icons.schedule_rounded,
              color: paidOff ? c.successInk : c.warningInk, size: 22)),
          const SizedBox(width: Space.x12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name.isEmpty ? 'Walk-in customer' : name, style: t.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text('${item['brand']} ${item['model']} · ${item['sell_date']}',
              style: t.bodySmall?.copyWith(color: c.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: Space.x8),
            ClipRRect(borderRadius: Shapes.pill, child: LinearProgressIndicator(
              minHeight: 5, value: progress,
              backgroundColor: c.textPrimary.withValues(alpha: .08),
              color: paidOff ? c.success : c.warning,
            )),
            const SizedBox(height: 4),
            Text('${rs(paid)} received of ${rs(total)}', style: t.labelSmall?.copyWith(color: c.textSecondary)),
          ])),
          const SizedBox(width: Space.x12),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(paidOff ? 'Paid' : rs(due), style: t.titleSmall?.copyWith(color: paidOff ? c.successInk : c.warningInk)),
            Text(paidOff ? 'complete' : 'due', style: t.labelSmall?.copyWith(color: c.textSecondary)),
            const SizedBox(height: Space.x8),
            Icon(Icons.chevron_right, size: 20, color: c.textSecondary),
          ]),
        ]),
      )),
    );
  }
}

class LedgerDetailScreen extends StatefulWidget {
  final int saleId;
  final Map<String, dynamic>? testData;
  const LedgerDetailScreen({super.key, required this.saleId, this.testData});

  @override
  State<LedgerDetailScreen> createState() => _LedgerDetailScreenState();
}

class _LedgerDetailScreenState extends State<LedgerDetailScreen> {
  Map<String, dynamic>? _data;
  Object? _error;
  bool _busy = false;
  final _scroll = ScrollController();

  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { _scroll.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final raw = widget.testData ?? await Api.get('/sales/${widget.saleId}/payments');
      if (mounted) setState(() => _data = Map<String, dynamic>.from(raw as Map));
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _addPayment() async {
    final sale = _data?['sale'] as Map?;
    if (sale == null || _busy) return;
    final body = await showModalBottomSheet<Map<String, dynamic>>(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => _AddPaymentSheet(sale: sale),
    );
    if (body == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await Api.post('/sales/${widget.saleId}/payments', body);
      if (!mounted) return;
      Haptics.success();
      toast(context, 'Payment added — balance updated');
      await _load();
    } catch (e) {
      if (mounted) toast(context, '$e', err: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _reminderText() {
    final data = _data ?? const {};
    final sale = data['sale'] as Map? ?? const {};
    final shop = data['shop'] as Map? ?? const {};
    final customer = '${sale['customer_name'] ?? ''}'.trim();
    final device = '${sale['brand'] ?? ''} ${sale['model'] ?? ''}'.trim();
    return [
      'Namaste${customer.isEmpty ? '' : ' $customer'},',
      '',
      '${shop['name'] ?? 'Mobile shop'} se payment reminder:',
      'Bill: ${sale['number'] ?? ''}',
      if (device.isNotEmpty) 'Phone: $device',
      'IMEI: ${sale['imei'] ?? ''}',
      'Total: ${rs(sale['sell_price'])}',
      'Received: ${rs(sale['paid_amount'])}',
      'Balance due: ${rs(sale['balance_due'])}',
      '',
      'Kripya baki payment clear kar dein. Payment kar chuke hain to is message ko ignore karein.',
      if ('${shop['phone'] ?? ''}'.trim().isNotEmpty) 'Contact: ${shop['phone']}',
      '— ${shop['name'] ?? 'Thank you'}',
    ].join('\n');
  }

  Future<void> _shareReminder() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      var result = await PdfActions.shareReminder(_reminderText());
      if (!mounted) return;
      if (result == 'whatsapp_not_installed' || result == 'unsupported') {
        result = await PdfActions.shareReminder(_reminderText(), whatsapp: false);
        if (result == 'unsupported' && mounted) toast(context, 'Reminder sharing is available on the Android app.', err: true);
      }
    } catch (e) {
      if (mounted) toast(context, 'Reminder share nahi hua: $e', err: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors, t = context.type;
    final top = MediaQuery.viewPaddingOf(context).top;
    final data = _data;
    final sale = data?['sale'] as Map?;
    final payments = (data?['payments'] as List?) ?? const [];
    final due = num.tryParse('${sale?['balance_due']}') ?? 0;
    final total = num.tryParse('${sale?['sell_price']}') ?? 0;
    final paid = num.tryParse('${sale?['paid_amount']}') ?? 0;
    final progress = total <= 0 ? 0.0 : (paid / total).clamp(0, 1).toDouble();
    return Scaffold(
      body: AuroraBackground(child: Stack(children: [
        ListView(
          controller: _scroll,
          padding: EdgeInsets.fromLTRB(Space.screen, top + 64 + Space.x8, Space.screen, Space.x32),
          children: [
            if (_error != null)
              ErrorState(title: "Couldn't load payment history", message: 'Please retry.', onRetry: _load)
            else if (sale == null)
              const Padding(padding: EdgeInsets.all(Space.x48), child: Center(child: CircularProgressIndicator()))
            else ...[
              GlassCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(width: 48, height: 48,
                    decoration: BoxDecoration(color: (due > 0 ? c.warning : c.success).withValues(alpha: .12), borderRadius: Shapes.md),
                    child: Icon(due > 0 ? Icons.account_balance_wallet_outlined : Icons.verified_outlined,
                      color: due > 0 ? c.warningInk : c.successInk)),
                  const SizedBox(width: Space.x12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(due > 0 ? 'Balance remaining' : 'Payment complete', style: t.labelLarge?.copyWith(color: c.textSecondary)),
                    Text(rs(due), style: t.headlineMedium?.copyWith(color: due > 0 ? c.warningInk : c.successInk)),
                  ])),
                  StatusChip(label: '${sale['number']}', tone: due > 0 ? ChipTone.warning : ChipTone.success),
                ]),
                const SizedBox(height: Space.x16),
                ClipRRect(borderRadius: Shapes.pill, child: LinearProgressIndicator(
                  minHeight: 8, value: progress,
                  backgroundColor: c.textPrimary.withValues(alpha: .08), color: due > 0 ? c.warning : c.success)),
                const SizedBox(height: Space.x8),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('${rs(paid)} received', style: t.bodySmall?.copyWith(color: c.textSecondary)),
                  Text('${rs(total)} total', style: t.bodySmall?.copyWith(color: c.textSecondary)),
                ]),
              ])),
              const SizedBox(height: Space.x16),
              GlassCard(blur: false, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${sale['customer_name'] ?? 'Walk-in customer'}', style: t.titleMedium),
                const SizedBox(height: 2),
                Text('${sale['brand']} ${sale['model']} · IMEI ${sale['imei']}',
                  style: t.bodySmall?.copyWith(color: c.textSecondary)),
                if ('${sale['customer_phone'] ?? ''}'.trim().isNotEmpty) ...[
                  const SizedBox(height: Space.x8),
                  Row(children: [Icon(Icons.phone_outlined, size: 17, color: c.textSecondary), const SizedBox(width: Space.x8),
                    SelectableText('${sale['customer_phone']}', style: t.bodyMedium)]),
                ],
              ])),
              const SizedBox(height: Space.x16),
              if (_busy) const LinearProgressIndicator(minHeight: 2),
              if (_busy) const SizedBox(height: Space.x8),
              if (due > 0) PrimaryButton(label: 'Add partial payment', icon: Icons.add_card_outlined,
                onPressed: _busy ? null : _addPayment),
              if (due > 0) const SizedBox(height: Space.x8),
              Row(children: [
                Expanded(child: OutlinedButton.icon(onPressed: _busy ? null : _shareReminder,
                  icon: const Icon(Icons.chat_outlined), label: const Text('Reminder'))),
                const SizedBox(width: Space.x8),
                Expanded(child: OutlinedButton.icon(
                  onPressed: () => SharedAxisRoute.push(context, (_) => ReceiptScreen(type: 'sale', id: widget.saleId)),
                  icon: const Icon(Icons.picture_as_pdf_outlined), label: const Text('PDF bill'))),
              ]),
              const SizedBox(height: Space.section),
              SectionHeader(title: 'Payment history'),
              const SizedBox(height: Space.x12),
              if (payments.isEmpty)
                const GlassCard(blur: false, child: EmptyState(icon: Icons.history, title: 'No payment received yet',
                  message: 'Add the first payment when the customer pays.'))
              else
                GlassCard(blur: false, padding: EdgeInsets.zero, child: Column(children: [
                  for (var i = 0; i < payments.length; i++) ...[
                    if (i > 0) Divider(height: 1, indent: 68, color: c.textPrimary.withValues(alpha: .08)),
                    _PaymentRow(payment: payments[i] as Map, first: i == 0),
                  ],
                ])),
            ],
          ],
        ),
        Positioned(top: 0, left: 0, right: 0, child: GlassTopBar(title: 'Payment details', scroll: _scroll)),
      ])),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  final Map payment;
  final bool first;
  const _PaymentRow({required this.payment, required this.first});
  @override
  Widget build(BuildContext context) {
    final c = context.colors, t = context.type;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.x16, vertical: Space.x12),
      child: Row(children: [
        Container(width: 40, height: 40,
          decoration: BoxDecoration(color: c.success.withValues(alpha: .12), borderRadius: Shapes.md),
          child: Icon(first ? Icons.check_circle_outline : Icons.payments_outlined, size: 20, color: c.successInk)),
        const SizedBox(width: Space.x12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${payment['payment_mode'] ?? 'cash'}'.toUpperCase(), style: t.titleSmall),
          Text('${payment['payment_date']}${'${payment['note'] ?? ''}'.trim().isEmpty ? '' : ' · ${payment['note']}'}',
            style: t.bodySmall?.copyWith(color: c.textSecondary), maxLines: 2, overflow: TextOverflow.ellipsis),
        ])),
        Text(rs(payment['amount']), style: t.titleSmall?.copyWith(color: c.successInk)),
      ]),
    );
  }
}

class _AddPaymentSheet extends StatefulWidget {
  final Map sale;
  const _AddPaymentSheet({required this.sale});
  @override
  State<_AddPaymentSheet> createState() => _AddPaymentSheetState();
}

class _AddPaymentSheetState extends State<_AddPaymentSheet> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _amount;
  final _note = TextEditingController();
  DateTime _date = DateTime.now();
  String _mode = 'Cash';

  num get _due => num.tryParse('${widget.sale['balance_due']}') ?? 0;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(text: _due.toStringAsFixed(_due % 1 == 0 ? 0 : 2));
  }

  @override
  void dispose() { _amount.dispose(); _note.dispose(); super.dispose(); }

  void _done() {
    if (!_form.currentState!.validate()) return;
    final code = switch (_mode) { 'UPI' => 'upi', 'Card' => 'card', 'Bank' => 'bank', 'Other' => 'other', _ => 'cash' };
    Navigator.pop(context, <String, dynamic>{
      'amount': _amount.text,
      'payment_date': DateFormat('yyyy-MM-dd').format(_date),
      'payment_mode': code,
      'note': _note.text,
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors, t = context.type;
    final sellDate = DateTime.tryParse('${widget.sale['sell_date']}') ?? DateTime(2020);
    final first = sellDate.isAfter(DateTime.now()) ? DateTime.now() : sellDate;
    return Padding(
      padding: EdgeInsets.fromLTRB(Space.x16, 0, Space.x16, MediaQuery.viewInsetsOf(context).bottom + MediaQuery.viewPaddingOf(context).bottom + Space.x16),
      child: GlassSurface(child: SafeArea(top: false, child: SingleChildScrollView(
        padding: const EdgeInsets.all(Space.x20),
        child: Form(key: _form, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(child: Container(width: 36, height: 4,
            decoration: BoxDecoration(color: c.textPrimary.withValues(alpha: .20), borderRadius: Shapes.pill))),
          const SizedBox(height: Space.x16),
          Text('Add payment', style: t.headlineSmall),
          Text('${rs(_due)} balance remaining', style: t.bodyMedium?.copyWith(color: c.textSecondary)),
          const SizedBox(height: Space.x20),
          GlassTextField(controller: _amount, label: 'Amount received (₹)', required: true,
            prefixIcon: Icons.currency_rupee, keyboardType: const TextInputType.numberWithOptions(decimal: true),
            validator: (v) {
              final n = num.tryParse(v ?? '');
              if (n == null || n <= 0) return 'Enter a valid amount';
              if (n > _due) return 'Maximum balance is ${rs(_due)}';
              return null;
            }),
          const SizedBox(height: Space.x12),
          DropdownButtonFormField<String>(
            initialValue: _mode,
            decoration: const InputDecoration(labelText: 'Payment mode'),
            items: const ['Cash', 'UPI', 'Card', 'Bank', 'Other']
              .map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
            onChanged: (v) => setState(() => _mode = v ?? _mode),
          ),
          const SizedBox(height: Space.x12),
          InkWell(
            borderRadius: Shapes.md,
            onTap: () async {
              final picked = await showDatePicker(context: context, initialDate: _date.isBefore(first) ? first : _date,
                firstDate: first, lastDate: DateTime.now());
              if (picked != null) setState(() => _date = picked);
            },
            child: Container(constraints: const BoxConstraints(minHeight: 56), padding: const EdgeInsets.symmetric(horizontal: Space.x16, vertical: Space.x12),
              decoration: BoxDecoration(borderRadius: Shapes.md, color: c.textPrimary.withValues(alpha: .05),
                border: Border.all(color: c.textPrimary.withValues(alpha: .10))),
              child: Row(children: [Icon(Icons.calendar_month_outlined, color: c.textSecondary), const SizedBox(width: Space.x12),
                Expanded(child: Text(DateFormat('d MMMM yyyy').format(_date))), Text('Change', style: t.labelLarge?.copyWith(color: c.brandInk))])),
          ),
          const SizedBox(height: Space.x12),
          GlassTextField(controller: _note, label: 'Note (optional)', textInputAction: TextInputAction.done),
          const SizedBox(height: Space.x20),
          PrimaryButton(label: 'Save payment', icon: Icons.check, onPressed: _done),
        ])),
      ))),
    );
  }
}
