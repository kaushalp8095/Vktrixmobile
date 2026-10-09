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
- **Buy Form**: IMEI likhte hi/scan karte hi Brand, Model, RAM, Storage apne aap bhar jata hai, IMEI valid hai ya nahi (Luhn check), duplicate check, pehle kab aaya tha wo history (catalog miss ho to wahi entry auto-fill karti hai), seller ki details + ID proof
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

#### ⚠️ Free TAC catalog ki limitations (zaroor padhein)
- **Data adhoora hai:** community catalog me bahut se naye aur India-only models (Redmi/Realme/Vivo/Oppo ke naye variants) **nahi** hain. Aise phone pehli baar manually bharne padenge; uske baad app khud seekh lega.
- **Sirf brand + model:** RAM, storage, colour catalog me nahi hote, shop ko khud bharne honge.
- **Naam hamesha marketing name nahi hota:** kabhi model code aata hai (jaise `SM-A515F/DSN` = Galaxy A51), aur ek TAC kai variants cover kar sakta hai.
- **Verified nahi hai:** data crowd-sourced hai, GSMA official nahi. Buy form me aisi entry par chip dikhega *"community data, verify model & fill RAM/storage"*. Kharidne se pehle phone (Settings → About / `*#06#`) se match karein.
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
| GET | /api/imei/:imei | IMEI se phone ki info |
| POST | /api/buy | Phone kharido (stock me add) |
| GET | /api/stock?search= | Stock list |
| GET/PUT/DELETE | /api/phones/:id | Phone detail/edit/delete |
| POST | /api/sell | Phone becho |
| GET | /api/sales?from=&to= | Sales list |
| DELETE | /api/sales/:id | Sale cancel |
| GET | /api/reports/summary?from=&to= | Report |
| GET | /api/reports/daily?from=&to= | Roz ka report |

Super admin kisi bhi shop API me `?shop_id=` laga kar us shop ka data dekh sakta hai.
