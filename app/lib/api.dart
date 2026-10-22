import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'models.dart';

class ApiException implements Exception {
  final String message;
  final int? status;
  ApiException(this.message, [this.status]);
  @override
  String toString() => message;
}

class Api {
  Api(this.baseUrl, {this.onUnauthorized});
  String baseUrl;
  final void Function()? onUnauthorized;
  String? token;
  final http.Client _client = http.Client();

  Future<dynamic> _req(String method, String path, [Object? body]) async {
    if (baseUrl.isEmpty) {
      throw ApiException('Pehle Server URL set karo (menu ya login screen par "Server").');
    }
    final req = http.Request(method, Uri.parse('$baseUrl$path'));
    req.headers['Content-Type'] = 'application/json';
    if (token != null) req.headers['Authorization'] = 'Bearer $token';
    if (body != null) req.body = jsonEncode(body);
    http.Response res;
    try {
      final streamed = await _client.send(req).timeout(const Duration(seconds: 20));
      res = await http.Response.fromStream(streamed);
    } on TimeoutException {
      throw ApiException('Server jawab nahi de raha. Internet check karo.');
    } on SocketException {
      throw ApiException('Internet ya server se connection nahi ho raha.');
    } on http.ClientException {
      throw ApiException('Internet ya server se connection nahi ho raha.');
    }
    dynamic data;
    try {
      data = res.body.isEmpty ? null : jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      throw ApiException('Server se ghalat jawab aaya (${res.statusCode}).', res.statusCode);
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return data;
    if (res.statusCode == 401 && token != null) onUnauthorized?.call();
    final msg = data is Map && data['error'] is String ? data['error'] as String : 'Error ${res.statusCode}';
    throw ApiException(msg, res.statusCode);
  }

  Future<({String token, Me user})> googleLogin(String idToken) async {
    final j = await _req('POST', '/auth/google', {'idToken': idToken}) as Map<String, dynamic>;
    return (token: j['token'] as String, user: Me.fromJson(j['user'] as Map<String, dynamic>));
  }

  Future<void> health() => _req('GET', '/health');

  Future<Board> board() async => Board.fromJson(await _req('GET', '/board') as Map<String, dynamic>);

  Future<void> updateProfile(Map<String, dynamic> body) => _req('PUT', '/me', body);
  Future<void> setOnline(bool online, double lat, double lng) =>
      _req('POST', '/me/online', {'online': online, 'lat': lat, 'lng': lng});
  Future<void> sendLocation(double lat, double lng) => _req('POST', '/me/location', {'lat': lat, 'lng': lng});

  Future<({double distanceKm, int suggestedFare})> estimate(Place a, Place b, String vehicleType, {double? routeKm}) async {
    final j = await _req('POST', '/estimate', {
      'pickup': {'lat': a.lat, 'lng': a.lng},
      'dropoff': {'lat': b.lat, 'lng': b.lng},
      'vehicleType': vehicleType,
      if (routeKm != null) 'routeKm': routeKm,
    }) as Map<String, dynamic>;
    return (distanceKm: (j['distanceKm'] as num).toDouble(), suggestedFare: j['suggestedFare'] as int);
  }

  Future<void> createRide(Place a, Place b, String vehicleType, int fare, {double? routeKm}) => _req('POST', '/rides', {
        'pickup': a.toJson(),
        'dropoff': b.toJson(),
        'vehicleType': vehicleType,
        'fare': fare,
        if (routeKm != null) 'routeKm': routeKm,
      });
  Future<void> raiseFare(int rideId, int fare) => _req('PUT', '/rides/$rideId/fare', {'fare': fare});
  Future<void> cancel(int rideId) => _req('POST', '/rides/$rideId/cancel');
  Future<void> bid(int rideId, int fare) => _req('POST', '/rides/$rideId/bids', {'fare': fare});
  Future<void> accept(int rideId, int bidId) => _req('POST', '/rides/$rideId/accept', {'bidId': bidId});
  Future<void> advance(int rideId) => _req('POST', '/rides/$rideId/advance');
  Future<void> rate(int rideId, int stars) => _req('POST', '/rides/$rideId/rate', {'stars': stars});
}
