import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/game_models.dart';
import '../../storage/database.dart';
import '../../storage/webp_compressor.dart';
import 'art_scanner_screen.dart';
import 'editor_screen.dart';
import 'map_parser_screen.dart';
import 'physics_engine_screen.dart';
import 'play_screen.dart';
import 'remapping_screen.dart';
import 'settings_screen.dart';

final projectsProvider =
    FutureProvider.autoDispose<List<GameProject>>((ref) async {
  return GameDatabase.instance.listProjects();
});

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projects = ref.watch(projectsProvider);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            title: const Text('Game Maker'),
            actions: [
              IconButton(
                tooltip: 'Controller remap',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const RemappingScreen()),
                ),
                icon: const Icon(Icons.gamepad_outlined),
              ),
              IconButton(
                tooltip: 'Settings',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                ),
                icon: const Icon(Icons.settings_outlined),
              ),
            ],
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _HeroBanner(
                    onCreate: () => _createProject(context, ref),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Studio tools',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _ToolChip(
                        icon: Icons.camera_alt_outlined,
                        label: 'Art Scanner',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ArtScannerScreen(),
                          ),
                        ),
                      ),
                      _ToolChip(
                        icon: Icons.map_outlined,
                        label: 'Map Parser',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const MapParserScreen(),
                          ),
                        ),
                      ),
                      _ToolChip(
                        icon: Icons.science_outlined,
                        label: 'Physics AI',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const PhysicsEngineScreen(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      Text(
                        'Your games',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () => _createProject(context, ref),
                        icon: const Icon(Icons.add),
                        label: const Text('New'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          projects.when(
            loading: () => const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => SliverFillRemaining(
              child: Center(child: Text('Error: $e')),
            ),
            data: (list) {
              if (list.isEmpty) {
                return const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Text(
                      'No games yet — tap New to start.',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                );
              }
              return SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final project = list[index];
                    return _ProjectTile(
                      project: project,
                      onPlay: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => PlayScreen(project: project),
                        ),
                      ),
                      onEdit: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => EditorScreen(project: project),
                          ),
                        );
                        ref.invalidate(projectsProvider);
                      },
                      onDelete: () async {
                        await GameDatabase.instance.deleteProject(project.id);
                        ref.invalidate(projectsProvider);
                      },
                    );
                  },
                ),
              );
            },
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }

  Future<void> _createProject(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(text: 'Untitled Game');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New game'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final project = GameProject.create(name: name);
    await GameDatabase.instance.upsertProject(project);
    // Touch cache housekeeping on create
    await CacheManager().clearStaleCache();
    ref.invalidate(projectsProvider);
    if (context.mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => EditorScreen(project: project)),
      );
      ref.invalidate(projectsProvider);
    }
  }
}

class _HeroBanner extends StatelessWidget {
  const _HeroBanner({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1B3A4B), Color(0xFF0D1B2A), Color(0xFF2A1F14)],
        ),
        border: Border.all(color: const Color(0x33FF8A50)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Mobile Game Maker',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFFFF8A50),
                ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Scan art, parse maps with Vision, tune physics, and play with dual controls — all on device.',
            style: TextStyle(color: Colors.white70, height: 1.4),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.rocket_launch_outlined),
            label: const Text('Create game'),
          ),
        ],
      ),
    );
  }
}

class _ToolChip extends StatelessWidget {
  const _ToolChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF162433),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0x22FFFFFF)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: const Color(0xFFFF8A50)),
            const SizedBox(width: 8),
            Text(label),
          ],
        ),
      ),
    );
  }
}

class _ProjectTile extends StatelessWidget {
  const _ProjectTile({
    required this.project,
    required this.onPlay,
    required this.onEdit,
    required this.onDelete,
  });

  final GameProject project;
  final VoidCallback onPlay;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF162433),
      borderRadius: BorderRadius.circular(16),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        title: Text(project.name, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          '${project.map.width}×${project.map.height} · '
          'speed ${project.physics.moveSpeed.toStringAsFixed(0)}',
        ),
        trailing: Wrap(
          spacing: 4,
          children: [
            IconButton(
              tooltip: 'Play',
              onPressed: onPlay,
              icon: const Icon(Icons.play_arrow_rounded),
            ),
            IconButton(
              tooltip: 'Edit',
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              tooltip: 'Delete',
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
      ),
    );
  }
}
