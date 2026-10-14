# IMEI se data dene wali APIs — free vs paid (practical guide)

Ye document batata hai ki IMEI se **kaun-kaun sa data** milta hai, kaunsa **free** hai,
kaunsa **paise** leta hai, aur is app (`Vktrixmobile`) me kya laga hua hai.

> Prices/limits July–Oct 2026 ke public pages se liye gaye hain. Provider inko badal
> sakta hai — integrate karne se pehle uski site par confirm karein.

---

## 1. Do bilkul alag layer — pehle ye samajhna zaroori hai

| Layer | IMEI ka kya use | Data | Free possible? |
|---|---|---|---|
| **TAC (IMEI ke pehle 8 digit)** | Type Allocation Code — model identify karta hai | Brand, model, kabhi model code / chipset / launch year | **Haan** — open datasets + free-tier APIs |
| **Live device status** | GSMA/carrier databases me lookup | Blacklist/stolen, iCloud/Find My lock, carrier SIM-lock, warranty, FRP | **Nahi** — sab paid (per check $0.05–$5) |

India ki dukaan ke liye **pehla layer hi kaafi hai** (kharidte waqt phone pehchan-na).
Doosra layer (blacklist/warranty) tab chahiye jab aap "verified report" bech rahe ho.

---

## 2. Free TAC / brand+model sources (ye actually chalta hai)

| Source | Kya deta hai | Kitna free | API key | Licence |
|---|---|---|---|---|
| **Osmocom TAC DB** — [tacdb.osmocom.org](http://tacdb.osmocom.org/) | Brand + model | Unlimited CSV (self-host) | Nahi | CC-BY-SA 3.0 |
| **MoazEb/tac-database** — [github.com/MoazEb/tac-database](https://github.com/MoazEb/tac-database) | Brand, model, internal model code, year, region (India/Global tag) | Unlimited CSV/XLSX (~2.5 lakh TAC, 2000–2025) | Nahi | MIT |
| **imeicheck.com free API** — `alpha.imeicheck.com/api/modelBrandName?imei=...&format=json` | Model + brand + name | Public link par Cloudflare CAPTCHA aa gaya; email karke **free personal key (60 req/min)** milti hai | Haan (free) | — |
| **Kelpom IMEI Checker** (RapidAPI) | Brand, model, model number; Apple serial bhi | Free tier: **10 requests/min** | Haan (free signup) | — |
| **HiCellTek IMEI/TAC API** — [hicelltek.com/en/api/imei](https://hicelltek.com/en/api/imei/) | Brand, model, year, bands | **100 lookups/month free**, no card | Haan (free) | — |
| **IMEIAPI.org** | brand, model, code_name, device_type, bands | 7-day trial, 100 lookups/day | Haan (free trial) | — |
| **Zyla API Hub** (IMEI Checker / Mobile Device ID / iPhone lookups) | Brand, model, device type | 7-day trial (~50 requests) | Haan (free trial) | — |
| **apiverve IMEI Generator** (npm/PyPI) | IMEI *generate/validate* (test data) | Open source | Nahi | MIT |

**Note:** free-tier APIs (HiCellTek / imeiapi / Zyla / Kelpom) mostly **wahi** data dete hain jo
upar ke do open CSV dete hain — bas HTTP par, rate limit ke saath. Isliye is app me
pehle **local catalog** check hota hai aur external API sirf **miss** par (per TAC max 1 request),
jisse free quota khatam na ho.

---

## 3. Paid APIs — "asli" device status (blacklist, iCloud, warranty, lock)

| Provider | Kya milta hai | Indicative price |
|---|---|---|
| **GSMA Device Check** (official) | Global blacklist/stolen status (carrier-reported) | ~$0.05–$0.10 per IMEI, verified businesses ke liye |
| **imei.info API v5** — [dash.imei.info](https://dash.imei.info/) | Blacklist, iCloud/FMI, FRP, carrier lock, specs, Apple serial | Credit-based, B2B paid (free plan nahi) |
| **imei.org API** — [imei.org/api-connect](https://imei.org/api-connect) | Apple/Android checks, blacklist, iCloud, carrier, MDM, warranty | Per-service $0.05–$0.15 |
| **iserial.us / imei.eu / CheckMEND / MyMobiCheck** | GSMA blacklist, lock, warranty, iCloud | ~$0.05–£1.50 per check |
| **GSX-type Apple per-serial lookup** (reseller ke through) | Asli **storage + colour**, warranty, purchase date | Per serial, paid |

⚠️ **RAM / storage / colour kisi bhi free (ya sasta) API se nahi milenge.** Ye IMEI me encoded
hi nahi hote (GSMA standard me nahi hain). Is app me ye dropdown app ke apne `learned` data se
bharte hain — jo asli kharid ke baad sabse reliable hota hai.

---

## 4. "Free IMEI check" websites — inka public API nahi hota

`imeilookup.com`, `fullimei.com`, `verimei.com`, `imeicheckpro.com`, `imei24.com`,
`imeicheck.com`, `imei.eu` — ye **web tools** hain:

- 1 free check/day ya "no signup" jaisa offer **browser** ke liye hai, developer API ke liye nahi.
- Inke form ko script se hit karna **ToS violation** hai (aur CAPTCHA/block bhi aata hai).
- Ye apna data **kisi aur ke paid backend** se lete hain — free me API dena unke business model me nahi hai.

Isliye inko app me "badge" ki tarah link kar sakte hain (shop khud check kare), par automate na karein.

---

## 5. India-specific: blacklist check ka official (free) rasta

- **CEIR / Sanchar Saathi** (Government of India, Department of Telecom) — IMEI ka
  lost/stolen/cloned status check karne ka official system hai ("Know your mobile" / Sanchar Saathi app).
  Certificate/status dekhne ka process waqt-waqt par badalta hai, isliye web par current steps dekhein.
  Free hai, par **koi public API nahi** — manual check.
- Police/carrier complaint ke baad IMEI block karwane ka official rasta bhi wahi hai.

Dukaan ke liye practical rule: **CEIR manual check (free) + app ka apna learned data**, aur
grahak se ID proof + "no warranty on stolen device" note. Paid GSMA check tab jab aap bulk me
phone kharid rahe ho bade dealer se.

---

## 6. Is app me kya laga hua hai

| Feature | Layer | Cost |
|---|---|---|
| `tac_models` local catalog + **Osmocom sync** | TAC (brand + model) | Free |
| **Extended catalog sync** (MoazEb/tac-database, India models + model code) | TAC (brand + model) | Free |
| Purchase `learned` rows + customer history auto-fill | TAC + app ka apna data | Free, no external call |
| Optional `TAC_API_URL` (e.g. HiCellTek 100/month free) | TAC on catalog miss | Free tier / paid, **default off** |
| RAM / storage / colour dropdown | App ka apna data + shop's typing | Free |
| Blacklist / iCloud / warranty report | Live device status | **Is app me nahi** (paid third-party chahiye) |

Safety rules jo kabhi nahi tootni chahiye:

1. Sync **additive** hai — koi row delete nahi hoti.
2. `learned` / `csv` / `legacy` / `seed` rows ko koi bhi free sync **overwrite nahi** karta
   (`TAC_SYNC_TACDB_REFRESH_OSMOCOM=true` sirf Osmocom↔extended ke beech refresh deta hai).
3. External TAC API sirf **miss** par call hota hai, aur jawab `source='api'` ke saath cache hota hai.
4. Poora IMEI (15 digit) kisi third-party ko nahi bhejna — TAC (pehle 8 digit) se kaam chalta hai.

### Optional external API lagane ka tarika (`backend/.env`)

```env
# HiCellTek (100 free lookups/month) — POST {query: "<tac>"}
TAC_API_URL=https://imei.hicelltek.com/api/v1/tac/lookup
TAC_API_KEY=<free key>
TAC_API_METHOD=POST

# imeicheck.com free API (email karke free key, 60 req/min) — GET
# TAC_API_URL=https://alpha.imeicheck.com/api/modelBrandName?imei={tac}&format=json
# TAC_API_METHOD=GET
```

`TAC_API_URL` khaali ho to module **no-op** hai: koi request kabhi nahi jati.

---

## 7. Licence / attribution (share karte waqt rakhein)

- **Osmocom:** *TAC data: Osmocom TAC database (c) Harald Welte and contributors, CC-BY-SA 3.0*
- **Extended:** *TAC data: MoazEb/tac-database (MIT), community maintained from public databases*

Dono ki attribution app ke TAC catalog screen par dikhti hai (`/api/admin/tac/status` → `licenses`).
Data aage public share karein to yahi attribution rakhein.
