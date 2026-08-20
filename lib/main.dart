import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'storage/database.dart';
import 'storage/webp_compressor.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Prefer landscape for play; UI handles both orientations.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

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

  runApp(const GameMakerApp());
}
