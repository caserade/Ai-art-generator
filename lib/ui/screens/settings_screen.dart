import 'package:flutter/material.dart';

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
  String _storageLabel = '…';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final key = await GameDatabase.instance.getSetting('openai_api_key');
    final bytes = await _cache.assetsByteSize();
    setState(() {
      _keyCtrl.text = key ?? '';
      _storageLabel = _formatBytes(bytes);
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
            'OpenAI API',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _keyCtrl,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'API key',
              hintText: 'sk-…',
              helperText: 'Stored locally in SQLite. Used for Vision map & physics.',
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
            'Dual controls · Art scanner · Vision maps · AI physics',
            style: TextStyle(color: Colors.white60, height: 1.4),
          ),
        ],
      ),
    );
  }
}
