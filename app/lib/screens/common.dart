import 'package:flutter/material.dart';
import '../api.dart';
import '../design/components/components.dart';
import '../design/design.dart';

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

/// Error toast design tokens se — `Colors.red` theme ke error tone se match nahi
/// karta tha (light #DC2626 / dark #F87171). Ek waqt par ek hi snackbar rehta hai.
void toast(BuildContext c, String m, {bool err = false}) {
  final scheme = Theme.of(c).colorScheme;
  final message = m.replaceFirst('Exception: ', '');
  ScaffoldMessenger.of(c)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message, style: TextStyle(color: err ? scheme.onError : null)),
      backgroundColor: err ? scheme.error : null,
    ));
}

/// Chhota icon + text pair — list rows me extra info bina jagah khaye dikhata hai.
class IconLabel extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const IconLabel({super.key, required this.icon, required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, size: 14, color: color),
    const SizedBox(width: 3),
    Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
      style: context.type.labelSmall?.copyWith(color: color))),
  ]);
}

/// Support mode ka read-only guard. Screen se chhupane ke saath-saath likhne wale
/// kaam yahan bhi rok dete hain (backend bhi 403 deta hai — ye sirf saaf message ke liye).
bool supportReadOnlyBlock(BuildContext c, String action) {
  if (!Api.supportReadOnly) return false;
  Haptics.error();
  toast(c, 'Support mode is read-only. The shop owner must $action.', err: true);
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

