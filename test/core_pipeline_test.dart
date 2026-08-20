import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mobile_game_maker/ai_vision/offline_presets.dart';
import 'package:mobile_game_maker/models/game_models.dart';
import 'package:mobile_game_maker/storage/art_scanner.dart';
import 'package:mobile_game_maker/storage/database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TileMapData', () {
    test('default platformer has spawn and ground', () {
      final map = TileMapData.defaultPlatformer();
      expect(map.findSpawn(), isNotNull);
      expect(map.tiles.contains(TileType.solidGround), isTrue);
      expect(map.tiles.contains(TileType.hazard), isTrue);
    });

    test('json round-trip', () {
      final map = TileMapData.defaultPlatformer(width: 10, height: 8);
      final copy = TileMapData.fromJson(map.toJson());
      expect(copy.width, map.width);
      expect(copy.height, map.height);
      expect(copy.tiles, map.tiles);
    });
  });

  group('PhysicsMetrics', () {
    test('json round-trip', () {
      const m = PhysicsMetrics(
        gravityY: 700,
        moveSpeed: 210,
        jumpVelocity: 400,
        doubleJump: true,
      );
      final copy = PhysicsMetrics.fromJson(m.toJson());
      expect(copy.gravityY, 700);
      expect(copy.doubleJump, isTrue);
      expect(copy.moveSpeed, 210);
    });
  });

  group('OfflinePresets', () {
    test('keyword matching', () {
      expect(
        OfflinePresets.physicsForDescription('floaty double jump').doubleJump,
        isTrue,
      );
      expect(
        OfflinePresets.physicsForDescription('fast speedrun').moveSpeed,
        greaterThan(200),
      );
      expect(
        OfflinePresets.physicsForDescription('heavy tank').moveSpeed,
        lessThan(150),
      );
    });
  });

  group('ArtScanner', () {
    test('isolates background and builds 4-frame sheet', () {
      // White bg with red square character
      final source = img.Image(width: 64, height: 64, numChannels: 4);
      img.fill(source, color: img.ColorRgba8(255, 255, 255, 255));
      for (var y = 16; y < 48; y++) {
        for (var x = 16; x < 48; x++) {
          source.setPixelRgba(x, y, 200, 40, 40, 255);
        }
      }

      final scanner = ArtScanner(frameSize: 32);
      final isolated = scanner.isolateBackground(source, threshold: 30);
      // Corners should be transparent-ish
      expect(isolated.getPixel(0, 0).a, 0);

      final cropped = scanner.cropToContent(isolated);
      final sheet = scanner.buildSpriteSheet(cropped);
      expect(sheet.width, 32 * 4);
      expect(sheet.height, 32);

      final hitbox = scanner.computeHitbox(sheet);
      expect(hitbox.width, greaterThan(0));
      expect(hitbox.height, greaterThan(0));
    });

    test('processScan stores sprite in memory DB', () async {
      GameDatabase.instance.resetForTest();
      await GameDatabase.instance.init(forceMemory: true);

      final source = img.Image(width: 48, height: 48, numChannels: 4);
      img.fill(source, color: img.ColorRgba8(240, 240, 240, 255));
      for (var y = 10; y < 38; y++) {
        for (var x = 10; x < 38; x++) {
          source.setPixelRgba(x, y, 30, 120, 200, 255);
        }
      }
      final bytes = Uint8List.fromList(img.encodePng(source));
      final scanner = ArtScanner(frameSize: 64);
      final asset = await scanner.processScan(rawBytes: bytes, name: 'Hero');
      expect(asset.frameCount, 4);
      expect(asset.name, 'Hero');
      final listed = await GameDatabase.instance.listSprites();
      expect(listed.any((s) => s.id == asset.id), isTrue);
    });
  });

  group('GameDatabase memory mode', () {
    test('project CRUD', () async {
      GameDatabase.instance.resetForTest();
      await GameDatabase.instance.init(forceMemory: true);
      final project = GameProject.create(name: 'Test');
      await GameDatabase.instance.upsertProject(project);
      final list = await GameDatabase.instance.listProjects();
      expect(list.length, 1);
      expect(list.first.name, 'Test');
      await GameDatabase.instance.deleteProject(project.id);
      expect(await GameDatabase.instance.listProjects(), isEmpty);
    });
  });
}
