import 'package:flutter/material.dart';

import '../../ai_vision/offline_presets.dart';
import '../../models/game_models.dart';
import '../../storage/database.dart';
import 'map_parser_screen.dart';
import 'physics_engine_screen.dart';
import 'play_screen.dart';

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, required this.project});

  final GameProject project;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late GameProject _project;
  int _brush = TileType.solidGround;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _project = widget.project;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await GameDatabase.instance.upsertProject(_project);
    setState(() => _saving = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Project saved')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: TextEditingController(text: _project.name),
          style: const TextStyle(fontWeight: FontWeight.w700),
          decoration: const InputDecoration(
            border: InputBorder.none,
            isDense: true,
          ),
          onChanged: (v) => _project.name = v,
        ),
        actions: [
          IconButton(
            tooltip: 'AI Map',
            onPressed: () async {
              final map = await Navigator.of(context).push<TileMapData>(
                MaterialPageRoute(
                  builder: (_) => const MapParserScreen(returnMap: true),
                ),
              );
              if (map != null) setState(() => _project.map = map);
            },
            icon: const Icon(Icons.map_outlined),
          ),
          IconButton(
            tooltip: 'Physics',
            onPressed: () async {
              final physics = await Navigator.of(context).push<PhysicsMetrics>(
                MaterialPageRoute(
                  builder: (_) => PhysicsEngineScreen(
                    initial: _project.physics,
                    returnResult: true,
                  ),
                ),
              );
              if (physics != null) setState(() => _project.physics = physics);
            },
            icon: const Icon(Icons.science_outlined),
          ),
          IconButton(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
          ),
          IconButton(
            tooltip: 'Play',
            onPressed: () async {
              await _save();
              if (!context.mounted) return;
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PlayScreen(project: _project),
                ),
              );
            },
            icon: const Icon(Icons.play_arrow_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                _brushChip(TileType.air, 'Air', Colors.blueGrey),
                _brushChip(TileType.solidGround, 'Ground', const Color(0xFF3E6B4F)),
                _brushChip(TileType.hazard, 'Hazard', Colors.red),
                _brushChip(TileType.playerSpawn, 'Spawn', Colors.blue),
                _brushChip(TileType.item, 'Item', Colors.amber),
                const SizedBox(width: 8),
                ActionChip(
                  label: const Text('Reset map'),
                  onPressed: () {
                    setState(() => _project.map = OfflinePresets.starterMap());
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: _project.map.width / _project.map.height,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final cellW = constraints.maxWidth / _project.map.width;
                    final cellH = constraints.maxHeight / _project.map.height;
                    return GestureDetector(
                      onTapDown: (d) => _paintAt(d.localPosition, cellW, cellH),
                      onPanUpdate: (d) =>
                          _paintAt(d.localPosition, cellW, cellH),
                      child: CustomPaint(
                        painter: _MapPainter(map: _project.map),
                        size: Size(constraints.maxWidth, constraints.maxHeight),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'Physics: g=${_project.physics.gravityY.toStringAsFixed(0)} '
              'spd=${_project.physics.moveSpeed.toStringAsFixed(0)} '
              'jmp=${_project.physics.jumpVelocity.toStringAsFixed(0)}'
              '${_project.physics.doubleJump ? ' · double-jump' : ''}',
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _brushChip(int type, String label, Color color) {
    final selected = _brush == type;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        selected: selected,
        label: Text(label),
        avatar: CircleAvatar(backgroundColor: color, radius: 8),
        onSelected: (_) => setState(() => _brush = type),
      ),
    );
  }

  void _paintAt(Offset local, double cellW, double cellH) {
    final x = (local.dx / cellW).floor();
    final y = (local.dy / cellH).floor();
    if (x < 0 || y < 0 || x >= _project.map.width || y >= _project.map.height) {
      return;
    }
    if (_brush == TileType.playerSpawn) {
      // Clear previous spawn
      for (var i = 0; i < _project.map.tiles.length; i++) {
        if (_project.map.tiles[i] == TileType.playerSpawn) {
          _project.map.tiles[i] = TileType.air;
        }
      }
    }
    setState(() => _project.map.set(x, y, _brush));
  }
}

class _MapPainter extends CustomPainter {
  _MapPainter({required this.map});

  final TileMapData map;

  @override
  void paint(Canvas canvas, Size size) {
    final cellW = size.width / map.width;
    final cellH = size.height / map.height;
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
        canvas.drawRect(
          Rect.fromLTWH(x * cellW, y * cellH, cellW + 0.5, cellH + 0.5),
          paint,
        );
      }
    }
    // Grid
    final grid = Paint()
      ..color = const Color(0x22FFFFFF)
      ..style = PaintingStyle.stroke;
    for (var x = 0; x <= map.width; x++) {
      canvas.drawLine(
        Offset(x * cellW, 0),
        Offset(x * cellW, size.height),
        grid,
      );
    }
    for (var y = 0; y <= map.height; y++) {
      canvas.drawLine(
        Offset(0, y * cellH),
        Offset(size.width, y * cellH),
        grid,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MapPainter oldDelegate) => true;
}
