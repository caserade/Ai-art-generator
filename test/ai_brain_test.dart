import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_game_maker/ai_vision/free_brain.dart';
import 'package:mobile_game_maker/ai_vision/game_brain.dart';
import 'package:mobile_game_maker/ai_vision/mcp_tools.dart';
import 'package:mobile_game_maker/models/game_models.dart';
import 'package:mobile_game_maker/storage/database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    GameDatabase.instance.resetForTest();
    await GameDatabase.instance.init(forceMemory: true);
  });

  group('FreeBrain', () {
    test('designs a full game from a brief', () async {
      final brain = FreeBrain(random: Random(42));
      final reply = await brain.think(
        'fast platformer with floaty double jump and gem collecting',
      );
      expect(reply.source, BrainSource.freeBrain);
      expect(reply.project, isNotNull);
      expect(reply.project!.map.findSpawn(), isNotNull);
      expect(reply.physics?.doubleJump, isTrue);
    });

    test('MCP generate_level creates valid spawn', () async {
      final brain = FreeBrain();
      final result = await brain.invokeTool('generate_level', {
        'style': 'hazard_gauntlet',
        'difficulty': 0.7,
      });
      expect(result.map, isNotNull);
      expect(result.map!.findSpawn(), isNotNull);
      expect(result.map!.tiles.contains(TileType.hazard), isTrue);
    });

    test('tune_physics understands icy', () async {
      final brain = FreeBrain();
      final result = await brain.invokeTool('tune_physics', {
        'description': 'icy sticky floors',
      });
      expect(result.physics!.friction, greaterThan(0.9));
    });
  });

  group('GameBrain', () {
    test('defaults to Free Brain without API key', () async {
      final brain = GameBrain(mode: BrainMode.openAiMcp);
      final reply = await brain.chat('make a chill vertical climb game');
      expect(reply.source, BrainSource.freeBrain);
      expect(reply.project ?? reply.map, isNotNull);
    });
  });

  test('MCP tool schemas are non-empty', () {
    expect(GameMakerMcpTools.openAiToolSchemas, isNotEmpty);
    expect(GameMakerMcpTools.mcpToolDescriptors().first['name'], 'design_game');
  });
}
