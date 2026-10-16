import 'package:flutter/material.dart';
import '../main.dart';
import '../theme.dart';
import '../widgets/common.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _busy = false;

  Future<void> _go() async {
    final app = AppScope.of(context);
    setState(() => _busy = true);
    await guard(context, () async {
      await app.signIn();
    });
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Spacer(),
            const Text('PakDrive', style: TextStyle(fontSize: 46, fontWeight: FontWeight.w900, color: Pk.green)),
            const SizedBox(height: 10),
            const Text('Apna fare khud tay karo.\nDrivers bid karte hain.',
                style: TextStyle(fontSize: 20, height: 1.35, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            const Text('Bike, rickshaw ya car — poore Pakistan mein.', style: TextStyle(color: Pk.muted)),
            const Spacer(),
            FilledButton.icon(
              onPressed: _busy ? null : _go,
              icon: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.g_mobiledata_rounded, size: 34),
              label: const Text('Google se continue karo'),
            ),
            const SizedBox(height: 12),
            const Text(
              'Continue karne par aap hamari terms aur privacy policy se agree karte hain.',
              style: TextStyle(color: Pk.muted, fontSize: 12),
            ),
          ]),
        ),
      ),
    );
  }
}
