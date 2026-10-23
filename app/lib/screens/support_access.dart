// TEMPORARY SUPPORT ACCESS (Super Admin)
//
// Screen par sirf manage karne layak cheezein rehti hain (shop name, status,
// masked contact). Shop ka business data kholne ke liye admin ko yahan se ek
// reason ke saath time-limited, read-only session lena padta hai — aur wahi
// session shop owner ko apni app me dikhta hai (Support access history).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../api.dart';
import '../design/components/components.dart';
import '../design/design.dart';
import 'common.dart';

/// Support session ke duration options (backend 5–240 minutes allow karta hai).
const supportDurations = <(String, int)>[('15 min', 15), ('30 min', 30), ('1 hour', 60), ('2 hours', 120)];

/// Reason + duration maangne wala dialog. Return: {'reason': ..., 'minutes': ...} ya null.
Future<Map<String, dynamic>?> showStartSupportDialog(BuildContext context, {required String shopName}) async {
  final result = await showDialog<Map<String, dynamic>>(
    context: context,
    barrierDismissible: true,
    builder: (_) => _StartSupportDialog(shopName: shopName),
  );
  return result;
}

/// Full contact dekhne ke baad dikhne wala sheet (number copy karne ke liye).
Future<void> showRevealedContactSheet(BuildContext context, {required String shopName, required String? phone, String? ownerName}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final c = ctx.colors, t = ctx.type;
        return Padding(
          padding: EdgeInsets.fromLTRB(Space.x16, 0, Space.x16, MediaQuery.viewPaddingOf(ctx).bottom + Space.x16),
          child: GlassSurface(child: SafeArea(top: false, child: Padding(
            padding: const EdgeInsets.all(Space.x20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Center(child: Container(width: 36, height: 4,
                  decoration: BoxDecoration(color: c.textPrimary.withValues(alpha: .20), borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: Space.x16),
              Semantics(header: true, child: Text(shopName, style: t.headlineSmall)),
              if (ownerName != null && ownerName.trim().isNotEmpty)
                Text(ownerName, style: t.bodyMedium?.copyWith(color: c.textSecondary)),
              const SizedBox(height: Space.x16),
              Container(
                padding: const EdgeInsets.all(Space.x16),
                decoration: BoxDecoration(color: c.brandInk.withValues(alpha: .10), borderRadius: Shapes.md,
                    border: Border.all(color: c.brandInk.withValues(alpha: .24))),
                child: Row(children: [
                  Icon(Icons.call_outlined, color: c.brandInk, size: 20),
                  const SizedBox(width: Space.x12),
                  Expanded(child: SelectableText(phone ?? '—', style: t.titleLarge)),
                  IconButton(
                    tooltip: 'Copy number',
                    icon: const Icon(Icons.copy_all_outlined),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: phone ?? ''));
                      if (ctx.mounted) toast(ctx, 'Number copied');
                    },
                  ),
                ]),
              ),
              const SizedBox(height: Space.x12),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.receipt_long_outlined, size: 16, color: c.textSecondary),
                const SizedBox(width: Space.x8),
                Expanded(child: Text('This reveal is written in the shop\'s access log — the owner can see it.',
                    style: t.bodySmall?.copyWith(color: c.textSecondary))),
              ]),
            ]),
          ))),
        );
      },
    );

class _StartSupportDialog extends StatefulWidget {
  final String shopName;
  const _StartSupportDialog({required this.shopName});
  @override
  State<_StartSupportDialog> createState() => _StartSupportDialogState();
}

class _StartSupportDialogState extends State<_StartSupportDialog> {
  final _reason = TextEditingController();
  int _minutes = 30;

  @override
  void dispose() { _reason.dispose(); super.dispose(); }

  bool get _valid => _reason.text.trim().length >= 10;

  @override
  Widget build(BuildContext context) {
    final c = context.colors, t = context.type, s = context.scheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: Space.x24, vertical: Space.x24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Material(
            color: s.surfaceContainer,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(borderRadius: Shapes.xl,
                side: BorderSide(color: c.textPrimary.withValues(alpha: .08))),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(height: 4, decoration: const BoxDecoration(gradient: AppColors.brandGradient)),
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.x24, Space.x24, Space.x24, Space.x20),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(width: 52, height: 52,
                      decoration: BoxDecoration(color: c.brandInk.withValues(alpha: .12), borderRadius: Shapes.md,
                          border: Border.all(color: c.brandInk.withValues(alpha: .24))),
                      child: Icon(Icons.shield_outlined, size: 26, color: c.brandInk)),
                    const SizedBox(width: Space.x16),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Support access', style: t.titleLarge),
                      Text(widget.shopName, style: t.bodySmall?.copyWith(color: c.textSecondary),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ])),
                  ]),
                  const SizedBox(height: Space.x16),
                  Text('Enter a reason to view shop data. Access is time-limited and read-only, and will be visible to the shop owner in the app.',
                      style: t.bodyMedium?.copyWith(color: c.textSecondary)),
                  const SizedBox(height: Space.x16),
                  TextField(
                    controller: _reason,
                    autofocus: true,
                    maxLines: 3,
                    maxLength: 300,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Reason (min 10 characters)',
                      hintText: 'e.g. Shop owner called: sale entry stuck, needs a correction',
                    ),
                  ),
                  const SizedBox(height: Space.x8),
                  Text('Time limit', style: t.labelLarge?.copyWith(color: c.textSecondary)),
                  const SizedBox(height: Space.x8),
                  Wrap(spacing: Space.x8, runSpacing: Space.x8, children: [
                    for (final d in supportDurations)
                      _DurationTile(label: d.$1, selected: _minutes == d.$2,
                          onTap: () { Haptics.tick(); setState(() => _minutes = d.$2); }),
                  ]),
                  const SizedBox(height: Space.x16),
                  Container(
                    padding: const EdgeInsets.all(Space.x12),
                    decoration: BoxDecoration(color: c.textPrimary.withValues(alpha: .04), borderRadius: Shapes.md,
                        border: Border.all(color: c.textPrimary.withValues(alpha: .08))),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _SupportRule(icon: Icons.visibility_off_outlined, text: 'Read-only — shop data cannot be changed.'),
                      const SizedBox(height: Space.x8),
                      _SupportRule(icon: Icons.timer_outlined, text: 'Access ends automatically when the time limit expires.'),
                      const SizedBox(height: Space.x8),
                      _SupportRule(icon: Icons.receipt_long_outlined, text: 'The shop owner can see the access log and its reason in the app.'),
                    ]),
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.x24, 0, Space.x24, Space.x24),
                child: Row(children: [
                  Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))),
                  const SizedBox(width: Space.x12),
                  Expanded(child: FilledButton(
                    onPressed: _valid ? () => Navigator.pop(context, {'reason': _reason.text.trim(), 'minutes': _minutes}) : null,
                    child: const Text('Start access'),
                  )),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Time-limit ki gol chip (Indigo/Mint: 14% brand fill + brand border jab selected ho).
class _DurationTile extends StatelessWidget {
  final String label; final bool selected; final VoidCallback onTap;
  const _DurationTile({required this.label, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final c = context.colors, t = context.type;
    return Semantics(
      button: true, selected: selected, label: '$label time limit',
      child: InkWell(
        borderRadius: Shapes.pill, onTap: onTap,
        child: AnimatedContainer(
          duration: Motion.of(context).d(Durations2.toggleTrack), curve: Curves2.enter,
          constraints: const BoxConstraints(minHeight: 42),
          padding: const EdgeInsets.symmetric(horizontal: Space.x16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? c.brandInk.withValues(alpha: .14) : c.textPrimary.withValues(alpha: .04),
            borderRadius: Shapes.pill,
            border: Border.all(color: selected ? c.brandInk : c.textPrimary.withValues(alpha: .16), width: selected ? 1.5 : 1),
          ),
          child: Text(label, style: t.labelLarge?.copyWith(color: selected ? c.brandInk : c.textPrimary)),
        ),
      ),
    );
  }
}

class _SupportRule extends StatelessWidget {
  final IconData icon; final String text;
  const _SupportRule({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 16, color: context.colors.textSecondary),
        const SizedBox(width: Space.x8),
        Expanded(child: Text(text, style: context.type.bodySmall?.copyWith(color: context.colors.textSecondary))),
      ]);
}

/// Access log entries. Admin: `/admin/support-access` (chaho to ek shop ka).
/// Shop owner: `/support-access` (sirf apni shop ka, backend scope karta hai).
class SupportLogBody extends StatefulWidget {
  final String endpoint;
  final bool showShopName;
  /// true = kisi doosre scroll view ke andar (bottom sheet), apna scroll nahi.
  final bool embedded;
  const SupportLogBody({super.key, required this.endpoint, this.showShopName = true, this.embedded = false});
  @override
  State<SupportLogBody> createState() => _SupportLogBodyState();
}

class _SupportLogBodyState extends State<SupportLogBody> {
  List items = [];
  bool loading = true;
  Object? _error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() { loading = true; _error = null; });
    try {
      final r = await Api.getUnscoped(widget.endpoint);
      if (!mounted) return;
      setState(() => items = (r is Map ? r['items'] : r) as List? ?? []);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return GlassCard(blur: false, child: Shimmer(child: Column(children: List.generate(3, (_) => const SkeletonListTile()))));
    }
    if (_error != null) {
      return ErrorState(title: "Couldn't load access log", message: 'Check your internet and retry.', onRetry: _load);
    }
    if (items.isEmpty) {
      return const GlassCard(blur: false, child: EmptyState(icon: Icons.shield_outlined, title: 'No support access yet',
          message: 'When Vktrix Support views shop data, the reason is shown here.'));
    }
    final tiles = [
      for (final item in items)
        SupportLogTile(entry: Map<String, dynamic>.from(item as Map), showShopName: widget.showShopName),
    ];
    if (widget.embedded) {
      return Column(children: [
        for (var i = 0; i < tiles.length; i++) ...[
          if (i > 0) const SizedBox(height: Space.x12),
          tiles[i],
        ],
      ]);
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        shrinkWrap: true,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        itemCount: tiles.length,
        separatorBuilder: (_, __) => const SizedBox(height: Space.x12),
        itemBuilder: (_, i) => tiles[i],
      ),
    );
  }
}

class SupportLogTile extends StatelessWidget {
  final Map<String, dynamic> entry;
  final bool showShopName;
  const SupportLogTile({super.key, required this.entry, this.showShopName = true});
  @override
  Widget build(BuildContext context) {
    final c = context.colors, t = context.type;
    final status = '${entry['status'] ?? 'ended'}';
    final active = status == 'active';
    final reads = (entry['reads'] as num?)?.toInt() ?? 0;
    final reveals = (entry['contact_reveals'] as num?)?.toInt() ?? 0;
    final started = (entry['started_at_ms'] as num?)?.toInt();
    final remainingMs = (entry['expires_in_ms'] as num?)?.toInt() ?? 0;
    final lines = <String>[
      if (showShopName && entry['shop_name'] != null) '${entry['shop_name']}',
      '${active ? agoFrom(started) : shortStamp(started)} · ${entry['minutes']} min session',
    ];
    return GlassCard(blur: false, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 40, height: 40,
          decoration: BoxDecoration(color: (active ? c.brandInk : c.textSecondary).withValues(alpha: .12),
              borderRadius: BorderRadius.circular(Radii.md)),
          child: Icon(active ? Icons.shield_outlined : Icons.shield,
              size: 20, color: active ? c.brandInk : c.textSecondary)),
        const SizedBox(width: Space.x12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${entry['reason'] ?? ''}', style: t.titleSmall, maxLines: 3, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(lines.join(' · '), style: t.bodySmall?.copyWith(color: c.textSecondary),
              maxLines: 2, overflow: TextOverflow.ellipsis),
        ])),
        const SizedBox(width: Space.x8),
        StatusChip(
          label: active ? 'ACTIVE ${clock(Duration(milliseconds: remainingMs))}' : status.toUpperCase(),
          tone: active ? ChipTone.brand : status == 'expired' ? ChipTone.neutral : ChipTone.success,
        ),
      ]),
      const SizedBox(height: Space.x12),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: Space.x12, vertical: Space.x8),
        decoration: BoxDecoration(color: c.textPrimary.withValues(alpha: .04), borderRadius: Shapes.md,
            border: Border.all(color: c.textPrimary.withValues(alpha: .08))),
        child: Wrap(spacing: Space.x16, runSpacing: Space.x4, children: [
          _LogFact(icon: Icons.person_outline, text: '${entry['admin_name'] ?? 'Super Admin'}'),
          _LogFact(icon: Icons.visibility_outlined, text: reads == 0 ? 'No data opened' : 'Viewed ${reads}×'),
          _LogFact(icon: reads == 0 ? Icons.contacts_outlined : Icons.contact_phone_outlined,
              text: reveals == 0 ? 'Contact hidden' : 'Contact revealed ${reveals}×'),
        ]),
      ),
    ]));
  }
}

class _LogFact extends StatelessWidget {
  final IconData icon; final String text;
  const _LogFact({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 15, color: c.textSecondary),
      const SizedBox(width: Space.x4),
      Text(text, style: context.type.labelSmall?.copyWith(color: c.textSecondary)),
    ]);
  }
}

/// Poori history ka screen (Super Admin → top bar ka shield button).
class SupportAccessLogScreen extends StatefulWidget {
  final int? shopId;
  final String? shopName;
  const SupportAccessLogScreen({super.key, this.shopId, this.shopName});
  @override
  State<SupportAccessLogScreen> createState() => _SupportAccessLogScreenState();
}

class _SupportAccessLogScreenState extends State<SupportAccessLogScreen> {
  final scroll = ScrollController();
  @override
  void dispose() { scroll.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.viewPaddingOf(context).top;
    final query = widget.shopId == null ? '' : '?shop_id=${widget.shopId}';
    return Scaffold(
      body: AuroraBackground(child: Stack(children: [
        ListView(
          controller: scroll,
          padding: EdgeInsets.fromLTRB(Space.screen, top + 64 + Space.x8, Space.screen, Space.x32),
          children: [
            GlassCard(blur: false, child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.shield_outlined, size: 20, color: context.colors.brandInk),
              const SizedBox(width: Space.x12),
              Expanded(child: Text(
                  'Super Admins do not have default access to shop data. Every session is reason-based, time-limited, and read-only. Shop owners can view this log in their app.',
                  style: context.type.bodySmall?.copyWith(color: context.colors.textSecondary))),
            ])),
            const SizedBox(height: Space.section),
            SupportLogBody(endpoint: '/admin/support-access$query', showShopName: widget.shopId == null),
            const SizedBox(height: Space.x32),
          ],
        ),
        Positioned(top: 0, left: 0, right: 0, child: GlassTopBar(
            title: widget.shopName == null ? 'Support access log' : 'Access log · ${widget.shopName}', scroll: scroll)),
      ])),
    );
  }
}

/// Shop owner ke Profile se khulne wala sheet (apni shop ka access log).
Future<void> showSupportLogSheet(BuildContext context, {String title = 'Support access'}) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .72,
        minChildSize: .4,
        maxChildSize: .95,
        builder: (ctx, controller) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewPaddingOf(ctx).bottom),
          child: GlassSurface(child: SafeArea(top: false, child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.x20, Space.x16, Space.x20, Space.x8),
              child: Row(children: [
                Expanded(child: Text(title, style: ctx.type.titleLarge)),
                GlassIconButton(icon: Icons.close, semanticLabel: 'Close', onPressed: () => Navigator.pop(ctx)),
              ]),
            ),
            Expanded(child: SingleChildScrollView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(Space.x16, 0, Space.x16, Space.x24),
              child: const SupportLogBody(endpoint: '/support-access', showShopName: false, embedded: true),
            )),
          ]))),
        ),
      ),
    );
