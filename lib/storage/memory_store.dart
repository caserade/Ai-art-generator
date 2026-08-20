import 'dart:convert';

import '../models/game_models.dart';
import 'database.dart';

/// In-memory store used on web and when SQLite is unavailable.
class MemoryGameStore {
  MemoryGameStore._();
  static final MemoryGameStore instance = MemoryGameStore._();

  final Map<String, GameProject> projects = {};
  final Map<String, SpriteSheetAsset> sprites = {};
  final Map<String, String> settings = {};

  List<GameProject> listProjects() {
    final list = projects.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  void upsertProject(GameProject project) {
    project.updatedAt = DateTime.now();
    projects[project.id] = project;
  }

  void deleteProject(String id) => projects.remove(id);

  List<SpriteSheetAsset> listSprites() => sprites.values.toList();

  void upsertSprite(SpriteSheetAsset sprite) => sprites[sprite.id] = sprite;

  void deleteSprite(String id) => sprites.remove(id);

  void setSetting(String key, String value) => settings[key] = value;

  String? getSetting(String key) => settings[key];

  String encodeProject(GameProject p) => jsonEncode(p.toJson());
}

/// Marks whether [GameDatabase] fell back to memory mode.
bool gameDbMemoryMode = false;
