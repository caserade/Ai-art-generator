import '../models/game_models.dart';

/// Offline fallback presets when OpenAI is unavailable.
abstract final class OfflinePresets {
  static TileMapData starterMap() => TileMapData.defaultPlatformer();

  static const PhysicsMetrics classic = PhysicsMetrics();

  static const PhysicsMetrics floatyDoubleJump = PhysicsMetrics(
    gravityY: 620,
    moveSpeed: 200,
    jumpVelocity: 380,
    acceleration: 900,
    friction: 0.88,
    doubleJump: true,
    airControl: 0.85,
  );

  static const PhysicsMetrics tightSpeedrun = PhysicsMetrics(
    gravityY: 1400,
    moveSpeed: 260,
    jumpVelocity: 480,
    acceleration: 1800,
    friction: 0.72,
    doubleJump: false,
    airControl: 0.45,
  );

  static const PhysicsMetrics heavyTank = PhysicsMetrics(
    gravityY: 1100,
    moveSpeed: 110,
    jumpVelocity: 340,
    acceleration: 600,
    friction: 0.9,
    doubleJump: false,
    airControl: 0.35,
  );

  static PhysicsMetrics physicsForDescription(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('floaty') ||
        lower.contains('double jump') ||
        lower.contains('celeste')) {
      return floatyDoubleJump;
    }
    if (lower.contains('fast') ||
        lower.contains('speedrun') ||
        lower.contains('sonic') ||
        lower.contains('tight')) {
      return tightSpeedrun;
    }
    if (lower.contains('heavy') ||
        lower.contains('tank') ||
        lower.contains('slow')) {
      return heavyTank;
    }
    return classic;
  }

  static List<({String name, PhysicsMetrics metrics})> catalog() => [
        (name: 'Classic Platformer', metrics: classic),
        (name: 'Floaty Double Jump', metrics: floatyDoubleJump),
        (name: 'Tight Speedrun', metrics: tightSpeedrun),
        (name: 'Heavy Tank', metrics: heavyTank),
      ];
}
