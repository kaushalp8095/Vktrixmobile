import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../api.dart';
import '../billing/pdf_actions.dart';
import '../billing/receipt_document.dart';
import '../design/components/components.dart';
import '../design/design.dart';
import 'common.dart';

class ReceiptScreen extends StatefulWidget {
  final String type; // sale | purchase
  final int id;
  final Map<String, dynamic>? testData;
  const ReceiptScreen({super.key, required this.type, required this.id, this.testData});

  @override
  State<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends State<ReceiptScreen> {
  Map<String, dynamic>? _data;
  Uint8List? _pdf;
  Object? _error;
  bool _actionBusy = false;
  final _scroll = ScrollController();

  bool get _sale => widget.type == 'sale';
  String get _fileName {
    final raw = '${_data?['number'] ?? '${widget.type}-${widget.id}'}';
    return '${raw.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}.pdf';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() { _scroll.dispose(); super.dispose(); }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() { _error = null; _data = null; _pdf = null; });
    try {
      final raw = widget.testData ?? await Api.get('/receipts/${widget.type}/${widget.id}');
      final data = Map<String, dynamic>.from(raw as Map);
      final bytes = await ReceiptDocument.build(data);
      if (!mounted) return;
      setState(() { _data = data; _pdf = bytes; });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  String get _caption {
    final shop = _data?['shop'] as Map? ?? const {};
    final kind = _sale ? 'Sale invoice' : 'Purchase receipt';
    return '$kind ${_data?['number'] ?? ''} · ${shop['name'] ?? 'Vktrix Mobile'} · ${rs(_data?['amount'])}';
  }

  Future<void> _save() async {
    if (_pdf == null || _actionBusy) return;
    setState(() => _actionBusy = true);
    try {
      final result = await PdfActions.savePdf(_pdf!, _fileName);
      if (mounted && result != 'cancelled') {
        toast(context, result == 'shared' ? 'Choose a save location' : 'PDF saved');
      }
    } catch (e) {
      if (mounted) toast(context, 'Could not save the PDF: $e', err: true);
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _share({required bool whatsapp}) async {
    if (_pdf == null || _actionBusy) return;
    setState(() => _actionBusy = true);
    try {
      final result = await PdfActions.sharePdf(_pdf!, _fileName, whatsapp: whatsapp, caption: _caption);
      if (!mounted) return;
      if (result == 'whatsapp_not_installed') {
        final fallback = await showConfirmDialog(context,
          title: 'WhatsApp is not available',
          message: 'Would you like to share the PDF using another app?',
          confirmLabel: 'Share PDF',
          cancelLabel: 'Cancel',
          icon: Icons.share_outlined);
        if (fallback) {
          await PdfActions.sharePdf(_pdf!, _fileName, whatsapp: false, caption: _caption);
        }
      }
    } catch (e) {
      if (mounted) toast(context, 'Could not share: $e', err: true);
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  void _view() {
    if (_pdf == null) return;
    SharedAxisRoute.push(context, (_) => _FullPdfView(bytes: _pdf!, fileName: _fileName,
      title: _sale ? 'Sale invoice' : 'Purchase receipt'));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors, t = context.type;
    final top = MediaQuery.viewPaddingOf(context).top;
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    return Scaffold(
      body: AuroraBackground(child: Stack(children: [
        Positioned.fill(
          child: Padding(
            padding: EdgeInsets.fromLTRB(Space.screen, top + 64 + Space.x8, Space.screen, bottom + Space.x16),
            child: _error != null
              ? Center(child: ErrorState(title: "Couldn't build PDF bill",
                  message: 'Check your internet connection and try again.', onRetry: _load))
              : _pdf == null || _data == null
                ? const Center(child: CircularProgressIndicator())
                : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    GlassCard(
                      padding: const EdgeInsets.all(Space.x16),
                      child: Row(children: [
                        Container(width: 48, height: 48,
                          decoration: BoxDecoration(color: context.scheme.primary.withValues(alpha: .12), borderRadius: Shapes.md),
                          child: Icon(_sale ? Icons.receipt_long_outlined : Icons.shopping_bag_outlined,
                            color: c.brandInk, size: 24)),
                        const SizedBox(width: Space.x12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(_sale ? 'Sale invoice ready' : 'Purchase receipt ready', style: t.titleMedium),
                          const SizedBox(height: 2),
                          Text('${_data!['number']} · ${rs(_data!['amount'])}',
                            style: t.bodySmall?.copyWith(color: c.textSecondary)),
                        ])),
                        StatusChip(
                          label: _sale
                            ? ((_data!['payment_status'] ?? 'paid') == 'paid' ? 'Paid' : '${rs(_data!['balance_due'])} due')
                            : 'Saved',
                          tone: !_sale || (_data!['payment_status'] ?? 'paid') == 'paid' ? ChipTone.success : ChipTone.warning,
                        ),
                      ]),
                    ),
                    const SizedBox(height: Space.x12),
                    Expanded(child: GlassCard(
                      blur: false,
                      padding: EdgeInsets.zero,
                      child: ClipRRect(borderRadius: Shapes.lg, child: PdfPreview(
                        build: (_) async => _pdf!,
                        initialPageFormat: PdfPageFormat.a4,
                        pdfFileName: _fileName,
                        useActions: false,
                        allowPrinting: false,
                        allowSharing: false,
                        canChangeOrientation: false,
                        canChangePageFormat: false,
                        canDebug: false,
                        dynamicLayout: false,
                        maxPageWidth: 420,
                        padding: const EdgeInsets.all(8),
                        scrollViewDecoration: BoxDecoration(color: c.textPrimary.withValues(alpha: .05)),
                        loadingWidget: const Center(child: CircularProgressIndicator()),
                      )),
                    )),
                    const SizedBox(height: Space.x12),
                    if (_actionBusy) const LinearProgressIndicator(minHeight: 2),
                    if (_actionBusy) const SizedBox(height: Space.x8),
                    LayoutBuilder(builder: (context, box) {
                      final width = (box.maxWidth - Space.x8) / 2;
                      return Wrap(spacing: Space.x8, runSpacing: Space.x8, children: [
                        SizedBox(width: width, child: _ReceiptAction(icon: Icons.open_in_full, label: 'View PDF', onTap: _view)),
                        SizedBox(width: width, child: _ReceiptAction(icon: Icons.download_outlined, label: 'Save PDF', onTap: _save)),
                        SizedBox(width: width, child: _ReceiptAction(icon: Icons.chat_outlined, label: 'WhatsApp',
                          highlighted: true, onTap: () => _share(whatsapp: true))),
                        SizedBox(width: width, child: _ReceiptAction(icon: Icons.share_outlined, label: 'Other apps',
                          onTap: () => _share(whatsapp: false))),
                      ]);
                    }),
                  ]),
          ),
        ),
        Positioned(top: 0, left: 0, right: 0, child: GlassTopBar(
          title: _sale ? 'PDF bill' : 'Purchase PDF', scroll: _scroll,
          leading: const BackButton(),
        )),
      ])),
    );
  }
}

class _ReceiptAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool highlighted;
  const _ReceiptAction({required this.icon, required this.label, required this.onTap, this.highlighted = false});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: highlighted ? context.scheme.primary : c.textPrimary.withValues(alpha: .05),
      shape: RoundedRectangleBorder(borderRadius: Shapes.md,
        side: BorderSide(color: highlighted ? context.scheme.primary : c.textPrimary.withValues(alpha: .10))),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.x12, vertical: Space.x8),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 19, color: highlighted ? context.scheme.onPrimary : c.brandInk),
              const SizedBox(width: Space.x8),
              Flexible(child: Text(label, style: context.type.labelLarge?.copyWith(
                color: highlighted ? context.scheme.onPrimary : c.textPrimary))),
            ]),
          ),
        ),
      ),
    );
  }
}

class _FullPdfView extends StatelessWidget {
  final Uint8List bytes;
  final String fileName, title;
  const _FullPdfView({required this.bytes, required this.fileName, required this.title});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: PdfPreview(
      build: (_) async => bytes,
      initialPageFormat: PdfPageFormat.a4,
      pdfFileName: fileName,
      useActions: false,
      allowPrinting: false,
      allowSharing: false,
      canChangeOrientation: false,
      canChangePageFormat: false,
      canDebug: false,
      dynamicLayout: false,
    ),
  );
}
