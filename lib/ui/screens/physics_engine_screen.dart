import 'dart:convert';

import 'package:flutter/material.dart';

import '../../ai_vision/offline_presets.dart';
import '../../ai_vision/openai_client.dart';
import '../../models/game_models.dart';
import '../widgets/loading_overlay.dart';

class PhysicsEngineScreen extends StatefulWidget {
  const PhysicsEngineScreen({
    super.key,
    this.initial,
    this.returnResult = false,
  });

  final PhysicsMetrics? initial;
  final bool returnResult;

  @override
  State<PhysicsEngineScreen> createState() => _PhysicsEngineScreenState();
}

class _PhysicsEngineScreenState extends State<PhysicsEngineScreen> {
  final _client = OpenAiClient();
  late final PhysicsExtractor _extractor = PhysicsExtractor(_client);
  late final TextEditingController _desc;
  late PhysicsMetrics _metrics;
  bool _busy = false;
  String? _message;
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    _metrics = widget.initial ?? const PhysicsMetrics();
    _desc = TextEditingController(
      text: 'fast platformer with floaty double jump',
    );
  }

  @override
  void dispose() {
    _desc.dispose();
    _client.dispose();
    super.dispose();
  }

  Future<void> _extract() async {
    setState(() {
      _busy = true;
      _message = 'Extracting physics metrics…';
    });
    final result = await _extractor.extractFromDescription(_desc.text.trim());
    setState(() {
      _busy = false;
      _metrics = result.value;
      _offline = result.fromOfflineFallback;
      _message = result.fromOfflineFallback
          ? 'Offline preset: ${result.error ?? "keyword match"}'
          : 'Applied AI physics metrics';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Video Game Understanding'),
        actions: [
          if (widget.returnResult)
            TextButton(
              onPressed: () => Navigator.pop(context, _metrics),
              child: const Text('Apply'),
            ),
        ],
      ),
      body: LoadingOverlay(
        visible: _busy,
        message: _message ?? 'Working…',
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Describe mechanics or paste notes from gameplay footage. '
              'OpenAI returns gravity, speed, jump, accel, and friction — '
              'or an offline preset is chosen from keywords.',
              style: TextStyle(color: Colors.white70, height: 1.4),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _desc,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Gameplay description',
                hintText: 'e.g. floaty double jump like Celeste',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy ? null : _extract,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Extract physics'),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: OfflinePresets.catalog()
                  .map(
                    (p) => ActionChip(
                      label: Text(p.name),
                      onPressed: () => setState(() {
                        _metrics = p.metrics;
                        _offline = true;
                        _message = 'Loaded ${p.name}';
                      }),
                    ),
                  )
                  .toList(),
            ),
            if (_message != null) ...[
              const SizedBox(height: 12),
              Text(
                _message!,
                style: TextStyle(
                  color: _offline ? Colors.amberAccent : Colors.greenAccent,
                ),
              ),
            ],
            const SizedBox(height: 20),
            _metricSlider(
              'Gravity Y',
              _metrics.gravityY,
              400,
              1800,
              (v) => setState(
                () => _metrics = _metrics.copyWith(gravityY: v),
              ),
            ),
            _metricSlider(
              'Move speed',
              _metrics.moveSpeed,
              60,
              360,
              (v) => setState(
                () => _metrics = _metrics.copyWith(moveSpeed: v),
              ),
            ),
            _metricSlider(
              'Jump velocity',
              _metrics.jumpVelocity,
              200,
              700,
              (v) => setState(
                () => _metrics = _metrics.copyWith(jumpVelocity: v),
              ),
            ),
            _metricSlider(
              'Acceleration',
              _metrics.acceleration,
              400,
              2400,
              (v) => setState(
                () => _metrics = _metrics.copyWith(acceleration: v),
              ),
            ),
            _metricSlider(
              'Friction',
              _metrics.friction,
              0.5,
              0.98,
              (v) => setState(
                () => _metrics = _metrics.copyWith(friction: v),
              ),
            ),
            SwitchListTile(
              title: const Text('Double jump'),
              value: _metrics.doubleJump,
              onChanged: (v) => setState(
                () => _metrics = _metrics.copyWith(doubleJump: v),
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SelectableText(
                  const JsonEncoder.withIndent('  ').convert(_metrics.toJson()),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: Colors.white70,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricSlider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label: ${value.toStringAsFixed(2)}'),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
