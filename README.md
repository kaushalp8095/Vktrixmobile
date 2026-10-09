# 📱 Mobile Shop Management (Purane Mobile ki Kharid/Bikri)

## Technology
| Hissa | Language / Tool | Kyun |
|---|---|---|
| **Android App (Frontend)** | **Flutter (Dart language)** | Google ka framework, ek code se Android (aur baad me iOS/Web) ban jata hai, fast aur stable |
| **Backend (Server/API)** | **Node.js (JavaScript) + Express** | Sabse zyada use hone wala, sasta hosting, lambe samay ka support |
| **Database** | **PostgreSQL** | Bank-level reliable, free, paise ke hisaab-kitaab ke liye sabse safe (transactions) |
| Login security | JWT token + bcrypt password hashing | |

## Features
- **Super Admin**: shops banana, har shop ko alag login dena, shop band/chalu karna, password reset, delete, har shop ka stock/sales/report dekhna, overall dashboard, TAC (IMEI model) CSV import + **free TAC catalog sync** (Osmocom community data)
- **Shop Login**: sirf apni shop ka data dikhega (dusri shop ka nahi)
- **Buy Form**: IMEI likhte hi/scan karte hi **Brand + Model free me apne aap** bhar jata hai (local TAC catalog, koi external API/paisa nahi), RAM/Storage/Color ke liye **dropdown** (app ke apne purane data se), IMEI valid hai ya nahi (Luhn check), duplicate check, pehle kab aaya tha wo history (**catalog miss ho to wahi entry sab fields auto-fill karti hai**), **Serial number (optional)**, Customer details + ID proof (**photo upload: camera ya gallery**)
- **Save karte hi stock me add** → Stock list me "BECHO" button → Sell form (profit/loss live dikhega)
- **Sales**: list, long-press karke sale cancel (phone wapas stock me)
- **Reports**: Aaj / 7 din / Mahina / Saal / Custom: kharidi, bikri, profit, stock value, payment mode, top models, roz ki sales
- **Back button (Android)**: Buy/Stock/Sales/Reports tab par back = pehle Home tab; Home par 2 second ke andar dobara back = app band. Super Admin jab kisi shop ka data dekh raha ho, tab back seedha shop list par wapas jata hai.

### IMEI auto-fill kaise kaam karta hai
IMEI ke pehle 8 digit (TAC) model batate hain. Database `tac_models` me har row ka `source` save hota hai:

| source | Kahan se aaya | Sync overwrite karega? |
|---|---|---|
| `learned` | Kisi shop ne ye phone kharida (brand/model/RAM/storage) | **Kabhi nahi** |
| `csv` | Super admin ka apna CSV import | **Kabhi nahi** |
| `legacy` / `seed` | Is update se pehle ki rows / sample rows | **Kabhi nahi** |
| `osmocom` | Free community TAC catalog sync | Haan, sirf agle sync me (brand/model) |

1. Jab bhi koi phone kharida jata hai, uska model/RAM/storage save ho jata hai (`learned`), **agli baar same model par sab auto-fill** (sabhi shops ke liye).
2. **Free TAC catalog sync (Super Admin):** app me Super Admin → top bar ka 🔍 *TAC catalog* button → **Sync free catalog now**. Server [Osmocom TAC database](http://tacdb.osmocom.org/) ka CSV download karke naye TAC add karta hai. Sync background me chalta hai (1-2 min); screen par coverage, last run (new / updated / kept / skipped) aur error dikhte hain.
3. Super admin apna CSV bhi import kar sakta hai: `POST /api/admin/tac/import` (form field `file`). Format `tac,brand,model[,ram,storage]` (header optional). Khaali columns purani RAM/storage ko blank **nahi** karte. Raw Osmocom export upload karne par wahi non-destructive sync rules lagte hain.
4. **Wahi IMEI dobara aaye to:** `GET /api/imei/:imei` us shop ki apni latest entry (`history[0]`) bhi bhejta hai. Catalog (TAC) miss ho jaye to Brand/Model/RAM/Storage/Color wahin se bhar jate hain aur chip "filled from your earlier entry" dikhata hai; community (`osmocom`) row me jo RAM/storage missing hote hain wo bhi isi entry se plug hote hain. Jo field aapne khud bhar diya hai use auto-fill **kabhi overwrite nahi** karta.

### RAM / Storage / Color dropdown kaise banta hai

**IMEI me RAM, storage aur colour encoded hi nahi hote** — ye GSMA standard ka hissa nahi hain, isliye
koi bhi TAC database (free ho ya paid) IMEI se ye nahi bata sakta. Sirf iPhone ke liye Apple ka
per-serial lookup asli storage/colour de sakta hai (GSX-type paid service se).

Isliye app ye karta hai:

1. IMEI daalte hi `GET /api/imei/:imei` **Brand + Model free me** local `tac_models` se bhar deta hai.
2. Saath me `options` bhejta hai — `{ram: [...], storage: [...], color: [...]}` — jo **poore app ke
   apne data** se bante hain:
   1. is exact TAC ke liye pichli baar jo bharaa tha
   2. usi model ke liye kisi aur TAC par jo bharaa tha
   3. usi brand ke liye jo bharaa tha
   4. ek chhoti static fallback list (taaki dropdown kabhi khaali na rahe)
3. Flutter me RAM/Storage/Color ek **text field + dropdown arrow** hain: shop ya to list me se
   tap kare, ya naya value type kare. Jo bhi save hoga wo agle phone ke liye dropdown me aa jayega.

Koi external API call nahi hoti, koi IMEI server se bahar nahi jata, aur iska koi kharcha nahi hai.

### Customer details + ID photo

- Section ka naam **Customer details** hai (phone jis se kharida jata hai).
  Backend/API me field names `seller_*` hi hain taaki purana data aur reports na tootein.
- **ID proof**: Aadhaar, PAN, Voter ID, Driving Licence, **Visiting Card**.
- **Upload ID**: tap karne par sheet khulti hai — **Gallery se choose karein** ya **Camera se photo
  lein**. Photo device par hi compress hoti hai (max 1280px, quality 72 → lagbhag 200-350 KB) aur
  base64 data URL ban kar `phones.customer_id_photo` me save hoti hai. Server cap: **3 MB**, sirf
  JPEG/PNG/WebP.
  - ⚠️ Photo DB me base64 me save hoti hai (Render ka disk ephemeral hai, isliye file system reliable
    nahi). Render ka `basic-256mb` Postgres plan me lagbhag 800-1500 photos aayengi — zyada volume ke
    liye DB plan badhayein ya photo ko S3/Cloudinary jaise object storage me shift karein.
  - Stock/sales list responses me photo **nahi** bheji jati (har row me base64 bhejne se response
    bahut bhaari ho jayega). Poori row ke liye `GET /api/phones/:id` use karein.

#### ⚠️ Free TAC catalog ki limitations (zaroor padhein)
- **Data adhoora hai:** community catalog me bahut se naye aur India-only models (Redmi/Realme/Vivo/Oppo ke naye variants) **nahi** hain. Aise phone pehli baar manually bharne padenge; uske baad app khud seekh lega.
- **Sirf brand + model:** RAM, storage, colour catalog me nahi hote — dropdown app ke apne data se
  bharata hai, nahi to shop khud bhar sakta hai.
- **Naam hamesha marketing name nahi hota:** kabhi model code aata hai (jaise `SM-A515F/DSN` = Galaxy A51), aur ek TAC kai variants cover kar sakta hai.
- **Verified nahi hai:** data crowd-sourced hai, GSMA official nahi. Buy form me aisi entry par chip dikhega *"community data, model verify karein"*. Kharidne se pehle phone (Settings → About / `*#06#`) se match karein.
- **Upstream sirf `http://` deta hai (HTTPS nahi):** isliye sync safety ke liye: file size limit, minimum valid rows check, sab ek transaction me, **koi row delete nahi hoti**, aur shop/CSV data kabhi overwrite nahi hota. Kharab/adhoora download par kuch nahi badalta (run "Failed" dikhega).
- **Licence:** data CC-BY-SA 3.0 hai: *TAC data: Osmocom TAC database (c) Harald Welte and contributors*. Attribution TAC catalog screen par dikhaya jata hai; data ko aage public share karein to yahi licence/attribution rakhein.

Optional env (`backend/.env`): `TAC_SYNC_URL` (mirror/alternate CSV), `TAC_SYNC_TIMEOUT_MS` (default 120000), `TAC_SYNC_MAX_MB` (default 25), `TAC_SYNC_MIN_ROWS` (default 100).

---
## 1) Backend chalana
```bash
cd backend
npm install
cp .env.example .env        # DATABASE_URL, JWT_SECRET, super admin password badlein
npm start                    # tables apne aap ban jayengi (migrations additive + idempotent)
npm test                     # backend tests (SQLite temp DB)
```
PostgreSQL par test: `TEST_DATABASE_URL=postgres://.../vktrix_test npm test` (DB naam me `test` hona zaroori).

> **Note (native build):** `better-sqlite3` ko compile karne ke liye node headers chahiye. Agar
> `npm install` nodejs.org se headers download nahi kar paaye, to
> `npm_config_nodedir=<node-install-dir> npm install` use karein.

### Flutter tests — golden files
App ke UI screenshots `app/goldens/*.png` me hain. **Kisi bhi screen ka layout badalne ke baad**
(naya field, row hili, label badla) goldens regenerate karne padte hain.

**Tarika 1 — GitHub Actions se (local me Flutter ki zaroorat nahi):**
`.github/workflows/update-goldens.yml` automatically chal jata hai jab `app/lib/**`, `app/test/**`
ya `app/pubspec.yaml` badle hain. Ye goldens regenerate karta hai, test suite dobara chalata hai,
aur PNGs wapas branch par commit kar deta hai.

**Tarika 2 — local me:**
```bash
cd app
flutter pub get
flutter test --update-goldens     # goldens/*.png overwrite ho jayenge
flutter test                      # sab green
```

⚠️ `flutter test --update-goldens` **saare** goldens dobara likhta hai, sirf badle hue nahi. Chhoti
si rendering drift (Flutter/font version) ki wajah se aisi PNGs bhi badal sakti hain jo 5% tolerance
ke andar pass ho rahi thin — commit se pehle diff me dekh lein ki koi anjaani screen to nahi badli.

Comparison me 5% tolerance hai (`test/flutter_test_config.dart`), par naye fields/rows usse zyada
badalte hain — isliye CI tab tak fail rahega jab tak nayi PNGs commit na ho jayein.

> Note: Actions tab me workflow tab dikhta hai jab wo repository ke **default branch** (`main`) par ho.
> Feature branch par rehne ke dauran use push trigger automatically chala deta hai.
> Bot (`github-actions[bot]`) ke commit se bana CI run "action_required" (approval) ka wait karta hai —
> aisi run ko PR page se manually approve karein, ya branch par apne credentials se koi commit push
> kar dein (nayi run bina approval ke chal jayegi).
Local testing ke liye bina Postgres: `.env` me `DB_CLIENT=better-sqlite3` rakhein.

**Default Super Admin:** `superadmin` / `Admin@123` (`.env` me badlein!)

**Hosting (lifetime ke liye):** koi bhi VPS (Hostinger / DigitalOcean / AWS Lightsail ~₹400-800/mahina) + PostgreSQL + `pm2 start src/server.js` + Nginx + free SSL (Let's Encrypt). Database ka roz backup `pg_dump` se lein.

## 2) Android App banana
```bash
flutter create mobile_shop_app
# is folder ka app/lib aur app/pubspec.yaml usme copy/replace karein
cd mobile_shop_app
flutter pub get
```
`lib/api.dart` me `baseUrl` apne server ka address daalein (e.g. `https://api.myshop.com`).

`android/app/src/main/AndroidManifest.xml` me `<manifest>` ke andar add karein:
```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.CAMERA"/>
```
(Agar server `http://` hai, bina SSL, to `<application>` tag me `android:usesCleartextTraffic="true"` bhi daalein.)

`android/app/build.gradle` me `minSdkVersion 21` (scanner ke liye).

APK banana:
```bash
flutter build apk --release
# file: build/app/outputs/flutter-apk/app-release.apk  → shops ko de dein
```

## App update (in-app, bina browser)
`app/version.json` me nayi `versionCode` aate hi app me **Update available** popup khulta hai. **Update now** dabane par:
1. APK app ke andar hi download hota hai. Popup me live % progress bar, MB, speed aur time-left dikhte hain. **Hide** dabane par download chalta rehta hai.
2. Download ke baad file check hoti hai (poori size + valid APK). Phir Android ka **Install** popup apne aap khulta hai.
3. Pehli baar Android *"Install unknown apps"* permission maangta hai. Settings me *Allow from this source* on karke wapas aate hi install apne aap aage badhta hai.
4. Fail hone par **Retry** milta hai, aur fallback ke liye *Download in browser instead* bhi hai.

⚠️ **Signing zaroori:** Android update tabhi install karta hai jab har release **same key** se sign ho. `auto-release.yml` ab GitHub secrets `ANDROID_KEYSTORE_BASE64`, `ANDROID_STORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` (wahi jo Firebase workflow use karta hai) se sign karta hai. Secrets na hon to release fail hoti hai. Jin phones me purani (random debug-key wali) APK hai, unhe **ek baar** purani app uninstall karke nayi APK install karni hogi. Uske baad har update app ke andar se ho jayega.

Note: download app ke process me chalta hai. App ko kuch der ke liye minimize karna theek hai, lekin app poori tarah band (swipe-kill) karne par download ruk jata hai. Agli baar **Update now** dabane par download fir se shuru hoga.

## API list
| Method | URL | Kaam |
|---|---|---|
| POST | /api/auth/login | Login |
| POST | /api/auth/change-password | Password badlo |
| GET | /api/admin/dashboard | Super admin summary |
| GET/POST | /api/admin/shops | Shops list / nayi shop + login |
| PUT/DELETE | /api/admin/shops/:id | Edit, band/chalu / delete |
| POST | /api/admin/shops/:id/reset-password | Password reset |
| POST | /api/admin/tac/import | TAC CSV import |
| GET | /api/admin/tac/status | TAC catalog coverage, last sync runs, limitations |
| POST | /api/admin/tac/sync | Free TAC catalog sync shuru (202; pehle se chal raha ho to 409) |
| GET | /api/imei/:imei | IMEI se phone ki info + RAM/storage/color ke dropdown `options` |
| POST | /api/buy | Phone kharido (stock me add) |
| GET | /api/stock?search= | Stock list |
| GET/PUT/DELETE | /api/phones/:id | Phone detail/edit/delete |
| POST | /api/sell | Phone becho |
| GET | /api/sales?from=&to= | Sales list |
| DELETE | /api/sales/:id | Sale cancel |
| GET | /api/reports/summary?from=&to= | Report |
| GET | /api/reports/daily?from=&to= | Roz ka report |

Super admin kisi bhi shop API me `?shop_id=` laga kar us shop ka data dekh sakta hai.
