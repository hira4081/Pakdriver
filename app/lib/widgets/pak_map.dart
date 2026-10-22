import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../config.dart';
import '../theme.dart';

Marker pin(LatLng p, IconData icon, Color color, {double size = 36}) => Marker(
      point: p,
      width: size + 8,
      height: size + 8,
      child: Icon(icon, color: color, size: size),
    );

class PakMap extends StatelessWidget {
  const PakMap({
    super.key,
    this.center,
    this.zoom = 14,
    this.fitPoints,
    this.fitPadding = const EdgeInsets.fromLTRB(50, 90, 50, 330),
    this.controller,
    this.markers = const [],
    this.line,
    this.onPositionChanged,
    this.onTap,
  });

  final LatLng? center;
  final double zoom;

  /// If set (2+ points), the camera opens fitted to these points.
  final List<LatLng>? fitPoints;

  /// Space kept free around the fitted route (large bottom value = room for the bottom sheet).
  final EdgeInsets fitPadding;
  final MapController? controller;
  final List<Marker> markers;
  final List<LatLng>? line;
  final void Function(MapCamera camera, bool hasGesture)? onPositionChanged;
  final void Function(LatLng point)? onTap;

  @override
  Widget build(BuildContext context) {
    final fit = fitPoints != null && fitPoints!.length >= 2;
    return FlutterMap(
      mapController: controller,
      options: MapOptions(
        initialCenter: center ?? const LatLng(AppConfig.defaultLat, AppConfig.defaultLng),
        initialZoom: zoom,
        initialCameraFit: fit
            ? CameraFit.bounds(bounds: LatLngBounds.fromPoints(fitPoints!), padding: fitPadding)
            : null,
        onPositionChanged: onPositionChanged,
        onTap: onTap == null ? null : (tapPos, p) => onTap!(p),
        interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: AppConfig.userAgent,
        ),
        if (line != null && line!.length >= 2)
          PolylineLayer(polylines: [Polyline(points: line!, strokeWidth: 4, color: Pk.green)]),
        MarkerLayer(markers: markers),
        const RichAttributionWidget(
          alignment: AttributionAlignment.bottomLeft,
          attributions: [TextSourceAttribution('© OpenStreetMap contributors')],
        ),
      ],
    );
  }
}
