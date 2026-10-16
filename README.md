# PakDrive

inDrive jaisi ride-hailing app for Pakistan. **Rider apna fare khud set karta hai, drivers bid karte hain**, rider jise chahe accept kare.
Bike, rickshaw aur car. Cash payment. Google (Gmail) se login.

```
backend/   Node.js + Express + Postgres API (Google sign-in, rides, bids, wallet)
app/       Flutter app (Android) — Rider aur Driver dono ek hi app mein
```

## Kya kya kaam karta hai (real, koi demo/bot nahi)

- Gmail se login (Google ID token server par verify hota hai, phir app ka apna JWT)
- Rider: pickup/dropoff search ya map par pin, vehicle chuno, fare set karo, drivers ki bids dekho, accept karo, driver ko live map par dekho, call karo, rate karo
- Driver: online/offline, apni gaari ki type ki qareebi requests (15 km), bid ya counter-offer, navigate (Google Maps), trip states, cash earnings ka hisaab
- Trip states: `open → matched → arriving → arrived → in_trip → completed` (+ cancel; driver cancel kare to ride wapas open ho jati hai)
- 20 min tak koi accept na kare to request khud expire

## 1) Google login setup (zaroori)

[Google Cloud Console](https://console.cloud.google.com) → naya project → **APIs & Services → OAuth consent screen** → Credentials:

1. **OAuth client ID → Web application** banao. Iska Client ID `WEB_CLIENT_ID` hai. Backend aur app dono isi ko use karte hain.
2. **OAuth client ID → Android** banao: package name `com.pakdrive.pakdrive` + apni keystore ka **SHA-1**.
   - Debug SHA-1: `keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android`
   - Play Store par daalo to Play Console ka "App signing" SHA-1 bhi ek aur Android client mein add karo.

## 2) Backend

Postgres chahiye (Neon / Supabase / Railway / Render sab free tier dete hain).

```bash
cd backend
cp .env.example .env          # DATABASE_URL, JWT_SECRET, GOOGLE_CLIENT_IDS (= WEB_CLIENT_ID) bharo
npm install
export $(grep -v '^#' .env | xargs) && npm start     # tables khud ban jati hain
npm test                      # 4 integration tests (poora ride flow)
```

Deploy: `backend/Dockerfile` hai (Render, Railway, Fly.io). Env variables wahi. **HTTPS URL** lagta hai production mein.

## 3) Flutter app

Flutter SDK + Android Studio chahiye.

```bash
cd app
flutter create --org com.pakdrive --project-name pakdrive --platforms=android .
python3 tools/patch_android.py        # permissions + app name "PakDrive"
flutter pub get
flutter run \
  --dart-define=API_URL=http://10.0.2.2:8080 \
  --dart-define=GOOGLE_SERVER_CLIENT_ID=WEB_CLIENT_ID.apps.googleusercontent.com
```

Emulator mein `10.0.2.2` = aap ka computer. Asli phone par apne backend ka URL do.

Release APK:

```bash
flutter build apk --release \
  --dart-define=API_URL=https://your-api.example.com \
  --dart-define=GOOGLE_SERVER_CLIENT_ID=WEB_CLIENT_ID.apps.googleusercontent.com
```

## GitHub Actions se APK (PC par Flutter ke bina)

`main` branch par push karte hi `.github/workflows/android.yml` APK banata hai (Actions tab → run → **Artifacts → PakDrive-apk**).
Repo ki **Settings → Secrets and variables → Actions** mein 3 secrets daalo:

| Secret | Kya |
|---|---|
| `API_URL` | Deployed backend ka **https** URL |
| `GOOGLE_SERVER_CLIENT_ID` | Web client ID (`...apps.googleusercontent.com`) |
| `DEBUG_KEYSTORE_BASE64` | Ek fixed signing key (neeche) |

Fixed key ek baar banao (warna har build ka SHA-1 badalta hai aur Google login fail hota hai):

```bash
keytool -genkey -v -keystore debug.keystore -storepass android -alias androiddebugkey \
  -keypass android -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Android Debug,O=Android,C=US"
base64 -w0 debug.keystore            # output ko DEBUG_KEYSTORE_BASE64 secret mein paste karo
keytool -list -v -keystore debug.keystore -alias androiddebugkey -storepass android | grep SHA1
```

Is SHA1 ko Google Cloud ke **Android OAuth client** mein daalo. Play Store ke liye baad mein alag proper release keystore banana.
`backend.yml` har push par backend ke tests chalata hai.

## Abhi ki limits (launch se pehle sochne wali baatein)

- Location tracking sirf jab app khula ho. Background tracking aur push notifications nahi hain (app har 3 sec poll karti hai).
- Sirf cash. Online payment, commission, driver KYC / CNIC / gaari documents verification, admin panel nahi hain.
- Maps aur search OpenStreetMap (Nominatim + OSM tiles) par hain. Chhote launch ke liye theek, zyada traffic par paid provider (Google Maps, Mapbox, LocationIQ) lagao.
- Distance seedha-line × 1.3 se nikalta hai, road routing nahi.
- Pakistan mein ride-hailing ke local qawaneen / provincial registration aap ki zimmedari hai.

## License

MIT
