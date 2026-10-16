// BUY FORM: IMEI 15 digits → free TAC lookup fills brand + model.
// Catalog (tac_models) first; if it misses, this shop's own last entry for the same
// IMEI fills it. RAM / storage / colour cannot come from an IMEI, so the server
// sends the values THIS app has already recorded for that model and the shop picks
// one from a dropdown (or types its own). Status shown as a live StatusChip;
// save adds to stock. Test hook: testLookup/testSave.
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
import 'scanner.dart';

class BuyForm extends StatefulWidget {
  final VoidCallback onSaved;
  final Future<Map<String, dynamic>> Function(String imei)? testLookup;
  final Future<void> Function(Map<String, dynamic> body)? testSave;
  final Future<Uint8List?> Function(ImageSource source)? testPickPhoto;
  final Future<Uint8List> Function(Uint8List bytes)? testPreparePhoto;
  const BuyForm({super.key, required this.onSaved, this.testLookup, this.testSave,
    this.testPickPhoto, this.testPreparePhoto});
  @override
  State<BuyForm> createState() => _BuyFormState();
}

enum _ImeiState { none, looking, found, community, fromHistory, newModel, invalid, duplicate }

/// Shown when the server has nothing recorded yet (new model, or a backend that
/// is not deployed with the `options` response). The dropdown stays usable
/// instead of opening empty.
const List<String> kDefaultRamOptions = ['2GB', '3GB', '4GB', '6GB', '8GB', '12GB', '16GB'];
const List<String> kDefaultStorageOptions = ['16GB', '32GB', '64GB', '128GB', '256GB', '512GB', '1TB'];
const List<String> kDefaultColorOptions = ['Black', 'White', 'Blue', 'Silver', 'Grey', 'Gold', 'Green', 'Purple', 'Red'];

class _BuyFormState extends State<BuyForm> {
  final _form = GlobalKey<FormState>();
  final _scroll = ScrollController();
  final imei = TextEditingController(), imei2 = TextEditingController(), serial = TextEditingController(),
      brand = TextEditingController(), model = TextEditingController(), ram = TextEditingController(),
      storage = TextEditingController(), color = TextEditingController(), accessories = TextEditingController(),
      price = TextEditingController(),
      // Server-side keys stay seller_* for compatibility; the shop calls this
      // person the customer, so the UI says "Customer".
      cName = TextEditingController(), cPhone = TextEditingController(),
      cAddr = TextEditingController(), notes = TextEditingController();
  String condition = 'Good', idType = 'Aadhaar';
  DateTime date = DateTime.now();
  ButtonPhase _phase = ButtonPhase.idle;
  _ImeiState _imeiState = _ImeiState.none;
  String _imeiLabel = '';
  int _timesBought = 0;

  // Dropdown values for RAM/storage/colour. Start with the built-in defaults so
  // the arrow works immediately; /imei/:imei replaces these with what this app
  // has actually recorded for the model.
  final List<String> _ramOptions = [...kDefaultRamOptions],
      _storageOptions = [...kDefaultStorageOptions],
      _colorOptions = [...kDefaultColorOptions];

  // Front uses the existing API column; the reverse side is optional.
  final List<Uint8List?> _idPhotos = [null, null];
  int? _pickingSide;
  bool get _saving => _phase == ButtonPhase.loading || _phase == ButtonPhase.success;

  @override
  void dispose() {
    _scroll.dispose();
    for (final c in [imei, imei2, serial, brand, model, ram, storage, color, accessories, price,
          cName, cPhone, cAddr, notes]) { c.dispose(); }
    super.dispose();
  }

  /// Remembers the dropdown options returned by /imei/:imei.
  void _setOptions(dynamic raw) {
    final Map<dynamic, dynamic> o = raw is Map ? raw : const <dynamic, dynamic>{};
    // An older/absent backend sends nothing: fall back to the built-in defaults.
    List<String> asList(dynamic v, List<String> fallback) {
      final list = (v as List? ?? const [])
          .map((e) => '$e'.trim()).where((e) => e.isNotEmpty).toList(growable: false);
      return list.isEmpty ? fallback : list;
    }
    setState(() {
      _ramOptions
        ..clear()
        ..addAll(asList(o['ram'], kDefaultRamOptions));
      _storageOptions
        ..clear()
        ..addAll(asList(o['storage'], kDefaultStorageOptions));
      _colorOptions
        ..clear()
        ..addAll(asList(o['color'], kDefaultColorOptions));
    });
  }

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
      _setOptions(r['options']);
      if (r['already_in_stock'] == true) { _imeiState = _ImeiState.duplicate; _imeiLabel = 'This phone is already in stock'; }
      else if (r['found'] == true) {
        final i = r['info'];
        brand.text = '${i['brand'] ?? ''}'; model.text = '${i['model'] ?? ''}';
        ram.text = '${i['ram'] ?? ''}'; storage.text = '${i['storage'] ?? ''}';
        if (i['color'] != null && color.text.isEmpty) color.text = '${i['color']}';
        // Community catalog rows (Osmocom, the extended India-models list, or an
        // optional external TAC API) are unverified and have no RAM/storage: plug those
        // gaps from the shop's earlier entry and say so, instead of claiming "auto-filled".
        final community = const {'osmocom', 'tacdb', 'api'}.contains(i['source']);
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
    into(serial, 'serial_number');
    return filled;
  }

  Future<void> _scan() async {
    final v = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const ImeiScanner()));
    if (v != null) { imei.text = v; _lookup(v); }
  }

  // ---- ID proof photos ----

  Future<void> _askIdPhotoSource(int side) async {
    if (_pickingSide != null || _saving) return;
    FocusScope.of(context).unfocus();
    setState(() => _pickingSide = side);
    try {
      final source = await showModalBottomSheet<ImageSource>(
        context: context,
        showDragHandle: true,
        builder: (sheet) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${side == 0 ? 'Front' : 'Back'} photo', style: context.type.titleMedium),
            ListTile(
              leading: Icon(Icons.photo_library_outlined, color: context.colors.brandInk),
              title: const Text('Gallery se choose karein'),
              onTap: () => Navigator.pop(sheet, ImageSource.gallery),
            ),
            ListTile(
              leading: Icon(Icons.photo_camera_outlined, color: context.colors.brandInk),
              title: const Text('Camera se photo lein'),
              onTap: () => Navigator.pop(sheet, ImageSource.camera),
            ),
            if (_idPhotos[side] != null)
              ListTile(
                leading: Icon(Icons.delete_outline, color: context.colors.errorInk),
                title: const Text('Photo hata dein'),
                onTap: () {
                  setState(() => _idPhotos[side] = null);
                  Navigator.pop(sheet);
                },
              ),
            const SizedBox(height: Space.x8),
          ]),
        ),
      );
      if (source == null || !mounted) return;
      Uint8List? bytes;
      if (widget.testPickPhoto != null) {
        bytes = await widget.testPickPhoto!(source);
      } else {
        // Bound decode memory and normalize camera orientation on the platform.
        // Final size/quality is chosen by our compressor, not a fixed picker quality.
        final picked = await ImagePicker().pickImage(
          source: source, maxWidth: 2000, maxHeight: 2000, imageQuality: 100,
          requestFullMetadata: false,
        );
        if (picked == null || !mounted) return;
        if (await picked.length() > documentPhotoMaxInputBytes) {
          throw const FormatException('Choose a photo smaller than 20 MB.');
        }
        bytes = await picked.readAsBytes();
      }
      if (bytes == null || !mounted) return;
      final compressed = await (widget.testPreparePhoto ?? prepareDocumentPhoto)(bytes);
      if (!mounted) return;
      setState(() => _idPhotos[side] = compressed);
      Haptics.success();
    } catch (_) {
      if (mounted) toast(context, 'Photo process nahi ho payi. JPEG/PNG ya camera se dobara try karein.', err: true);
    } finally {
      if (mounted) setState(() => _pickingSide = null);
    }
  }

  Future<void> _previewIdPhoto(int side) async {
    final bytes = _idPhotos[side];
    if (bytes == null) return;
    await showDialog<void>(context: context, builder: (dialog) => Dialog(
      child: Padding(
        padding: const EdgeInsets.all(Space.x16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Expanded(child: Text('${side == 0 ? 'Front' : 'Back'} · ${(bytes.length / 1024).ceil()} KB',
              style: context.type.titleMedium)),
            IconButton(tooltip: 'Close preview', onPressed: () => Navigator.pop(dialog), icon: const Icon(Icons.close)),
          ]),
          Flexible(child: InteractiveViewer(minScale: 1, maxScale: 5,
            child: Image.memory(bytes, fit: BoxFit.contain))),
          const SizedBox(height: Space.x8),
          const Text('Zoom karke document ka text check karein.'),
        ]),
      ),
    ));
  }

  Future<void> _save() async {
    if (_pickingSide != null || _saving) return;
    if (supportReadOnlyBlock(context, 'Buying a phone')) return;
    FocusScope.of(context).unfocus();
    if (!_form.currentState!.validate()) return;
    setState(() => _phase = ButtonPhase.loading);
    final body = {
      'imei': imei.text, 'imei2': imei2.text, 'serial_number': serial.text, 'brand': brand.text, 'model': model.text,
      'ram': ram.text, 'storage': storage.text, 'color': color.text, 'condition': condition, 'accessories': accessories.text,
      'buy_price': price.text, 'buy_date': DateFormat('yyyy-MM-dd').format(date),
      'seller_name': cName.text, 'seller_phone': cPhone.text, 'seller_id_type': idType,
      'seller_address': cAddr.text, 'notes': notes.text, 'customer_id_photo': _photoDataUrl(0),
      'customer_id_photo_back': _photoDataUrl(1),
    };
    try {
      int? receiptId;
      if (widget.testSave != null) {
        await widget.testSave!(body);
      } else {
        final saved = await Api.post('/buy', body);
        receiptId = saved is Map ? int.tryParse('${saved['id']}') : null;
      }
      if (!mounted) return;
      setState(() => _phase = ButtonPhase.success);
      Haptics.success();
      await Future<void>.delayed(Motion.of(context).d(const Duration(milliseconds: 500)));
      if (!mounted) return;
      if (receiptId != null) {
        await SharedAxisRoute.push(context, (_) => ReceiptScreen(type: 'purchase', id: receiptId!));
        if (!mounted) return;
      }
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

  String _photoDataUrl(int side) => _idPhotos[side] == null
      ? '' : 'data:image/jpeg;base64,${base64Encode(_idPhotos[side]!)}';

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
              const SizedBox(height: Space.x12),
              GlassTextField(controller: serial, label: 'Serial number (optional)', prefixIcon: Icons.tag,
                  maxLength: 64, textInputAction: TextInputAction.next),
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
                Expanded(child: _OptionField(controller: ram, label: 'RAM (e.g. 8GB)', title: 'RAM', icon: Icons.memory_outlined, options: _ramOptions)),
                const SizedBox(width: Space.x12),
                Expanded(child: _OptionField(controller: storage, label: 'Storage (e.g. 128GB)', title: 'Storage', icon: Icons.storage_rounded, options: _storageOptions)),
              ]),
              const SizedBox(height: Space.x12),
              Row(children: [
                Expanded(child: _OptionField(controller: color, label: 'Color', title: 'Color', icon: Icons.palette_outlined, options: _colorOptions)),
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
                    constraints: const BoxConstraints(minHeight: 56),
                    padding: const EdgeInsets.symmetric(horizontal: Space.x16, vertical: Space.x12),
                    decoration: BoxDecoration(borderRadius: Shapes.md, color: c.textPrimary.withValues(alpha: .05),
                        border: Border.all(color: c.textPrimary.withValues(alpha: .10))),
                    child: Row(children: [
                      Icon(Icons.calendar_month_outlined, size: 20, color: c.textSecondary),
                      const SizedBox(width: Space.x12),
                      Expanded(child: Text(DateFormat('d MMMM yyyy').format(date), style: t.bodyLarge)),
                      const SizedBox(width: Space.x8),
                      Text('Change', style: t.labelLarge?.copyWith(color: c.brandInk)),
                    ]),
                  ),
                )),
            ])),
            const SizedBox(height: Space.section),
            // ---- Customer (the person the phone is bought from) ----
            SectionHeader(title: 'Customer details'),
            const SizedBox(height: Space.x12),
            GlassCard(blur: false, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: GlassTextField(controller: cName, label: 'Customer name', required: true, prefixIcon: Icons.person_outline, textInputAction: TextInputAction.next)),
                const SizedBox(width: Space.x12),
                Expanded(child: GlassTextField(controller: cPhone, label: 'Mobile', prefixIcon: Icons.phone_outlined, keyboardType: TextInputType.phone, maxLength: 10, textInputAction: TextInputAction.next)),
              ]),
              const SizedBox(height: Space.x12),
              _GlassDropdown(label: 'ID proof', value: idType,
                  items: const ['Aadhaar', 'PAN', 'Voter ID', 'Driving Licence', 'Visiting Card'],
                  onChanged: (v) => setState(() => idType = v!)),
              const SizedBox(height: Space.x12),
              _idUploadSection(c, t),
              const SizedBox(height: Space.x12),
              GlassTextField(controller: cAddr, label: 'Address (optional)'),
              const SizedBox(height: Space.x12),
              GlassTextField(controller: notes, label: 'Notes (optional)'),
            ])),
            const SizedBox(height: Space.section),
            PrimaryButton(label: 'Save & add to stock', icon: Icons.add, phase: _phase, onPressed: _pickingSide == null ? _save : null),
          ],
        ),
      ),
      Positioned(top: 0, left: 0, right: 0, child: GlassTopBar(title: 'Buy phone', scroll: _scroll, leading: const SizedBox(width: Space.x12))),
    ]);
  }

  Widget _idUploadSection(AppColors c, TextTheme t) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.verified_user_outlined, size: 20, color: c.brandInk),
        const SizedBox(width: Space.x8),
        Expanded(child: Text('Document photos', style: t.titleSmall)),
        Text('${_idPhotos.whereType<Uint8List>().length}/2', style: t.labelLarge?.copyWith(color: c.brandInk)),
      ]),
      const SizedBox(height: Space.x8),
      Text('Front aur back upload karein. Sirf 1 photo bhi chalegi.',
        style: t.bodySmall?.copyWith(color: c.textSecondary)),
      const SizedBox(height: Space.x12),
      LayoutBuilder(builder: (context, box) => box.maxWidth < 280
        ? Column(children: [_idUploadTile(0, c, t), const SizedBox(height: Space.x12), _idUploadTile(1, c, t)])
        : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: _idUploadTile(0, c, t)),
            const SizedBox(width: Space.x12),
            Expanded(child: _idUploadTile(1, c, t)),
          ])),
      const SizedBox(height: Space.x8),
      Text('Auto-compress · Target 100 KB/photo. Text clarity ke liye size zyada ho sakta hai.',
        style: t.bodySmall?.copyWith(color: c.textSecondary)),
    ]);
  }

  Widget _idUploadTile(int side, AppColors c, TextTheme t) {
    final bytes = _idPhotos[side];
    final busy = _pickingSide == side;
    final enabled = _pickingSide == null && !_saving;
    final name = side == 0 ? 'Front' : 'Back';
    return Material(
      color: context.scheme.primary.withValues(alpha: .06),
      shape: RoundedRectangleBorder(borderRadius: Shapes.md,
        side: BorderSide(color: context.scheme.primary.withValues(alpha: bytes == null ? .20 : .5))),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          key: ValueKey('id-photo-$side'),
          onTap: enabled ? () => _askIdPhotoSource(side) : null,
          child: Semantics(button: true, label: 'Upload $name document photo',
            child: Padding(
              padding: const EdgeInsets.all(Space.x12),
              child: Column(children: [
                SizedBox(height: 72, width: double.infinity,
                  child: busy
                    ? const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)))
                    : bytes != null
                      ? ClipRRect(borderRadius: Shapes.xs, child: Image.memory(bytes, fit: BoxFit.contain))
                      : Icon(side == 0 ? Icons.badge_outlined : Icons.flip_to_back_rounded, size: 32, color: c.brandInk)),
                const SizedBox(height: Space.x8),
                Text('$name photo', style: t.labelLarge),
                const SizedBox(height: Space.x4),
                Text(busy ? 'Processing…' : bytes == null ? 'Tap to upload' : '${(bytes.length / 1024).ceil()} KB · Change',
                  textAlign: TextAlign.center, style: t.bodySmall?.copyWith(color: c.brandInk)),
              ]),
            ),
          ),
        ),
        if (bytes != null)
          TextButton.icon(onPressed: () => _previewIdPhoto(side),
            icon: const Icon(Icons.zoom_in, size: 18), label: const Text('Preview')),
      ]),
    );
  }
}

/// A normal text field with a dropdown of values this app has already recorded
/// for the same model/brand. The list opens as a bottom sheet, which always
/// lands in the same place no matter where the field sits in the scrolling
/// form (a popup menu anchored to the field can be clipped or misplaced).
/// Typing a new value still works — that is what teaches the app for next time.
class _OptionField extends StatelessWidget {
  final TextEditingController controller;
  final String label, title;
  final IconData icon;
  final List<String> options;
  const _OptionField({required this.controller, required this.label, required this.title,
    required this.icon, required this.options});

  Future<void> _openPicker(BuildContext context) async {
    FocusScope.of(context).unfocus();
    final c = context.colors, t = context.type, scheme = context.scheme;
    final current = controller.text.trim();
    final values = <String>[];
    for (final value in [if (current.isNotEmpty) current, ...options]) {
      if (value.trim().isNotEmpty && !values.any((v) => v.toLowerCase() == value.trim().toLowerCase())) {
        values.add(value.trim());
      }
    }
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: scheme.surfaceContainer,
      barrierColor: scheme.scrim.withValues(alpha: .5),
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(Radii.xl)),
        side: BorderSide(color: scheme.primary.withValues(alpha: .18))),
      builder: (sheet) => SafeArea(top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheet).height * .72),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(Space.x20, 0, Space.x20, Space.x24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(width: 48, height: 48,
                  decoration: BoxDecoration(color: scheme.primary.withValues(alpha: .12), borderRadius: Shapes.md),
                  child: Icon(icon, color: c.brandInk)),
                const SizedBox(width: Space.x12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Choose $title', style: t.titleLarge?.copyWith(color: c.textPrimary)),
                  Text('Apne phone ka variant select karein', style: t.bodySmall?.copyWith(color: c.textSecondary)),
                ])),
                IconButton(tooltip: 'Close $title options', onPressed: () => Navigator.pop(sheet),
                  icon: Icon(Icons.close_rounded, color: c.textSecondary)),
              ]),
              const SizedBox(height: Space.x24),
              LayoutBuilder(builder: (context, box) {
                final columns = box.maxWidth < 300 || MediaQuery.textScalerOf(context).scale(14) > 20 ? 1 : 2;
                final width = (box.maxWidth - (columns - 1) * Space.x12) / columns;
                return Wrap(spacing: Space.x12, runSpacing: Space.x12, children: [
                  for (final option in values)
                    SizedBox(width: width, child: _optionTile(sheet, option,
                      selected: option.toLowerCase() == current.toLowerCase())),
                ]);
              }),
              const SizedBox(height: Space.x20),
              Container(
                padding: const EdgeInsets.all(Space.x12),
                decoration: BoxDecoration(color: c.accent.withValues(alpha: .08), borderRadius: Shapes.sm),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.edit_outlined, size: 18, color: c.brandInk),
                  const SizedBox(width: Space.x8),
                  Expanded(child: Text('Option nahi mila? Sheet band karke field mein apna value type karein.',
                    style: t.bodySmall?.copyWith(color: c.textSecondary))),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
    if (picked == null || !context.mounted) return;
    Haptics.tick();
    controller.text = picked;
  }

  Widget _optionTile(BuildContext context, String option, {required bool selected}) {
    final c = context.colors, scheme = context.scheme;
    return Semantics(selected: selected, button: true,
      child: Material(
        color: selected ? scheme.primary.withValues(alpha: .14) : scheme.surfaceContainerHigh.withValues(alpha: .55),
        shape: RoundedRectangleBorder(borderRadius: Shapes.md,
          side: BorderSide(color: selected ? scheme.primary : scheme.outline.withValues(alpha: .35), width: selected ? 1.5 : 1)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: () => Navigator.pop(context, option),
          child: ConstrainedBox(constraints: const BoxConstraints(minHeight: 60),
            child: Padding(padding: const EdgeInsets.all(Space.x12),
              child: Row(children: [
                Icon(icon, size: 20, color: selected ? c.brandInk : c.textSecondary),
                const SizedBox(width: Space.x8),
                Expanded(child: Text(option, style: context.type.titleSmall?.copyWith(
                  color: selected ? c.brandInk : c.textPrimary))),
                const SizedBox(width: Space.x4),
                Icon(selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                  size: 20, color: selected ? c.brandInk : scheme.outline),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GlassTextField(
      controller: controller,
      label: label,
      textInputAction: TextInputAction.next,
      suffix: IconButton(
        tooltip: '$label choose karein',
        icon: Icon(Icons.expand_more_rounded, color: context.colors.brandInk),
        style: IconButton.styleFrom(backgroundColor: context.scheme.primary.withValues(alpha: .08)),
        onPressed: () => _openPicker(context),
      ),
    );
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
