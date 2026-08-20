import 'package:flutter/material.dart';

import '../../ai_vision/companion.dart';
import '../../ai_vision/free_brain.dart';
import '../../models/game_models.dart';
import '../../storage/database.dart';
import '../screens/editor_screen.dart';
import '../screens/play_screen.dart';

/// Global companion host — auto-opens on first launch, floats on every screen.
class CompanionScope extends StatefulWidget {
  const CompanionScope({super.key, required this.child});

  final Widget child;

  static CompanionScopeState? of(BuildContext context) {
    return context.findAncestorStateOfType<CompanionScopeState>();
  }

  @override
  State<CompanionScope> createState() => CompanionScopeState();
}

class CompanionScopeState extends State<CompanionScope>
    with TickerProviderStateMixin {
  final CompanionBrain brain = CompanionBrain();
  final _messages = <_CompanionMsg>[];
  final _input = TextEditingController();
  bool _panelOpen = false;
  bool _busy = false;
  bool _booted = false;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _boot();
  }

  Future<void> _boot() async {
    await brain.init();
    final seen = await GameDatabase.instance.getSetting('kaiju_welcomed');
    setState(() {
      _booted = true;
      _messages.add(
        _CompanionMsg(text: CompanionIdentity.welcome, isUser: false),
      );
    });
    if (seen != '1') {
      await GameDatabase.instance.setSetting('kaiju_welcomed', '1');
      // Auto-open companion on first launch
      await Future<void>.delayed(const Duration(milliseconds: 600));
      if (mounted) setState(() => _panelOpen = true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    _input.dispose();
    brain.dispose();
    super.dispose();
  }

  void setRoute(String route) {
    brain.currentRoute = route;
  }

  void setProject(GameProject? project) {
    brain.activeProject = project;
  }

  void openPanel({String? seedMessage}) {
    setState(() => _panelOpen = true);
    if (seedMessage != null) {
      _send(seedMessage);
    }
  }

  void closePanel() => setState(() => _panelOpen = false);

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || _busy) return;
    setState(() {
      _messages.add(_CompanionMsg(text: text, isUser: true));
      _input.clear();
      _busy = true;
    });

    final reply = await brain.respond(text);
    if (!mounted) return;
    setState(() {
      _messages.add(_CompanionMsg(text: reply.text, isUser: false, reply: reply));
      _busy = false;
    });
  }

  Future<void> _applyDraft(BrainReply reply) async {
    final project = reply.project;
    if (project == null) return;
    await GameDatabase.instance.upsertProject(project);
    brain.activeProject = project;
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => EditorScreen(project: project)),
    );
  }

  Future<void> _playDraft(BrainReply reply) async {
    final project = reply.project ?? brain.activeProject;
    if (project == null) return;
    await GameDatabase.instance.upsertProject(project);
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PlayScreen(project: project)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_booted) ...[
          Positioned(
            right: 16,
            bottom: 24 + MediaQuery.paddingOf(context).bottom,
            child: _Fab(
              pulse: _pulse,
              open: _panelOpen,
              onTap: () => setState(() => _panelOpen = !_panelOpen),
            ),
          ),
          if (_panelOpen)
            Positioned.fill(
              child: _CompanionPanel(
                messages: _messages,
                busy: _busy,
                input: _input,
                onClose: closePanel,
                onSend: _send,
                onTip: () => _send(CompanionIdentity.tipForRoute(brain.currentRoute)),
                onApply: _applyDraft,
                onPlay: _playDraft,
              ),
            ),
        ],
      ],
    );
  }
}

class _CompanionMsg {
  _CompanionMsg({required this.text, required this.isUser, this.reply});
  final String text;
  final bool isUser;
  final BrainReply? reply;
}

class _Fab extends StatelessWidget {
  const _Fab({
    required this.pulse,
    required this.open,
    required this.onTap,
  });

  final AnimationController pulse;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween(begin: 1.0, end: 1.06).animate(
        CurvedAnimation(parent: pulse, curve: Curves.easeInOut),
      ),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF8A50).withValues(alpha: 0.45),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
            border: Border.all(color: const Color(0xFFFF8A50), width: 2.5),
          ),
          child: ClipOval(
            child: open
                ? const ColoredBox(
                    color: Color(0xFF1B2838),
                    child: Icon(Icons.close, color: Colors.white, size: 28),
                  )
                : Image.asset(
                    CompanionIdentity.assetPath,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const ColoredBox(
                      color: Color(0xFFC62828),
                      child: Icon(Icons.pets, color: Colors.white),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _CompanionPanel extends StatelessWidget {
  const _CompanionPanel({
    required this.messages,
    required this.busy,
    required this.input,
    required this.onClose,
    required this.onSend,
    required this.onTip,
    required this.onApply,
    required this.onPlay,
  });

  final List<_CompanionMsg> messages;
  final bool busy;
  final TextEditingController input;
  final VoidCallback onClose;
  final void Function([String?]) onSend;
  final VoidCallback onTip;
  final Future<void> Function(BrainReply) onApply;
  final Future<void> Function(BrainReply) onPlay;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Material(
      color: Colors.black54,
      child: SafeArea(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            height: MediaQuery.sizeOf(context).height * 0.62,
            decoration: BoxDecoration(
              color: const Color(0xFF0F1C28),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0x44FF8A50)),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.asset(
                          CompanionIdentity.assetPath,
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              CompanionIdentity.name,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 17,
                              ),
                            ),
                            Text(
                              CompanionIdentity.tagline,
                              style: TextStyle(
                                color: Colors.white60,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: onClose,
                        icon: const Icon(Icons.keyboard_arrow_down),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: messages.length,
                    itemBuilder: (context, i) {
                      final m = messages[i];
                      return Align(
                        alignment: m.isUser
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.sizeOf(context).width * 0.78,
                          ),
                          decoration: BoxDecoration(
                            color: m.isUser
                                ? const Color(0xFFFF8A50)
                                : const Color(0xFF1B2838),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                m.text,
                                style: TextStyle(
                                  color: m.isUser
                                      ? const Color(0xFF1A120C)
                                      : Colors.white,
                                  height: 1.35,
                                ),
                              ),
                              if (m.reply?.project != null) ...[
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    ActionChip(
                                      label: const Text('Open editor'),
                                      onPressed: () => onApply(m.reply!),
                                    ),
                                    ActionChip(
                                      label: const Text('Play now'),
                                      onPressed: () => onPlay(m.reply!),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (busy)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 6),
                    child: LinearProgressIndicator(
                      minHeight: 2,
                      color: Color(0xFFFF8A50),
                    ),
                  ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    children: [
                      ActionChip(
                        avatar: const Icon(Icons.lightbulb_outline, size: 16),
                        label: const Text('Tip for this screen'),
                        onPressed: busy ? null : onTip,
                      ),
                      const SizedBox(width: 6),
                      ActionChip(
                        label: const Text('Design a game'),
                        onPressed: busy
                            ? null
                            : () => onSend(
                                  'design a floaty double-jump gem hunt platformer',
                                ),
                      ),
                      const SizedBox(width: 6),
                      ActionChip(
                        label: const Text('Help'),
                        onPressed: busy ? null : () => onSend('help'),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(10, 6, 10, 10 + bottom * 0.2),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: input,
                          minLines: 1,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            hintText: 'Ask Kaiju…',
                            isDense: true,
                          ),
                          onSubmitted: (_) => onSend(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: busy ? null : () => onSend(),
                        child: const Icon(Icons.send_rounded, size: 20),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
