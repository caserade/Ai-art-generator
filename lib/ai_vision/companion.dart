import '../models/game_models.dart';
import 'free_brain.dart';
import 'game_brain.dart';

/// Kaiju — the always-on, fully aware Game Maker companion.
abstract final class CompanionIdentity {
  static const name = 'Kaiju';
  static const assetPath = 'assets/images/companion_kaiju.webp';
  static const tagline = 'Your helpful game-making buddy';

  static const welcome = '''
Hey! I'm Kaiju 👋

I live inside Game Maker and I'm here to help you make games.
I can design levels, tune physics, guide the art scanner, and playtest tips.

Try saying: “make a floaty gem-hunt platformer”
Or tap a quick tip below!
''';

  static String tipForRoute(String route) {
    switch (route) {
      case 'home':
        return 'Tap Create game or ask me to design one from a one-line fantasy. '
            'Art Scanner, Map Parser, and Physics AI are in Studio tools.';
      case 'editor':
        return 'Paint tiles with the brushes. Use the map/physics icons in the '
            'app bar — or ask me “generate a hazard gauntlet map”.';
      case 'play':
        return 'Left stick / D-Pad to move, A to jump. Collect yellow items, '
            'avoid red hazards. Ask me if the jump feels wrong!';
      case 'brain':
        return 'Tell me the vibe — floaty, tight, vertical climb, gem collectathon — '
            'and I’ll build a playable draft.';
      case 'art':
        return 'Photograph a sketch on a plain background. I’ll guide threshold '
            'and turn it into a 4-frame WebP sprite.';
      case 'map':
        return 'Upload a level doodle or use the offline preset. Tile legend: '
            '0 air · 1 ground · 2 hazard · 3 spawn · 4 item.';
      case 'physics':
        return 'Describe the feel (“icy”, “moon gravity”, “Celeste precision”) '
            'or grab a preset chip.';
      case 'settings':
        return 'Free Brain works offline. Add an OpenAI key for cloud MCP tools. '
            'Hybrid mode is the sweet spot.';
      default:
        return 'Ask me anything about making your game — I’m always here.';
    }
  }
}

/// Context-aware companion brain wrapping Free Brain / OpenAI.
class CompanionBrain {
  CompanionBrain({GameBrain? gameBrain})
      : _gameBrain = gameBrain ?? GameBrain(mode: BrainMode.hybrid);

  final GameBrain _gameBrain;
  String currentRoute = 'home';
  GameProject? activeProject;

  Future<void> init() => _gameBrain.loadMode();

  void dispose() => _gameBrain.dispose();

  Future<BrainReply> respond(String userMessage) async {
    final lower = userMessage.toLowerCase().trim();

    // Companion-aware meta questions
    if (lower.isEmpty) {
      return BrainReply(
        text: CompanionIdentity.tipForRoute(currentRoute),
        source: BrainSource.freeBrain,
      );
    }
    if (_isHelpMeta(lower)) {
      return BrainReply(
        text: _awareHelp(),
        source: BrainSource.freeBrain,
      );
    }

    final enriched = '''
[Companion: ${CompanionIdentity.name}]
[Screen: $currentRoute]
${activeProject != null ? '[Project: ${activeProject!.name}]' : ''}
User: $userMessage
''';

    final reply = await _gameBrain.chat(enriched, context: activeProject);
    if (reply.project != null) activeProject = reply.project;
    if (reply.map != null && activeProject != null) {
      activeProject!.map = reply.map!;
    }
    if (reply.physics != null && activeProject != null) {
      activeProject!.physics = reply.physics!;
    }

    return BrainReply(
      text: _withKaijuVoice(reply.text),
      source: reply.source,
      toolResult: reply.toolResult,
      project: reply.project ?? activeProject,
      map: reply.map,
      physics: reply.physics,
    );
  }

  bool _isHelpMeta(String lower) {
    return lower == 'help' ||
        lower == '?' ||
        lower.contains('who are you') ||
        lower.contains('what can you') ||
        lower.contains('how do i');
  }

  String _awareHelp() {
    final projectLine = activeProject == null
        ? 'No project open yet — say “design a game” and I’ll start one.'
        : 'Working on “${activeProject!.name}” '
            '(${activeProject!.map.width}×${activeProject!.map.height}, '
            'spd ${activeProject!.physics.moveSpeed.toStringAsFixed(0)}).';
    return '''
I'm ${CompanionIdentity.name}, your always-on companion.

Right now you're on: $currentRoute
$projectLine

I can:
• Design whole games from a sentence
• Generate maps & tune physics
• Guide Art Scanner / Map Parser
• Explain why a jump feels floaty or tight

Mode: ${_gameBrain.modeLabel}
''';
  }

  String _withKaijuVoice(String text) {
    if (text.startsWith('Hey!') || text.startsWith("I'm Kaiju")) return text;
    // Light companion framing without drowning the useful answer
    return text;
  }
}
