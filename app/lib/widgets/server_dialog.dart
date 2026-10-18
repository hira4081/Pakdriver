import 'package:flutter/material.dart';
import '../main.dart';
import '../theme.dart';
import 'common.dart';

/// Lets the user change the server link without rebuilding the app.
Future<void> showServerDialog(BuildContext context) async {
  final app = AppScope.read(context);
  final ctrl = TextEditingController(text: app.serverUrl);
  var busy = false;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: const Text('Server link'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Backend ka https link paste karo. Link badle to yahan naya daal do, app dobara install nahi karni.',
              style: TextStyle(color: Pk.muted, fontSize: 13)),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: TextInputType.url,
            decoration: deco('Server URL', hint: 'https://abc.trycloudflare.com'),
          ),
        ]),
        actions: [
          TextButton(onPressed: busy ? null : () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          TextButton(
            onPressed: busy
                ? null
                : () async {
                    setLocal(() => busy = true);
                    final ok = await guard(context, () => app.setServerUrl(ctrl.text));
                    if (!dialogContext.mounted) return;
                    if (ok) {
                      Navigator.pop(dialogContext);
                      if (context.mounted) toast(context, 'Server connect ho gaya');
                    } else {
                      setLocal(() => busy = false);
                    }
                  },
            child: Text(busy ? 'Check ho raha hai…' : 'Save'),
          ),
        ],
      ),
    ),
  );
  ctrl.dispose();
}
