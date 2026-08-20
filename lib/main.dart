import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'platform/desktop_bootstrap.dart';
import 'storage/database.dart';
import 'storage/webp_compressor.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Native PC window (title, size, focus) — skipped on mobile/web.
  await bootstrapDesktopWindow();

  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  if (kIsWeb) {
    await GameDatabase.instance.init(forceMemory: true);
  } else {
    try {
      await getApplicationDocumentsDirectory();
      await GameDatabase.instance.init();
      await CacheManager().clearStaleCache();
    } catch (e, st) {
      debugPrint('Storage init failed, memory fallback: $e\n$st');
      await GameDatabase.instance.init(forceMemory: true);
    }
  }

  await _seedOpenAiKeyFromEnvironment();

  runApp(const GameMakerApp());
}

/// Prefer dart-define, then process env (Cloud Agent / desktop secrets).
Future<void> _seedOpenAiKeyFromEnvironment() async {
  const defined = String.fromEnvironment('OPENAI_API_KEY');
  var key = defined;
  if (key.isEmpty && !kIsWeb) {
    key = Platform.environment['OPENAI_API_KEY'] ?? '';
  }
  if (key.isEmpty) return;

  final existing = await GameDatabase.instance.getSetting('openai_api_key');
  if (existing == null || existing.isEmpty) {
    await GameDatabase.instance.setSetting('openai_api_key', key);
  }
}
