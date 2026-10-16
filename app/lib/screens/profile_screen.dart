import 'package:flutter/material.dart';
import '../main.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.first = false, this.initialRole});

  /// First-time setup (no back button, no cancel).
  final bool first;
  final String? initialRole;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final TextEditingController _name, _phone, _make, _model, _color, _plate;
  late String _role;
  late String _vType;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final me = AppScope.read(context).me!;
    _name = TextEditingController(text: me.name);
    _phone = TextEditingController(text: me.phone ?? '');
    final v = me.vehicle;
    _make = TextEditingController(text: v?.make ?? '');
    _model = TextEditingController(text: v?.model ?? '');
    _color = TextEditingController(text: v?.color ?? '');
    _plate = TextEditingController(text: v?.plate ?? '');
    _vType = v?.type ?? 'car';
    _role = widget.initialRole ?? me.role;
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _make, _model, _color, _plate]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final phone = _phone.text.replaceAll(RegExp(r'[\s-]'), '');
    if (!RegExp(r'^\+?[0-9]{10,14}$').hasMatch(phone)) {
      toast(context, 'Sahi phone number likho (e.g. 03001234567)');
      return;
    }
    if (_name.text.trim().length < 2) {
      toast(context, 'Naam likho');
      return;
    }
    final body = <String, dynamic>{'name': _name.text.trim(), 'phone': phone, 'role': _role};
    if (_role == 'driver') {
      if (_plate.text.trim().length < 3) {
        toast(context, 'Number plate likho');
        return;
      }
      body['vehicleType'] = _vType;
      body['vehiclePlate'] = _plate.text.trim();
      if (_make.text.trim().isNotEmpty) body['vehicleMake'] = _make.text.trim();
      if (_model.text.trim().isNotEmpty) body['vehicleModel'] = _model.text.trim();
      if (_color.text.trim().isNotEmpty) body['vehicleColor'] = _color.text.trim();
    }
    final app = AppScope.of(context);
    setState(() => _busy = true);
    final ok = await guard(context, () => app.updateProfile(body));
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok && !widget.first) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.first ? 'Profile banao' : 'Profile'),
        automaticallyImplyLeading: !widget.first,
        actions: [
          if (widget.first) TextButton(onPressed: app.signOut, child: const Text('Sign out')),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(app.me!.email, style: const TextStyle(color: Pk.muted)),
        const SizedBox(height: 12),
        TextField(controller: _name, textCapitalization: TextCapitalization.words, decoration: deco('Naam', icon: Icons.person_outline)),
        const SizedBox(height: 12),
        TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: deco('Phone number', hint: '03001234567', icon: Icons.phone_outlined)),
        const SizedBox(height: 20),
        const Text('Aap kya karna chahte hain?', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'rider', label: Text('Ride lena'), icon: Icon(Icons.person_pin_circle_outlined)),
            ButtonSegment(value: 'driver', label: Text('Drive karna'), icon: Icon(Icons.directions_car_outlined)),
          ],
          selected: {_role},
          onSelectionChanged: (s) => setState(() => _role = s.first),
        ),
        if (_role == 'driver') ...[
          const SizedBox(height: 20),
          const Text('Aap ki gaari', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            for (final t in vehicleTypes)
              ChoiceChip(label: Text(vehicleLabel(t)), selected: _vType == t, onSelected: (_) => setState(() => _vType = t)),
          ]),
          const SizedBox(height: 12),
          TextField(controller: _plate, textCapitalization: TextCapitalization.characters, decoration: deco('Number plate', hint: 'ABC-123')),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextField(controller: _make, decoration: deco('Company', hint: 'Suzuki'))),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: _model, decoration: deco('Model', hint: 'Cultus'))),
          ]),
          const SizedBox(height: 12),
          TextField(controller: _color, decoration: deco('Rang', hint: 'White')),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save'),
        ),
      ]),
    );
  }
}
