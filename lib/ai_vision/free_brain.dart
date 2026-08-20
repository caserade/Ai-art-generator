import 'dart:math';

import '../models/game_models.dart';
import 'mcp_tools.dart';
import 'offline_presets.dart';

/// On-device "Free Brain" — smart game-design AI with zero API cost.
///
/// Uses genre heuristics, procedural generation, and MCP tool routing so the
/// studio stays useful offline. OpenAI can call the same tools when a key exists.
class FreeBrain {
  FreeBrain({Random? random}) : _rng = random ?? Random();

  final Random _rng;

  static const identity =
      'Free Brain — on-device game design intelligence (no API key required).';

  /// Chat entry: routes intent to MCP tools and returns a designer reply.
  Future<BrainReply> think(String userMessage, {GameProject? context}) async {
    final text = userMessage.trim();
    if (text.isEmpty) {
      return const BrainReply(
        text: 'Tell me the game you want — genre, feel, or a one-line fantasy.',
        source: BrainSource.freeBrain,
      );
    }

    final lower = text.toLowerCase();
    final wordCount = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

    // Rich briefs → full game design (before single-keyword physics routing)
    if (wordCount >= 6 ||
        _matches(lower, [
          'design',
          'make a game',
          'create a game',
          'build me',
          'new game',
          'platformer',
          'metroidvania',
          'roguelike',
        ])) {
      final result = await invokeTool('design_game', {
        'prompt': text,
        'name': _guessTitle(text),
      });
      return BrainReply(
        text: '${result.message}\n\nTip: say “generate map” or “make it floaty” to refine.',
        source: BrainSource.freeBrain,
        toolResult: result,
        project: result.project,
        map: result.map,
        physics: result.physics,
      );
    }

    if (_matches(lower, ['level', 'map', 'stage', 'generate map', 'new map'])) {
      final style = _inferLevelStyle(lower);
      final result = await invokeTool('generate_level', {
        'style': style,
        'difficulty': _inferDifficulty(lower),
      });
      return BrainReply(
        text: result.message,
        source: BrainSource.freeBrain,
        toolResult: result,
        map: result.map,
      );
    }

    if (_matches(lower, [
      'physics',
      'gravity',
      'feel',
      'floaty',
      'tight',
      'controls',
      'icy',
      'moon',
    ])) {
      final result = await invokeTool('tune_physics', {'description': text});
      return BrainReply(
        text: result.message,
        source: BrainSource.freeBrain,
        toolResult: result,
        physics: result.physics,
      );
    }

    if (_matches(lower, ['art', 'sprite', 'character', 'scan', 'draw'])) {
      final result = await invokeTool('suggest_art_pipeline', {
        'character': text,
      });
      return BrainReply(
        text: result.message,
        source: BrainSource.freeBrain,
        toolResult: result,
      );
    }

    final explain = await invokeTool('explain_mechanics', {
      'question': text,
      if (context != null) 'physics': context.physics.toJson(),
    });
    return BrainReply(
      text: explain.message,
      source: BrainSource.freeBrain,
      toolResult: explain,
      physics: explain.physics,
    );
  }

  /// Execute a named MCP tool with Free Brain intelligence.
  Future<McpToolResult> invokeTool(
    String name,
    Map<String, dynamic> args,
  ) async {
    switch (name) {
      case 'design_game':
        return _designGame(
          prompt: args['prompt'] as String? ?? '',
          name: args['name'] as String?,
        );
      case 'generate_level':
        return _generateLevel(
          style: args['style'] as String? ?? 'classic',
          width: (args['width'] as num?)?.toInt() ?? 20,
          height: (args['height'] as num?)?.toInt() ?? 12,
          difficulty: (args['difficulty'] as num?)?.toDouble() ?? 0.45,
        );
      case 'tune_physics':
        return _tunePhysics(args['description'] as String? ?? '');
      case 'suggest_art_pipeline':
        return _suggestArt(args['character'] as String? ?? 'hero');
      case 'explain_mechanics':
        return _explain(
          args['question'] as String? ?? '',
          physics: args['physics'] is Map<String, dynamic>
              ? PhysicsMetrics.fromJson(args['physics'] as Map<String, dynamic>)
              : null,
        );
      default:
        return McpToolResult(
          toolName: name,
          message: 'Unknown tool "$name". Available: design_game, generate_level, '
              'tune_physics, suggest_art_pipeline, explain_mechanics.',
        );
    }
  }

  McpToolResult _designGame({required String prompt, String? name}) {
    final lower = prompt.toLowerCase();
    final style = _inferLevelStyle(lower);
    final difficulty = _inferDifficulty(lower);
    final physics = OfflinePresets.physicsForDescription(prompt);
    // Blend physics with style bias
    final tuned = _styleBiasPhysics(physics, style, difficulty);
    final level = _generateLevel(
      style: style,
      width: style == 'vertical' ? 14 : 22,
      height: style == 'vertical' ? 16 : 12,
      difficulty: difficulty,
    );
    final title = (name != null && name.trim().isNotEmpty)
        ? name.trim()
        : _guessTitle(prompt);
    final project = GameProject(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: title,
      description: prompt,
      map: level.map!,
      physics: tuned,
    );
    final notes = _designNotes(prompt, style, tuned);
    return McpToolResult(
      toolName: 'design_game',
      message: 'Designed "$title" ($style, difficulty ${(difficulty * 100).round()}%).\n$notes',
      project: project,
      map: project.map,
      physics: project.physics,
      data: {'style': style, 'difficulty': difficulty},
    );
  }

  McpToolResult _generateLevel({
    required String style,
    required int width,
    required int height,
    required double difficulty,
  }) {
    final w = width.clamp(12, 32);
    final h = height.clamp(8, 18);
    final tiles = List<int>.filled(w * h, TileType.air);

    // Floor
    for (var x = 0; x < w; x++) {
      tiles[(h - 1) * w + x] = TileType.solidGround;
      tiles[(h - 2) * w + x] = TileType.solidGround;
    }

    switch (style) {
      case 'vertical':
        _carveVertical(tiles, w, h, difficulty);
      case 'speedrun':
        _carveSpeedrun(tiles, w, h, difficulty);
      case 'puzzle':
        _carvePuzzle(tiles, w, h, difficulty);
      case 'hazard_gauntlet':
        _carveHazards(tiles, w, h, difficulty, dense: true);
      case 'collectathon':
        _carveCollectathon(tiles, w, h, difficulty);
      default:
        _carveClassic(tiles, w, h, difficulty);
    }

    // Ensure spawn + at least one item
    _forceSpawn(tiles, w, h);
    if (!tiles.contains(TileType.item)) {
      tiles[2 * w + (w ~/ 2)] = TileType.item;
    }

    final map = TileMapData(width: w, height: h, tiles: tiles);
    return McpToolResult(
      toolName: 'generate_level',
      message:
          'Generated $style level ${w}x$h with ${tiles.where((t) => t == TileType.hazard).length} hazards '
          'and ${tiles.where((t) => t == TileType.item).length} items.',
      map: map,
      data: {'style': style, 'difficulty': difficulty},
    );
  }

  McpToolResult _tunePhysics(String description) {
    final base = OfflinePresets.physicsForDescription(description);
    final lower = description.toLowerCase();
    var m = base;

    // Fine-grained free-brain tuning
    if (lower.contains('super float') || lower.contains('moon')) {
      m = m.copyWith(gravityY: 480, jumpVelocity: 360, airControl: 0.95, doubleJump: true);
    } else if (lower.contains('sticky') || lower.contains('ice')) {
      m = m.copyWith(friction: 0.96, acceleration: 700, airControl: 0.3);
    } else if (lower.contains('arcade') || lower.contains('mario')) {
      m = m.copyWith(gravityY: 1100, jumpVelocity: 460, moveSpeed: 200, friction: 0.8);
    } else if (lower.contains('precision') || lower.contains('celeste')) {
      m = m.copyWith(
        gravityY: 900,
        jumpVelocity: 400,
        moveSpeed: 190,
        acceleration: 1400,
        friction: 0.78,
        doubleJump: true,
        airControl: 0.9,
      );
    }

    return McpToolResult(
      toolName: 'tune_physics',
      message: 'Physics tuned for “$description”.\n'
          'g=${m.gravityY.toStringAsFixed(0)} spd=${m.moveSpeed.toStringAsFixed(0)} '
          'jmp=${m.jumpVelocity.toStringAsFixed(0)}'
          '${m.doubleJump ? ' · double-jump' : ''}',
      physics: m,
      data: m.toJson(),
    );
  }

  McpToolResult _suggestArt(String character) {
    final lower = character.toLowerCase();
    final size = lower.contains('boss') || lower.contains('big') ? 128 : 64;
    final threshold = lower.contains('sketch') || lower.contains('pencil') ? 55.0 : 42.0;
    final frames = 'Idle → Walk A → Walk B → Jump';
    return McpToolResult(
      toolName: 'suggest_art_pipeline',
      message: 'Art pipeline for “$character”:\n'
          '• Capture on plain contrasting background\n'
          '• Threshold ≈ ${threshold.toStringAsFixed(0)} · target ${size}x$size WebP\n'
          '• Sprite sheet frames: $frames\n'
          '• Auto-hitbox from opaque pixels of Idle frame\n'
          'Open Art Scanner → Camera/Gallery → Generate 4-frame sprite.',
      data: {
        'frame_size': size,
        'bg_threshold': threshold,
        'frames': frames,
      },
    );
  }

  McpToolResult _explain(String question, {PhysicsMetrics? physics}) {
    final p = physics ?? const PhysicsMetrics();
    final feel = p.gravityY < 700
        ? 'floaty / dreamy'
        : p.gravityY > 1200
            ? 'snappy / weighty'
            : 'balanced arcade';
    return McpToolResult(
      toolName: 'explain_mechanics',
      message: 'Free Brain read: current feel is $feel '
          '(g=${p.gravityY.toStringAsFixed(0)}, move=${p.moveSpeed.toStringAsFixed(0)}, '
          'jump=${p.jumpVelocity.toStringAsFixed(0)}'
          '${p.doubleJump ? ', double-jump on' : ''}).\n'
          'Q: $question\n'
          'Try “make it floaty double jump” or “generate a hazard gauntlet map” — '
          'I route those through MCP tools instantly, free.',
      physics: p,
    );
  }

  // —— Procedural carvers ——

  void _carveClassic(List<int> tiles, int w, int h, double d) {
    final platforms = 3 + (d * 4).round();
    for (var i = 0; i < platforms; i++) {
      final y = 3 + _rng.nextInt((h - 5).clamp(1, h));
      final len = 3 + _rng.nextInt(5);
      final x0 = _rng.nextInt((w - len).clamp(1, w));
      for (var x = x0; x < x0 + len && x < w; x++) {
        tiles[y * w + x] = TileType.solidGround;
      }
      if (_rng.nextDouble() < 0.35 + d * 0.4) {
        tiles[(y - 1).clamp(0, h - 1) * w + (x0 + len ~/ 2).clamp(0, w - 1)] =
            TileType.item;
      }
    }
    _scatterHazards(tiles, w, h, (2 + d * 5).round());
  }

  void _carveVertical(List<int> tiles, int w, int h, double d) {
    for (var step = 0; step < h - 3; step += 2) {
      final y = h - 3 - step;
      if (y < 1) break;
      final side = step.isEven ? 2 : w ~/ 2;
      final len = w ~/ 3;
      for (var x = side; x < side + len && x < w - 1; x++) {
        tiles[y * w + x] = TileType.solidGround;
      }
      if (step % 3 == 0) {
        tiles[(y - 1) * w + (side + 1).clamp(0, w - 1)] = TileType.item;
      }
    }
    _scatterHazards(tiles, w, h, (1 + d * 4).round());
  }

  void _carveSpeedrun(List<int> tiles, int w, int h, double d) {
    var x = 2;
    var y = h - 4;
    while (x < w - 3) {
      final gap = 1 + (d * 3).round();
      final run = 2 + _rng.nextInt(4);
      for (var i = 0; i < run && x < w; i++, x++) {
        tiles[y * w + x] = TileType.solidGround;
      }
      x += gap;
      y = (y + (_rng.nextBool() ? -1 : 1)).clamp(3, h - 3);
    }
    _scatterHazards(tiles, w, h, (3 + d * 4).round());
  }

  void _carvePuzzle(List<int> tiles, int w, int h, double d) {
    // Stepping stones with items as keys
    for (var i = 0; i < 6; i++) {
      final x = 2 + i * ((w - 4) ~/ 6);
      final y = h - 4 - (i % 3);
      tiles[y * w + x] = TileType.solidGround;
      tiles[y * w + x + 1] = TileType.solidGround;
      if (i.isOdd) tiles[(y - 1) * w + x] = TileType.item;
    }
    _scatterHazards(tiles, w, h, (1 + d * 3).round());
  }

  void _carveHazards(List<int> tiles, int w, int h, double d, {bool dense = false}) {
    _carveClassic(tiles, w, h, d);
    _scatterHazards(tiles, w, h, dense ? (6 + d * 8).round() : (3 + d * 5).round());
  }

  void _carveCollectathon(List<int> tiles, int w, int h, double d) {
    _carveClassic(tiles, w, h, d * 0.7);
    for (var i = 0; i < 8 + (d * 6).round(); i++) {
      final x = 1 + _rng.nextInt(w - 2);
      final y = 1 + _rng.nextInt(h - 3);
      if (tiles[y * w + x] == TileType.air) {
        tiles[y * w + x] = TileType.item;
      }
    }
  }

  void _scatterHazards(List<int> tiles, int w, int h, int count) {
    var placed = 0;
    var guard = 0;
    while (placed < count && guard < 200) {
      guard++;
      final x = 1 + _rng.nextInt(w - 2);
      final y = h - 3;
      if (tiles[y * w + x] == TileType.air) {
        tiles[y * w + x] = TileType.hazard;
        placed++;
      }
    }
  }

  void _forceSpawn(List<int> tiles, int w, int h) {
    for (var i = 0; i < tiles.length; i++) {
      if (tiles[i] == TileType.playerSpawn) tiles[i] = TileType.air;
    }
    final y = h - 3;
    tiles[y * w + 2] = TileType.playerSpawn;
  }

  PhysicsMetrics _styleBiasPhysics(
    PhysicsMetrics base,
    String style,
    double difficulty,
  ) {
    switch (style) {
      case 'speedrun':
        return base.copyWith(
          moveSpeed: base.moveSpeed + 40,
          acceleration: base.acceleration + 200,
          friction: (base.friction - 0.05).clamp(0.5, 0.98),
        );
      case 'vertical':
        return base.copyWith(
          jumpVelocity: base.jumpVelocity + 30,
          doubleJump: true,
          airControl: 0.85,
        );
      case 'hazard_gauntlet':
        return base.copyWith(
          gravityY: base.gravityY + 80 * difficulty,
          airControl: 0.7,
        );
      default:
        return base;
    }
  }

  String _designNotes(String prompt, String style, PhysicsMetrics p) {
    return 'Style: $style · Physics: g=${p.gravityY.round()} / '
        'spd=${p.moveSpeed.round()} / jmp=${p.jumpVelocity.round()}'
        '${p.doubleJump ? ' / double-jump' : ''}.\n'
        'Brief: ${prompt.length > 120 ? '${prompt.substring(0, 120)}…' : prompt}';
  }

  String _inferLevelStyle(String lower) {
    if (lower.contains('vertical') || lower.contains('climb')) return 'vertical';
    if (lower.contains('speed') || lower.contains('race')) return 'speedrun';
    if (lower.contains('puzzle') || lower.contains('think')) return 'puzzle';
    if (lower.contains('hazard') || lower.contains('spike') || lower.contains('danger')) {
      return 'hazard_gauntlet';
    }
    if (lower.contains('collect') || lower.contains('coin') || lower.contains('gem')) {
      return 'collectathon';
    }
    return 'classic';
  }

  double _inferDifficulty(String lower) {
    if (lower.contains('easy') || lower.contains('chill') || lower.contains('kids')) {
      return 0.25;
    }
    if (lower.contains('hard') || lower.contains('brutal') || lower.contains('nightmare')) {
      return 0.85;
    }
    if (lower.contains('medium') || lower.contains('normal')) return 0.5;
    return 0.45;
  }

  String _guessTitle(String prompt) {
    final words = prompt
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 2)
        .take(3)
        .map((w) => '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
        .toList();
    if (words.isEmpty) return 'Free Brain Game';
    return words.join(' ');
  }

  bool _matches(String lower, List<String> keys) =>
      keys.any(lower.contains);
}

enum BrainSource { freeBrain, openAi, hybrid }

class BrainReply {
  const BrainReply({
    required this.text,
    required this.source,
    this.toolResult,
    this.project,
    this.map,
    this.physics,
  });

  final String text;
  final BrainSource source;
  final McpToolResult? toolResult;
  final GameProject? project;
  final TileMapData? map;
  final PhysicsMetrics? physics;
}
