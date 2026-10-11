import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peghunt/scan/matcher.dart';
import 'package:peghunt/scan/scanner.dart';
import 'package:peghunt/scan/tiled_ocr.dart';

const fixture = 'test/fixtures/wall_300x400.jpg';

/// Records every image it was asked to read and answers from [answers],
/// keyed by the end of the file name ("tile3.png"), or the whole photo.
class RecordingOcr implements OcrEngine {
  RecordingOcr(this.answers);
  final Map<String, List<OcrLine>> answers;
  final reads = <String, ui.Size>{};

  @override
  Future<List<OcrLine>> read(String imagePath) async {
    final bytes = await File(imagePath).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final image = (await codec.getNextFrame()).image;
    final name = imagePath.endsWith('.png') ? imagePath.split(RegExp(r'[\\/]')).last : 'whole';
    reads[name] = ui.Size(image.width.toDouble(), image.height.toDouble());
    image.dispose();
    return answers[name] ?? const [];
  }

  @override
  Future<void> close() async {}
}

void main() {
  test('tiles cover the photo and overlap', () {
    final tiles = tileRects(const Size(300, 400), 2);
    expect(tiles, hasLength(4));
    expect(tiles.first.topLeft, Offset.zero);
    expect(tiles.last.bottomRight, const Offset(300, 400));
    expect(tiles[0].overlaps(tiles[1]), isTrue);
    expect(tiles[0].right, greaterThan(150));
  });

  test('a line read twice keeps the copy that read more', () {
    final kept = dedupeLines([
      const OcrLine('THEN AND NO', Rect.fromLTWH(0, 0, 100, 20)),
      const OcrLine('THEN AND NOW', Rect.fromLTWH(2, 1, 110, 20)),
      const OcrLine('ROD SQUAD', Rect.fromLTWH(0, 300, 90, 20)),
    ]);
    expect(kept.map((l) => l.text), ['THEN AND NOW', 'ROD SQUAD']);
  });

  testWidgets('a small photo is read whole and as four enlarged tiles', (tester) async {
    await tester.runAsync(() async {
      final ocr = RecordingOcr({
        'whole': const [OcrLine('ROD SQUAD', Rect.fromLTWH(10, 10, 60, 10))],
        // In the bottom right tile, enlarged 3x.
        'tile3.png': const [OcrLine('CONE SHAKER', Rect.fromLTWH(30, 60, 60, 30))],
      });
      final lines = await TiledOcr(ocr).read(fixture);

      expect(ocr.reads.keys, containsAll(['whole', 'tile0.png', 'tile1.png', 'tile2.png', 'tile3.png']));
      // 300x400 is enlarged 3x (the cap): each tile is 168x224 of the photo.
      expect(ocr.reads['tile3.png'], const ui.Size(504, 672));

      final cone = lines.singleWhere((l) => l.text == 'CONE SHAKER');
      // Back in photo pixels: tile origin (132, 176) plus 30/3, 60/3.
      expect(cone.box.left, closeTo(142, 0.01));
      expect(cone.box.top, closeTo(196, 0.01));
      expect(cone.box.width, closeTo(20, 0.01));
      expect(lines.map((l) => l.text), contains('ROD SQUAD'));
    });
  });

  testWidgets('a full size photo is read once', (tester) async {
    await tester.runAsync(() async {
      final ocr = RecordingOcr({});
      await TiledOcr(ocr, targetLongSide: 400).read(fixture);
      expect(ocr.reads.keys, ['whole']);
    });
  });
}
