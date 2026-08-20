import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'database.dart';

class StoredAsset {
  const StoredAsset({required this.path, required this.bytes});

  final String path;
  final Uint8List bytes;
}

/// Lossless/near-lossless WebP conversion at target game resolutions.
class WebpCompressor {
  WebpCompressor({this.targetSize = 128});

  final int targetSize;
  static const _uuid = Uuid();

  Future<StoredAsset> compressAndStore(
    Uint8List rawBytes, {
    String? nameHint,
    int? size,
  }) async {
    final decoded = img.decodeImage(rawBytes);
    if (decoded == null) {
      throw StateError('Unable to decode image bytes');
    }
    final edge = size ?? targetSize;
    final resized = img.copyResize(
      decoded,
      width: edge,
      height: edge,
      interpolation: img.Interpolation.average,
    );
    return storeImage(resized, nameHint: nameHint);
  }

  Future<StoredAsset> storeImage(img.Image image, {String? nameHint}) async {
    final bytes = Uint8List.fromList(img.encodeWebP(image));
    final id = _uuid.v4();
    final safe = (nameHint ?? 'asset').replaceAll(RegExp(r'[^\w\-]+'), '_');
    final fileName = '${safe}_$id.webp';

    if (kIsWeb || GameDatabase.instance.memoryMode) {
      return StoredAsset(path: 'memory://$fileName', bytes: bytes);
    }

    final assets = await GameDatabase.instance.assetsDir();
    final path = p.join(assets, fileName);
    await File(path).writeAsBytes(bytes, flush: true);
    return StoredAsset(path: path, bytes: bytes);
  }

  Future<StoredAsset> storeSpriteSheet(
    img.Image sheet, {
    required String name,
  }) async {
    return storeImage(sheet, nameHint: name);
  }
}

/// Periodically clears temp cache folders to keep storage footprint low.
class CacheManager {
  CacheManager({this.maxAge = const Duration(days: 2)});

  final Duration maxAge;

  Future<int> clearStaleCache() async {
    if (kIsWeb || GameDatabase.instance.memoryMode) return 0;
    final cachePath = await GameDatabase.instance.cacheDir();
    final dir = Directory(cachePath);
    if (!await dir.exists()) return 0;

    var removed = 0;
    final cutoff = DateTime.now().subtract(maxAge);
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final stat = await entity.stat();
      if (stat.modified.isBefore(cutoff)) {
        await entity.delete();
        removed++;
      }
    }
    return removed;
  }

  Future<void> clearAllCache() async {
    if (kIsWeb || GameDatabase.instance.memoryMode) return;
    final cachePath = await GameDatabase.instance.cacheDir();
    final dir = Directory(cachePath);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    await GameDatabase.instance.cacheDir();
  }

  Future<int> assetsByteSize() async {
    if (kIsWeb || GameDatabase.instance.memoryMode) return 0;
    final assets = await GameDatabase.instance.assetsDir();
    final dir = Directory(assets);
    var total = 0;
    if (!await dir.exists()) return 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        total += await entity.length();
      }
    }
    return total;
  }
}
