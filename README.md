# 📱 Mobile Shop Management (Purane Mobile ki Kharid/Bikri)

## Technology
| Hissa | Language / Tool | Kyun |
|---|---|---|
| **Android App (Frontend)** | **Flutter (Dart language)** | Google ka framework, ek code se Android (aur baad me iOS/Web) ban jata hai, fast aur stable |
| **Backend (Server/API)** | **Node.js (JavaScript) + Express** | Sabse zyada use hone wala, sasta hosting, lambe samay ka support |
| **Database** | **PostgreSQL** | Bank-level reliable, free, paise ke hisaab-kitaab ke liye sabse safe (transactions) |
| Login security | JWT token + bcrypt password hashing | |

## Features
- **Super Admin**: shops banana, har shop ko alag login dena, shop band/chalu karna, password reset, delete, TAC (IMEI model) CSV import + **do free TAC catalog sync**: Osmocom community list aur **extended India-models list** (Redmi/Realme/Poco/Vivo ke naye variants + internal model code, koi API key/paisa nahi). **Shop ka business data (stock, IMEI, sales, profit, payment ledger, customer/ID proof) usse default me nahi dikhta** — uske liye reason ke saath *temporary, read-only support access* lena padta hai (neeche section dekhein).
- **Shop Login**: sirf apni shop ka data dikhega (dusri shop ka nahi)
- **Buy Form**: IMEI likhte hi/scan karte hi **Brand + Model free me apne aap** bhar jata hai (local TAC catalog, koi external API/paisa nahi), RAM/Storage/Color ke liye **dropdown** (app ke apne purane data se), IMEI valid hai ya nahi (Luhn check), duplicate check, pehle kab aaya tha wo history (**catalog miss ho to wahi entry sab fields auto-fill karti hai**), **Serial number (optional)**, Customer details + ID proof (**photo upload: camera ya gallery**)
- **Save karte hi stock me add** → Stock list me "BECHO" button → Sell form (profit/loss live dikhega)
- **PDF bill + attachment sharing**: Buy/Sell save ke baad branded PDF screen; purane purchase ke liye Stock detail aur purane sale ke liye Sales detail se dobara khol sakte hain. View, Android document picker se Save, WhatsApp par actual PDF attachment, aur other-app share available hai. Bill me shop logo/details, customer, IMEI, amount, date aur sale warranty aati hai; **profit, purchase cost, internal notes, ID number/photos kabhi customer PDF me nahi jaate**.
- **Udhaar ledger**: sale par kitna mila aur kitna baki hai; 0/full/partial collection, har partial payment ki date/mode/note history, outstanding summary, paid/pending filters aur WhatsApp reminder. Payment kabhi sale total se zyada add nahi ho sakta.
- **Sales**: list, payment-due status, detail se PDF/payment ledger, aur sale cancel (phone wapas stock me; linked payment history bhi remove hoti hai)
- **Reports**: Aaj / 7 din / Mahina / Saal / Custom: kharidi, bikri, profit, stock value, payment mode, pending receivables, top models, roz ki sales
- **Back button (Android)**: Buy/Stock/Sales/Reports tab par back = pehle Home tab; Home par 2 second ke andar dobara back = app band. Super Admin jab support session me kisi shop ka data dekh raha ho, tab back seedha shop list par wapas jata hai.
- **Logout confirmation (dono side)**: shop owner aur Super Admin — dono ke liye ek hi popup (Indigo/Mint glass card, brand hairline, account identity). Options: **Stay logged in** aur **Log out**. Logout sirf confirm karne ke baad hota hai; Super Admin pehle seedha logout kar deta tha, ab nahi.

### IMEI auto-fill kaise kaam karta hai
IMEI ke pehle 8 digit (TAC) model batate hain. Database `tac_models` me har row ka `source` save hota hai:

| source | Kahan se aaya | Sync overwrite karega? |
|---|---|---|
| `learned` | Kisi shop ne ye phone kharida (brand/model/RAM/storage) | **Kabhi nahi** |
| `csv` | Super admin ka apna CSV import | **Kabhi nahi** |
| `legacy` / `seed` | Is update se pehle ki rows / sample rows | **Kabhi nahi** |
| `api` | Optional external TAC API (jab `TAC_API_URL` set ho) | **Kabhi nahi** |
| `osmocom` | Free community TAC catalog sync (Osmocom) | Haan, sirf agle Osmocom sync me (brand/model) |
| `tacdb` | Free extended TAC catalog sync (India models, MIT) | Haan, sirf agle extended sync me (brand/model) |

1. Jab bhi koi phone kharida jata hai, uska model/RAM/storage save ho jata hai (`learned`), **agli baar same model par sab auto-fill** (sabhi shops ke liye).
2. **Free TAC catalog sync (Super Admin):** app me Super Admin → top bar ka 🔍 *TAC catalog* button → har catalog ke saath **Sync** button:
   - **Community catalog (Osmocom)** — [tacdb.osmocom.org](http://tacdb.osmocom.org/) ka CSV (brand + model only). 1–2 min.
   - **Extended catalog (India models)** — [MoazEb/tac-database](https://github.com/MoazEb/tac-database) (MIT licence) ka `tac_full.csv` (~2.5 lakh TAC, India/global variants + internal model code jaise `13 5G (2406ERN9CI)`). Pehli baar **3–5 min** lagte hain (bade DB par), uske baad sirf naye/badle rows likhte hain.
   Dono sync background me chalte hain; ek time par ek hi sync chalta hai. Screen par coverage, per-catalog last run (new / updated / kept / skipped), licence/attribution aur error dikhte hain. Sync **kabhi kuch delete nahi karta** aur `learned`/`csv`/`legacy` rows ko **kabhi overwrite nahi karta** (default: ek catalog doosre catalog ki rows bhi nahi chhedta).
   Server me GitHub block ho to mirror bhi hai (`jsDelivr`), aur `TAC_SYNC_TACDB_URL` se apna URL de sakte hain.
3. Super admin apna CSV bhi import kar sakta hai: `POST /api/admin/tac/import` (form field `file`). Format `tac,brand,model[,ram,storage]` (header optional). Khaali columns purani RAM/storage ko blank **nahi** karte. Raw Osmocom export upload karne par wahi non-destructive sync rules lagte hain.
4. **Wahi IMEI dobara aaye to:** `GET /api/imei/:imei` us shop ki apni latest entry (`history[0]`) bhi bhejta hai. Catalog (TAC) miss ho jaye to Brand/Model/RAM/Storage/Color wahin se bhar jate hain aur chip "filled from your earlier entry" dikhata hai; community catalog (`osmocom` / `tacdb` / optional `api`) row me jo RAM/storage missing hote hain wo bhi isi entry se plug hote hain. Jo field aapne khud bhar diya hai use auto-fill **kabhi overwrite nahi** karta.

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
3. Flutter me RAM/Storage/Color ek **text field + dropdown arrow** hain: Indigo/Mint theme wali
   rounded selection sheet (light/dark) me current value highlighted rehti hai. Shop list se
   tap kare ya naya value type kare. Jo bhi save hoga wo agle phone ke liye dropdown me aa jayega.

Koi external API call nahi hoti, koi IMEI server se bahar nahi jata, aur iska koi kharcha nahi hai.

### Customer details + ID photo

- Section ka naam **Customer details** hai (phone jis se kharida jata hai).
  Backend/API me field names `seller_*` hi hain taaki purana data aur reports na tootein.
- **ID proof**: Aadhaar, PAN, Voter ID, Driving Licence, **Visiting Card**.
- **Document photos**: Front aur Back ke alag cards — **Gallery se choose karein** ya **Camera se
  photo lein**. Sirf ek side ya dono sides save kar sakte hain; replace/remove alag-alag hota hai.
  - Photo device par background isolate me compress hoti hai: **target 100 KB/photo**, JPEG quality
    94–80, long edge 1800–1280px (chhoti photo upscale nahi hoti). Text clarity ke liye noisy/detailed
    photos target se badi ho sakti hain. **Actual size + zoom preview** se save se pehle text check karein.
    Lossless quality ki guarantee nahi hai; camera orientation apply hoti hai aur EXIF/GPS strip hota hai.
  - Front/legacy single photo `phones.customer_id_photo` aur optional back photo
    `phones.customer_id_photo_back` me base64 JPEG ke roop me save hoti hai. Purane clients ke liye
    server JPEG/PNG/WebP aur **3 MiB/side** accept karta hai; combined JSON body limit **9 MiB** hai.
  - ⚠️ Base64 se size ~33% badhta hai aur dono photos DB storage leti hain. Zyada volume ke liye DB
    plan badhayein ya S3/Cloudinary jaise object storage me shift karein.
  - Stock/history list responses me photos **nahi** bheji jati. Shop-scoped complete row ke liye
    `GET /api/phones/:id` use karein.
  - **Rollout:** updated app se pehle backend deploy karein; startup migration optional back-photo
    column add karti hai aur purane front photos preserve rehte hain. [Details/tests](docs/buy-documents.md).

### PDF bills, shop logo aur WhatsApp

- Super Admin → shop ke **Edit details** dialog me *Bill logo* choose karein. Logo compressed data URL ke roop me `shops.logo_data` me save hota hai (server cap 768 KB); logo na ho to PDF shop-name initial use karti hai.
- **Buy save** → Purchase PDF; **Stock → phone detail** → *Purchase PDF & WhatsApp*.
- **Sell save** → Sale invoice; **Sales → sale detail** → *PDF bill & WhatsApp*.
- *WhatsApp* Android share intent ko WhatsApp/WhatsApp Business par target karta hai. PDF actual `application/pdf` attachment hoti hai; app recipient select ya Send automatically nahi karti. OEM direct-share failure par wahi PDF system chooser me khulti hai, jahan recipient/app aur Send user select karta hai. *Other apps* bhi system chooser kholta hai.
- APK updates aur bill PDFs ek non-exported `${applicationId}.updates` FileProvider se share hote hain; provider sirf `cache/updates/` aur `cache/bills/` expose karta hai.
- *Save PDF* Storage permission nahi maangta: Android ka `ACTION_CREATE_DOCUMENT` picker user ko location/file-name choose karne deta hai.
- Stock aur Sales detail sheets background ko dim nahi karti, lekin bahar tap karke band ki ja sakti hain. API ke ISO timestamps user-facing details me `YYYY-MM-DD` ke roop me dikhte hain.
- Customer-safe receipt APIs alag allowlist use karti hain. Sale receipt response me buy price/profit/internal notes/ID proof columns hain hi nahi; purchase receipt me ID number/photo aur internal notes nahi hain.

### Udhaar / pending-payment ledger

- Sell form ka **Amount received now** full, partial ya `0` ho sakta hai. `0`/partial sale automatically Udhaar ledger me dikhti hai.
- Har collection `sale_payments` me separate append-only row hai: amount, date, mode aur optional note. Backend transaction current balance lock/check karke overpayment aur cross-shop access rokta hai.
- **Home → Udhaar**, ya **Sales top bar ka wallet icon**: pending/paid/all, customer/model/IMEI search, total outstanding aur collection progress.
- Sale detail/payment detail se partial payment add, complete history, customer-safe PDF aur pre-filled WhatsApp reminder milta hai.
- Existing deployment par migration purane non-credit sales ko fully paid opening entry banati hai; old `credit` rows unpaid rehti hain. Pehle updated backend deploy karein, phir APK.

### Super Admin: manage karein, data sirf support session me

Shop ke liye ye sabse bada security sawal hai: *"admin mera stock, IMEI, sale, profit aur customer ka ID proof dekhta rehta hai?"* Isliye Super Admin ko ab **default me kuch nahi** dikhta.

| Kya | Super Admin ko default | Kaise |
|---|---|---|
| Shop name, status (active/off), login username, owner/address/GST, shop since | ✅ Dikhta hai | `GET /api/admin/shops` |
| Contact number | ⚠️ **Masked** (`98•••••210`) | Full number sirf chalu support session me, aur wo bhi log hokar |
| Stock, IMEI, serial, buy price | ❌ Nahi | `?shop_id=` **403** deta hai |
| Sales, profit, PDF bills, receivables/ledger | ❌ Nahi | 403 |
| Customer details + ID proof photos | ❌ Nahi | 403 |
| "Open as shop" (bina wajah ke andar jhaka) | ❌ **Hata diya gaya** | Ab sirf chalu support session me, read-only |

**Support access kaise kaam karta hai**

1. Super Admin → shop row → **Start support access** → **reason** (min 10 characters) + **time limit** (15 min / 30 min / 1 hour / 2 hours) chunein.
2. Backend `support_access` table me row banata hai: kaun, kis shop ka, kyun, kab tak, `expires_at_ms`.
3. Session ke andar admin shop ko **read-only** dekhta hai (Stock/Sales/Reports/Ledger/PDF khul jaate hain). Buy, sell, payment, edit, delete aur sale-cancel **band** hain — screen par "*Support mode · read-only*" bar countdown ke saath chalti hai, aur backend bhi **403** deta hai (`support_access_read_only`).
4. Time khatam = access khatam (`expires_at_ms` cross hone par wahi query 403). Admin **End access** se turant band kar sakta hai.
5. Session admin ke local app me rehti hai, par **server hi sach hai**: `/api/admin/shops` jab tak chalu grant dikhata hai, tab tak hi app me session maani jaati hai.
6. Sab kuch **log** hota hai: reason, started/expires, kitni baar data padha gaya (`read_count`, 1 minute me kai requests = ek view), aur contact reveal kitni baar hua.
7. **Shop owner bhi wahi log dekhta hai**: Profile → **Support access** → "Vktrix support ne kab, kyun aur kitna data dekha". Isse support chori chhupe nahi hoti.

Backend enforcement (screen se chhupana kaafi nahi):

- `routes/shop.js` ka middleware: `role === 'superadmin'` + `shop_id` → **chalu reason-logged grant** hona zaroori, warna **403** `support_access_required`.
- Us session me bhi sirf `GET` — koi bhi POST/PUT/DELETE **403** `support_access_read_only`.
- Grant shop-scoped hai: shop A ka grant shop B ke liye kaam nahi karta; invalid `shop_id` 400.
- `POST /api/admin/shops/:id/reveal-contact` bhi chalu session ke bina 403 deta hai, aur reveal bhi log hota hai.

Isse purane deployment par kaam nahi rukta: agar kisi ko support chahiye, wo 15 second me reason ke saath session le leta hai — par har baar *likh kar*.

### IMEI scanner `genericError` fix

`mobile_scanner` controller ab `autoStart: false` hai. Pehle widget auto-start aur screen ka manual `start()` ek saath CameraX ko start karte the, jis se kuch Android phones par `genericError` aata tha. Ab camera ka ek hi lifecycle owner hai, overlapping starts guard hote hain aur newer Android camera selector rear-camera variants handle karta hai.

#### ⚠️ Free TAC catalog ki limitations (zaroor padhein)
- **Data adhoora hai:** Osmocom me bahut se naye aur India-only models (Redmi/Realme/Poco/Vivo ke naye variants) **nahi** hain. Isliye extended catalog bhi hai; phir bhi bilkul naya model pehli baar manually bhar na pade — uske baad app khud seekh lega.
- **Sirf brand + model:** RAM, storage, colour catalog me nahi hote — dropdown app ke apne data se
  bharata hai, nahi to shop khud bhar sakta hai.
- **Naam hamesha marketing name nahi hota:** kabhi model code aata hai (jaise `SM-A515F/DSN` = Galaxy A51), aur ek TAC kai variants cover kar sakta hai.
- **Verified nahi hai:** data crowd-sourced hai, GSMA official nahi. Buy form me aisi entry par chip dikhega *"community data, model verify karein"*. Kharidne se pehle phone (Settings → About / `*#06#`) se match karein.
- **Osmocom upstream sirf `http://` deta hai (HTTPS nahi):** isliye sync safety ke liye: file size limit, minimum valid rows check, sab ek transaction me, **koi row delete nahi hoti**, aur shop/CSV data kabhi overwrite nahi hota. Kharab/adhoora download par kuch nahi badalta (run "Failed" dikhega).
- **Extended catalog ka nature:** ye MoazEb/tac-database (MIT) hai — 2.5 lakh rows 2000–2025 tak, jisme purane/overseas variants bhi hain, aur model code brackets me hota hai (`13 5G (2406ERN9CI)`, `SM-A556B`). Kabhi galti bhi ho sakti hai (jaise `9A` vs `9A Sport`), isliye buy form me community chip *"verify model"* dikhata hai. Chipset/bands/release year is app me **sync nahi** hote (sirf brand + model chahiye).
- **Pehla extended sync bhaari hai:** ~2.5 lakh rows ek transaction me jaate hain (chhote chunks me, batch lookups ke saath). Render ke chhote plan par 3–5 min lag sakte hain aur DB kuch MB bada hoga; baad ke syncs bahut tez hote hain (sirf badle rows).
- **Licence:** Osmocom data CC-BY-SA 3.0 hai: *TAC data: Osmocom TAC database (c) Harald Welte and contributors*; extended data MIT: *TAC data: MoazEb/tac-database (MIT)*. Dono ki attribution TAC catalog screen par dikhayi jati hai — aage share karte waqt yahi licence/attribution rakhein.

Optional env (`backend/.env`):
- Osmocom: `TAC_SYNC_URL` (mirror/alternate CSV), `TAC_SYNC_TIMEOUT_MS` (default 120000), `TAC_SYNC_MAX_MB` (default 25), `TAC_SYNC_MIN_ROWS` (default 100).
- Extended: `TAC_SYNC_TACDB_URL` (comma se alag kai mirrors — pehla fail hone par agla try hota hai), `TAC_SYNC_TACDB_TIMEOUT_MS` (default 300000), `TAC_SYNC_TACDB_MAX_MB` (default 30), `TAC_SYNC_TACDB_MIN_ROWS` (default 150000 — isse kam rows aayein to sync "failed" hota hai aur kuch nahi badalta).
- `TAC_SYNC_TACDB_REFRESH_OSMOCOM=true` — extended list ko purani Osmocom rows bhi update karne dena (default off).
- `TAC_API_URL` + `TAC_API_KEY` — optional paid/free TAC API, sirf tab jab local catalog miss ho (per TAC max 1 request). Khaali chhodne par koi request nahi jati.

Kaun-kaunsi free/paid IMEI API hai aur kya-kya free me mil sakta hai: **[docs/FREE_IMEI_APIS.md](docs/FREE_IMEI_APIS.md)**.

### "New model — fill brand & model once" kyon aata hai aur kya karein

Iska matlab sirf itna hai: **ye TAC (IMEI ke pehle 8 digit) abhi tak catalog me nahi hai.** IMEI se
sirf Brand + Model hi mil sakte hain (RAM/storage/colour nahi — upar dekhein), aur wo bhi tabhi jab
TAC pahle se maujood ho. Coverage badhane ke 4 tarike, saste se mehenge ki taraf:

1. **Free catalog sync (pehle ye try karein):** Super Admin → 🔍 *TAC catalog* → **Sync free catalog now**.
   Osmocom ka free data hai, par isme naye aur India-only models (Redmi/Realme/Vivo/Oppo ke naye
   variants) aksar **nahi** hote.
2. **App khud seekh lega:** ek baar aapne brand/model bhar diya to wahi TAC dobara aane par
   auto-fill ho jata hai — aur wo sabhi shops ke liye. Roz ke use me yahi sabse zyada kaam aata hai.
3. **CSV import:** `POST /api/admin/tac/import`, format `tac,brand,model[,ram,storage]`.
4. **TAC API (optional, sirf miss hone par):** `.env` me daalein —
   ```ini
   TAC_API_URL=https://imei.hicelltek.com/api/v1/tac/lookup   # misal
   TAC_API_KEY=                 # provider ka key (agar chahiye)
   TAC_API_METHOD=POST          # ya GET; URL me {tac} likha ho to wahan TAC lag jata hai
   TAC_API_TIMEOUT_MS=4000
   ```
   Ye **sirf tab** call hota hai jab local catalog miss kare, aur jo mile wo `source='api'` ke saath
   save ho jata hai — isliye **har TAC par zyada se zyada ek request, kabhi dobara nahi**
   (HiCellTek ka free tier 100/month kaafi ho jata hai). Community sync in rows ko kabhi overwrite
   nahi karta, aur jo shop ne khud bharaa hai wo hamesha bacha rehta hai.
   Bina `TAC_API_URL` ke ye feature band hai aur koi request jaati hi nahi.

> ⚠️ **Backend deploy hona zaroori hai.** App `lib/api.dart` ke `baseUrl` par jata hai
> (abhi `https://vktrixmobile.onrender.com`). Backend me ye code tabhi kaam karega jab branch
> merge ho kar Render par deploy ho jaye — tab tak purana server chal raha hota hai.

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
| GET | /api/admin/dashboard | Super admin summary (sirf operational counts: shops/active/support open) |
| GET/POST | /api/admin/shops | Shops list (masked contact, koi business data nahi) / nayi shop + login |
| PUT/DELETE | /api/admin/shops/:id | Edit, band/chalu / delete |
| POST | /api/admin/shops/:id/reset-password | Password reset |
| POST | /api/admin/shops/:id/support-access | Temporary support session (`reason` + `minutes`; 201 / 409) |
| DELETE | /api/admin/shops/:id/support-access | Chalu session turant band |
| POST | /api/admin/shops/:id/reveal-contact | Full contact (sirf chalu session me, log hokar) |
| GET | /api/admin/support-access?shop_id= | Access log (kaun/kab/kyun/kitna dekha) |
| GET | /api/support-access | Shop owner ko apni shop ka access log |
| POST | /api/admin/tac/import | TAC CSV import |
| GET | /api/admin/tac/status | TAC catalog coverage, last sync runs, limitations |
| POST | /api/admin/tac/sync | Free TAC catalog sync shuru (202; pehle se chal raha ho to 409) |
| GET | /api/imei/:imei | IMEI se phone ki info + RAM/storage/color ke dropdown `options` |
| POST | /api/buy | Phone kharido (stock me add) |
| GET | /api/stock?search= | Stock list |
| GET/PUT/DELETE | /api/phones/:id | Phone detail/edit/delete |
| POST | /api/sell | Phone becho (`amount_received` full/partial/0) |
| GET | /api/sales?from=&to= | Sales list + paid amount/balance/status |
| DELETE | /api/sales/:id | Sale cancel + linked payment history remove |
| GET | /api/receipts/purchase/:phone_id | Customer-safe purchase PDF payload |
| GET | /api/receipts/sale/:sale_id | Customer-safe sale PDF payload |
| GET | /api/ledger?status=pending&search= | Udhaar summary/list (`pending`, `paid`, `all`) |
| GET/POST | /api/sales/:id/payments | Partial-payment history / naya collection |
| GET | /api/reports/summary?from=&to= | Report + receivables |
| GET | /api/reports/daily?from=&to= | Roz ka report |

Super admin `?shop_id=` sirf **chalu support session** ke saath laga sakta hai (read-only) — warna shop APIs 403 deti hain. Detail: *"Super Admin: manage karein, data sirf support session me"* section aur `docs/D6_SUPPORT_ACCESS.md`.
