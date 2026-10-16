import 'package:flutter/material.dart';
import '../api.dart';
import '../design/components/components.dart';

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

/// Support mode ka read-only guard. Screen se chhupane ke saath-saath likhne wale
/// kaam yahan bhi rok dete hain (backend bhi 403 deta hai — ye sirf saaf message ke liye).
bool supportReadOnlyBlock(BuildContext c, String action) {
  if (!Api.supportReadOnly) return false;
  Haptics.error();
  toast(c, 'Support mode read-only hai — $action shop owner khud karega.', err: true);
  return true;
}

/// 12:34 countdown (minutes:seconds).
String clock(Duration d) =>
    '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// Server epoch ms → device-local time, e.g. "14:32".
String shortClock(int? ms) {
  if (ms == null || ms <= 0) return '—';
  final d = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
  return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// Server epoch ms → "16 Oct, 14:32" (device timezone).
String shortStamp(int? ms) {
  if (ms == null || ms <= 0) return '—';
  final d = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
  return '${d.day} ${_months[d.month - 1]}, ${shortClock(ms)}';
}

/// "just now" / "12 min ago" / "3 hr ago" / "2 d ago".
String agoFrom(int? ms) {
  if (ms == null || ms <= 0) return '—';
  final d = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms));
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} hr ago';
  return '${d.inDays} d ago';
}

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
