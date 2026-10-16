# D6 — Super Admin support access + ek hi logout popup

Do cheezein jo shop ke liye "bharosa" banati hain: (1) admin ka shop data par access
default me **nahi**, aur jo access hai wo *likhit, time-limited aur read-only*; (2) logout
dono side par ek hi confirmation popup se — galti se tap hone par session band nahi hoti.

---

## 1) Super Admin ke liye kya badla

| Pehle | Ab | Kyun |
|---|---|---|
| `GET /api/admin/dashboard` → shops, stock_count, stock_value, sales_count, sales_value | Sirf `shops`, `active_shops`, `inactive_shops`, `support_active` | Stock value/sales shop ka business data hai — admin ko uski zaroorat nahi |
| `GET /api/admin/shops` → `phone`, `stock_count`, `login`, poora row | `phone_masked` (`98•••••210`), `has_phone`, `login` (username only), `support`, `support_sessions` — **phone aur stock_count kabhi nahi** | Shop ka number aam taur par public hota hai, par data nahi; masked + reveal par control |
| Shop row par tap = **Open as shop** (bina wajah ke poora shop app) | Tap = **management sheet** (basic details + actions). Shop data khulne ke liye **Start support access** (reason + time limit) | "Chupke se andar jhaka" band; har baar ek wajah likhni padti hai |
| Super admin `?shop_id=` laga kar koi bhi shop API chala sakta tha | Chalu support grant ke bina **403** `support_access_required`; session me bhi **sirf GET** | Screen se chhupana kaafi nahi — permission backend me honi chahiye |
| Contact full number list me | `POST /api/admin/shops/:id/reveal-contact` — chalu session me, aur wo bhi log hokar | Reveal bhi ek audit event hai |

### Screen par kya dikhta hai (admin)

- **Overview:** Shops · Active · Support open (business numbers nahi).
- **Info card:** "Shop ka stock, IMEI, sales, profit aur customer details aapko yahan nahi dikhte…".
- **Shop row:** name, `ACTIVE`/`OFF` chip, `@username · 98•••••210`, aur chalu session ho to `SUPPORT 12:00` chip.
- **Shop sheet:** Login, Contact (masked), Owner, Address, GST, Shop since, Support sessions + actions
  (Start support access / Open shop data · read-only / Show full contact / End support access /
  Access log / Edit details / Reset password / Activate-Deactivate / Delete shop).

### Support session ka jeevan-chakra

```
reason + minutes (15/30/60/120)
        │
        ▼
POST /api/admin/shops/:id/support-access ──► support_access row (started_at_ms, expires_at_ms, read_count=0)
        │                                         │
        │  GET shop APIs (stock/sales/ledger/…)   │  har read par read_count++ (1 min me ek "view")
        ▼                                         ▼
   read-only data  ◄── POST/PUT/DELETE par 403 (support_access_read_only)
        │
        ├─ admin "End access"  ──► DELETE /api/admin/shops/:id/support-access  (end_reason=admin_ended)
        └─ expires_at_ms cross ──► status 'expired' (lazy close, access turant band)
```

Rules (backend, `backend/src/support.js` + `routes/shop.js` middleware):

1. Ek shop par ek time par **ek hi** chalu session (dobara start = 409).
2. `reason` min 10 characters, `minutes` 5–240 (app 15/30/60/120 offer karta hai).
3. Grant **shop-scoped** hai. Shop A ka grant shop B ke liye kaam nahi karta; `shop_id` invalid = 400.
4. Session me **write kuch nahi**: buy, sell, payment, phone edit/delete, sale cancel — sab 403.
5. `expires_at_ms` epoch ms me hai (SQLite/PostgreSQL dono par ek jaisa compare).
6. Har response me `expires_in_ms` jaata hai — phone ki clock galat ho to bhi countdown sahi rehta hai.
7. App **server ko hi sach maanti hai**: `/api/admin/shops` jab tak chalu grant dikhata hai, tab tak hi
   local session (`Api.viewShopId`) rehti hai; warna apne aap hat jaati hai.

### Shop owner ko kya dikhta hai

Profile → **Support access** (bottom sheet) — apni shop ka poora log:

- reason, kab shuru hua, kitne minute ka tha, abhi chalu hai ya khatam,
- **kitni baar data khola gaya** (`Viewed 3×` / `No data opened`),
- **contact kab reveal hua** (`Contact revealed 1×` / `Contact hidden`),
- aur kisne dekha (`Super Admin`).

Ye log shop ke login se hi milta hai — `GET /api/support-access` (shop_id query **ignore** hoti hai,
isliye ek shop dusri shop ka log nahi dekh sakta).

---

## 2) Ek hi reusable logout popup (dono side)

`app/lib/design/components/confirm_dialog.dart`

- `showConfirmDialog(...)` — generic Indigo/Mint confirmation. Structure: 4dp brand hairline
  (Indigo→Mint) → icon disc (12% tint + 24% border) → title → message → identity chip → note →
  `[safe action] [confirm action]`. Enter: fade + scale .94→1 (320ms, `Curves2.enter`); reduced motion
  par instant. Barrier tap / back = cancel (`false`).
- `showLogoutDialog(context, identity: ...)` — **Log out?** · *"You'll need your username and password
  to sign back in."* · buttons **Stay logged in** (outlined, safe) aur **Log out** (filled, brand).
  Identity chip batata hai kaun logout kar raha hai (`Krishna Mobiles · @krishna` ya `Super Admin · @superadmin`).

Use hone ki jagah:

| Screen | Pehle | Ab |
|---|---|---|
| Shop owner → Profile → Log out | Simple Material `AlertDialog` (Cancel / Log out) | `showLogoutDialog` (Stay logged in / Log out) |
| Super Admin → top bar logout | **Turant logout, koi confirmation nahi** | `showLogoutDialog` — confirm karne ke baad hi `Api.logout()` |

Wahi component baaki risky decisions me bhi lagta hai (ek hi visual language): shop
Deactivate/Activate, Delete shop permanently, Cancel sale, Remove from stock, End support access.

---

## 3) Tests

**Backend** — `backend/test/support_access.test.js` (11 assertions ke saath 10 subtests):

- masked contact list me full phone kabhi nahi; dashboard me business numbers nahi,
- bina session: stock/sales/ledger/reports/phones/receipts sab par 403 (`support_access_required`),
- reason chhota/`minutes` galat = 400; chalu session par dobara start = 409,
- session ke saath read chal jaata hai aur `read_count` + `last_read_ms` log me aata hai,
- session me buy/sell/payment/edit/delete/cancel — sab 403 aur DB row **untouched**,
- reveal-contact session ke bina 403, session ke saath 200 + `contact_reveals: 1`,
- shop owner apna log dekhta hai, `?shop_id=` doosri shop ka log nahi kholta,
- end/expire hone par turant 403, log me `ended` / `expired`.

**App** — `app/test/logout_dialog_test.dart`:

- shop side Profile: logout popup aata hai, **Stay logged in** par session zinda rehti hai (login screen nahi),
- Super Admin: logout turant nahi hota; wahi `ConfirmDialogCard` khulta hai; admin screen par shop ka
  business data nahi (na "in stock", na "Sales value") par masked contact dikhta hai,
- support mode: shop shell "Support mode · read-only" bar + countdown dikhata hai aur Buy page band karta hai,
- `supportReadOnlyBlock()` shop owner ke apne session me `false`, support mode me `true` + snackbar.

---

## 4) Deploy notes

1. **Backend pehle** deploy karein (`support_access` table migration additive hai — kuch delete nahi hota).
2. Uske baad APK. Purana APK naye backend ke saath: Super Admin ka "Open as shop" 403 dega
   (`support_access_required`) — isliye app update ke saath-saath ye change ship karein.
3. Koi env var ya extra service zaroori nahi; support sessions bina kisi cron ke lazy expire hote hain.
