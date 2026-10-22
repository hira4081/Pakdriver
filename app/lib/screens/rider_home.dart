import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../api.dart';
import '../config.dart';
import '../location.dart';
import '../main.dart';
import '../models.dart';
import '../routing.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/pak_map.dart';
import 'place_picker.dart';

class RiderHome extends StatefulWidget {
  const RiderHome({super.key});
  @override
  State<RiderHome> createState() => _RiderHomeState();
}

class _RiderHomeState extends State<RiderHome> {
  Place? _pickup, _dropoff;
  String _vehicle = 'car';
  int? _fare;
  int? _suggested;
  double? _km;
  List<RouteInfo> _routes = [];
  int _routeIdx = 0;
  bool _estimating = false, _busy = false;

  RouteInfo? get _route => _routes.isEmpty ? null : _routes[_routeIdx];

  @override
  void initState() {
    super.initState();
    _locate();
  }

  Future<void> _locate() async {
    final p = await currentPosition();
    if (p == null || !mounted) return;
    final label = await reverseGeocode(p.latitude, p.longitude);
    if (!mounted) return;
    setState(() => _pickup = Place(label, p.latitude, p.longitude));
    _loadRoutes();
  }

  Future<void> _pick(bool pickup) async {
    final near = _pickup ?? _dropoff;
    final p = await Navigator.of(context).push<Place>(MaterialPageRoute(
      builder: (_) => PlacePickerScreen(title: pickup ? 'Pickup' : 'Kahan jana hai?', nearLat: near?.lat, nearLng: near?.lng),
    ));
    if (p == null || !mounted) return;
    setState(() => pickup ? _pickup = p : _dropoff = p);
    _loadRoutes();
  }

  /// Fetch real road routes (with alternatives) for the chosen places, then price the trip.
  Future<void> _loadRoutes() async {
    final a = _pickup, b = _dropoff;
    if (a == null || b == null) return;
    setState(() {
      _estimating = true;
      _routes = [];
      _routeIdx = 0;
    });
    final routes = await fetchRoutes(LatLng(a.lat, a.lng), LatLng(b.lat, b.lng), alternatives: true);
    if (!mounted) return;
    setState(() => _routes = routes);
    await _recalc();
  }

  Future<void> _recalc() async {
    final a = _pickup, b = _dropoff;
    if (a == null || b == null) return;
    final app = AppScope.read(context);
    setState(() => _estimating = true);
    try {
      final e = await app.api.estimate(a, b, _vehicle, routeKm: _route?.km);
      if (!mounted) return;
      setState(() {
        _km = e.distanceKm;
        _suggested = e.suggestedFare;
        _fare = e.suggestedFare;
      });
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    } finally {
      if (mounted) setState(() => _estimating = false);
    }
  }

  Future<void> _submit() async {
    final app = AppScope.of(context);
    setState(() => _busy = true);
    await guard(context, () => app.createRide(_pickup!, _dropoff!, _vehicle, _fare!, routeKm: _route?.km));
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final a = _pickup, b = _dropoff;
    final ready = a != null && b != null && _fare != null;
    final route = _route;
    final pts = route != null
        ? route.points
        : [
            if (a != null) LatLng(a.lat, a.lng),
            if (b != null) LatLng(b.lat, b.lng),
          ];

    return Stack(children: [
      Positioned.fill(
        child: PakMap(
          key: ValueKey('${a?.lat}-${a?.lng}-${b?.lat}-${b?.lng}-$_routeIdx-${_routes.length}'),
          center: a != null ? LatLng(a.lat, a.lng) : const LatLng(AppConfig.defaultLat, AppConfig.defaultLng),
          zoom: 14,
          fitPoints: pts,
          line: route?.points,
          markers: [
            if (a != null) pin(LatLng(a.lat, a.lng), Icons.my_location, Pk.green, size: 30),
            if (b != null) pin(LatLng(b.lat, b.lng), Icons.location_on, Pk.danger),
          ],
        ),
      ),
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: Sheet(
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _PlaceTile(icon: Icons.circle, color: Pk.green, label: 'Pickup', value: a?.label, onTap: () => _pick(true)),
              const SizedBox(height: 8),
              _PlaceTile(icon: Icons.square_rounded, color: Pk.danger, label: 'Kahan jana hai?', value: b?.label, onTap: () => _pick(false)),
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (final t in vehicleTypes)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Text(vehicleLabel(t)),
                      selected: _vehicle == t,
                      onSelected: (_) {
                        setState(() => _vehicle = t);
                        _recalc();
                      },
                    ),
                  ),
              ]),
              if (_routes.length > 1) ...[
                const SizedBox(height: 8),
                Wrap(alignment: WrapAlignment.center, spacing: 8, children: [
                  for (var i = 0; i < _routes.length; i++)
                    ChoiceChip(
                      label: Text('Route ${i + 1} • ${_routes[i].label}'),
                      selected: _routeIdx == i,
                      onSelected: (_) {
                        setState(() => _routeIdx = i);
                        _recalc();
                      },
                    ),
                ]),
              ],
              if (ready) ...[
                const SizedBox(height: 10),
                FareStepper(fare: _fare!, onChanged: (v) => setState(() => _fare = v)),
                const SizedBox(height: 4),
                Text(
                  'Suggested ${rs(_suggested ?? 0)}  •  ${_km?.toStringAsFixed(1)} km'
                  '${route != null ? '  •  ~${route.minutes} min' : ''}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Pk.muted, fontSize: 13),
                ),
                if (route != null)
                  const Text('Time andaza hai, live traffic ke bagair', textAlign: TextAlign.center, style: TextStyle(color: Pk.muted, fontSize: 11)),
              ],
              const SizedBox(height: 12),
              FilledButton(
                onPressed: ready && !_busy && !_estimating ? _submit : null,
                child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Drivers dhoondo'),
              ),
            ]),
          ),
        ),
      ),
    ]);
  }
}

class _PlaceTile extends StatelessWidget {
  const _PlaceTile({required this.icon, required this.color, required this.label, required this.value, required this.onTap});
  final IconData icon;
  final Color color;
  final String label;
  final String? value;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(color: Pk.surface2, borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                value ?? label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: value == null ? Pk.muted : null),
              ),
            ),
          ]),
        ),
      );
}
