import 'package:flutter/material.dart';

import '../../ai_vision/game_brain.dart';
import '../../storage/database.dart';
import '../../storage/webp_compressor.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _keyCtrl = TextEditingController();
  final _cache = CacheManager();
  final _brain = GameBrain();
  String _storageLabel = '…';
  bool _saving = false;
  BrainMode _mode = BrainMode.hybrid;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final key = await GameDatabase.instance.getSetting('openai_api_key');
    final bytes = await _cache.assetsByteSize();
    await _brain.loadMode();
    setState(() {
      _keyCtrl.text = key ?? '';
      _storageLabel = _formatBytes(bytes);
      _mode = _brain.mode;
    });
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    _brain.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'AI Brain',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const SizedBox(height: 8),
          const Text(
            'Free Brain is always on (no cost). OpenAI MCP adds GPT-4o tool calling '
            'when you paste a key. Hybrid uses Free Brain first and escalates to OpenAI.',
            style: TextStyle(color: Colors.white70, height: 1.35),
          ),
          const SizedBox(height: 12),
          SegmentedButton<BrainMode>(
            segments: const [
              ButtonSegment(
                value: BrainMode.freeBrain,
                label: Text('Free'),
                icon: Icon(Icons.psychology_alt_outlined),
              ),
              ButtonSegment(
                value: BrainMode.hybrid,
                label: Text('Hybrid'),
                icon: Icon(Icons.hub_outlined),
              ),
              ButtonSegment(
                value: BrainMode.openAiMcp,
                label: Text('OpenAI'),
                icon: Icon(Icons.cloud_outlined),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: (s) async {
              final next = s.first;
              await _brain.saveMode(next);
              setState(() => _mode = next);
            },
          ),
          const SizedBox(height: 28),
          const Text(
            'OpenAI API (MCP tools)',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _keyCtrl,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'API key',
              hintText: 'sk-…',
              helperText:
                  'Powers GPT-4o Vision maps + MCP tool loop. Optional — Free Brain works without it.',
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _saving
                ? null
                : () async {
                    setState(() => _saving = true);
                    await GameDatabase.instance
                        .setSetting('openai_api_key', _keyCtrl.text.trim());
                    setState(() => _saving = false);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('API key saved')),
                      );
                    }
                  },
            child: Text(_saving ? 'Saving…' : 'Save API key'),
          ),
          const SizedBox(height: 28),
          const Text(
            'Storage',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Game assets (WebP)'),
            subtitle: Text(_storageLabel),
            trailing: IconButton(
              tooltip: 'Refresh',
              onPressed: _load,
              icon: const Icon(Icons.refresh),
            ),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              final n = await _cache.clearStaleCache();
              await _load();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Cleared $n stale cache files')),
                );
              }
            },
            icon: const Icon(Icons.cleaning_services_outlined),
            label: const Text('Clear stale cache'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () async {
              await _cache.clearAllCache();
              await _load();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Cache cleared')),
                );
              }
            },
            icon: const Icon(Icons.delete_sweep_outlined),
            label: const Text('Clear all cache'),
          ),
          const SizedBox(height: 28),
          const Text(
            'About',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const SizedBox(height: 8),
          const Text(
            'Mobile Game Maker · Flutter + Flame\n'
            'Free Brain · OpenAI MCP tools · Dual controls · Art scanner',
            style: TextStyle(color: Colors.white60, height: 1.4),
          ),
        ],
      ),
    );
  }
}
