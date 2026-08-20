import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../controllers/dual_control_engine.dart';
import '../../engine/maker_game.dart';
import '../../models/game_models.dart';
import '../../platform/desktop_bootstrap.dart';
import '../widgets/control_overlay.dart';

class PlayScreen extends StatefulWidget {
  const PlayScreen({super.key, required this.project});

  final GameProject project;

  @override
  State<PlayScreen> createState() => _PlayScreenState();
}

class _PlayScreenState extends State<PlayScreen> {
  late final DualControlEngine _controls;
  late final MakerGame _game;
  late final FocusNode _focusNode;
  int _score = 0;
  bool _dead = false;
  bool _showVirtual = !isDesktopNative;

  @override
  void initState() {
    super.initState();
    _controls = DualControlEngine();
    _game = MakerGame(project: widget.project, controls: _controls);
    _focusNode = FocusNode();
    _controls.start();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      _tickHud();
    });
  }

  void _tickHud() {
    if (!mounted) return;
    setState(() {
      _score = _game.score;
      _dead = _game.isDead;
    });
    Future<void>.delayed(const Duration(milliseconds: 200), _tickHud);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (_controls.handleKeyEvent(event)) {
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controls.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        body: Stack(
          children: [
            GameWidget(game: _game),
            Positioned(
              top: MediaQuery.paddingOf(context).top + 8,
              left: 12,
              right: 12,
              child: Row(
                children: [
                  IconButton.filledTonal(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Score $_score',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                      shadows: [Shadow(blurRadius: 8, color: Colors.black)],
                    ),
                  ),
                  const Spacer(),
                  if (isDesktopNative) ...[
                    Text(
                      'WASD · Space',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontWeight: FontWeight.w600,
                        shadows: const [
                          Shadow(blurRadius: 6, color: Colors.black),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      tooltip: _showVirtual
                          ? 'Hide on-screen controls'
                          : 'Show on-screen controls',
                      onPressed: () =>
                          setState(() => _showVirtual = !_showVirtual),
                      icon: Icon(
                        _showVirtual
                            ? Icons.videogame_asset_off
                            : Icons.videogame_asset,
                      ),
                    ),
                  ],
                  if (_controls.connectedPadNames.isNotEmpty)
                    Chip(
                      label: Text(_controls.connectedPadNames.first),
                      avatar: const Icon(Icons.sports_esports, size: 16),
                    ),
                ],
              ),
            ),
            if (_showVirtual) ControlOverlay(engine: _controls),
            if (_dead)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black54,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Ouch!',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: () {
                            _game.respawn();
                            setState(() => _dead = false);
                            _focusNode.requestFocus();
                          },
                          child: const Text('Respawn'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
