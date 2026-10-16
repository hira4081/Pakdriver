import 'dart:async';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../config.dart';
import '../location.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/pak_map.dart';

/// Search a place by name, use GPS, or pick on the map. Pops with a [Place].
class PlacePickerScreen extends StatefulWidget {
  const PlacePickerScreen({super.key, required this.title, this.nearLat, this.nearLng});
  final String title;
  final double? nearLat, nearLng;
  @override
  State<PlacePickerScreen> createState() => _PlacePickerScreenState();
}

class _PlacePickerScreenState extends State<PlacePickerScreen> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  List<Place> _results = [];
  bool _loading = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    if (q.trim().length < 3) {
      setState(() => _results = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 600), () async {
      setState(() => _loading = true);
      List<Place> r = [];
      try {
        r = await searchPlaces(q.trim(), nearLat: widget.nearLat, nearLng: widget.nearLng);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _results = r;
        _loading = false;
      });
    });
  }

  Future<void> _useGps() async {
    final p = await currentPosition();
    if (!mounted) return;
    if (p == null) {
      toast(context, 'Location nahi mili. GPS on karo aur permission do.');
      return;
    }
    final label = await reverseGeocode(p.latitude, p.longitude);
    if (mounted) Navigator.of(context).pop(Place(label, p.latitude, p.longitude));
  }

  Future<void> _pickOnMap() async {
    final start = LatLng(widget.nearLat ?? AppConfig.defaultLat, widget.nearLng ?? AppConfig.defaultLng);
    final place = await Navigator.of(context).push<Place>(MaterialPageRoute(builder: (_) => MapPickerScreen(start: start)));
    if (place != null && mounted) Navigator.of(context).pop(place);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            controller: _ctrl,
            autofocus: true,
            onChanged: _onChanged,
            decoration: deco('Jagah ka naam likho', hint: 'e.g. Dolmen Mall Clifton', icon: Icons.search),
          ),
        ),
        ListTile(leading: const Icon(Icons.my_location, color: Pk.green), title: const Text('Meri current location'), onTap: _useGps),
        ListTile(leading: const Icon(Icons.map_outlined, color: Pk.green), title: const Text('Map par chuno'), onTap: _pickOnMap),
        const Divider(height: 1),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: ListView.builder(
            itemCount: _results.length,
            itemBuilder: (_, i) {
              final p = _results[i];
              return ListTile(
                leading: const Icon(Icons.place_outlined),
                title: Text(p.label, maxLines: 2, overflow: TextOverflow.ellipsis),
                onTap: () => Navigator.of(context).pop(p),
              );
            },
          ),
        ),
      ]),
    );
  }
}

class MapPickerScreen extends StatefulWidget {
  const MapPickerScreen({super.key, required this.start});
  final LatLng start;
  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  late LatLng _center = widget.start;
  bool _busy = false;

  Future<void> _confirm() async {
    setState(() => _busy = true);
    final label = await reverseGeocode(_center.latitude, _center.longitude);
    if (mounted) Navigator.of(context).pop(Place(label, _center.latitude, _center.longitude));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Map par jagah chuno')),
      body: Stack(children: [
        PakMap(
          center: widget.start,
          zoom: 15,
          onPositionChanged: (camera, _) => _center = camera.center,
        ),
        const Center(child: Padding(padding: EdgeInsets.only(bottom: 40), child: Icon(Icons.location_on, size: 48, color: Pk.danger))),
        Positioned(
          left: 16,
          right: 16,
          bottom: 24,
          child: FilledButton(onPressed: _busy ? null : _confirm, child: const Text('Yahan confirm karo')),
        ),
      ]),
    );
  }
}
