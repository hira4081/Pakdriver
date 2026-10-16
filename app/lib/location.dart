import 'dart:async';
import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'config.dart';
import 'models.dart';

/// Returns null if GPS is off or permission is denied.
Future<Position?> currentPosition() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return null;
    return await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high)
        .timeout(const Duration(seconds: 8));
  } catch (_) {
    return null;
  }
}

const _headers = {'User-Agent': AppConfig.userAgent, 'Accept-Language': 'en'};

/// Place search via OpenStreetMap Nominatim (Pakistan only).
/// Fine for launch / low traffic. For heavy use switch to a paid geocoder.
Future<List<Place>> searchPlaces(String q, {double? nearLat, double? nearLng}) async {
  final params = {
    'q': q,
    'format': 'jsonv2',
    'limit': '8',
    'countrycodes': 'pk',
    if (nearLat != null && nearLng != null)
      'viewbox': '${nearLng - 0.6},${nearLat + 0.6},${nearLng + 0.6},${nearLat - 0.6}',
  };
  final uri = Uri.https('nominatim.openstreetmap.org', '/search', params);
  final res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 10));
  if (res.statusCode != 200) return [];
  final list = jsonDecode(utf8.decode(res.bodyBytes)) as List;
  return list.map((e) {
    final m = e as Map<String, dynamic>;
    return Place(_short(m['display_name'] as String), double.parse(m['lat'] as String), double.parse(m['lon'] as String));
  }).toList();
}

Future<String> reverseGeocode(double lat, double lng) async {
  try {
    final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
      'lat': '$lat',
      'lon': '$lng',
      'format': 'jsonv2',
      'zoom': '17',
    });
    final res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 8));
    if (res.statusCode == 200) {
      final m = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      if (m['display_name'] is String) return _short(m['display_name'] as String);
    }
  } catch (_) {}
  return 'Pinned location (${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)})';
}

String _short(String s) {
  final parts = s.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  return parts.take(3).join(', ');
}
