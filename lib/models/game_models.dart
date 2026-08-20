/// Shared domain models for projects, sprites, maps, and physics.
library;

class PhysicsMetrics {
  const PhysicsMetrics({
    this.gravityY = 980,
    this.moveSpeed = 180,
    this.jumpVelocity = 420,
    this.acceleration = 1200,
    this.friction = 0.82,
    this.doubleJump = false,
    this.airControl = 0.65,
  });

  final double gravityY;
  final double moveSpeed;
  final double jumpVelocity;
  final double acceleration;
  final double friction;
  final bool doubleJump;
  final double airControl;

  PhysicsMetrics copyWith({
    double? gravityY,
    double? moveSpeed,
    double? jumpVelocity,
    double? acceleration,
    double? friction,
    bool? doubleJump,
    double? airControl,
  }) {
    return PhysicsMetrics(
      gravityY: gravityY ?? this.gravityY,
      moveSpeed: moveSpeed ?? this.moveSpeed,
      jumpVelocity: jumpVelocity ?? this.jumpVelocity,
      acceleration: acceleration ?? this.acceleration,
      friction: friction ?? this.friction,
      doubleJump: doubleJump ?? this.doubleJump,
      airControl: airControl ?? this.airControl,
    );
  }

  Map<String, dynamic> toJson() => {
        'gravity_y': gravityY,
        'move_speed': moveSpeed,
        'jump_velocity': jumpVelocity,
        'acceleration': acceleration,
        'friction': friction,
        'double_jump': doubleJump,
        'air_control': airControl,
      };

  factory PhysicsMetrics.fromJson(Map<String, dynamic> json) {
    return PhysicsMetrics(
      gravityY: (json['gravity_y'] as num?)?.toDouble() ?? 980,
      moveSpeed: (json['move_speed'] as num?)?.toDouble() ?? 180,
      jumpVelocity: (json['jump_velocity'] as num?)?.toDouble() ?? 420,
      acceleration: (json['acceleration'] as num?)?.toDouble() ?? 1200,
      friction: (json['friction'] as num?)?.toDouble() ?? 0.82,
      doubleJump: json['double_jump'] as bool? ?? false,
      airControl: (json['air_control'] as num?)?.toDouble() ?? 0.65,
    );
  }
}

/// Tile indices for map grids.
abstract final class TileType {
  static const int air = 0;
  static const int solidGround = 1;
  static const int hazard = 2;
  static const int playerSpawn = 3;
  static const int item = 4;
}

class TileMapData {
  TileMapData({
    required this.width,
    required this.height,
    required this.tiles,
    this.tileSize = 32,
  }) : assert(tiles.length == width * height);

  final int width;
  final int height;
  final List<int> tiles;
  final int tileSize;

  int at(int x, int y) => tiles[y * width + x];

  void set(int x, int y, int value) => tiles[y * width + x] = value;

  (int, int)? findSpawn() {
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        if (at(x, y) == TileType.playerSpawn) return (x, y);
      }
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'width': width,
        'height': height,
        'tile_size': tileSize,
        'tiles': tiles,
      };

  factory TileMapData.fromJson(Map<String, dynamic> json) {
    final tiles = (json['tiles'] as List).map((e) => (e as num).toInt()).toList();
    return TileMapData(
      width: json['width'] as int,
      height: json['height'] as int,
      tileSize: (json['tile_size'] as int?) ?? 32,
      tiles: tiles,
    );
  }

  /// Simple platformer starter map used offline.
  factory TileMapData.defaultPlatformer({int width = 20, int height = 12}) {
    final tiles = List<int>.filled(width * height, TileType.air);
    for (var x = 0; x < width; x++) {
      tiles[(height - 1) * width + x] = TileType.solidGround;
      if (height > 1) {
        tiles[(height - 2) * width + x] = TileType.solidGround;
      }
    }
    // Mid platforms (clamped to map size)
    final platformY1 = (height * 0.58).floor().clamp(1, height - 3);
    final platformY2 = (height * 0.42).floor().clamp(1, height - 3);
    final p1Start = (width * 0.2).floor();
    final p1End = (width * 0.4).floor().clamp(p1Start + 1, width - 1);
    final p2Start = (width * 0.55).floor();
    final p2End = (width * 0.8).floor().clamp(p2Start + 1, width - 1);
    for (var x = p1Start; x < p1End; x++) {
      tiles[platformY1 * width + x] = TileType.solidGround;
    }
    for (var x = p2Start; x < p2End; x++) {
      tiles[platformY2 * width + x] = TileType.solidGround;
    }
    final hazardX = (width * 0.45).floor().clamp(0, width - 1);
    final hazardY = (height - 3).clamp(0, height - 1);
    tiles[hazardY * width + hazardX] = TileType.hazard;
    final itemX = (width * 0.7).floor().clamp(0, width - 1);
    final itemY = (platformY2 - 1).clamp(0, height - 1);
    tiles[itemY * width + itemX] = TileType.item;
    final spawnX = 2.clamp(0, width - 1);
    final spawnY = (height - 3).clamp(0, height - 1);
    tiles[spawnY * width + spawnX] = TileType.playerSpawn;
    return TileMapData(width: width, height: height, tiles: tiles);
  }
}
class HitboxRect {
  const HitboxRect({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final double x;
  final double y;
  final double width;
  final double height;

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'width': width,
        'height': height,
      };

  factory HitboxRect.fromJson(Map<String, dynamic> json) => HitboxRect(
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
        width: (json['width'] as num).toDouble(),
        height: (json['height'] as num).toDouble(),
      );
}

class SpriteSheetAsset {
  const SpriteSheetAsset({
    required this.id,
    required this.name,
    required this.webpPath,
    required this.frameWidth,
    required this.frameHeight,
    required this.frameCount,
    required this.hitbox,
    this.createdAt,
  });

  final String id;
  final String name;
  final String webpPath;
  final int frameWidth;
  final int frameHeight;
  final int frameCount;
  final HitboxRect hitbox;
  final DateTime? createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'webp_path': webpPath,
        'frame_width': frameWidth,
        'frame_height': frameHeight,
        'frame_count': frameCount,
        'hitbox': hitbox.toJson(),
        'created_at': createdAt?.toIso8601String(),
      };

  factory SpriteSheetAsset.fromJson(Map<String, dynamic> json) =>
      SpriteSheetAsset(
        id: json['id'] as String,
        name: json['name'] as String,
        webpPath: json['webp_path'] as String,
        frameWidth: json['frame_width'] as int,
        frameHeight: json['frame_height'] as int,
        frameCount: json['frame_count'] as int,
        hitbox: HitboxRect.fromJson(json['hitbox'] as Map<String, dynamic>),
        createdAt: json['created_at'] != null
            ? DateTime.tryParse(json['created_at'] as String)
            : null,
      );
}

class GameProject {
  GameProject({
    required this.id,
    required this.name,
    required this.map,
    required this.physics,
    this.spriteId,
    this.description = '',
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  final String id;
  String name;
  String description;
  TileMapData map;
  PhysicsMetrics physics;
  String? spriteId;
  DateTime updatedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'map': map.toJson(),
        'physics': physics.toJson(),
        'sprite_id': spriteId,
        'updated_at': updatedAt.toIso8601String(),
      };

  factory GameProject.fromJson(Map<String, dynamic> json) => GameProject(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String? ?? '',
        map: TileMapData.fromJson(json['map'] as Map<String, dynamic>),
        physics: PhysicsMetrics.fromJson(json['physics'] as Map<String, dynamic>),
        spriteId: json['sprite_id'] as String?,
        updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? '') ??
            DateTime.now(),
      );

  factory GameProject.create({required String name}) {
    return GameProject(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      map: TileMapData.defaultPlatformer(),
      physics: const PhysicsMetrics(),
    );
  }
}

enum GamepadButton { a, b, x, y, up, down, left, right, start, select }

class ControlState {
  double leftX = 0;
  double leftY = 0;
  double rightX = 0;
  double rightY = 0;
  final Set<GamepadButton> pressed = {};

  bool get jump => pressed.contains(GamepadButton.a);
  bool get action => pressed.contains(GamepadButton.b);
  bool get moveLeft => leftX < -0.3 || pressed.contains(GamepadButton.left);
  bool get moveRight => leftX > 0.3 || pressed.contains(GamepadButton.right);
}
