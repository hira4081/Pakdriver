# PakDrive (Flutter)

Setup steps root [README](../README.md) mein hain. Short version:

```bash
flutter create --org com.pakdrive --project-name pakdrive --platforms=android .
python3 tools/patch_android.py
flutter pub get
flutter run --dart-define=API_URL=http://10.0.2.2:8080 --dart-define=GOOGLE_SERVER_CLIENT_ID=<WEB_CLIENT_ID>
```

`lib/` layout: `api.dart` (HTTP), `app_state.dart` (login, polling, actions), `screens/` (rider, driver, ride, profile, history), `widgets/` (map, shared UI).
