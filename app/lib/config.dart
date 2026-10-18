/// Build-time config. Pass with --dart-define, e.g.
///   flutter run --dart-define=API_URL=https://api.example.com \
///               --dart-define=GOOGLE_SERVER_CLIENT_ID=xxxx.apps.googleusercontent.com
class AppConfig {
  /// Optional default server. Users can change it inside the app (Server setting),
  /// so a new APK is NOT needed when the server URL changes. Empty = ask the user.
  static const apiUrl = String.fromEnvironment('API_URL');

  /// The *Web application* OAuth client ID from Google Cloud (not the Android one).
  static const googleServerClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  static const appName = 'PakDrive';
  static const userAgent = 'com.pakdrive.app';

  /// Where the map opens if GPS is unavailable (Karachi).
  static const defaultLat = 24.8607;
  static const defaultLng = 67.0011;
}
