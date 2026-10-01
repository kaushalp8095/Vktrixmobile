# D4 — Before → After rationale

Old app (v1, functional Material default) vs redesigned app (Indigo Mint design system).
Git history shows both: pre-redesign code is in commits up to `2718b79`; redesign starts at `a7b5053`.

Every change below traces to the design brief's locked tokens (D1) and components (D2) — no new color,
spacing, or timing was invented while redesigning screens (D3).

---

## Global

| Before | After | Why |
|---|---|---|
| Default Material theme, Roboto, scaffold grays | Indigo Mint tokens, Manrope 400–800, aurora background | Brand identity + calmer reading; aurora uses radial gradients (zero real-blur cost) |
| Flat white/colored cards | One glass recipe (GlassSurface) everywhere | One physics model for the whole UI: blur ≤3 nodes/screen, translucent fill, hairline gradient border |
| Instant/snappy system curves | 4 springs (micro/emphasis/standard/slow) + 320/200ms shared-axis nav | Motion now communicates cause → effect (tap → press, save → success) instead of decoration |
| `Colors.green/red/orange` ad hoc | `ChipTone` statuses: 12% fill, 24% border, dark ink + icon | Status never relies on color alone (color-blind safe); measured AA contrast |
| No haptics | tick/tap/success(double-tick)/error(strong) mapped to interactions | Confirm actions are felt, not just seen |
| No reduced-motion support | `Motion.of(context)` — springs→instant, loops stop | Accessibility + respects OS setting |
| No dark-mode-specific recipe | Separate dark glass tokens (weaker highlights, stronger scrim) | Dark glass stays readable, neon-free |

## Splash → Login

| Before | After | Why |
|---|---|---|
| Straight to plain login screen | Brand mark springs in (slow spring), wordmark fades, then route by session | One 1.2s brand moment; no fake spinner — session check happens during it |
| Login = plain column of grey fields | Greeting headline + one blurred glass card + primary button | One focal action; only 1 blurred node on the screen (perf budget) |
| Server URL field always visible | Collapsed "Server settings" (preset to production), server also editable in Profile | Shop owners should never need to think about the server |
| Errors as red Snackbars | Error StatusChip in card (live region) + button shake | Error appears where you were looking; TalkBack reads it automatically |

## Home (Dashboard)

| Before | After | Why |
|---|---|---|
| 4 equal stat cards + 2 buttons | Greeting → stock-value hero (biggest number) → Buy/Sell quick actions → Today → Recent activity | Reading order = owner's questions: what do I hold → what happened today → what happened lately |
| CircularProgressIndicator while loading | Shimmer skeletons shaped like the real content | No layout jump when data lands; skeleton announces "Loading" once |
| Generic AppBar + logout icon | GlassTopBar (transparent → blur on scroll), refresh + profile actions | Top bar earns its blur only when content is behind it; logout moved to Profile |
| System bottom NavigationBar | Floating glass tab bar, 16dp margins, spring indicator | Indicator slides/stretches with physics; bar floats over content like a control you hold |
| Hard Hindi labels ("Aaj ka hisaab") | English copy everywhere, consistent terms (Buy/Sell/Stock/Sales) | Locked brief: English-only UI |

## Buy form

| Before | After | Why |
|---|---|---|
| One long flat form | 3 grouped cards: Phone details → device → price/date, then Seller details | Grouping matches how a deal actually happens: phone first, seller second |
| IMEI status as colored text line | StatusChip states: found/new-model/invalid/duplicate + "bought N× before" | Duplicate-IMEI warning is impossible to miss and announced by screen reader |
| Save = disabled text change | PrimaryButton phase: collapse → spinner → green tick → navigate | The button itself is the receipt that the phone hit stock |
| Date as plain OutlinedButton | Styled glass row with "Change" affordance + semantic label | Touch target ≥48dp and announced properly |

## Stock → Detail → Sell

| Before | After | Why |
|---|---|---|
| Cards with ListTile, 2-line crammed subtitle | Phone rows: tinted icon, model, spec line, "in stock N days", price, chevron | One row = one glance; age-in-stock nudges which phone to push first |
| Detail = plain bottom sheet of label pairs | Glass sheet: header + status chips + copy-able (SelectableText) rows + Sell CTA | IMEI can be long-pressed and copied (insurance/Police verification needs exact IMEI) |
| Delete directly in sheet | "Remove from stock" red text + confirm dialog | Destructive actions never sit one accidental tap away |
| Sell = separate plain form | Phone summary card pinned top, profit chip updates live as price changes, customer grouped below | Seller sees the deal (buy vs sell vs profit) while typing |

## Sales

| Before | After | Why |
|---|---|---|
| Long-press row to cancel (hidden gesture) | Tap → glass detail sheet with full bill + "Cancel sale" + 2-step confirm | Hidden gestures are un-discoverable; cancel returns phone to stock visibly |
| Profit colored text only | Profit text + green/red + sign, date/customer/payment in subtitle | Still redundant (sign + color), plus profit sounds positive feedback when selling well |

## Reports

| Before | After | Why |
|---|---|---|
| 4 stat cards + LinearProgressIndicator rows | Range chips → net-profit hero → custom daily bar chart → payment split → top models | Answers: how much did I earn → which days → how was I paid |
| `LinearProgressIndicator` as fake chart | Hand-painted CustomPainter bar chart (bars animate in) + full TalkBack summary | No chart dependency to break over the app's lifetime; chart is accessible as text |
| Date range row plain chips | Consistent RangeChips with animated selection + custom range dialog | Same component language as the rest of the app |

## Super Admin

| Before | After | Why |
|---|---|---|
| 3 full-width stat cards | 3 compact overview tiles (auto-shrink long numbers) | Scannable dashboard; ₹4,02,500 never overflows |
| ListTile + PopupMenu | Shop rows with active/deactivated visual + organized menu | Tap = open shop's data; destructive actions confirmed twice |
| FAB "Nayi Shop" with big dialog | Same flow, dialog fields use consistent validation copy | One-shot shop creation (shop + login together) |

## Profile & Settings (new) + Onboarding (new)

| Before | After | Why |
|---|---|---|
| No settings at all; logout in AppBar | Profile: shop card, theme (System/Light/Dark), change password, server, logout | Owner control without leaving the app; theme persists |
| First launch = login form | 3-slide onboarding (Buy/Sell/Reports value), shown once | A new shop owner learns the app's value in 20 seconds |

---

## Performance & accessibility summary (applies to all screens)

- **Blur budget**: ≤3 blurred nodes per screen (top bar + hero card + tab bar); inner cards use `blur:false`.
- **Aurora**: radial-gradient blobs + 128px 3%/4% grain, paused in background, static under reduced motion.
- **Targets**: every interactive element ≥48dp; text scales to 200% without clipping.
- **Semantics**: headers marked, live regions for errors/lookups, chart exposes a full data summary.
- **States**: every screen has skeleton → content, plus EmptyState / ErrorState with retry.
