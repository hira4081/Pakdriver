import 'dart:async';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../location.dart';
import '../main.dart';
import '../models.dart';
import '../routing.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/pak_map.dart';

String statusText(Ride r) {
  switch (r.status) {
    case 'open':
      return 'Drivers dhoond rahe hain…';
    case 'matched':
      return r.isRider ? 'Driver confirm ho gaya' : 'Rider ne aap ko chun liya!';
    case 'arriving':
      return r.isRider ? 'Driver raste mein hai' : 'Pickup ki taraf ja rahe hain';
    case 'arrived':
      return r.isRider ? 'Driver pohanch gaya' : 'Aap pickup par hain';
    case 'in_trip':
      return 'Trip chal rahi hai';
    case 'completed':
      return 'Trip complete!';
    default:
      return r.status;
  }
}

class RideScreen extends StatefulWidget {
  const RideScreen({super.key, required this.ride});
  final Ride ride;
  @override
  State<RideScreen> createState() => _RideScreenState();
}

class _RideScreenState extends State<RideScreen> {
  RouteInfo? _route; // real road route currently drawn
  LatLng? _me; // driver's own position (driver side only)
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    // Driver's route to pickup/dropoff changes as they move.
    _timer = Timer.periodic(const Duration(seconds: 25), (_) {
      if (!widget.ride.isRider) _load();
    });
  }

  @override
  void didUpdateWidget(RideScreen old) {
    super.didUpdateWidget(old);
    if (old.ride.id != widget.ride.id || old.ride.status != widget.ride.status) {
      _route = null;
      _load();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final r = widget.ride;
    if (r.status == 'completed') return;
    final pick = LatLng(r.pickup.lat, r.pickup.lng);
    final drop = LatLng(r.dropoff.lat, r.dropoff.lng);
    var from = pick;
    var to = drop;
    LatLng? me;
    if (!r.isRider) {
      final p = await currentPosition();
      if (p != null) {
        me = LatLng(p.latitude, p.longitude);
        from = me;
        to = r.status == 'in_trip' ? drop : pick;
      }
    }
    final routes = await fetchRoutes(from, to);
    if (!mounted || widget.ride.id != r.id) return;
    setState(() {
      _me = me;
      _route = routes.isEmpty ? null : routes.first;
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final ride = widget.ride;
    final driver = ride.driver;
    final pick = LatLng(ride.pickup.lat, ride.pickup.lng);
    final drop = LatLng(ride.dropoff.lat, ride.dropoff.lng);
    final live = ['matched', 'arriving', 'arrived', 'in_trip'].contains(ride.status);
    final dPos = driver != null && driver.lat != null && driver.lng != null && live && ride.isRider
        ? LatLng(driver.lat!, driver.lng!)
        : null;
    final route = _route;
    final toPickup = ride.status != 'in_trip';

    String? note;
    if (route != null) {
      note = ride.isRider
          ? 'Trip: ${route.label}'
          : (_me != null ? '${toPickup ? 'Pickup' : 'Dropoff'} tak: ${route.label}' : 'Trip: ${route.label}');
    }

    return Stack(children: [
      Positioned.fill(
        child: PakMap(
          key: ValueKey('ride-${ride.id}-${ride.status}-${route != null}'),
          center: pick,
          fitPoints: route?.points ?? [pick, drop],
          line: route?.points ?? [pick, drop],
          markers: [
            pin(pick, Icons.my_location, Pk.green, size: 30),
            pin(drop, Icons.location_on, Pk.danger),
            if (dPos != null) pin(dPos, Icons.directions_car_filled, Pk.amber, size: 34),
            if (_me != null) pin(_me!, Icons.directions_car_filled, Pk.amber, size: 34),
          ],
        ),
      ),
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: Sheet(
          child: SingleChildScrollView(
            child: ride.isRider
                ? _RiderPanel(ride: ride, bids: app.board!.bids, note: note)
                : _DriverPanel(ride: ride, note: note),
          ),
        ),
      ),
    ]);
  }
}

/* ------------------------------ RIDER ------------------------------ */

class _RiderPanel extends StatefulWidget {
  const _RiderPanel({required this.ride, required this.bids, this.note});
  final Ride ride;
  final List<Bid> bids;
  final String? note;
  @override
  State<_RiderPanel> createState() => _RiderPanelState();
}

class _RiderPanelState extends State<_RiderPanel> {
  late int _fare = widget.ride.offeredFare;
  bool _busy = false;

  Future<void> _run(Future<void> Function() fn) async {
    setState(() => _busy = true);
    await guard(context, fn);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _confirmCancel() async {
    final app = AppScope.read(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Ride cancel karni hai?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Nahi')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Haan, cancel')),
        ],
      ),
    );
    if (yes == true) await _run(() => app.cancel(widget.ride.id));
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.read(context);
    final r = widget.ride;
    final driver = r.driver;

    final children = <Widget>[
      Text(statusText(r), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      const SizedBox(height: 10),
      RouteLines(pickup: r.pickup.label, dropoff: r.dropoff.label),
      if (widget.note != null) ...[
        const SizedBox(height: 8),
        Row(children: [
          const Icon(Icons.route_outlined, size: 16, color: Pk.green),
          const SizedBox(width: 6),
          Text(widget.note!, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        ]),
        const Text('Time andaza hai (live traffic ke bagair). Traffic ke liye Navigate dabao.',
            style: TextStyle(color: Pk.muted, fontSize: 11)),
      ],
      const SizedBox(height: 12),
    ];

    if (r.status == 'open') {
      children.addAll([
        FareStepper(fare: _fare, onChanged: (v) => setState(() => _fare = v)),
        if (_fare != r.offeredFare) ...[
          const SizedBox(height: 8),
          OutlinedButton(onPressed: _busy ? null : () => _run(() => app.raiseFare(r.id, _fare)), child: const Text('Fare update karo')),
        ],
        const SizedBox(height: 12),
        if (widget.bids.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 10),
              Text('Abhi koi bid nahi aayi. Fare barha kar dekho.', style: TextStyle(color: Pk.muted)),
            ]),
          )
        else
          ...widget.bids.map((b) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Pk.surface2, borderRadius: BorderRadius.circular(14)),
                  child: Column(children: [
                    DriverTile(driver: b.driver),
                    const SizedBox(height: 10),
                    Row(children: [
                      Text('${b.etaMinutes} min door', style: const TextStyle(color: Pk.muted)),
                      const Spacer(),
                      SizedBox(
                        width: 150,
                        child: FilledButton(
                          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                          onPressed: _busy ? null : () => _run(() => app.accept(r.id, b.id)),
                          child: Text('Accept ${rs(b.fare)}'),
                        ),
                      ),
                    ]),
                  ]),
                ),
              )),
        const SizedBox(height: 4),
        OutlinedButton(onPressed: _busy ? null : _confirmCancel, child: const Text('Cancel')),
      ]);
    } else if (r.status == 'completed') {
      children.addAll([
        Center(child: Text('Cash ${rs(r.fare)} driver ko den', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
        const SizedBox(height: 12),
        if (driver != null) Center(child: Text('${driver.name} ko rate karo')),
        const SizedBox(height: 8),
        _Stars(onRate: (s) => _run(() => app.rate(r.id, s))),
        TextButton(onPressed: () => app.dismissRide(r.id), child: const Text('Skip')),
      ]);
    } else {
      if (driver != null) {
        children.addAll([
          DriverTile(
            driver: driver,
            trailing: IconButton.filled(onPressed: () => callNumber(context, driver.phone), icon: const Icon(Icons.call)),
          ),
          const SizedBox(height: 12),
          Row(children: [
            const Text('Fare (cash)', style: TextStyle(color: Pk.muted)),
            const Spacer(),
            Text(rs(r.fare), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          ]),
        ]);
      }
      if (r.status != 'in_trip') {
        children.addAll([
          const SizedBox(height: 12),
          OutlinedButton(onPressed: _busy ? null : _confirmCancel, child: const Text('Cancel ride')),
        ]);
      }
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: children);
  }
}

/* ------------------------------ DRIVER ------------------------------ */

class _DriverPanel extends StatefulWidget {
  const _DriverPanel({required this.ride, this.note});
  final Ride ride;
  final String? note;
  @override
  State<_DriverPanel> createState() => _DriverPanelState();
}

class _DriverPanelState extends State<_DriverPanel> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() fn) async {
    setState(() => _busy = true);
    await guard(context, fn);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.read(context);
    final r = widget.ride;
    final p = r.passenger;

    final label = switch (r.status) {
      'matched' => 'Raste mein hoon',
      'arriving' => 'Pohanch gaya',
      'arrived' => 'Trip shuru karo',
      'in_trip' => 'Trip complete — ${rs(r.fare)} cash lo',
      _ => '',
    };
    final toPickup = r.status != 'in_trip';

    final children = <Widget>[
      Text(statusText(r), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      const SizedBox(height: 10),
      RouteLines(pickup: r.pickup.label, dropoff: r.dropoff.label),
      if (widget.note != null) ...[
        const SizedBox(height: 8),
        Row(children: [
          const Icon(Icons.route_outlined, size: 16, color: Pk.green),
          const SizedBox(width: 6),
          Text(widget.note!, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        ]),
        const Text('Time andaza hai (live traffic ke bagair). Traffic ke liye Navigate dabao.',
            style: TextStyle(color: Pk.muted, fontSize: 11)),
      ],
      const SizedBox(height: 12),
      Row(children: [
        CircleAvatar(backgroundColor: Pk.surface2, child: Text(p.name.isEmpty ? '?' : p.name[0].toUpperCase())),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
            RatingChip(p.rating),
          ]),
        ),
        if (r.status != 'completed') IconButton.filled(onPressed: () => callNumber(context, p.phone), icon: const Icon(Icons.call)),
      ]),
      const SizedBox(height: 12),
    ];

    if (r.status == 'completed') {
      children.addAll([
        Center(child: Text('Aap ne ${rs(r.fare)} kamaye', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
        const SizedBox(height: 12),
        Center(child: Text('${p.name} ko rate karo')),
        const SizedBox(height: 8),
        _Stars(onRate: (s) => _run(() => app.rate(r.id, s))),
        TextButton(onPressed: () => app.dismissRide(r.id), child: const Text('Skip')),
      ]);
    } else {
      children.addAll([
        OutlinedButton.icon(
          onPressed: () => openNavigation(context, toPickup ? r.pickup.lat : r.dropoff.lat, toPickup ? r.pickup.lng : r.dropoff.lng),
          icon: const Icon(Icons.navigation_outlined),
          label: Text(toPickup ? 'Pickup tak navigate' : 'Dropoff tak navigate'),
        ),
        const SizedBox(height: 10),
        FilledButton(onPressed: _busy ? null : () => _run(() => app.advance(r.id)), child: Text(label)),
        if (r.status != 'in_trip') ...[
          const SizedBox(height: 8),
          TextButton(onPressed: _busy ? null : () => _run(() => app.cancel(r.id)), child: const Text('Cancel (ride wapas open hogi)')),
        ],
      ]);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: children);
  }
}

class _Stars extends StatelessWidget {
  const _Stars({required this.onRate});
  final ValueChanged<int> onRate;
  @override
  Widget build(BuildContext context) => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        for (var i = 1; i <= 5; i++)
          IconButton(
            iconSize: 38,
            onPressed: () => onRate(i),
            icon: const Icon(Icons.star_rounded, color: Pk.amber),
          ),
      ]);
}
