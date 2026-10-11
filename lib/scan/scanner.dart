import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../data/hunt_book.dart';
import 'matcher.dart';

/// Reads the text in a photo. ML Kit on the phone; a fake in tests.
abstract interface class OcrEngine {
  Future<List<OcrLine>> read(String imagePath);
  Future<void> close();
}

/// Google ML Kit's on-device Latin text recognizer. No network, no account.
class MlKitOcr implements OcrEngine {
  final _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  @override
  Future<List<OcrLine>> read(String imagePath) async {
    final text = await _recognizer.processImage(InputImage.fromFilePath(imagePath));
    return [
      for (final (i, block) in text.blocks.indexed)
        for (final l in block.lines) OcrLine(l.text, l.boundingBox, block: i),
    ];
  }

  @override
  Future<void> close() => _recognizer.close();
}

/// Photo in, rings out.
class Scanner {
  Scanner(this._ocr);
  final OcrEngine _ocr;

  Future<MatchResult> scan(String imagePath, HuntBook book, Set<int> years) async {
    final lines = await _ocr.read(imagePath);
    return matchLines(lines, book, years);
  }

  Future<void> close() => _ocr.close();
}
