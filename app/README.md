# Vktrix Mobile — Flutter app

Purane mobile ki kharid/bikri ka poora kaam: Buy, Stock, Sell, Udhaar ledger, Reports,
PDF bill, TAC (IMEI) catalog, aur Super Admin ka shop management.

## Structure

```
lib/
  api.dart                     HTTP client + session (token, user, support session)
  main.dart                    MaterialApp, theme, splash → login/shop/admin routing
  design/                      Aqua Emerald design system (locked tokens, glass, motion)
    colors.dart dimens.dart theme.dart typography.dart glass.dart motion.dart
    components/                GlassCard, PrimaryButton, StatusChip, AnimatedTabBar,
                               AuroraBackground, GlassTopBar, ConfirmDialog, …
  billing/                     Customer-safe PDF bill + share (WhatsApp/other apps)
  documents/                   ID-proof photo compress (isolate) + validation
  update/                      In-app update (version.json → APK download + install)
  screens/
    splash.dart onboarding.dart login.dart
    shop_home.dart             Shop shell (5 tabs) + support-mode bar
    dashboard.dart buy_form.dart stock.dart sell_form.dart sales.dart
    ledger.dart reports.dart receipt.dart scanner.dart profile.dart
    admin_home.dart            Super Admin: shops + support access
    support_access.dart        Support session dialog, access log (admin + shop side)
    tac_catalog.dart           TAC catalog sync (Super Admin)
    update_checker.dart        Update prompt
test/                          Widget + golden tests (see ../README.md)
goldens/                       Committed PNGs for the golden tests
```

## Do zaroori rules

1. **Colour, spacing aur timing sirf `lib/design/**` se aate hain.** Screen me hard-coded
   colour ya duration mat likhein — token add karein.
2. **Super Admin ke paas shop ka business data default me nahi hota.** Uske liye
   `support_access.dart` ka reason + time-limit wala session zaroori hai, aur wo
   read-only hai (`Api.supportReadOnly`) — screen par likhne wale action
   `supportReadOnlyBlock()` se rok kar wajah dikhayein. Detail: `../docs/D6_SUPPORT_ACCESS.md`.

## Chalane ka tarika

```bash
flutter pub get
flutter analyze
flutter test                 # goldens compare (5% tolerance)
flutter test --update-goldens   # layout badla ho to (diff review karna zaroori hai)
flutter run                  # debug
flutter build apk --release  # signed APK (CI: .github/workflows/auto-release.yml)
```

Goldens CI se bhi refresh hote hain: `.github/workflows/update-goldens.yml`
har `app/lib/**` / `app/test/**` badlav par chal kar PNGs wapas branch me commit kar deta hai.
