# Full project audit — 23 Oct 2026

Scope: `app/lib` (30 files, 8,982 lines), `app/android`, `backend/src` (13 files, 1,964 lines),
API contract between the two. Reviewed file by file: design tokens → components → screens →
API wrapper → backend routes/validation/migrations → packaging (manifest, updater, release workflow).

Legend — **P0** breaks production or security, **P1** wrong data / broken flow, **P2** polish, perf,
maintainability. "Fixed" means the fix is in this PR; everything else is documented with a concrete fix.

---

## P0

### 1. JWT signing falls back to a public secret — forged super-admin tokens
`backend/src/auth.js:3`

```js
const SECRET = () => process.env.JWT_SECRET || 'dev_secret';
```

`render.yaml` generates `JWT_SECRET`, but any other deployment (a fork, a self-host, a restored
env, a local run exposed on a LAN) silently signs every token with `dev_secret`. Anyone who reads
this repository can mint `{role:'superadmin'}` and read every shop through the support endpoints.

**Fix:** refuse to start in production without a real secret; keep the fallback only for
`NODE_ENV=test`. *(fixed)*

### 2. Super admin seeded with a known default password
`backend/src/migrate.js:216`

```js
password_hash: bcrypt.hashSync(process.env.SUPERADMIN_PASSWORD || 'Admin@123', 10)
```

`render.yaml` marks `SUPERADMIN_PASSWORD` as `sync: false` — it is **optional** for Render. If the
operator forgets it, the internet-facing panel boots with `superadmin / Admin@123`.

**Fix:** in production, fail the boot (with a clear message) instead of seeding a default; outside
production generate a random password and print it once. *(fixed)*

---

## P1

### 3. No request timeout — one stalled request freezes a screen forever
`app/lib/api.dart:69-80`

Every call is `await http.get(...)` with no `.timeout()`. On a cold Render instance, a captive
Wi-Fi portal, or a dying connection the future never completes; the screen keeps its skeleton /
spinner and the user has no retry that can run (the same page awaits again). `update_checker.dart`
already uses `.timeout(10s)` — the API layer does not.

**Fix:** 30 s timeout on all five verbs, mapped to "The server did not respond. Check your internet
and try again." *(fixed)*

### 4. `_parse` assumes the body is a JSON object
`app/lib/api.dart:58-63`

```dart
final body = r.body.isEmpty ? null : jsonDecode(r.body);
if (r.statusCode >= 400) throw Exception(body?['error'] ?? 'Error ${r.statusCode}');
```

* A proxy/502/HTML error page makes `jsonDecode` throw `FormatException` — the user sees
  `FormatException: Unexpected character (at character 1)`.
* A JSON **array** body makes `body?['error']` throw `NoSuchMethodError` inside the error path,
  masking the real status.
* Success bodies that are not JSON also throw a raw codec error.

**Fix:** decode defensively, only read `error` from a `Map`, always fall back to HTTP status. *(fixed)*

### 5. Expired/revoked session is a dead end
`app/lib/api.dart:58-63`, every screen's `_load()`

Nothing handles `401`. When the 30-day token expires, or the password is changed on another device
(`token_version` bump), every tab shows "Couldn't load …" with **no route back to login** — Profile →
Log out is the only escape, and the Profile screen itself is reached from the dashboard the user
cannot load. Reproduction: log in on two phones, change the password on one, pull-to-refresh on the
other.

**Fix:** a single `Api.onUnauthorized` hook fired from `_parse`; `main.dart` clears the session and
routes to `LoginScreen` once. *(fixed)*

### 6. Support mode "locks" the data but leaves it on screen
`app/lib/screens/shop_home.dart:113-118,180`

```dart
final locked = _readOnly && expired;
IgnorePointer(ignoring: locked, child: PageView(...))
```

When the session expires the banner says "Support access expired · Shop data is locked", yet the
dashboard, stock, sales and customer names stay fully visible — only taps are blocked. That
contradicts the support-access promise shop owners are shown (`docs/D6_SUPPORT_ACCESS.md`).

**Fix:** replace the page content with a lock/blur surface when expired. *(fixed)*

### 7. Buy form: stale IMEI lookup overwrites a newer one
`app/lib/screens/buy_form.dart:106-118,330`

`onChanged: _lookup` fires as soon as 15 digits are present; there is no debounce and no
"is this still the current IMEI?" check after `await`. On a slow network: scan IMEI **A**, correct it
to IMEI **B**, B's lookup returns first, then A's response lands and rewrites brand/model/options.
The operator saves a phone whose recorded model does not match its IMEI.

**Fix:** generation counter + compare against the live field text before applying. *(fixed)*

### 8. `setState` after dispose on delete/save paths
`app/lib/screens/stock.dart:57`, `sales.dart:74`, `admin_home.dart:194,252`, `tac_catalog.dart`

```dart
try { await Api.delete(...); _load(); } catch (e) { ... }
```

`_load()` starts with an unguarded `setState`. If the user leaves the screen while the delete is in
flight, `setState() called after dispose()` is thrown. The `toast` above it is guarded, the reload
is not.

**Fix:** guard `_load()` entry with `if (!mounted) return;` in these screens. *(fixed)*

### 9. Error toasts use a raw `Colors.red`
`app/lib/screens/common.dart:23`

```dart
SnackBar(content: Text(...), backgroundColor: err ? Colors.red : null)
```

`Colors.red` (#F44336) is not `AppColors.error` (#DC2626 light / #F87171 dark); every failure toast
and every validation toast in the app is off-palette in both themes — the exact "colour match"
problem, 39 call sites deep. In dark mode it is also brighter than the token.

**Fix:** use the resolved `AppColors.error` background + `colorScheme.onError` text. *(fixed)*

### 10. Server URL: message says `https://`, code accepts anything starting with `http`
`app/lib/screens/login.dart:135`, `app/lib/screens/profile.dart:163-170`, `app/lib/api.dart:82-86`

* `startsWith('http')` accepts `http://…` (password in clear text) and junk like `httpfoo`.
* `Api.setServer` only strips trailing slashes: entering `https://` stores `https:` and **every**
  request fails afterwards, with no "reset to default" in the Server dialog.
* `AndroidManifest.xml:9` sets `usesCleartextTraffic="true"` for release builds, so plain HTTP login
  attempts are not even blocked by the platform.

Reproduction: Profile → Server → `https://` → Save → log out → login can never succeed again
without retyping a correct URL.

**Fix:** validate with `Uri.parse` + require `http/https` and a host, show the error inline, add a
"Use default server" action; report the cleartext issue (fix needs a decision on LAN servers).
*(partly fixed)*

### 11. App version is hardcoded in Profile
`app/lib/screens/profile.dart:176` — `'Vktrix Mobile · v1.0'`

Actual build is `1.0.0.20769` (release workflow passes `--build-number`). Every screenshot a shop
sends for support says "v1.0", so the updater/backend generation cannot be identified.

**Fix:** `PackageInfo.fromPlatform()`, with the pubspec value as fallback. *(fixed)*

### 12. Customer invoices round paise away
`app/lib/api.dart:113-116` (`rs()` uses `toStringAsFixed(0)`), used by
`billing/receipt_document.dart:117,187`

Prices are stored with 2 decimals (`validation.js: decimalMoney`), the ledger keeps them, but the
printed invoice shows ₹12,501 for a ₹12,500.50 sale. On the one document a customer keeps, the total
does not match the books.

**Fix:** `rs()` ab rupees + paise cents me ginta hai — poore amount par `₹12,500`, paise hone par
`₹12,500.50` (`.00` force nahi hota). Ek hi formatter poore app me (invoice, ledger, receipts), to
kisi bhi screen par books se alag number nahi aa sakta. Tests: `app/test/money_format_test.dart`
+ PDF build test. *(fixed in the follow-up PR)*

### 13. Deleting a shop destroys its support audit trail
`backend/src/routes/admin.js:110-125`

The hard delete removes `support_access`, `sale_payments`, `sales`, `phones`, `users`, `shops` — so
the record of *who looked at this shop's data*, which the owner is promised, disappears with the
shop. It also allows wiping a shop that has thousands of sales in one tap.

**Fix:** hard delete sirf **khaali** shop par — `phones` / `sales` / `support_access` me ek bhi row
ho to `DELETE /admin/shops/:id` 409 `shop_has_history` deta hai aur app "Deactivate shop" ka raasta
dikhata hai. List me `can_delete` flag aata hai, isliye button pehle hi chhup jata hai.
`backend/test/shop_delete.test.js` in sab cases ko cover karta hai. *(fixed in the follow-up PR)*

### 14. Keyboard covers the Buy/Sell forms
`app/lib/screens/shop_home.dart:122`, `app/lib/screens/sell_form.dart:184`

Both scaffolds set `resizeToAvoidBottomInset: false` while the manifest asks for
`windowSoftInputMode="adjustResize"`. The page viewport therefore keeps its full height under the
IME: with the cursor in "Notes"/"Address" the field, and the primary button on Sell, sit behind the
keyboard. Flutter's `ensureVisible` scrolls to a rect that includes the keyboard area, so focusing
the last field does not bring it into view.

**Fix:** shrink the page by `MediaQuery.viewInsetsOf(context).bottom` so the scroll view ends above
the keyboard. *(fixed)*

### 15. Password-change dialog bypasses the design system and leaks controllers
`app/lib/screens/profile.dart:41-58`

A stock `AlertDialog` with three `TextFormField`s — square corners, default indigo, default text
colour — next to glass cards and Manrope type. The three `TextEditingController`s are never disposed.
The same pattern appears in `admin_home.dart:108-198` (7 controllers),
`admin_home.dart:203`, `tac_catalog.dart:107`, `receipt.dart:87` (WhatsApp fallback).

**Fix:** naya `design/components/glass_dialog.dart` (`GlassDialogCard` + `GlassDialogActions` +
`showGlassDialog` / `showGlassFormDialog`), aur `ConfirmDialogCard` bhi wahi chrome use karta hai.
Chhe AlertDialog (shop form, reset password, change password, server address, WhatsApp fallback, TAC
sync) ab isi glass shell me hain; saare controllers dispose hote hain, forms ke andar hi validate
hote hain, aur poora card scrollable hai (200 % text scale + keyboard). *(fixed in the follow-up PR)*

### 16. Dashboard shows a loss as `+-₹500` in green
`app/lib/screens/dashboard.dart:311`

```dart
if (item.isSale) Text('+${rs(item.profit)}', color: c.successInk)
```

`rs(-500)` already prints the minus sign, so the row reads `+-₹500`, coloured as a success. Sell
form handles this correctly (`profit >= 0 ? '+… profit' : '… loss'`) — the dashboard copy was missed.

**Fix:** sign-aware label + `errorInk` for losses. *(fixed)*

### 17. "Recent activity" is not chronological
`app/lib/screens/dashboard.dart:74-86`

Purchases keep `id`, sales are remapped to `1000000 + id`, then everything is sorted by that number.
Every sale therefore sorts above every purchase: a phone bought this morning can be pushed out of
the five visible rows by a sale from last month. The row subtitle calls it "Recent activity".

**Fix:** sort by date, then id. *(fixed)*

---

## P2

| # | Where | Issue | Fix |
|---|-------|-------|-----|
| 18 | `dashboard.dart:62-70` | Every Home load fetches `/stock`, `/sales` (all rows, unbounded), `/reports/summary`, `/ledger/summary`; only 4 rows are used. `/sales` also runs `withPaymentTotals` over every sale. | Add `?limit=` to `/sales`/`/stock` or a `/dashboard` endpoint. |
| 19 | `design/components/primary_button.dart:82,120` | Fixed `height: _h` with `softWrap: true`; a two-line label at 200 % text scale overflows. | `minHeight` + intrinsic height. *(fixed)* |
| 20 | `buy_form.dart:634`, `sell_form.dart:227,369` | `Container(height: 56)` around dropdown/date text. | `ConstrainedBox(minHeight: 56)` + padding. *(fixed; also `reports.dart:163` range chip, `profile.dart:243` theme tile)* |
| 21 | `billing/receipt_document.dart:155` | `substring(0, 1)` on the shop name splits an emoji (surrogate pair). | `String.fromCharCode(name.runes.first)`. *(fixed)* |
| 22 | `admin_home.dart:201-216` | "Reset password" closes on a too-short password and loses what was typed; no validator. | Validate inside the dialog like `_shopForm`. *(fixed)* |
| 23 | `sell_form.dart:251-270` | Choosing Credit then back to Cash leaves "Received" at 0, so the cash sale is recorded as fully unpaid. | Reset to the price when leaving Credit. |
| 24 | `sell_form.dart:240` | `maxLength: 10` on Mobile blocks `+91 98765 43210` even though the backend accepts it. | Strip spaces/`+91` on paste, or raise the limit. |
| 25 | `backend/src/support.js:170-190` | Comment says "30 din ka total"; `summaryByShop` counts all sessions ever. | Fix the comment or filter by 30 days. |
| 26 | `shop_home.dart:85-95` | "End" on an already-expired session gets a 404 from the server, shows an error, and leaves the client in support mode. | Treat 404 as success (`Api.endSupport()`). |
| 27 | `screens/common.dart:64-96` | `field()` and `statCard()` are dead pre-design-system helpers (raw `Colors.grey`, Material `Card`). | Delete them. *(fixed)* |
| 28 | `app/lib/api.dart:73-74` | `getUnscoped` builds its URL by hand, bypassing `_u` (no encoding, no query support). | Route through `_u` with a flag. |
| 29 | `backend/src/migrate.js:196` | `UPDATE sales SET buy_price_at_sale …` runs on every boot (full-table write). | Guard with a `NULL`-row check. |
| 30 | `backend/src/migrate.js:98` | No unique index on `(shop_id, imei)`; duplicate in-stock IMEI is prevented only in JS, so two concurrent buys can both pass. | Unique partial index. |
| 31 | `dashboards/_load` | A failed pull-to-refresh replaces good data with `ErrorState` (dashboard, stock, sales, reports). | Keep stale data + a non-blocking error banner. |

---

## Fixed in the first audit PR

P0 #1, #2 · P1 #3, #4, #5, #6, #7, #8, #9, #10 (validation + reset), #11, #14,
#15 (controller leak), #16, #17 · P2 #21, #27.

## Fixed in the follow-up PR (the four deferred decisions)

#12 invoices keep paise · #13 only empty shops can be deleted · #15 all six dialogs on the glass
shell + controller disposal · #19/#20 fixed heights become minHeight + padding · #22 reset-password
validator. 200 % text-scale widget tests: `app/test/text_scale_test.dart` (Buy, Sell, Reports,
Profile, Stock + both dialog kinds).

New tests: `backend/test/security_defaults.test.js` (5), `app/test/api_response_test.dart` (6),
`app/test/dashboard_activity_test.dart` (3), `app/test/buy_lookup_race_test.dart` (1).
Existing backend suite: 61/61 local; Flutter analyze + full widget/golden suite green in CI.

The "Update goldens" bot refreshed 10 PNGs for this branch; pixel comparison against the previous
files shows ≤ 0.22 % of pixels changed with a mean channel delta < 0.12/255 — font antialiasing
noise, not layout drift. None of the fixed screens changes its layout at rest.

## Checked and found correct

* **No colour mismatches outside `common.dart`**: every screen resolves `context.colors` /
  `context.scheme`; raw black/white exists only where it is justified (camera viewfinder,
  gradient CTA card). `AppColors.brandGradient` (2 stops, hue gap ≤ 45°) is used only for the
  support banner/hero, as documented. No `withOpacity` (deprecated) left.
* **`pageTransitionsTheme` with only Android** is fine — other platforms fall back to the framework
  defaults.
* **Money validation** is enforced server-side (`saleData` rejects `amount_received > sell_price`,
  `paymentData` rejects overpayment against the remaining due, decimals limited to 2).
* **Support access is genuinely read-only**: the guard in `shop.js` rejects every non-GET for a
  super-admin session, and every read increments the coalesced `read_count`.
* **One sale per phone** is enforced by a unique index plus a conditional update inside the
  transaction; `/sell` handles the unique-violation race with a 409.
* **Scanner lifecycle** (single start owner, generation-keyed controllers, lens fallback) is
  consistent; no double-start path found.
* **Goldens** no longer depend on `DateTime.now()` for the dashboard (the `greeting` test hook is
  used); form default dates remain a known determinism risk for new golden tests.

---

## Reproductions worth keeping in QA

1. **Support expiry** — start a session for 15 min, open the shop shell, wait for the countdown to
   hit 00:00 → data must disappear (today it stays).
2. **Stale IMEI** — throttle the network (or stop the backend), type IMEI A, clear it and type IMEI B
   before A returns → brand/model must stay B.
3. **Session revoked** — change the password on phone 1, pull-to-refresh on phone 2 → app must land
   on Login, not on "Couldn't load dashboard".
4. **Cash sale with empty Received** — clear the pre-filled amount, save → ledger shows the full
   balance due on a "Cash" sale (P2 #23).
5. **Invoice with paise** — sell at ₹12,500.50, open the PDF → total prints ₹12,501 (P1 #12).
