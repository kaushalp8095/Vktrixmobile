// SUPER ADMIN — shop Add/Edit dialog ka "Bill logo" row.
//
// Pehle yahan hamesha ek generic store ka icon dikhta tha, chahe shop ka logo
// upload ho chuka ho (aur button bhi "Add" hi kehta tha). Isse admin ko pata hi
// nahi chalta tha ki kaunsa logo laga hua hai — dobara upload karne par purana
// logo chup-chaap badal jata tha. Ab yahan asli logo ka preview dikhta hai aur
// neeche uski state (uploaded / naya chuna hua / remove) likhi hoti hai.
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../design/design.dart';
import 'shop_logo.dart';

class BillLogoField extends StatelessWidget {
  /// Preview: server se aaya uploaded logo ya abhi chuna hua naya logo.
  final Uint8List? bytes;
  /// Purana logo server se aa raha hai (pehla frame se hi true rehta hai).
  final bool loading;
  /// Server par logo maujood hai — preview load fail ho jaye tab bhi true.
  final bool uploaded;
  /// Admin ne isi dialog me logo badla ya hataya (Save par hi apply hoga).
  final bool changed;
  final VoidCallback onPick;
  /// X button; widget khud decide karta hai ki dikhana hai ya nahi.
  final VoidCallback? onRemove;

  const BillLogoField({
    super.key,
    required this.bytes,
    required this.loading,
    required this.uploaded,
    required this.changed,
    required this.onPick,
    this.onRemove,
  });

  /// Logo hataya ja sakta hai: preview hai, ya server par hai aur abhi hataya
  /// nahi gaya. (Remove ke baad X dobara nahi dikhta.)
  bool get _canRemove => onRemove != null && (bytes != null || (uploaded && !changed));

  bool get _hasLogo => bytes != null || (uploaded && !changed);

  String get _status {
    if (loading && bytes == null) return 'Loading the uploaded logo…';
    if (changed && bytes != null) return 'New logo · tap Save to apply';
    if (changed) return 'Removed · tap Save to apply';
    if (bytes != null) return 'Uploaded · prints on PDF bills';
    if (uploaded) return 'Logo uploaded · preview unavailable';
    return 'No logo uploaded yet';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors, t = context.type, scheme = context.scheme;
    return Container(
      padding: const EdgeInsets.all(Space.x12),
      decoration: BoxDecoration(
        color: c.textPrimary.withValues(alpha: .04),
        borderRadius: Shapes.md,
        border: Border.all(color: c.textPrimary.withValues(alpha: .10)),
      ),
      child: Row(children: [
        Semantics(
          label: _hasLogo ? 'Uploaded bill logo' : 'No bill logo',
          image: true,
          child: Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              // Server save par logo ko square tile bana deta hai; preview bhi
              // wahi shape dikhaye (rounded square, poora bhara hua). Safed plate
              // jaan-boojh kar nahi — transparent PNG logo ka box dikhta tha.
              color: bytes != null ? c.textPrimary.withValues(alpha: .05) : scheme.primary.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(logoRadius(54)),
              border: bytes != null ? Border.all(color: c.textPrimary.withValues(alpha: .12)) : null,
            ),
            clipBehavior: Clip.antiAlias,
            child: _preview(c),
          ),
        ),
        const SizedBox(width: Space.x12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Bill logo', style: t.titleSmall),
            Text(_status, style: t.bodySmall?.copyWith(color: c.textSecondary)),
          ]),
        ),
        TextButton(
          onPressed: onPick,
          child: Text(_hasLogo ? 'Change' : 'Add'),
        ),
        if (_canRemove)
          IconButton(tooltip: 'Remove logo', icon: const Icon(Icons.close), onPressed: onRemove),
      ]),
    );
  }

  Widget _preview(AppColors c) {
    final bytes = this.bytes;
    if (bytes != null) return Image.memory(bytes, fit: BoxFit.cover);
    if (loading) {
      return const Center(
        child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    return Icon(Icons.storefront_outlined, color: c.brandInk);
  }
}
