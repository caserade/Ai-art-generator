import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/game_models.dart';
import '../storage/database.dart';
import 'free_brain.dart';
import 'mcp_tools.dart';
import 'offline_presets.dart';
import 'openai_client.dart';

enum BrainMode {
  /// Always-on, zero-cost local intelligence.
  freeBrain,

  /// OpenAI GPT with MCP tool calling when API key present; else Free Brain.
  openAiMcp,

  /// Prefer Free Brain, escalate hard prompts to OpenAI if keyed.
  hybrid,
}

/// Studio brain: Free Brain by default + optional OpenAI MCP tool loop.
class GameBrain {
  GameBrain({
    FreeBrain? freeBrain,
    OpenAiClient? openAi,
    this.mode = BrainMode.hybrid,
  })  : freeBrain = freeBrain ?? FreeBrain(),
        openAi = openAi ?? OpenAiClient();

  final FreeBrain freeBrain;
  final OpenAiClient openAi;
  BrainMode mode;

  static const systemPrompt = '''
You are the Mobile Game Maker studio brain. You design 2D platformers.
You MUST solve tasks by calling the provided MCP tools when possible:
design_game, generate_level, tune_physics, suggest_art_pipeline, explain_mechanics.
After tools run, summarize results for the player in concise friendly language.
Tile legend: 0=Air, 1=Ground, 2=Hazard, 3=Spawn, 4=Item.
''';

  Future<void> loadMode() async {
    final saved = await GameDatabase.instance.getSetting('brain_mode');
    mode = switch (saved) {
      'free' => BrainMode.freeBrain,
      'openai' => BrainMode.openAiMcp,
      'hybrid' => BrainMode.hybrid,
      _ => BrainMode.hybrid,
    };
  }

  Future<void> saveMode(BrainMode next) async {
    mode = next;
    final value = switch (next) {
      BrainMode.freeBrain => 'free',
      BrainMode.openAiMcp => 'openai',
      BrainMode.hybrid => 'hybrid',
    };
    await GameDatabase.instance.setSetting('brain_mode', value);
  }

  String get modeLabel => switch (mode) {
        BrainMode.freeBrain => 'Free Brain',
        BrainMode.openAiMcp => 'OpenAI MCP',
        BrainMode.hybrid => 'Hybrid (Free + OpenAI)',
      };

  Future<BrainReply> chat(String message, {GameProject? context}) async {
    final hasKey = await openAi.hasApiKey;

    if (mode == BrainMode.freeBrain ||
        (mode == BrainMode.openAiMcp && !hasKey) ||
        (mode == BrainMode.hybrid && !hasKey)) {
      final reply = await freeBrain.think(message, context: context);
      if (mode == BrainMode.openAiMcp && !hasKey) {
        return BrainReply(
          text: '${reply.text}\n\n(OpenAI MCP unavailable — Free Brain answered. '
              'Add an API key in Settings to enable cloud tools.)',
          source: BrainSource.freeBrain,
          toolResult: reply.toolResult,
          project: reply.project,
          map: reply.map,
          physics: reply.physics,
        );
      }
      return reply;
    }

    // OpenAI or hybrid-with-key path
    try {
      final cloud = await _openAiToolLoop(message, context: context);
      return cloud;
    } catch (e) {
      final fallback = await freeBrain.think(message, context: context);
      return BrainReply(
        text: '${fallback.text}\n\n(OpenAI MCP error → Free Brain: $e)',
        source: BrainSource.hybrid,
        toolResult: fallback.toolResult,
        project: fallback.project,
        map: fallback.map,
        physics: fallback.physics,
      );
    }
  }

  Future<BrainReply> _openAiToolLoop(
    String message, {
    GameProject? context,
  }) async {
    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': systemPrompt},
      {
        'role': 'user',
        'content': context == null
            ? message
            : '$message\n\nCurrent project JSON:\n${jsonEncode({
                  'name': context.name,
                  'physics': context.physics.toJson(),
                  'map_size': '${context.map.width}x${context.map.height}',
                })}',
      },
    ];

    McpToolResult? lastTool;
    GameProject? project;
    TileMapData? map;
    PhysicsMetrics? physics;
    final notes = <String>[];

    for (var step = 0; step < 4; step++) {
      final response = await openAi.chatWithTools(
        messages: messages,
        tools: GameMakerMcpTools.openAiToolSchemas,
      );

      final choice = (response['choices'] as List).first as Map<String, dynamic>;
      final msg = choice['message'] as Map<String, dynamic>;
      messages.add(Map<String, dynamic>.from(msg));

      final toolCalls = msg['tool_calls'] as List?;
      if (toolCalls == null || toolCalls.isEmpty) {
        final content = msg['content'] as String? ?? 'Done.';
        return BrainReply(
          text: [
            content,
            if (notes.isNotEmpty) ...['', 'Tools run:', ...notes],
          ].join('\n'),
          source: BrainSource.openAi,
          toolResult: lastTool,
          project: project,
          map: map,
          physics: physics,
        );
      }

      for (final raw in toolCalls) {
        final call = raw as Map<String, dynamic>;
        final id = call['id'] as String? ?? 'call_$step';
        final fn = call['function'] as Map<String, dynamic>;
        final name = fn['name'] as String;
        final argsRaw = fn['arguments'];
        final args = argsRaw is String
            ? jsonDecode(argsRaw) as Map<String, dynamic>
            : (argsRaw as Map<String, dynamic>? ?? {});

        // Execute via Free Brain tool implementations (shared MCP surface)
        final result = await freeBrain.invokeTool(name, args);
        lastTool = result;
        project = result.project ?? project;
        map = result.map ?? map;
        physics = result.physics ?? physics;
        notes.add('• $name — ${result.message.split('\n').first}');

        messages.add({
          'role': 'tool',
          'tool_call_id': id,
          'content': jsonEncode(result.toJson()),
        });
      }
    }

    return BrainReply(
      text: 'OpenAI MCP finished tool loop.\n${notes.join('\n')}',
      source: BrainSource.openAi,
      toolResult: lastTool,
      project: project,
      map: map,
      physics: physics,
    );
  }

  /// Quick design without chat UI.
  Future<GameProject> designFromPrompt(String prompt, {String? name}) async {
    final reply = await chat(
      name == null ? 'Design a game: $prompt' : 'Design a game named $name: $prompt',
    );
    return reply.project ??
        GameProject(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          name: name ?? 'AI Game',
          description: prompt,
          map: OfflinePresets.starterMap(),
          physics: OfflinePresets.physicsForDescription(prompt),
        );
  }

  void dispose() => openAi.dispose();
}

/// Extends [OpenAiClient] with tool-calling chat.
extension OpenAiTools on OpenAiClient {
  Future<Map<String, dynamic>> chatWithTools({
    required List<Map<String, dynamic>> messages,
    required List<Map<String, dynamic>> tools,
  }) async {
    final key = await GameDatabase.instance.getSetting('openai_api_key');
    if (key == null || key.isEmpty) {
      throw StateError('OpenAI API key not configured');
    }

    final body = {
      'model': model,
      'temperature': 0.2,
      'messages': messages,
      'tools': tools,
      'tool_choice': 'auto',
    };

    final response = await http
        .post(
          Uri.parse('$baseUrl/chat/completions'),
          headers: {
            'Authorization': 'Bearer $key',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 90));

    if (response.statusCode >= 400) {
      throw StateError('OpenAI tools error ${response.statusCode}: ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }
}
