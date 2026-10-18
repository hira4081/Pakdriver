import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api.dart';
import 'config.dart';
import 'location.dart';
import 'models.dart';

class AppState extends ChangeNotifier {
  AppState() {
    api = Api(AppConfig.apiUrl, onUnauthorized: _expired);
    _normalizeDefault();
  }

  late final Api api;
  final GoogleSignIn _google = GoogleSignIn(
    scopes: const ['email', 'profile'],
    serverClientId: AppConfig.googleServerClientId.isEmpty ? null : AppConfig.googleServerClientId,
  );

  bool booting = true;
  bool signedIn = false;
  Board? board;
  String? connectionError;

  Timer? _timer;
  bool _inFlight = false;
  bool _paused = false;
  int _tick = 0;

  Me? get me => board?.me;

  String get serverUrl => api.baseUrl;

  void _normalizeDefault() => api.baseUrl = normalizeUrl(api.baseUrl);

  static String normalizeUrl(String raw) {
    var u = raw.trim();
    if (u.isEmpty) return '';
    if (!u.startsWith('http://') && !u.startsWith('https://')) u = 'https://$u';
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  /// Saves a new server URL and checks that it answers. Throws ApiException if not.
  Future<void> setServerUrl(String raw) async {
    final url = normalizeUrl(raw);
    final uri = Uri.tryParse(url);
    if (url.isEmpty || uri == null || uri.host.isEmpty) {
      throw ApiException('Sahi link likho, jaise https://abc.trycloudflare.com');
    }
    final old = api.baseUrl;
    api.baseUrl = url;
    try {
      await api.health();
    } catch (_) {
      api.baseUrl = old;
      throw ApiException('Is link par server nahi mila. Link aur tunnel check karo.');
    }
    (await SharedPreferences.getInstance()).setString('server_url', url);
    connectionError = null;
    notifyListeners();
    if (signedIn) await refresh();
  }

  final Set<int> _dismissed = {};

  /// The ride to show on screen (a finished ride the user chose to skip rating is hidden).
  Ride? get activeRide {
    final r = board?.ride;
    if (r == null) return null;
    if (r.status == 'completed' && _dismissed.contains(r.id)) return null;
    return r;
  }

  void dismissRide(int id) {
    _dismissed.add(id);
    notifyListeners();
  }

  /* ---------- lifecycle ---------- */

  Future<void> boot() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('server_url');
    if (saved != null && saved.isNotEmpty) api.baseUrl = saved;
    api.token = prefs.getString('token');
    signedIn = api.token != null;
    booting = false;
    notifyListeners();
    if (signedIn) {
      await refresh();
      _startPolling();
    }
  }

  void setPaused(bool paused) {
    _paused = paused;
    if (!paused && signedIn) refresh();
  }

  void _startPolling() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _onTick());
  }

  Future<void> _onTick() async {
    if (_paused || !signedIn) return;
    _tick++;
    final b = board;
    final r = b?.ride;
    final driving = b != null && b.me.isDriver && (b.me.isOnline || (r != null && r.myRole == 'driver'));
    if (driving && _tick % 3 == 0) {
      final p = await currentPosition();
      if (p != null) {
        try {
          await api.sendLocation(p.latitude, p.longitude);
        } catch (_) {}
      }
    }
    await refresh();
  }

  Future<void> refresh() async {
    if (_inFlight || !signedIn) return;
    _inFlight = true;
    try {
      board = await api.board();
      connectionError = null;
    } on ApiException catch (e) {
      if (e.status != 401) connectionError = e.message;
    } catch (_) {
      connectionError = 'Kuch ghalat ho gaya. Dobara koshish karo.';
    } finally {
      _inFlight = false;
      notifyListeners();
    }
  }

  void _expired() {
    _timer?.cancel();
    signedIn = false;
    board = null;
    api.token = null;
    SharedPreferences.getInstance().then((p) => p.remove('token'));
    notifyListeners();
  }

  /* ---------- auth ---------- */

  /// Returns false if the user cancelled the Google picker.
  Future<bool> signIn() async {
    final acct = await _google.signIn();
    if (acct == null) return false;
    final auth = await acct.authentication;
    final idToken = auth.idToken;
    if (idToken == null) {
      throw ApiException('Google ne ID token nahi diya. GOOGLE_SERVER_CLIENT_ID check karo.');
    }
    final res = await api.googleLogin(idToken);
    api.token = res.token;
    (await SharedPreferences.getInstance()).setString('token', res.token);
    signedIn = true;
    notifyListeners();
    await refresh();
    _startPolling();
    return true;
  }

  Future<void> signOut() async {
    _timer?.cancel();
    try {
      await _google.signOut();
    } catch (_) {}
    (await SharedPreferences.getInstance()).remove('token');
    api.token = null;
    signedIn = false;
    board = null;
    notifyListeners();
  }

  /* ---------- actions (each refreshes the board afterwards) ---------- */

  Future<T> _then<T>(Future<T> f) async {
    final r = await f;
    await refresh();
    return r;
  }

  Future<void> updateProfile(Map<String, dynamic> body) => _then(api.updateProfile(body));

  Future<void> setOnline(bool online) async {
    final p = await currentPosition();
    if (p == null) {
      throw ApiException('Location on karo aur permission do, phir online ho sakte hain.');
    }
    await _then(api.setOnline(online, p.latitude, p.longitude));
  }

  Future<void> createRide(Place a, Place b, String type, int fare) => _then(api.createRide(a, b, type, fare));
  Future<void> raiseFare(int id, int fare) => _then(api.raiseFare(id, fare));
  Future<void> cancel(int id) => _then(api.cancel(id));
  Future<void> bid(int id, int fare) => _then(api.bid(id, fare));
  Future<void> accept(int rideId, int bidId) => _then(api.accept(rideId, bidId));
  Future<void> advance(int id) => _then(api.advance(id));
  Future<void> rate(int id, int stars) => _then(api.rate(id, stars));

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
