import 'package:flutter/material.dart';

import '../../ai_vision/free_brain.dart';
import '../../ai_vision/game_brain.dart';
import '../../models/game_models.dart';
import '../../storage/database.dart';
import '../widgets/loading_overlay.dart';
import 'editor_screen.dart';
import 'play_screen.dart';

class _ChatBubble {
  _ChatBubble({required this.text, required this.isUser, this.reply});

  final String text;
  final bool isUser;
  final BrainReply? reply;
}

/// Conversational Free Brain / OpenAI MCP studio assistant.
class BrainChatScreen extends StatefulWidget {
  const BrainChatScreen({super.key, this.seedProject});

  final GameProject? seedProject;

  @override
  State<BrainChatScreen> createState() => _BrainChatScreenState();
}

class _BrainChatScreenState extends State<BrainChatScreen> {
  final _brain = GameBrain();
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <_ChatBubble>[];
  bool _busy = false;
  GameProject? _draft;

  @override
  void initState() {
    super.initState();
    _draft = widget.seedProject;
    _boot();
  }

  Future<void> _boot() async {
    await _brain.loadMode();
    setState(() {
      _messages.add(
        _ChatBubble(
          text: 'Hi — I\'m ${FreeBrain.identity}\n'
              'Mode: ${_brain.modeLabel}\n\n'
              'Try: “fast platformer with floaty double jump and gem collecting”',
          isUser: false,
        ),
      );
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _brain.dispose();
    super.dispose();
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || _busy) return;
    setState(() {
      _messages.add(_ChatBubble(text: text, isUser: true));
      _input.clear();
      _busy = true;
    });
    _scrollToEnd();

    final reply = await _brain.chat(text, context: _draft);
    if (reply.project != null) _draft = reply.project;
    if (reply.map != null && _draft != null) {
      _draft!.map = reply.map!;
    } else if (reply.map != null && _draft == null) {
      _draft = GameProject(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: 'Brain Level',
        map: reply.map!,
        physics: reply.physics ?? const PhysicsMetrics(),
        description: text,
      );
    }
    if (reply.physics != null && _draft != null) {
      _draft!.physics = reply.physics!;
    }

    setState(() {
      _messages.add(_ChatBubble(text: reply.text, isUser: false, reply: reply));
      _busy = false;
    });
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent + 80,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _saveAndOpen() async {
    final project = _draft;
    if (project == null) return;
    await GameDatabase.instance.upsertProject(project);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => EditorScreen(project: project)),
    );
  }

  Future<void> _playDraft() async {
    final project = _draft;
    if (project == null) return;
    await GameDatabase.instance.upsertProject(project);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PlayScreen(project: project)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Brain'),
        actions: [
          if (_draft != null) ...[
            IconButton(
              tooltip: 'Play draft',
              onPressed: _playDraft,
              icon: const Icon(Icons.play_arrow_rounded),
            ),
            IconButton(
              tooltip: 'Open in editor',
              onPressed: _saveAndOpen,
              icon: const Icon(Icons.edit_outlined),
            ),
          ],
        ],
      ),
      body: LoadingOverlay(
        visible: _busy,
        message: 'Brain thinking…',
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: const Color(0xFF132536),
              child: Text(
                '${_brain.modeLabel} · MCP tools ready · draft: '
                '${_draft?.name ?? "none"}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.all(16),
                itemCount: _messages.length,
                itemBuilder: (context, i) {
                  final m = _messages[i];
                  return Align(
                    alignment:
                        m.isUser ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.sizeOf(context).width * 0.86,
                      ),
                      decoration: BoxDecoration(
                        color: m.isUser
                            ? const Color(0xFFFF8A50)
                            : const Color(0xFF1B2838),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        m.text,
                        style: TextStyle(
                          color: m.isUser
                              ? const Color(0xFF1A120C)
                              : Colors.white,
                          height: 1.35,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  _chip('Floaty double-jump gem hunt'),
                  _chip('Brutal speedrun spikes'),
                  _chip('Generate vertical climb map'),
                  _chip('Make physics icy'),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                12,
                8,
                12,
                12 + MediaQuery.paddingOf(context).bottom,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: 'Describe a game, map, or feel…',
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _busy ? null : _send,
                    child: const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label) {
    return Padding(
      padding: const EdgeInsets.only(right: 8, bottom: 4),
      child: ActionChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        onPressed: _busy ? null : () => _send(label),
      ),
    );
  }
}
