import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/game_models.dart';
import 'memory_store.dart';

/// SQLite-backed local store with in-memory fallback (web / test).
class GameDatabase {
  GameDatabase._();
  static final GameDatabase instance = GameDatabase._();

  Database? _db;
  Directory? _docs;
  bool memoryMode = false;

  Future<void> init({bool forceMemory = false}) async {
    if (_db != null || memoryMode) return;

    if (forceMemory || kIsWeb) {
      memoryMode = true;
      gameDbMemoryMode = true;
      return;
    }

    try {
      if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
      }

      _docs = await getApplicationDocumentsDirectory();
      final dbPath = p.join(_docs!.path, 'mobile_game_maker.db');
      _db = await openDatabase(
        dbPath,
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE projects (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              description TEXT,
              map_json TEXT NOT NULL,
              physics_json TEXT NOT NULL,
              sprite_id TEXT,
              updated_at TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE sprites (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              webp_path TEXT NOT NULL,
              frame_width INTEGER NOT NULL,
              frame_height INTEGER NOT NULL,
              frame_count INTEGER NOT NULL,
              hitbox_json TEXT NOT NULL,
              created_at TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE settings (
              key TEXT PRIMARY KEY,
              value TEXT NOT NULL
            )
          ''');
        },
      );
    } catch (e) {
      debugPrint('SQLite unavailable, using memory store: $e');
      memoryMode = true;
      gameDbMemoryMode = true;
    }
  }

  Future<String> assetsDir() async {
    if (memoryMode) return '/tmp/game_assets';
    final dir = Directory(p.join(_docs!.path, 'game_assets'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }

  Future<String> cacheDir() async {
    if (memoryMode) return '/tmp/game_cache';
    final dir = Directory(p.join(_docs!.path, 'cache'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }

  Future<List<GameProject>> listProjects() async {
    if (memoryMode) return MemoryGameStore.instance.listProjects();
    final rows = await _db!.query('projects', orderBy: 'updated_at DESC');
    return rows.map(_projectFromRow).toList();
  }

  Future<GameProject?> getProject(String id) async {
    if (memoryMode) return MemoryGameStore.instance.projects[id];
    final rows = await _db!.query('projects', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return _projectFromRow(rows.first);
  }

  Future<void> upsertProject(GameProject project) async {
    if (memoryMode) {
      MemoryGameStore.instance.upsertProject(project);
      return;
    }
    project.updatedAt = DateTime.now();
    await _db!.insert(
      'projects',
      {
        'id': project.id,
        'name': project.name,
        'description': project.description,
        'map_json': jsonEncode(project.map.toJson()),
        'physics_json': jsonEncode(project.physics.toJson()),
        'sprite_id': project.spriteId,
        'updated_at': project.updatedAt.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteProject(String id) async {
    if (memoryMode) {
      MemoryGameStore.instance.deleteProject(id);
      return;
    }
    await _db!.delete('projects', where: 'id = ?', whereArgs: [id]);
  }

  GameProject _projectFromRow(Map<String, Object?> row) {
    return GameProject(
      id: row['id'] as String,
      name: row['name'] as String,
      description: row['description'] as String? ?? '',
      map: TileMapData.fromJson(
        jsonDecode(row['map_json'] as String) as Map<String, dynamic>,
      ),
      physics: PhysicsMetrics.fromJson(
        jsonDecode(row['physics_json'] as String) as Map<String, dynamic>,
      ),
      spriteId: row['sprite_id'] as String?,
      updatedAt: DateTime.tryParse(row['updated_at'] as String) ?? DateTime.now(),
    );
  }

  Future<List<SpriteSheetAsset>> listSprites() async {
    if (memoryMode) return MemoryGameStore.instance.listSprites();
    final rows = await _db!.query('sprites', orderBy: 'created_at DESC');
    return rows.map(_spriteFromRow).toList();
  }

  Future<SpriteSheetAsset?> getSprite(String id) async {
    if (memoryMode) return MemoryGameStore.instance.sprites[id];
    final rows = await _db!.query('sprites', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return _spriteFromRow(rows.first);
  }

  Future<void> upsertSprite(SpriteSheetAsset sprite) async {
    if (memoryMode) {
      MemoryGameStore.instance.upsertSprite(sprite);
      return;
    }
    await _db!.insert(
      'sprites',
      {
        'id': sprite.id,
        'name': sprite.name,
        'webp_path': sprite.webpPath,
        'frame_width': sprite.frameWidth,
        'frame_height': sprite.frameHeight,
        'frame_count': sprite.frameCount,
        'hitbox_json': jsonEncode(sprite.hitbox.toJson()),
        'created_at':
            (sprite.createdAt ?? DateTime.now()).toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteSprite(String id) async {
    if (memoryMode) {
      MemoryGameStore.instance.deleteSprite(id);
      return;
    }
    final sprite = await getSprite(id);
    if (sprite != null) {
      final file = File(sprite.webpPath);
      if (await file.exists()) await file.delete();
    }
    await _db!.delete('sprites', where: 'id = ?', whereArgs: [id]);
  }

  SpriteSheetAsset _spriteFromRow(Map<String, Object?> row) {
    return SpriteSheetAsset(
      id: row['id'] as String,
      name: row['name'] as String,
      webpPath: row['webp_path'] as String,
      frameWidth: row['frame_width'] as int,
      frameHeight: row['frame_height'] as int,
      frameCount: row['frame_count'] as int,
      hitbox: HitboxRect.fromJson(
        jsonDecode(row['hitbox_json'] as String) as Map<String, dynamic>,
      ),
      createdAt: DateTime.tryParse(row['created_at'] as String),
    );
  }

  Future<void> setSetting(String key, String value) async {
    if (memoryMode) {
      MemoryGameStore.instance.setSetting(key, value);
      return;
    }
    await _db!.insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> getSetting(String key) async {
    if (memoryMode) return MemoryGameStore.instance.getSetting(key);
    final rows =
        await _db!.query('settings', where: 'key = ?', whereArgs: [key]);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String;
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
    memoryMode = false;
  }

  /// Test helper: reset singleton state.
  @visibleForTesting
  void resetForTest() {
    _db = null;
    _docs = null;
    memoryMode = false;
    MemoryGameStore.instance.projects.clear();
    MemoryGameStore.instance.sprites.clear();
    MemoryGameStore.instance.settings.clear();
  }
}
