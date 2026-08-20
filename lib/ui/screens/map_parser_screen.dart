import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../ai_vision/openai_client.dart';
import '../../models/game_models.dart';
import '../widgets/loading_overlay.dart';

class MapParserScreen extends StatefulWidget {
  const MapParserScreen({super.key, this.returnMap = false});

  final bool returnMap;

  @override
  State<MapParserScreen> createState() => _MapParserScreenState();
}

class _MapParserScreenState extends State<MapParserScreen> {
  final _picker = ImagePicker();
  final _client = OpenAiClient();
  late final MapParser _parser = MapParser(_client);

  TileMapData? _map;
  bool _busy = false;
  String? _message;
  bool _offline = false;

  @override
  void dispose() {
    _client.dispose();
    super.dispose();
  }

  Future<void> _parseFromGallery() async {
    final file = await _picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    final b64 = base64Encode(bytes);
    setState(() {
      _busy = true;
      _message = 'Sending sketch to OpenAI Vision…';
    });
    final result = await _parser.parseMapImage(imageBase64: b64);
    setState(() {
      _busy = false;
      _map = result.value;
      _offline = result.fromOfflineFallback;
      _message = result.fromOfflineFallback
          ? 'Offline fallback: ${result.error ?? "preset map"}'
          : 'Map parsed · ${result.value.width}×${result.value.height}';
    });
  }

  Future<void> _useOfflinePreset() async {
    setState(() {
      _map = TileMapData.defaultPlatformer();
      _offline = true;
      _message = 'Loaded offline starter map';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Map & Layout Parser'),
        actions: [
          if (widget.returnMap && _map != null)
            TextButton(
              onPressed: () => Navigator.pop(context, _map),
              child: const Text('Use map'),
            ),
        ],
      ),
      body: LoadingOverlay(
        visible: _busy,
        message: _message ?? 'Parsing…',
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Upload a level sketch. GPT-4o Vision returns a strict tile grid '
              '(0 Air · 1 Ground · 2 Hazard · 3 Spawn · 4 Item). '
              'Without an API key, an offline preset is used.',
              style: TextStyle(color: Colors.white70, height: 1.4),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _parseFromGallery,
              icon: const Icon(Icons.image_search),
              label: const Text('Parse map image'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _useOfflinePreset,
              icon: const Icon(Icons.offline_bolt_outlined),
              label: const Text('Use offline preset'),
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
            if (_map != null) ...[
              const SizedBox(height: 20),
              AspectRatio(
                aspectRatio: _map!.width / _map!.height,
                child: CustomPaint(painter: _MiniMapPainter(_map!)),
              ),
              const SizedBox(height: 12),
              Text(
                'Tiles: ${_map!.tiles.where((t) => t != 0).length} non-air · '
                'spawn @ ${_map!.findSpawn()}',
                style: const TextStyle(color: Colors.white60),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MiniMapPainter extends CustomPainter {
  _MiniMapPainter(this.map);
  final TileMapData map;

  @override
  void paint(Canvas canvas, Size size) {
    final cw = size.width / map.width;
    final ch = size.height / map.height;
    final paint = Paint();
    for (var y = 0; y < map.height; y++) {
      for (var x = 0; x < map.width; x++) {
        final t = map.at(x, y);
        paint.color = switch (t) {
          TileType.solidGround => const Color(0xFF3E6B4F),
          TileType.hazard => const Color(0xFFC62828),
          TileType.playerSpawn => const Color(0xFF1565C0),
          TileType.item => const Color(0xFFF9A825),
          _ => const Color(0xFF1B2838),
        };
        canvas.drawRect(Rect.fromLTWH(x * cw, y * ch, cw, ch), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MiniMapPainter oldDelegate) => true;
}
