import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../../models/game_models.dart';
import '../../storage/art_scanner.dart';
import '../../storage/database.dart';
import '../widgets/loading_overlay.dart';

class ArtScannerScreen extends StatefulWidget {
  const ArtScannerScreen({super.key});

  @override
  State<ArtScannerScreen> createState() => _ArtScannerScreenState();
}

class _ArtScannerScreenState extends State<ArtScannerScreen> {
  final _picker = ImagePicker();
  final _scanner = ArtScanner(frameSize: 128);
  final _nameCtrl = TextEditingController(text: 'Hero');
  Uint8List? _preview;
  SpriteSheetAsset? _result;
  bool _busy = false;
  String? _status;
  double _threshold = 42;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    final file = await _picker.pickImage(source: source, imageQuality: 92);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _preview = bytes;
      _result = null;
      _status = null;
    });
  }

  Future<void> _process() async {
    if (_preview == null) return;
    setState(() {
      _busy = true;
      _status = 'Isolating background & building sprite sheet…';
    });
    try {
      final asset = await _scanner.processScan(
        rawBytes: _preview!,
        name: _nameCtrl.text.trim().isEmpty ? 'Sprite' : _nameCtrl.text.trim(),
        bgThreshold: _threshold,
      );
      // Build preview of sheet for UI
      final sheetPreview = _scanner.buildSpriteSheet(
        _scanner.cropToContent(
          _scanner.isolateBackground(
            img.decodeImage(_preview!)!,
            threshold: _threshold,
          ),
        ),
      );
      setState(() {
        _result = asset;
        _preview = Uint8List.fromList(img.encodePng(sheetPreview));
        _status = 'Saved WebP · ${asset.frameCount} frames · hitbox '
            '${asset.hitbox.width.toStringAsFixed(0)}×'
            '${asset.hitbox.height.toStringAsFixed(0)}';
      });
    } catch (e) {
      setState(() => _status = 'Failed: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Art Scanner')),
      body: LoadingOverlay(
        visible: _busy,
        message: _status ?? 'Processing…',
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Sprite name'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pick(ImageSource.camera),
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('Camera'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pick(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Gallery'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Background threshold: ${_threshold.toStringAsFixed(0)}'),
            Slider(
              value: _threshold,
              min: 10,
              max: 120,
              onChanged: (v) => setState(() => _threshold = v),
            ),
            const SizedBox(height: 8),
            if (_preview != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: ColoredBox(
                  color: const Color(0xFF1B2838),
                  child: Image.memory(_preview!, fit: BoxFit.contain, height: 220),
                ),
              )
            else
              Container(
                height: 180,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF162433),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Capture a hand-drawn character or sketch',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _preview == null || _busy ? null : _process,
              icon: const Icon(Icons.brush_outlined),
              label: const Text('Generate 4-frame sprite'),
            ),
            if (_status != null) ...[
              const SizedBox(height: 12),
              Text(_status!, style: const TextStyle(color: Colors.white70)),
            ],
            if (_result != null) ...[
              const SizedBox(height: 16),
              ListTile(
                tileColor: const Color(0xFF162433),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                title: Text(_result!.name),
                subtitle: Text(_result!.webpPath),
                trailing: const Icon(Icons.check_circle, color: Colors.greenAccent),
              ),
            ],
            const SizedBox(height: 24),
            const Text('Saved sprites', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            FutureBuilder(
              future: GameDatabase.instance.listSprites(),
              builder: (context, snap) {
                final list = snap.data ?? [];
                if (list.isEmpty) {
                  return const Text('None yet', style: TextStyle(color: Colors.white54));
                }
                return Column(
                  children: list
                      .map(
                        (s) => ListTile(
                          title: Text(s.name),
                          subtitle: Text(
                            '${s.frameWidth}px · ${s.frameCount} frames',
                          ),
                          dense: true,
                        ),
                      )
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Helper for tests / map parser to encode small PNGs as base64.
String encodePngBase64(img.Image image) =>
    base64Encode(Uint8List.fromList(img.encodePng(image)));
