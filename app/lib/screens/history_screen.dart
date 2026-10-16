import 'package:flutter/material.dart';
import '../main.dart';
import '../theme.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final b = AppScope.of(context).board!;
    return Scaffold(
      appBar: AppBar(title: const Text('Trips & earnings')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (b.me.isDriver || b.wallet > 0)
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: Pk.surface, borderRadius: BorderRadius.circular(18)),
            child: Row(children: [
              const Text('Total kamai (cash)', style: TextStyle(color: Pk.muted)),
              const Spacer(),
              Text(rs(b.wallet), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Pk.green)),
            ]),
          ),
        const SizedBox(height: 16),
        if (b.trips.isEmpty) const Center(child: Padding(padding: EdgeInsets.all(40), child: Text('Abhi koi trip nahi', style: TextStyle(color: Pk.muted)))),
        for (final t in b.trips)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Pk.surface, borderRadius: BorderRadius.circular(16)),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${t.pickup} → ${t.dropoff}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(
                      '${t.role == 'rider' ? 'Driver' : 'Rider'}: ${t.counterpart}  •  ${t.status == 'completed' ? 'Complete' : 'Cancelled'}',
                      style: const TextStyle(color: Pk.muted, fontSize: 12),
                    ),
                  ]),
                ),
                const SizedBox(width: 10),
                Text(rs(t.fare), style: TextStyle(fontWeight: FontWeight.w800, color: t.status == 'completed' ? null : Pk.muted)),
              ]),
            ),
          ),
      ]),
    );
  }
}
