# Security audit — 23 October 2026

Scope: `backend/src` (14 files, ~2,100 lines), `app/lib` (32 files, ~9,000 lines),
`app/android` (manifest, FileProvider, native channels), CI/CD workflows, `render.yaml`,
dependency tree (npm + pub), and the running API contract between app and server.

Method: every route read line by line, every auth/authorization check traced to the SQL it
guards, then attacked on purpose — IDOR, cross-shop access, super-admin privilege escalation,
parameter tampering, brute force, body-size abuse, JWT forgery, MITM assumptions, backup/recovery
paths, and the in-app APK update pipeline. Dependency advisories were pulled live from the npm
registry and the GitHub Advisory Database (pub ecosystem).

Legend — **P0** exploitable by an unauthenticated attacker, **P1** serious but needs an
authenticated/positioned attacker, **P2** hardening. "Fixed" means the fix ships in this PR.

---

## Verdict

**No P0 was found.** Authentication, authorization and SQL injection are solid:

- every query that returns shop data is scoped by `shop_id` derived from the JWT/DB user, never
  from a client-supplied value (`routes/shop.js` `shopId()` / `needShop()`);
- the super-admin read-only support-session guard (`routes/shop.js:20-45`) is enforced in the
  backend, not just hidden in the UI, and it also blocks every non-GET;
- all SQL is parameterised through knex; the four `db.raw(...)` calls use fixed identifiers only;
- every write route validates a strict field allow-list (`Unsupported … field`) before touching
  the DB, so `shop_id`, `id`, `created_by` cannot be mass-assigned;
- password hashes are per-user bcrypt, JWTs carry a `token_version` that a password change/reset
  bumps, and the production boot refuses to start without `JWT_SECRET` / `SUPERADMIN_PASSWORD`.

The real gaps were around the login endpoint (unlimited attempts), the HTTP/Android transport
hardening, and the update pipeline. Those are fixed below.

| Severity | Found | Fixed in this PR |
|---|---|---|
| P0 | 0 | — |
| P1 | 7 | 7 |
| P2 | 9 | 7 (2 accepted with mitigation) |

---

## P1

### 1. Login had no rate limit or lockout — unlimited password guessing
`backend/src/routes/auth.js` (before this PR)

Nothing throttled `POST /api/auth/login`. With shop usernames being guessable
(`krishna`, `ganesh22`) and the old 6-character minimum, an attacker could try thousands of
passwords a minute from one IP. `/auth/change-password` had the same problem for the current
password.

**Fix:** `backend/src/ratelimit.js` (dependency-free fixed-window counters) + two limits on login:
10 attempts / 15 min per **username** (case-insensitive, reset on success) and 100 / 15 min per IP.
`/change-password` is limited to 10 / 15 min per user. Responses are `429` with `Retry-After` and
`code: login_rate_limited`. All values are env-tunable (`AUTH_LOGIN_MAX`, `AUTH_LOGIN_WINDOW_MS`,
`AUTH_IP_MAX`, `AUTH_PASSWORD_MAX`). A global per-IP cap (`RATE_LIMIT_MAX`, default 1000/min) also
stops scraping and accidental request loops. Tests: `backend/test/ratelimit.test.js`,
`backend/test/login_throttle.test.js`.

### 2. Username enumeration and account probing by timing
`backend/src/routes/auth.js:37-41` (before)

`bcrypt.compareSync` only ran when the username existed, so "unknown user" answered in ~1 ms and
"wrong password" in ~60 ms — a free oracle to harvest valid usernames.

**Fix:** an unknown/inactive user now runs a bcrypt comparison against a fixed dummy hash, and a
non-string password does the same. Both paths return the same 401 body.

### 3. The shipped APK allowed cleartext HTTP
`app/android/app/src/main/AndroidManifest.xml`

`android:usesCleartextTraffic="true"` stayed in the release manifest. Every URL the app uses is
HTTPS today, but the flag means one bad URL (a typo in a config, a plugin, a redirected link) is
enough to expose the bearer token or a customer bill on public Wi-Fi. It is also a Play
pre-launch security warning.

**Fix:** `usesCleartextTraffic="false"` + `res/xml/network_security_config.xml` with
`cleartextTrafficPermitted="false"` and system trust anchors. The in-app update fallback also
stopped accepting `http://` links (`update_checker.dart`).

### 4. Login token and shop data could leave the phone via backup
`AndroidManifest.xml`

`allowBackup` defaults to `true`. The JWT is stored in SharedPreferences (`Api.load()`), so an
ADB backup or a cloud backup of a shop's phone contained a valid 30-day session plus the cached
shop/user JSON.

**Fix:** `android:allowBackup="false"`, `android:fullBackupContent="false"`, and
`res/xml/data_extraction_rules.xml` excluding `sharedpref`/`database`/`file`/`external` from
cloud backup **and** device transfer (Android 12+). Asserted in
`app/test/android_file_provider_test.dart`.

### 5. A 9 MB JSON body was parsed on every route, including unauthenticated login
`backend/src/server.js`

`express.json({ limit: '9mb' })` was global. A script could post 9 MB bodies to `/api/auth/login`
and force large allocations before any auth (memory/CPU DoS). The 9 MB is only needed by the six
routes that accept ID photos or a shop logo.

**Fix:** a cheap `Content-Length` guard runs before the JSON parser. Bodies over 128 KB are
rejected with `413 body_too_large` everywhere except `/api/buy`, `/api/sell`, `PUT /api/phones/:id`
and `POST|PUT /api/admin/shops`; multipart uploads keep their own multer cap. The parser still
caps chunked bodies at 9 MB. Test: `security_hardening.test.js`.

### 6. CORS was wide open
`backend/src/server.js`

`app.use(cors())` echoed `Access-Control-Allow-Origin: *` for every origin. The mobile app never
sends an `Origin` header, so this only helped a browser-based attacker: any website's JS could hit
the API with a token it managed to read (e.g. from a shared browser profile or an XSS elsewhere)
and read the response.

**Fix:** no CORS headers at all unless `CORS_ORIGINS` lists exact origins; then only those get
`Access-Control-Allow-Origin`. Mobile requests (no `Origin`) are unaffected. Test:
`security_hardening.test.js`.

### 7. Production runtime was Node 20 (end-of-life April 2026)
`render.yaml`

The service pinned `NODE_VERSION: "20"` and used `npm install` instead of the lockfile-exact
`npm ci`. Node 20 stopped receiving security patches in April 2026, so the API was running on an
unsupported runtime; `npm install` could also resolve outside the reviewed lockfile during a
deploy.

**Fix:** `NODE_VERSION: "22"` (LTS, security support into 2027), `buildCommand: npm ci --omit=dev`,
and `NODE_ENV: production` so the existing `JWT_SECRET` / `SUPERADMIN_PASSWORD` boot guards
actually run on Render (they were keyed on `NODE_ENV`, which Render does not set for you).

---

## P2

| # | Where | Issue | Status |
|---|-------|-------|--------|
| 8 | `backend/src/auth.js` | `jwt.verify` did not pin an algorithm, so the accepted algorithm came from the token header. | **Fixed:** `algorithms: ['HS256']` on verify and `algorithm: 'HS256'` on sign. Forged HS384 token is rejected in `security_hardening.test.js`. |
| 9 | `backend/src/server.js` (error handler) | 5xx responses sent `err.message` to the client — DB connection strings, SQL fragments and library internals could leak. | **Fixed:** 5xx returns a generic message; details go to the server log only. Tested. |
| 10 | `backend/src/validation.js` | Password minimum was 6 characters. | **Fixed:** 8 characters (NIST SP 800-63B; length beats composition). App validators updated. Existing passwords keep working until changed. |
| 11 | `backend/src/db.js` | Managed-Postgres TLS used `rejectUnauthorized: false`, so the DB connection was encrypted but unauthenticated. | **Mitigated:** `DB_SSL_CA` (PEM) now enables full verification; without it the old behaviour is kept (so existing deployments do not break) and a warning is logged at boot. |
| 12 | `backend/src/tac.js` | The Osmocom catalog was downloaded over plain `http://`. | **Fixed:** `https://` for both the CSV and the homepage. A MITM could otherwise inject brand/model text that every shop's Buy form then shows. |
| 13 | `app/lib/update/apk_updater.dart` | The downloaded update APK was checked only for the ZIP magic bytes (`PK`) before being handed to the installer. | **Fixed:** the release workflow publishes `sha256` in `version.json`; the app hashes the download (streamed, so a 20 MB APK never lands in memory) and refuses to install on mismatch, deleting the file. A stale complete file is re-hashed and re-downloaded. Tests: `app/test/update_integrity_test.dart`. |
| 14 | `backend/src/server.js` | `/api` responses had no cache policy. | **Fixed:** `Cache-Control: no-store` on all `/api` responses, so an intermediate proxy/browser cannot retain IMEI/sales/customer JSON. |
| 15 | `render.yaml` / `server.js` | `trust proxy` was unset, so behind Render every request had the proxy's IP. | **Fixed:** `TRUST_PROXY_HOPS` (Render: `1`, default `0`). Rate limiting now keys on the real client. Deliberately not `trust proxy = true`, which would let a client spoof `X-Forwarded-For`. |
| 16 | `backend/src/tacApi.js`, `support.js`, `admin.js` | Third-party TAC lookup is enabled by env URL and consumes a paid quota. | Accepted: super-admin-only config, one request per TAC ever, 4 s timeout, and the global rate limit caps abuse. Documented. |

---

## Checked and found sound

- **IDOR / cross-shop access** — `/stock`, `/phones/:id`, `/sales`, `/ledger`, `/reports/*`,
  `/receipts/*`, `/sales/:id/payments` all filter on the derived `shop_id`; `safety.test.js`
  already locks this for two shops.
- **Privilege escalation** — role comes from the DB row, never from the token payload; admin
  routes are behind `requireRole('superadmin')`; a super-admin without an active support grant
  gets `403` on shop data (and the grant is checked per request, expiry-aware).
- **SQL injection** — knex parameter binding everywhere; `like` searches pass the term as a
  bound parameter; the only `raw` statements use fixed identifiers.
- **Mass assignment** — allow-lists on buy/sell/phone/shop/payment bodies.
- **Money logic** — overpayment rejected with cents arithmetic; sale/phone state changes inside
  transactions with row locks; one-sale-per-phone unique index.
- **File handling** — ID photos/logo are validated as JPEG/PNG/WebP data URLs with size caps
  before decode; PDFs are generated locally and shared through a non-exported FileProvider whose
  path map only exposes `cache/updates` and `cache/bills`; `installApk` re-checks the canonical
  parent directory.
- **Secrets** — no key material in git history (`.env`, `keystore/` are ignored); the only
  credential-shaped file is `google-services.json`, which is public-by-design app config.
- **Dependencies** — `npm audit`: 0 vulnerabilities (also 0 / 0 / 0 / 0 / 0 by severity); GitHub
  Advisory Database for pub: no advisory touches any locked Dart package (`http 1.6.0`,
  `shared_preferences_android 2.4.28`, `archive 4.5.2`, `image 4.12.0` are all above their
  patched versions).
- **CI/CD** — no `pull_request_target`, workflows declare least-privilege `permissions`, release
  signing keys come from secrets and the workflow fails if they are missing.
- **Logging** — no request bodies, tokens or passwords are logged; the app only `debugPrint`s
  error text.

## Accepted risks (with reasons)

1. **Token in SharedPreferences (plaintext).** Android app sandbox + `allowBackup=false` + no
   rooted-device threat model. Moving to `flutter_secure_storage` would need a migration and a
   new platform dependency; the gain is limited on a non-rooted device.
2. **No certificate pinning.** Pinning GitHub/Render certificates would brick the app on the next
   CA rotation and adds no protection against the realistic threat (stolen token). HTTPS + the
   SHA-256 APK check cover the practical cases.
3. **Logout is client-side.** The 30-day JWT stays valid if it was already exfiltrated; a password
   change/reset or admin reset bumps `token_version` and revokes every session. Server-side
   logout-all would sign the shop out of every device — a product decision, not a code one.
4. **Multi-instance rate limiting.** Counters are in-process. This deployment runs a single
   instance; scaling out needs Redis-backed counters (noted in `ratelimit.js`).
5. **Configurable server URL.** The server field exists for self-hosting; a user who is tricked
   into pointing the app at an attacker's HTTPS host would leak credentials. Marked in the docs;
   the default is pinned and shown in the dialog.
6. **ID photos at rest** live base64-in-Postgres. Encryption at rest depends on the managed
   database; field-level encryption would require a key-management story that this app does not
   have yet.

## How this was verified

```
cd backend && npm ci --build-from-source && npm test      # 70/70
```

New backend tests: `ratelimit.test.js` (4), `login_throttle.test.js` (lockout + reset + case
handling), `security_hardening.test.js` (CORS, headers, cache policy, body guard, JWT algorithm
pinning, generic 5xx).

New app tests: `update_integrity_test.dart` (match, tamper, stale file, no-hash, malformed hash),
plus the manifest assertions in `android_file_provider_test.dart`.

Manual spot checks worth doing on a staging build:

1. 11 wrong passwords on one username → `429`, and the correct password is refused until the
   window ends (15 min).
2. A correct login after two wrong ones → counter cleared (no lockout).
3. On a phone: `adb backup` cannot extract app data; flipping the server URL to `http://` is
   rejected before any request leaves the app.
4. Publish a release with a tampered `sha256` in `version.json` → the updater stops at
   "failed its integrity check" and deletes the file.
