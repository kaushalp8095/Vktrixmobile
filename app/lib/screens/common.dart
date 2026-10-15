import 'package:flutter/material.dart';

/// Keeps API timestamps compact in business screens without shifting a UTC
/// calendar date into the previous/next local day.
String dateOnly(dynamic value) {
  if (value == null) return '—';
  final raw = value.toString().trim();
  if (raw.isEmpty || raw == 'null') return '—';

  final isoPrefix = RegExp(r'^(\d{4}-\d{2}-\d{2})(?:$|[Tt ].*)').firstMatch(raw);
  if (isoPrefix != null) return isoPrefix.group(1)!;

  final parsed = DateTime.tryParse(raw);
  if (parsed == null) return raw;
  return '${parsed.year.toString().padLeft(4, '0')}-'
      '${parsed.month.toString().padLeft(2, '0')}-'
      '${parsed.day.toString().padLeft(2, '0')}';
}

void toast(BuildContext c, String m, {bool err = false}) => ScaffoldMessenger.of(c)
    .showSnackBar(SnackBar(content: Text(m.replaceFirst('Exception: ', '')), backgroundColor: err ? Colors.red : null));

Widget field(TextEditingController c, String label,
        {TextInputType? type, int? maxLength, bool required = false, ValueChanged<String>? onChanged, Widget? suffix, bool obscure = false}) =>
    Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: c, keyboardType: type, maxLength: maxLength, onChanged: onChanged, obscureText: obscure,
        decoration: InputDecoration(labelText: required ? '$label *' : label, suffixIcon: suffix, counterText: ''),
        validator: required ? (v) => (v == null || v.trim().isEmpty) ? '$label zaroori hai' : null : null,
      ),
    );

Widget statCard(String title, String value, IconData icon, Color color) => Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          CircleAvatar(backgroundColor: color.withValues(alpha: .15), child: Icon(icon, color: color)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(color: Colors.grey)),
            Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ])),
        ]),
      ),
    );
