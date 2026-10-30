// Glass dialogs ka visual baseline: form (Create shop) aur confirm (Delete shop),
// light + dark. `AlertDialog` se `GlassDialogCard` par aane ke baad dono ek hi
// chrome (brand hairline, icon disc, identity chip, footer) share karte hain —
// ye goldens wahi layout pin karte hain.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_shop/design/components/components.dart';
import 'package:mobile_shop/design/design.dart';
import 'showcase_golden_test.dart' show loadFonts;

Widget _app(bool dark, {required bool form}) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(dark ? AppTheme.darkScheme : AppTheme.lightScheme),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!),
      home: Scaffold(
        body: Builder(builder: (ctx) => Center(child: FilledButton(
          onPressed: () => form
              ? showGlassFormDialog(ctx,
                  title: 'New shop', icon: Icons.add_business_outlined,
                  confirmLabel: 'Create shop',
                  body: (_) => Column(mainAxisSize: MainAxisSize.min, children: [
                    TextFormField(
                        initialValue: 'Krishna Mobiles',
                        decoration: const InputDecoration(labelText: 'Shop name *')),
                    const SizedBox(height: 8),
                    TextFormField(
                        initialValue: 'Krishna Patel',
                        decoration: const InputDecoration(labelText: 'Owner name')),
                    const SizedBox(height: 8),
                    TextFormField(
                        decoration: const InputDecoration(
                            labelText: 'Mobile (new number, optional)',
                            helperText: 'Leave blank to keep the current number.')),
                    const SizedBox(height: 12),
                    Align(alignment: Alignment.centerLeft, child: Text('Shop login',
                        style: ctx.type.titleSmall)),
                    const SizedBox(height: 8),
                    TextFormField(
                        initialValue: 'krishna',
                        decoration: const InputDecoration(labelText: 'Username *')),
                  ]))
              : showConfirmDialog(ctx,
                  title: 'Delete shop permanently?',
                  message: 'Krishna Mobiles — this shop has no stock or sales yet, so it can be '
                      'deleted. This cannot be undone.',
                  confirmLabel: 'Delete forever',
                  cancelLabel: 'Cancel',
                  icon: Icons.delete_forever_outlined,
                  destructive: true,
                  identity: '@krishna · 98•••••210'),
          child: Text(form ? 'Open form' : 'Open confirm'),
        ))),
      ),
    );

void main() {
  for (final form in [true, false]) {
    for (final dark in [false, true]) {
      final kind = form ? 'dialog_form' : 'dialog_confirm';
      testWidgets('$kind ${dark ? 'dark' : 'light'}', (t) async {
        await loadFonts();
        t.view.physicalSize = const Size(1080, 2340);
        t.view.devicePixelRatio = 2.625;
        t.view.padding = const FakeViewPadding(top: 63, bottom: 63);
        t.view.viewPadding = const FakeViewPadding(top: 63, bottom: 63);
        addTearDown(t.view.reset);
        await t.pumpWidget(_app(dark, form: form));
        await t.pump(const Duration(milliseconds: 100));
        await t.tap(find.byType(FilledButton).first);
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));
        expect(find.byType(GlassDialogCard), findsOneWidget);
        await expectLater(find.byType(MaterialApp),
            matchesGoldenFile('goldens/${kind}_${dark ? 'dark' : 'light'}.png'));
        await t.pumpWidget(const SizedBox());
      });
    }
  }
}
