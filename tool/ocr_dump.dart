// Runs the real ML Kit reader on a phone or emulator over a folder of photos
// served from the computer, and posts back what it read plus what the
// matcher made of it. This is how the card reader gets tuned against real
// cards instead of guesses.
//
//   python tool/ocr_server.py training/photos out.json        (on the computer)
//   flutter run -t tool/ocr_dump.dart -d emulator-5554 --release --no-resident
//
// The server prints "saved" when the results are in. The emulator reaches
// the computer at 10.0.2.2; for a real phone pass
// --dart-define=OCR_HOST=http://<pc ip>:8765. --dart-define=TILED=false
// reads each photo once, without tiles.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:peghunt/data/hunt_book.dart';
import 'package:peghunt/scan/image_size.dart';
import 'package:peghunt/scan/matcher.dart';
import 'package:peghunt/scan/scanner.dart';
import 'package:peghunt/scan/tiled_ocr.dart';

const host = String.fromEnvironment('OCR_HOST', defaultValue: 'http://10.0.2.2:8765');
const tiled = bool.fromEnvironment('TILED', defaultValue: true);

final status = ValueNotifier('Reading photos…');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MaterialApp(
    home: Scaffold(
      body: Center(child: ValueListenableBuilder(valueListenable: status, builder: (_, s, _) => Text(s))),
    ),
  ));
  try {
    final n = await dump();
    status.value = 'Done: $n photos read and posted to $host.';
  } catch (e) {
    status.value = 'Failed: $e';
    rethrow;
  }
}

Future<List<int>> _get(HttpClient http, String path) async {
  final res = await (await http.getUrl(Uri.parse('$host$path'))).close();
  final bytes = <int>[];
  await for (final chunk in res) {
    bytes.addAll(chunk);
  }
  if (res.statusCode != 200) throw HttpException('GET $path: ${res.statusCode}');
  return bytes;
}

Future<int> dump() async {
  final book = HuntBook.fromJsonString(
    await rootBundle.loadString('assets/hunts.json'),
    castings: await rootBundle.loadString('assets/castings.json'),
  );
  final http = HttpClient();
  final names = (jsonDecode(utf8.decode(await _get(http, '/index.json'))) as List).cast<String>();
  final dir = await Directory.systemTemp.createTemp('ocr');
  final OcrEngine ocr = tiled ? TiledOcr(MlKitOcr()) : MlKitOcr();
  final out = <Map<String, Object?>>[];
  for (final (i, name) in names.indexed) {
    status.value = 'Reading ${i + 1} of ${names.length}: $name';
    final file = File('${dir.path}/$i${name.substring(name.lastIndexOf('.'))}');
    await file.writeAsBytes(await _get(http, '/img/${Uri.encodeComponent(name)}'));
    final watch = Stopwatch()..start();
    final size = await orientedImageSize(file.path);
    final lines = await ocr.read(file.path);
    final ms = watch.elapsedMilliseconds;
    final result = matchLines(lines, book, book.years.toSet());
    out.add({
      'file': name,
      'w': size.width,
      'h': size.height,
      'ms': ms,
      'lines': [
        for (final l in lines)
          {'t': l.text, 'k': l.block, 'b': [l.box.left, l.box.top, l.box.right, l.box.bottom]},
      ],
      'cardsRead': result.cardsRead,
      'hits': [
        for (final h in result.hits)
          {
            'kind': h.kind.name,
            'certainty': h.certainty.name,
            'b': [h.box.left, h.box.top, h.box.right, h.box.bottom],
            'cands': [for (final c in h.candidates) c.toString()],
            'evidence': h.evidence,
          },
      ],
    });
  }
  await ocr.close();
  final req = await http.postUrl(Uri.parse('$host/result'));
  final body = utf8.encode(jsonEncode(out));
  req.headers.contentType = ContentType.json;
  req.contentLength = body.length;
  req.add(body);
  final res = await req.close();
  await res.drain<void>();
  http.close();
  if (res.statusCode != 200) throw HttpException('POST /result: ${res.statusCode}');
  return names.length;
}
