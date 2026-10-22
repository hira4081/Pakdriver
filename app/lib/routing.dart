import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// One driving route: the line to draw, real road distance and travel time.
class RouteInfo {
  final List<LatLng> points;
  final double km;
  final int minutes;
  const RouteInfo(this.points, this.km, this.minutes);
  String get label => '${km.toStringAsFixed(1)} km • $minutes min';
}

/// Road routes from OSRM (free, no API key). Returns [] if the service is unreachable,
/// so callers must always have a fallback.
///
/// Times are free-flow estimates WITHOUT live traffic. The public demo server is for
/// light use; for many users run your own OSRM or switch to a paid routing API.
Future<List<RouteInfo>> fetchRoutes(LatLng a, LatLng b, {bool alternatives = false}) async {
  try {
    final coords = '${a.longitude},${a.latitude};${b.longitude},${b.latitude}';
    final uri = Uri.https('router.project-osrm.org', '/route/v1/driving/$coords', {
      'overview': 'full',
      'geometries': 'geojson',
      'alternatives': alternatives ? 'true' : 'false',
    });
    final res = await http.get(uri).timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) return [];
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    if (j['code'] != 'Ok') return [];
    final out = <RouteInfo>[];
    for (final r in (j['routes'] as List)) {
      final m = r as Map<String, dynamic>;
      final raw = (m['geometry'] as Map<String, dynamic>)['coordinates'] as List;
      final pts = _thin(raw.map((c) {
        final p = c as List;
        return LatLng((p[1] as num).toDouble(), (p[0] as num).toDouble());
      }).toList());
      final km = ((m['distance'] as num) / 1000 * 10).round() / 10;
      final mins = ((m['duration'] as num) / 60).round();
      out.add(RouteInfo(pts, km, mins < 1 ? 1 : mins));
    }
    return out;
  } catch (_) {
    return [];
  }
}

/// Keeps long routes light enough to draw smoothly.
List<LatLng> _thin(List<LatLng> pts) {
  if (pts.length <= 500) return pts;
  final step = (pts.length / 500).ceil();
  final out = <LatLng>[];
  for (var i = 0; i < pts.length; i += step) {
    out.add(pts[i]);
  }
  if (out.last != pts.last) out.add(pts.last);
  return out;
}
