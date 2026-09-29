# 📱 Mobile Shop Management (Purane Mobile ki Kharid/Bikri)

## Technology
| Hissa | Language / Tool | Kyun |
|---|---|---|
| **Android App (Frontend)** | **Flutter (Dart language)** | Google ka framework, ek code se Android (aur baad me iOS/Web) ban jata hai, fast aur stable |
| **Backend (Server/API)** | **Node.js (JavaScript) + Express** | Sabse zyada use hone wala, sasta hosting, lambe samay ka support |
| **Database** | **PostgreSQL** | Bank-level reliable, free, paise ke hisaab-kitaab ke liye sabse safe (transactions) |
| Login security | JWT token + bcrypt password hashing | |

## Features
- **Super Admin**: shops banana, har shop ko alag login dena, shop band/chalu karna, password reset, delete, har shop ka stock/sales/report dekhna, overall dashboard, TAC (IMEI model) CSV import
- **Shop Login**: sirf apni shop ka data dikhega (dusri shop ka nahi)
- **Buy Form**: IMEI likhte hi/scan karte hi Brand, Model, RAM, Storage apne aap bhar jata hai, IMEI valid hai ya nahi (Luhn check), duplicate check, pehle kab aaya tha wo history, seller ki details + ID proof
- **Save karte hi stock me add** → Stock list me "BECHO" button → Sell form (profit/loss live dikhega)
- **Sales**: list, long-press karke sale cancel (phone wapas stock me)
- **Reports**: Aaj / 7 din / Mahina / Saal / Custom: kharidi, bikri, profit, stock value, payment mode, top models, roz ki sales

### IMEI auto-fill kaise kaam karta hai
IMEI ke pehle 8 digit (TAC) model batate hain. Database `tac_models` me:
1. Jab bhi koi phone pehli baar kharida jata hai, uska model/RAM/storage save ho jata hai, **agli baar same model par sab auto-fill** ho jayega (app khud seekhta hai, sabhi shops ke liye).
2. Super admin ek CSV bhi import kar sakta hai (`tac,brand,model,ram,storage`), jaise free Osmocom TAC database: `POST /api/admin/tac/import` (form field `file`).

---
## 1) Backend chalana
```bash
cd backend
npm install
cp .env.example .env        # DATABASE_URL, JWT_SECRET, super admin password badlein
npm start                    # tables apne aap ban jayengi
```
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
