import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:uuid/uuid.dart';

import '../models/game_models.dart';
import 'database.dart';
import 'webp_compressor.dart';

/// Local art pipeline: background isolation, edge-aware crop, 4-frame sprites.
class ArtScanner {
  ArtScanner({
    WebpCompressor? compressor,
    this.frameSize = 128,
  }) : compressor = compressor ?? WebpCompressor(targetSize: frameSize);

  final WebpCompressor compressor;
  final int frameSize;
  static const _uuid = Uuid();

  /// Strip near-uniform background via color-distance thresholding.
  img.Image isolateBackground(
    img.Image source, {
    double threshold = 42,
  }) {
    final sample = _sampleCornerAverage(source);
    final out = img.Image.from(source);
    for (var y = 0; y < out.height; y++) {
      for (var x = 0; x < out.width; x++) {
        final px = out.getPixel(x, y);
        final dist = _colorDistance(
          px.r.toDouble(),
          px.g.toDouble(),
          px.b.toDouble(),
          sample.$1,
          sample.$2,
          sample.$3,
        );
        if (dist < threshold) {
          out.setPixelRgba(x, y, 0, 0, 0, 0);
        }
      }
    }
    return out;
  }

  /// Sobel-style edge magnitude for optional outline boost.
  img.Image detectEdges(img.Image source) {
    final gray = img.grayscale(source);
    return img.sobel(gray);
  }

  /// Crop to opaque bounding box then pad to square.
  img.Image cropToContent(img.Image source, {int padding = 4}) {
    var minX = source.width;
    var minY = source.height;
    var maxX = 0;
    var maxY = 0;
    var found = false;

    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        if (source.getPixel(x, y).a > 16) {
          found = true;
          if (x < minX) minX = x;
          if (y < minY) minY = y;
          if (x > maxX) maxX = x;
          if (y > maxY) maxY = y;
        }
      }
    }
    if (!found) return source;

    minX = (minX - padding).clamp(0, source.width - 1);
    minY = (minY - padding).clamp(0, source.height - 1);
    maxX = (maxX + padding).clamp(0, source.width - 1);
    maxY = (maxY + padding).clamp(0, source.height - 1);

    final w = maxX - minX + 1;
    final h = maxY - minY + 1;
    final cropped = img.copyCrop(source, x: minX, y: minY, width: w, height: h);
    final side = w > h ? w : h;
    final canvas = img.Image(width: side, height: side, numChannels: 4);
    img.compositeImage(
      canvas,
      cropped,
      dstX: (side - w) ~/ 2,
      dstY: (side - h) ~/ 2,
    );
    return canvas;
  }

  /// Build a horizontal 4-frame sheet: Idle, Walk A, Walk B, Jump.
  img.Image buildSpriteSheet(img.Image character) {
    final base = img.copyResize(
      character,
      width: frameSize,
      height: frameSize,
      interpolation: img.Interpolation.average,
    );
    final sheet = img.Image(
      width: frameSize * 4,
      height: frameSize,
      numChannels: 4,
    );

    // Frame 0 — Idle
    img.compositeImage(sheet, base, dstX: 0, dstY: 0);

    // Frame 1 — Walk lean left
    final walkA = img.copyRotate(base, angle: -6);
    final walkAFit = img.copyResize(walkA, width: frameSize, height: frameSize);
    img.compositeImage(sheet, walkAFit, dstX: frameSize, dstY: 0);

    // Frame 2 — Walk lean right
    final walkB = img.copyRotate(base, angle: 6);
    final walkBFit = img.copyResize(walkB, width: frameSize, height: frameSize);
    img.compositeImage(sheet, walkBFit, dstX: frameSize * 2, dstY: 0);

    // Frame 3 — Jump (slight upward nudge + squash)
    final jump = img.copyResize(
      base,
      width: (frameSize * 0.9).round(),
      height: (frameSize * 1.05).round(),
    );
    img.compositeImage(
      sheet,
      jump,
      dstX: frameSize * 3 + ((frameSize - jump.width) ~/ 2),
      dstY: ((frameSize - jump.height) ~/ 2) - 4,
    );

    return sheet;
  }

  /// Auto hitbox from opaque pixels of first frame region.
  HitboxRect computeHitbox(img.Image sheet) {
    final frame = img.copyCrop(
      sheet,
      x: 0,
      y: 0,
      width: frameSize,
      height: frameSize,
    );
    var minX = frameSize;
    var minY = frameSize;
    var maxX = 0;
    var maxY = 0;
    var found = false;
    for (var y = 0; y < frame.height; y++) {
      for (var x = 0; x < frame.width; x++) {
        if (frame.getPixel(x, y).a > 16) {
          found = true;
          if (x < minX) minX = x;
          if (y < minY) minY = y;
          if (x > maxX) maxX = x;
          if (y > maxY) maxY = y;
        }
      }
    }
    if (!found) {
      return HitboxRect(
        x: frameSize * 0.2,
        y: frameSize * 0.2,
        width: frameSize * 0.6,
        height: frameSize * 0.6,
      );
    }
    return HitboxRect(
      x: minX.toDouble(),
      y: minY.toDouble(),
      width: (maxX - minX + 1).toDouble(),
      height: (maxY - minY + 1).toDouble(),
    );
  }

  /// Full pipeline: isolate → crop → sheet → WebP → DB.
  Future<SpriteSheetAsset> processScan({
    required Uint8List rawBytes,
    required String name,
    double bgThreshold = 42,
  }) async {
    final decoded = img.decodeImage(rawBytes);
    if (decoded == null) {
      throw StateError('Could not decode scanned image');
    }
    final isolated = isolateBackground(decoded, threshold: bgThreshold);
    final cropped = cropToContent(isolated);
    final sheet = buildSpriteSheet(cropped);
    final hitbox = computeHitbox(sheet);
    final file = await compressor.storeSpriteSheet(sheet, name: name);
    final asset = SpriteSheetAsset(
      id: _uuid.v4(),
      name: name,
      webpPath: file.path,
      frameWidth: frameSize,
      frameHeight: frameSize,
      frameCount: 4,
      hitbox: hitbox,
      createdAt: DateTime.now(),
    );
    await GameDatabase.instance.upsertSprite(asset);
    return asset;
  }

  (double, double, double) _sampleCornerAverage(img.Image source) {
    final samples = <(int, int)>[
      (2, 2),
      (source.width - 3, 2),
      (2, source.height - 3),
      (source.width - 3, source.height - 3),
    ];
    var r = 0.0, g = 0.0, b = 0.0;
    for (final s in samples) {
      final px = source.getPixel(
        s.$1.clamp(0, source.width - 1),
        s.$2.clamp(0, source.height - 1),
      );
      r += px.r;
      g += px.g;
      b += px.b;
    }
    return (r / 4, g / 4, b / 4);
  }

  double _colorDistance(
    double r1,
    double g1,
    double b1,
    double r2,
    double g2,
    double b2,
  ) {
    final dr = r1 - r2;
    final dg = g1 - g2;
    final db = b1 - b2;
    return (dr * dr + dg * dg + db * db).abs();
  }
}
