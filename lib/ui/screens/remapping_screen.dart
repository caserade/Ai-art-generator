import 'package:flutter/material.dart';

import '../../controllers/dual_control_engine.dart';
import '../../models/game_models.dart';

class RemappingScreen extends StatefulWidget {
  const RemappingScreen({super.key});

  @override
  State<RemappingScreen> createState() => _RemappingScreenState();
}

class _RemappingScreenState extends State<RemappingScreen> {
  late final DualControlEngine _engine;
  String? _listeningFor;
  final _physicalKeys = const [
    'a',
    'b',
    'x',
    'y',
    'cross',
    'circle',
    'square',
    'triangle',
    'button_a',
    'button_b',
    'dpad_up',
    'dpad_down',
    'dpad_left',
    'dpad_right',
  ];

  @override
  void initState() {
    super.initState();
    _engine = DualControlEngine();
    _engine.start();
  }

  @override
  void dispose() {
    _engine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pads = _engine.connectedPadNames;
    return Scaffold(
      appBar: AppBar(title: const Text('Controller Remapping')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            pads.isEmpty
                ? 'No physical gamepad detected. Connect Xbox, DualSense, or 8BitDo via Bluetooth/USB.'
                : 'Connected: ${pads.join(", ")}',
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            title: const Text('Haptic feedback'),
            value: _engine.hapticsEnabled,
            onChanged: (v) => setState(() => _engine.hapticsEnabled = v),
          ),
          const Divider(),
          const Text(
            'Logical bindings',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          ...GamepadButton.values.map((logical) {
            final physical = _engine.remap.bindings.entries
                .where((e) => e.value == logical)
                .map((e) => e.key)
                .take(3)
                .join(', ');
            return ListTile(
              title: Text(logical.name.toUpperCase()),
              subtitle: Text(physical.isEmpty ? 'Unmapped' : physical),
              trailing: TextButton(
                onPressed: () => _showRemapDialog(logical),
                child: const Text('Remap'),
              ),
            );
          }),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              setState(() {
                _engine.remap.bindings
                  ..clear()
                  ..addAll(ButtonRemapConfig.defaultBindings());
              });
            },
            child: const Text('Reset to defaults'),
          ),
        ],
      ),
    );
  }

  Future<void> _showRemapDialog(GamepadButton logical) async {
    String? selected;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: Text('Map physical → ${logical.name.toUpperCase()}'),
              content: DropdownButton<String>(
                isExpanded: true,
                value: selected,
                hint: const Text('Physical key id'),
                items: _physicalKeys
                    .map((k) => DropdownMenuItem(value: k, child: Text(k)))
                    .toList(),
                onChanged: (v) => setLocal(() => selected = v),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: selected == null
                      ? null
                      : () {
                          _engine.remap.setBinding(selected!, logical);
                          Navigator.pop(ctx);
                          setState(() => _listeningFor = selected);
                        },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
    if (_listeningFor != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Bound $_listeningFor → ${logical.name}')),
      );
      _listeningFor = null;
    }
  }
}
