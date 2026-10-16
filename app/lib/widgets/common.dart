import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api.dart';
import '../models.dart';
import '../theme.dart';

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
}

/// Runs [fn], shows any error as a snackbar. Returns true on success.
Future<bool> guard(BuildContext context, Future<void> Function() fn) async {
  try {
    await fn();
    return true;
  } on ApiException catch (e) {
    if (context.mounted) toast(context, e.message);
  } catch (e) {
    if (context.mounted) toast(context, 'Kuch ghalat ho gaya: $e');
  }
  return false;
}

Future<void> callNumber(BuildContext context, String? phone) async {
  if (phone == null) return;
  final ok = await launchUrl(Uri(scheme: 'tel', path: phone));
  if (!ok && context.mounted) toast(context, 'Call nahi ho saki');
}

Future<void> openNavigation(BuildContext context, double lat, double lng) async {
  final uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving');
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) toast(context, 'Maps khul nahi saka');
}

class RatingChip extends StatelessWidget {
  const RatingChip(this.rating, {super.key});
  final double? rating;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.star_rounded, size: 16, color: Pk.amber),
        const SizedBox(width: 2),
        Text(rating == null ? 'New' : rating!.toStringAsFixed(1), style: const TextStyle(fontSize: 13)),
      ]);
}

class DriverTile extends StatelessWidget {
  const DriverTile({super.key, required this.driver, this.trailing});
  final Person driver;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    final v = driver.vehicle;
    return Row(children: [
      CircleAvatar(
        radius: 22,
        backgroundColor: Pk.surface2,
        child: Text(driver.name.isEmpty ? '?' : driver.name[0].toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Flexible(child: Text(driver.name, style: const TextStyle(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 8),
            RatingChip(driver.rating),
          ]),
          if (v != null)
            Text('${v.title} • ${v.plate ?? ''}', style: const TextStyle(color: Pk.muted, fontSize: 13), overflow: TextOverflow.ellipsis),
        ]),
      ),
      if (trailing != null) trailing!,
    ]);
  }
}

class RouteLines extends StatelessWidget {
  const RouteLines({super.key, required this.pickup, required this.dropoff});
  final String pickup, dropoff;
  @override
  Widget build(BuildContext context) => Column(children: [
        Row(children: [
          const Icon(Icons.circle, size: 12, color: Pk.green),
          const SizedBox(width: 10),
          Expanded(child: Text(pickup, maxLines: 1, overflow: TextOverflow.ellipsis)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          const Icon(Icons.square_rounded, size: 12, color: Pk.danger),
          const SizedBox(width: 10),
          Expanded(child: Text(dropoff, maxLines: 1, overflow: TextOverflow.ellipsis)),
        ]),
      ]);
}

/// Bottom sheet card used over maps.
class Sheet extends StatelessWidget {
  const Sheet({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          color: Pk.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 24)],
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: SafeArea(top: false, child: child),
      );
}

/// Fare editor: [-] Rs 450 [+]
class FareStepper extends StatelessWidget {
  const FareStepper({super.key, required this.fare, required this.onChanged, this.step = 20});
  final int fare, step;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        IconButton.filledTonal(onPressed: fare - step >= 50 ? () => onChanged(fare - step) : null, icon: const Icon(Icons.remove)),
        const SizedBox(width: 18),
        Text(rs(fare), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
        const SizedBox(width: 18),
        IconButton.filledTonal(onPressed: fare + step <= 100000 ? () => onChanged(fare + step) : null, icon: const Icon(Icons.add)),
      ]);
}
