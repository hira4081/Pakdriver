import 'package:flutter/material.dart';
import 'app_state.dart';
import 'config.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/profile_screen.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PakDriveApp());
}

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState app, required super.child}) : super(notifier: app);
  /// Rebuilds the caller whenever the app state changes.
  static AppState of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  /// No rebuild subscription — safe to call from initState / callbacks.
  static AppState read(BuildContext context) => context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}

class PakDriveApp extends StatefulWidget {
  const PakDriveApp({super.key});
  @override
  State<PakDriveApp> createState() => _PakDriveAppState();
}

class _PakDriveAppState extends State<PakDriveApp> with WidgetsBindingObserver {
  final AppState app = AppState();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    app.boot();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    app.setPaused(state != AppLifecycleState.resumed);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    app.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      app: app,
      child: MaterialApp(
        title: AppConfig.appName,
        debugShowCheckedModeBanner: false,
        theme: Pk.theme(),
        home: const _Root(),
      ),
    );
  }
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (app.booting) return const _Splash();
    if (!app.signedIn) return const LoginScreen();
    final board = app.board;
    if (board == null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (app.connectionError == null) ...[
                const CircularProgressIndicator(),
              ] else ...[
                const Icon(Icons.wifi_off_rounded, size: 48, color: Pk.muted),
                const SizedBox(height: 12),
                Text(app.connectionError!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(onPressed: app.refresh, child: const Text('Dobara koshish karo')),
                const SizedBox(height: 8),
                TextButton(onPressed: app.signOut, child: const Text('Sign out')),
              ],
            ]),
          ),
        ),
      );
    }
    if (board.me.needsSetup) return const ProfileScreen(first: true);
    return const HomeScreen();
  }
}

class _Splash extends StatelessWidget {
  const _Splash();
  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(child: Text('PakDrive', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: Pk.green))),
      );
}
