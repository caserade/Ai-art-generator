import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/painting.dart';

import '../controllers/dual_control_engine.dart';
import '../models/game_models.dart';

/// Flame tile map built from Vision/offline tile indices.
class GameTileMapComponent extends PositionComponent {
  GameTileMapComponent({
    required this.map,
    this.palette = const TilePalette(),
  }) : super(
          size: Vector2(
            map.width * map.tileSize.toDouble(),
            map.height * map.tileSize.toDouble(),
          ),
        );

  final TileMapData map;
  final TilePalette palette;

  @override
  void render(Canvas canvas) {
    final ts = map.tileSize.toDouble();
    final paint = Paint();
    for (var y = 0; y < map.height; y++) {
      for (var x = 0; x < map.width; x++) {
        final tile = map.at(x, y);
        if (tile == TileType.air) continue;
        paint.color = palette.colorFor(tile);
        canvas.drawRect(
          Rect.fromLTWH(x * ts, y * ts, ts, ts),
          paint,
        );
        if (tile == TileType.item) {
          paint.color = const Color(0xFFFFF59D);
          canvas.drawCircle(
            Offset(x * ts + ts / 2, y * ts + ts / 2),
            ts * 0.28,
            paint,
          );
        }
      }
    }
  }

  bool isSolidAtWorld(double wx, double wy) {
    final tx = (wx / map.tileSize).floor();
    final ty = (wy / map.tileSize).floor();
    if (tx < 0 || ty < 0 || tx >= map.width || ty >= map.height) return true;
    final t = map.at(tx, ty);
    return t == TileType.solidGround;
  }

  bool isHazardAtWorld(double wx, double wy) {
    final tx = (wx / map.tileSize).floor();
    final ty = (wy / map.tileSize).floor();
    if (tx < 0 || ty < 0 || tx >= map.width || ty >= map.height) return false;
    return map.at(tx, ty) == TileType.hazard;
  }

  bool collectItemAtWorld(double wx, double wy) {
    final tx = (wx / map.tileSize).floor();
    final ty = (wy / map.tileSize).floor();
    if (tx < 0 || ty < 0 || tx >= map.width || ty >= map.height) return false;
    if (map.at(tx, ty) == TileType.item) {
      map.set(tx, ty, TileType.air);
      return true;
    }
    return false;
  }
}

class TilePalette {
  const TilePalette();

  Color colorFor(int tile) {
    switch (tile) {
      case TileType.solidGround:
        return const Color(0xFF3E6B4F);
      case TileType.hazard:
        return const Color(0xFFC62828);
      case TileType.playerSpawn:
        return const Color(0xFF1565C0);
      case TileType.item:
        return const Color(0xFF2E7D32);
      default:
        return const Color(0x00000000);
    }
  }
}

/// Kinematic platformer body driven by [PhysicsMetrics] + [DualControlEngine].
class PlayerComponent extends PositionComponent {
  PlayerComponent({
    required this.physics,
    required this.controls,
    required this.tileMap,
    Vector2? position,
    this.hitbox,
  }) : super(
          position: position ?? Vector2.zero(),
          size: Vector2(24, 28),
          anchor: Anchor.center,
        );

  PhysicsMetrics physics;
  final DualControlEngine controls;
  final GameTileMapComponent tileMap;
  HitboxRect? hitbox;

  Vector2 velocity = Vector2.zero();
  bool onGround = false;
  int jumpsRemaining = 1;
  int score = 0;
  bool dead = false;
  int animFrame = 0;
  double _animTimer = 0;

  void applyPhysics(PhysicsMetrics metrics) {
    physics = metrics;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (dead) return;

    final input = controls.state;
    var move = 0.0;
    if (input.moveLeft) move -= 1;
    if (input.moveRight) move += 1;
    if (move == 0 && input.leftX.abs() > 0.2) {
      move = input.leftX.sign;
    }

    final accel = onGround ? physics.acceleration : physics.acceleration * physics.airControl;
    if (move != 0) {
      velocity.x += move * accel * dt;
    } else {
      velocity.x *= physics.friction;
      if (velocity.x.abs() < 4) velocity.x = 0;
    }
    velocity.x = velocity.x.clamp(-physics.moveSpeed, physics.moveSpeed);

    // Jump
    final wantsJump = input.jump;
    if (wantsJump && jumpsRemaining > 0 && !_jumpLatched) {
      velocity.y = -physics.jumpVelocity;
      jumpsRemaining--;
      onGround = false;
      _jumpLatched = true;
    }
    if (!wantsJump) _jumpLatched = false;

    velocity.y += physics.gravityY * dt;
    velocity.y = velocity.y.clamp(-900, 1200);

    _moveAxis(dt, horizontal: true);
    _moveAxis(dt, horizontal: false);

    if (tileMap.collectItemAtWorld(position.x, position.y)) {
      score += 1;
    }
    if (tileMap.isHazardAtWorld(position.x, position.y + size.y * 0.4)) {
      dead = true;
    }

    // Animation
    _animTimer += dt;
    if (_animTimer > 0.12) {
      _animTimer = 0;
      if (!onGround) {
        animFrame = 3;
      } else if (velocity.x.abs() > 20) {
        animFrame = animFrame == 1 ? 2 : 1;
      } else {
        animFrame = 0;
      }
    }
  }

  bool _jumpLatched = false;

  void _moveAxis(double dt, {required bool horizontal}) {
    final delta = horizontal ? velocity.x * dt : velocity.y * dt;
    if (horizontal) {
      position.x += delta;
    } else {
      position.y += delta;
    }

    final halfW = size.x * 0.45;
    final halfH = size.y * 0.45;
    final samples = <Vector2>[
      Vector2(position.x - halfW, position.y - halfH),
      Vector2(position.x + halfW, position.y - halfH),
      Vector2(position.x - halfW, position.y + halfH),
      Vector2(position.x + halfW, position.y + halfH),
    ];

    var collided = false;
    for (final s in samples) {
      if (tileMap.isSolidAtWorld(s.x, s.y)) {
        collided = true;
        break;
      }
    }

    if (collided) {
      if (horizontal) {
        position.x -= delta;
        velocity.x = 0;
      } else {
        position.y -= delta;
        if (velocity.y > 0) {
          onGround = true;
          jumpsRemaining = physics.doubleJump ? 2 : 1;
        }
        velocity.y = 0;
      }
    } else if (!horizontal) {
      onGround = false;
    }
  }

  @override
  void render(Canvas canvas) {
    final body = Paint()..color = const Color(0xFFE65100);
    final eye = Paint()..color = const Color(0xFFFFFFFF);
    // Squash/stretch per anim frame
    final sx = animFrame == 3 ? 0.9 : 1.0;
    final sy = animFrame == 3 ? 1.1 : (animFrame == 0 ? 1.0 : 0.95);
    canvas.save();
    canvas.translate(size.x / 2, size.y / 2);
    canvas.scale(sx, sy);
    canvas.translate(-size.x / 2, -size.y / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.x, size.y),
        const Radius.circular(6),
      ),
      body,
    );
    canvas.drawCircle(Offset(size.x * 0.35, size.y * 0.35), 2.5, eye);
    canvas.drawCircle(Offset(size.x * 0.65, size.y * 0.35), 2.5, eye);
    canvas.restore();
  }
}

/// Top-level Flame game that owns map + player + camera.
class MakerGame extends FlameGame {
  MakerGame({
    required this.project,
    required this.controls,
  });

  final GameProject project;
  final DualControlEngine controls;

  late GameTileMapComponent tileMap;
  late PlayerComponent player;
  int get score => player.score;
  bool get isDead => player.dead;

  @override
  Color backgroundColor() => const Color(0xFF0D1B2A);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    tileMap = GameTileMapComponent(map: project.map);
    await add(tileMap);

    final spawn = project.map.findSpawn() ?? (2, project.map.height - 3);
    final spawnPos = Vector2(
      (spawn.$1 + 0.5) * project.map.tileSize,
      (spawn.$2 + 0.5) * project.map.tileSize,
    );

    player = PlayerComponent(
      physics: project.physics,
      controls: controls,
      tileMap: tileMap,
      position: spawnPos,
    );
    await add(player);

    camera.viewfinder.anchor = Anchor.center;
    camera.follow(player);
  }

  void applyPhysics(PhysicsMetrics metrics) {
    project.physics = metrics;
    player.applyPhysics(metrics);
  }

  void respawn() {
    final spawn = project.map.findSpawn() ?? (2, project.map.height - 3);
    player.position = Vector2(
      (spawn.$1 + 0.5) * project.map.tileSize,
      (spawn.$2 + 0.5) * project.map.tileSize,
    );
    player.velocity.setZero();
    player.dead = false;
    player.score = 0;
  }
}
