import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../config.dart';
import '../main.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/pak_map.dart';

class DriverHome extends StatefulWidget {
  const DriverHome({super.key});
  @override
  State<DriverHome> createState() => _DriverHomeState();
}

class _DriverHomeState extends State<DriverHome> {
  bool _busy = false;

  Future<void> _toggle(bool online) async {
    final app = AppScope.read(context);
    setState(() => _busy = true);
    await guard(context, () => app.setOnline(online));
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _bid(Nearby n) async {
    final app = AppScope.read(context);
    final fare = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Pk.surface,
      builder: (_) => _BidSheet(nearby: n),
    );
    if (fare == null || !mounted) return;
    final ok = await guard(context, () => app.bid(n.id, fare));
    if (ok && mounted) toast(context, 'Bid bhej di: ${rs(fare)}');
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final b = app.board!;
    final me = b.me;

    if (!me.isOnline) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: Pk.surface, borderRadius: BorderRadius.circular(18)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Total kamai (cash)', style: TextStyle(color: Pk.muted)),
              const SizedBox(height: 4),
              Text(rs(b.wallet), style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: Pk.green)),
              const SizedBox(height: 4),
              Text('${me.tripsCount} trips • ${me.rating?.toStringAsFixed(1) ?? 'New'} ★', style: const TextStyle(color: Pk.muted)),
            ]),
          ),
          const Spacer(),
          Text('${vehicleLabel(me.vehicle?.type ?? 'car')} • ${me.vehicle?.plate ?? ''}', textAlign: TextAlign.center, style: const TextStyle(color: Pk.muted)),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy ? null : () => _toggle(true),
            child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Online ho jao'),
          ),
          const SizedBox(height: 8),
        ]),
      );
    }

    final pts = b.nearby.map((n) => pin(LatLng(n.pickup.lat, n.pickup.lng), Icons.person_pin_circle, Pk.green)).toList();
    return Column(children: [
      SizedBox(
        height: 210,
        child: PakMap(
          key: ValueKey('nearby-${b.nearby.length}'),
          center: const LatLng(AppConfig.defaultLat, AppConfig.defaultLng),
          zoom: 12,
          fitPoints: b.nearby.length >= 2 ? b.nearby.map((n) => LatLng(n.pickup.lat, n.pickup.lng)).toList() : null,
          markers: pts,
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
        child: Row(children: [
          const Icon(Icons.circle, size: 10, color: Pk.green),
          const SizedBox(width: 8),
          const Text('Aap online hain', style: TextStyle(fontWeight: FontWeight.w700)),
          const Spacer(),
          Text(rs(b.wallet), style: const TextStyle(color: Pk.green, fontWeight: FontWeight.w800)),
          const SizedBox(width: 12),
          OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 36)),
            onPressed: _busy ? null : () => _toggle(false),
            child: const Text('Offline'),
          ),
        ]),
      ),
      Expanded(
        child: b.nearby.isEmpty
            ? const Center(child: Text('Aap ke qareeb abhi koi request nahi.\nNayi requests yahan aa jayengi.', textAlign: TextAlign.center, style: TextStyle(color: Pk.muted)))
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: b.nearby.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _NearbyCard(n: b.nearby[i], onBid: () => _bid(b.nearby[i])),
              ),
      ),
    ]);
  }
}

class _NearbyCard extends StatelessWidget {
  const _NearbyCard({required this.n, required this.onBid});
  final Nearby n;
  final VoidCallback onBid;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Pk.surface, borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Text(n.passengerName, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            RatingChip(n.passengerRating),
            const Spacer(),
            Text(rs(n.offeredFare), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          ]),
          const SizedBox(height: 10),
          RouteLines(pickup: n.pickup.label, dropoff: n.dropoff.label),
          const SizedBox(height: 8),
          Text('${n.pickupAwayKm} km door • trip ${n.distanceKm} km', style: const TextStyle(color: Pk.muted, fontSize: 13)),
          const SizedBox(height: 10),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
            onPressed: onBid,
            child: Text(n.myBid == null ? 'Bid karo' : 'Aap ki bid ${rs(n.myBid!)} — badlo'),
          ),
        ]),
      );
}

class _BidSheet extends StatefulWidget {
  const _BidSheet({required this.nearby});
  final Nearby nearby;
  @override
  State<_BidSheet> createState() => _BidSheetState();
}

class _BidSheetState extends State<_BidSheet> {
  late int _fare = widget.nearby.myBid ?? widget.nearby.offeredFare;
  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).padding.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Rider ka offer: ${rs(widget.nearby.offeredFare)}', textAlign: TextAlign.center, style: const TextStyle(color: Pk.muted)),
          const SizedBox(height: 12),
          FareStepper(fare: _fare, step: 10, onChanged: (v) => setState(() => _fare = v)),
          const SizedBox(height: 16),
          FilledButton(onPressed: () => Navigator.pop(context, _fare), child: Text('${rs(_fare)} ki bid bhejo')),
        ]),
      );
}
