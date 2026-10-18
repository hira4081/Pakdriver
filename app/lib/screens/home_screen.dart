import 'package:flutter/material.dart';
import '../config.dart';
import '../main.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/server_dialog.dart';
import 'driver_home.dart';
import 'history_screen.dart';
import 'profile_screen.dart';
import 'rider_home.dart';
import 'ride_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _switchRole(BuildContext context) async {
    final app = AppScope.of(context);
    final me = app.me!;
    if (me.isDriver) {
      await guard(context, () => app.updateProfile({'role': 'rider'}));
    } else if (me.vehicle == null) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileScreen(initialRole: 'driver')));
    } else {
      await guard(context, () => app.updateProfile({'role': 'driver'}));
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final me = app.me!;
    final ride = app.activeRide;

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppConfig.appName, style: TextStyle(fontWeight: FontWeight.w900, color: Pk.green)),
        actions: [
          if (ride == null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: ActionChip(
                avatar: Icon(me.isDriver ? Icons.person_pin_circle_outlined : Icons.directions_car_outlined, size: 18),
                label: Text(me.isDriver ? 'Ride lo' : 'Drive karo'),
                onPressed: () => _switchRole(context),
              ),
            ),
          PopupMenuButton<String>(
            onSelected: (v) {
              final nav = Navigator.of(context);
              if (v == 'profile') nav.push(MaterialPageRoute(builder: (_) => const ProfileScreen()));
              if (v == 'history') nav.push(MaterialPageRoute(builder: (_) => const HistoryScreen()));
              if (v == 'server') showServerDialog(context);
              if (v == 'out') app.signOut();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'profile', child: Text('Profile')),
              PopupMenuItem(value: 'history', child: Text('Trips & earnings')),
              PopupMenuItem(value: 'server', child: Text('Server link')),
              PopupMenuItem(value: 'out', child: Text('Sign out')),
            ],
          ),
        ],
      ),
      body: Column(children: [
        if (app.connectionError != null)
          Container(
            width: double.infinity,
            color: Pk.danger,
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
            child: Text(app.connectionError!, style: const TextStyle(fontSize: 12)),
          ),
        Expanded(
          child: ride != null
              ? RideScreen(ride: ride)
              : (me.isDriver ? const DriverHome() : const RiderHome()),
        ),
      ]),
    );
  }
}
