import '../models/game_models.dart';

/// OpenAI-compatible MCP tool definitions for the Game Maker.
///
/// These schemas mirror Model Context Protocol tool descriptors so Free Brain
/// and OpenAI function-calling can invoke the same game-studio capabilities.
abstract final class GameMakerMcpTools {
  static const List<Map<String, dynamic>> openAiToolSchemas = [
    {
      'type': 'function',
      'function': {
        'name': 'design_game',
        'description':
            'Design a complete 2D platformer from a natural-language brief: name, map, physics, and design notes.',
        'parameters': {
          'type': 'object',
          'properties': {
            'prompt': {
              'type': 'string',
              'description': 'Player fantasy / mechanics brief',
            },
            'name': {
              'type': 'string',
              'description': 'Optional game title',
            },
          },
          'required': ['prompt'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'generate_level',
        'description':
            'Procedurally generate a tile map (0=Air,1=Ground,2=Hazard,3=Spawn,4=Item).',
        'parameters': {
          'type': 'object',
          'properties': {
            'style': {
              'type': 'string',
              'enum': [
                'classic',
                'vertical',
                'speedrun',
                'puzzle',
                'hazard_gauntlet',
                'collectathon',
              ],
            },
            'width': {'type': 'integer', 'minimum': 12, 'maximum': 32},
            'height': {'type': 'integer', 'minimum': 8, 'maximum': 18},
            'difficulty': {
              'type': 'number',
              'minimum': 0,
              'maximum': 1,
            },
          },
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'tune_physics',
        'description':
            'Derive platformer physics metrics from a feel description.',
        'parameters': {
          'type': 'object',
          'properties': {
            'description': {'type': 'string'},
          },
          'required': ['description'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'suggest_art_pipeline',
        'description':
            'Suggest art-scan settings and animation intent for a character brief.',
        'parameters': {
          'type': 'object',
          'properties': {
            'character': {'type': 'string'},
          },
          'required': ['character'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'explain_mechanics',
        'description':
            'Explain how current physics/map will feel and suggest improvements.',
        'parameters': {
          'type': 'object',
          'properties': {
            'question': {'type': 'string'},
          },
          'required': ['question'],
        },
      },
    },
  ];

  /// MCP-style tool list (name + description + inputSchema) for docs/clients.
  static List<Map<String, dynamic>> mcpToolDescriptors() {
    return openAiToolSchemas.map((t) {
      final fn = t['function'] as Map<String, dynamic>;
      return {
        'name': fn['name'],
        'description': fn['description'],
        'inputSchema': fn['parameters'],
      };
    }).toList();
  }
}

/// Result of invoking a Game Maker MCP tool.
class McpToolResult {
  const McpToolResult({
    required this.toolName,
    required this.message,
    this.project,
    this.map,
    this.physics,
    this.data = const {},
  });

  final String toolName;
  final String message;
  final GameProject? project;
  final TileMapData? map;
  final PhysicsMetrics? physics;
  final Map<String, dynamic> data;

  Map<String, dynamic> toJson() => {
        'tool': toolName,
        'message': message,
        if (project != null) 'project': project!.toJson(),
        if (map != null) 'map': map!.toJson(),
        if (physics != null) 'physics': physics!.toJson(),
        'data': data,
      };
}
