import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'image_size.dart';
import 'matcher.dart';
import 'scanner.dart';

/// Reads small photos twice: whole, then as four enlarged tiles.
///
/// Measured on real shop photos (WhatsApp copies, about 1300 px across):
/// ML Kit misses text under about 8 px tall, which is every card name in a
/// photo of a whole wall. The same photos read 2.5 times as many words as
/// 2x2 tiles each enlarged 2x. A full size camera photo (4000 px) already
/// has the pixels, so it is read once, as is.
class TiledOcr implements OcrEngine {
  TiledOcr(this._inner, {this.targetLongSide = 2600, this.maxScale = 3});

  final OcrEngine _inner;

  /// Photos at least this long on their long side are read in one pass.
  final double targetLongSide;
  final double maxScale;

  @override
  Future<List<OcrLine>> read(String imagePath) async {
    final whole = await _inner.read(imagePath);
    final shown = await orientedImageSize(imagePath);
    final long = math.max(shown.width, shown.height);
    if (long >= targetLongSide) return whole;

    final buffer = await ui.ImmutableBuffer.fromFilePath(imagePath);
    final codec = await ui.instantiateImageCodecFromBuffer(buffer);
    final image = (await codec.getNextFrame()).image;
    codec.dispose();
    final size = ui.Size(image.width.toDouble(), image.height.toDouble());
    final scale = (targetLongSide / long).clamp(1.0, maxScale);
    final dir = await Directory.systemTemp.createTemp('peghunt_tiles');
    try {
      final all = [...whole];
      for (final (i, rect) in tileRects(size, 2).indexed) {
        final path = '${dir.path}/tile$i.png';
        await _writeTile(image, rect, scale, path);
        for (final l in await _inner.read(path)) {
          all.add(OcrLine(
            l.text,
            ui.Rect.fromLTRB(
              rect.left + l.box.left / scale,
              rect.top + l.box.top / scale,
              rect.left + l.box.right / scale,
              rect.top + l.box.bottom / scale,
            ),
            block: (i + 1) * 100000 + l.block,
          ));
        }
      }
      return dedupeLines(all);
    } finally {
      image.dispose();
      await dir.delete(recursive: true);
    }
  }

  static Future<void> _writeTile(ui.Image image, ui.Rect rect, double scale, String path) async {
    final w = (rect.width * scale).round(), h = (rect.height * scale).round();
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawImageRect(
      image,
      rect,
      ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      ui.Paint()..filterQuality = ui.FilterQuality.high,
    );
    final tile = await recorder.endRecording().toImage(w, h);
    final png = await tile.toByteData(format: ui.ImageByteFormat.png);
    tile.dispose();
    await File(path).writeAsBytes(png!.buffer.asUint8List(), flush: true);
  }

  @override
  Future<void> close() => _inner.close();
}

/// An n×n grid over [size], each tile grown so neighbours overlap by
/// [overlap] of a tile. Text cut by one tile's edge is whole in the next.
List<ui.Rect> tileRects(ui.Size size, int n, {double overlap = 0.12}) {
  final tw = math.min(size.width, size.width / n * (1 + overlap));
  final th = math.min(size.height, size.height / n * (1 + overlap));
  return [
    for (var r = 0; r < n; r++)
      for (var c = 0; c < n; c++)
        ui.Rect.fromLTWH(
          n == 1 ? 0 : (size.width - tw) * c / (n - 1),
          n == 1 ? 0 : (size.height - th) * r / (n - 1),
          tw,
          th,
        ),
  ];
}

int _alnum(String s) => RegExp(r'[A-Za-z0-9]').allMatches(s).length;

/// The whole photo and its overlapping tiles read the same text more than
/// once, often with one copy cut short ("THEN AND NO"). Where two lines
/// cover the same spot, keep the one that read more.
List<OcrLine> dedupeLines(List<OcrLine> lines) {
  final byLength = [...lines]..sort((a, b) => _alnum(b.text).compareTo(_alnum(a.text)));
  final kept = <OcrLine>[];
  for (final l in byLength) {
    final area = l.box.width * l.box.height;
    final dup = kept.any((k) {
      final i = k.box.intersect(l.box);
      if (i.width <= 0 || i.height <= 0) return false;
      final smaller = math.min(area, k.box.width * k.box.height);
      return i.width * i.height >= 0.5 * smaller;
    });
    if (!dup) kept.add(l);
  }
  // Back in reading order, so lines of one block stay next to each other.
  kept.sort((a, b) {
    final c = a.block.compareTo(b.block);
    return c != 0 ? c : a.box.top.compareTo(b.box.top);
  });
  return kept;
}
