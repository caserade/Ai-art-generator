import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/game_models.dart';
import '../storage/database.dart';
import 'offline_presets.dart';

class AiRequestResult<T> {
  const AiRequestResult({
    required this.value,
    required this.fromOfflineFallback,
    this.error,
  });

  final T value;
  final bool fromOfflineFallback;
  final String? error;
}

/// Thin OpenAI client for GPT-4o Vision + chat completions.
class OpenAiClient {
  OpenAiClient({
    http.Client? httpClient,
    this.baseUrl = 'https://api.openai.com/v1',
    this.model = 'gpt-4o',
  }) : _http = httpClient ?? http.Client();

  final http.Client _http;
  final String baseUrl;
  final String model;

  Future<String?> _apiKey() => GameDatabase.instance.getSetting('openai_api_key');

  Future<bool> get hasApiKey async {
    final key = await _apiKey();
    return key != null && key.trim().isNotEmpty;
  }

  Future<Map<String, dynamic>> chatJson({
    required String systemPrompt,
    required String userText,
    String? imageBase64,
    String imageMime = 'image/jpeg',
  }) async {
    final key = await _apiKey();
    if (key == null || key.isEmpty) {
      throw StateError('OpenAI API key not configured');
    }

    final userContent = <Map<String, dynamic>>[
      {'type': 'text', 'text': userText},
    ];
    if (imageBase64 != null) {
      userContent.add({
        'type': 'image_url',
        'image_url': {
          'url': 'data:$imageMime;base64,$imageBase64',
        },
      });
    }

    final body = {
      'model': model,
      'temperature': 0.1,
      'response_format': {'type': 'json_object'},
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': userContent},
      ],
    };

    final response = await _http
        .post(
          Uri.parse('$baseUrl/chat/completions'),
          headers: {
            'Authorization': 'Bearer $key',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 60));

    if (response.statusCode >= 400) {
      throw StateError('OpenAI error ${response.statusCode}: ${response.body}');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final content =
        (decoded['choices'] as List).first['message']['content'] as String;
    return jsonDecode(content) as Map<String, dynamic>;
  }

  void dispose() => _http.close();
}

/// Image → tile grid via Vision API with offline fallback.
class MapParser {
  MapParser(this.client);

  final OpenAiClient client;

  static const systemPrompt = '''
You convert 2D level sketches into a tile grid JSON.
Return ONLY JSON matching:
{"width":N,"height":N,"tiles":[...row-major integers...]}
Tile indices: 0=Air, 1=Solid Ground, 2=Hazard, 3=Player Spawn, 4=Item/Collectible.
Prefer width 16-24 and height 10-14. Exactly one tile must be 3 (player spawn).
''';

  Future<AiRequestResult<TileMapData>> parseMapImage({
    required String imageBase64,
    String mime = 'image/jpeg',
  }) async {
    try {
      if (!await client.hasApiKey) {
        return AiRequestResult(
          value: OfflinePresets.starterMap(),
          fromOfflineFallback: true,
          error: 'No API key — using offline preset map',
        );
      }
      final json = await client.chatJson(
        systemPrompt: systemPrompt,
        userText:
            'Parse this level sketch into a playable tile grid. Follow the schema strictly.',
        imageBase64: imageBase64,
        imageMime: mime,
      );
      final map = TileMapData.fromJson(json);
      _ensureSpawn(map);
      return AiRequestResult(value: map, fromOfflineFallback: false);
    } catch (e) {
      return AiRequestResult(
        value: OfflinePresets.starterMap(),
        fromOfflineFallback: true,
        error: e.toString(),
      );
    }
  }

  void _ensureSpawn(TileMapData map) {
    if (map.findSpawn() != null) return;
    map.set(2, map.height - 3, TileType.playerSpawn);
  }
}

/// Gameplay description / keyframes → physics metrics.
class PhysicsExtractor {
  PhysicsExtractor(this.client);

  final OpenAiClient client;

  static const systemPrompt = '''
You extract 2D platformer physics metrics from text descriptions or gameplay notes.
Return ONLY JSON:
{"gravity_y":number,"move_speed":number,"jump_velocity":number,"acceleration":number,"friction":number,"double_jump":boolean,"air_control":number}
Use pixel/second-ish units suitable for a 32px tile game (gravity ~600-1400, jump 300-560, move 120-280).
''';

  Future<AiRequestResult<PhysicsMetrics>> extractFromDescription(
    String description,
  ) async {
    try {
      if (!await client.hasApiKey) {
        final preset = OfflinePresets.physicsForDescription(description);
        return AiRequestResult(
          value: preset,
          fromOfflineFallback: true,
          error: 'No API key — using offline physics preset',
        );
      }
      final json = await client.chatJson(
        systemPrompt: systemPrompt,
        userText: description,
      );
      return AiRequestResult(
        value: PhysicsMetrics.fromJson(json),
        fromOfflineFallback: false,
      );
    } catch (e) {
      return AiRequestResult(
        value: OfflinePresets.physicsForDescription(description),
        fromOfflineFallback: true,
        error: e.toString(),
      );
    }
  }
}
