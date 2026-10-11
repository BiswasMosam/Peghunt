import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../data/app_state.dart';
import '../data/hunt_book.dart';
import '../scan/matcher.dart';
import '../scan/scanner.dart';
import '../theme.dart';
import 'hit_sheet.dart';
import 'rail.dart';

/// Builds the scanner a result screen uses. Tests swap in a fake OCR.
typedef ScannerFactory = Scanner Function();

Scanner defaultScanner() => Scanner(MlKitOcr());

/// The photo, dimmed, with a ring around every card worth a look, and the
/// same hits as a list underneath. Tapping a row flies the photo to its card.
class ResultScreen extends StatefulWidget {
  const ResultScreen({super.key, required this.imagePath, required this.state, this.scanner = defaultScanner});

  final String imagePath;
  final AppState state;
  final ScannerFactory scanner;

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> with TickerProviderStateMixin {
  late final _reveal = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
  late final _reading = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();
  late final _fly = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  final _zoom = TransformationController();
  Animation<Matrix4>? _flight;

  Size? _imageSize;
  Size _viewport = Size.zero;
  MatchResult? _result;
  Object? _error;
  Hit? _selected;

  @override
  void initState() {
    super.initState();
    _fly.addListener(() {
      final f = _flight;
      if (f != null) _zoom.value = f.value;
    });
    _run();
  }

  @override
  void dispose() {
    _reveal.dispose();
    _reading.dispose();
    _fly.dispose();
    _zoom.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final scanner = widget.scanner();
    try {
      final size = await orientedImageSize(widget.imagePath);
      if (!mounted) return;
      setState(() => _imageSize = size);
      final result = await scanner.scan(widget.imagePath, widget.state.book, widget.state.scanYears);
      if (!mounted) return;
      _reading.stop();
      setState(() => _result = result);
      _reveal.forward();
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      await scanner.close();
    }
  }

  void _tapPhoto(Offset imagePoint) {
    final result = _result;
    final size = _imageSize;
    if (result == null || size == null) return;
    Hit? best;
    var bestDist = double.infinity;
    for (final h in result.hits) {
      final ring = ringFor(h, size);
      final d = (ring.center - imagePoint).distance;
      if (d <= ring.radius * 1.15 && d < bestDist) {
        best = h;
        bestDist = d;
      }
    }
    if (best != null) showHitSheet(context, best, widget.state);
  }

  /// First tap on a row flies the photo to its card; a second tap on the
  /// same row opens what to check. Tapping it a third time flies back out.
  void _tapRow(Hit h) {
    if (_selected == h) {
      showHitSheet(context, h, widget.state);
      return;
    }
    setState(() => _selected = h);
    _flyTo(_matrixFor(h));
  }

  void _zoomOut() {
    setState(() => _selected = null);
    _flyTo(Matrix4.identity());
  }

  void _flyTo(Matrix4 target) {
    _flight = Matrix4Tween(begin: _zoom.value.clone(), end: target)
        .animate(CurvedAnimation(parent: _fly, curve: Curves.easeInOutCubic));
    _fly.forward(from: 0);
  }

  Matrix4 _matrixFor(Hit h) {
    final size = _imageSize!;
    final vw = _viewport.width, vh = _viewport.height;
    final fit = math.min(vw / size.width, vh / size.height);
    final offset = Offset((vw - size.width * fit) / 2, (vh - size.height * fit) / 2);
    final ring = ringFor(h, size);
    final p = offset + ring.center * fit;
    final s = (math.min(vw, vh) * 0.32 / (ring.radius * 2 * fit)).clamp(1.5, 6.0);
    final tx = (vw / 2 - p.dx * s).clamp(vw - vw * s, 0.0);
    final ty = (vh / 2 - p.dy * s).clamp(vh - vh * s, 0.0);
    return Matrix4.identity()
      ..translateByDouble(tx, ty, 0, 1)
      ..scaleByDouble(s, s, 1, 1);
  }

  String get _label {
    if (_error != null) return 'Error';
    final r = _result;
    if (r == null) return 'Reading';
    if (r.hits.isEmpty) return 'Nothing';
    return '${r.hits.length} spotted';
  }

  @override
  Widget build(BuildContext context) {
    final hits = _result?.hits ?? const <Hit>[];
    final counts = <HuntKind, int>{
      for (final k in HuntKind.values) k: hits.where((h) => h.kind == k).length,
    };
    return Scaffold(
      body: Row(
        children: [
          SideRail(
            leading: const RailBack(),
            label: _label,
            bottom: [
              for (final k in HuntKind.values)
                if (counts[k]! > 0) _Count(kind: k, count: counts[k]!),
              const SizedBox(height: 8),
            ],
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    final size = _imageSize;
    if (_error != null) {
      return _Note(title: 'Could not read this photo.', body: '$_error');
    }
    if (size == null) return const ColoredBox(color: Colors.black);
    return LayoutBuilder(builder: (context, box) {
      final top = MediaQuery.paddingOf(context).top;
      final photoH = math.min(box.maxHeight * 0.64, box.maxWidth * size.height / size.width);
      return Column(
        children: [
          SizedBox(height: top),
          SizedBox(height: photoH, child: _photo(size)),
          Expanded(
            child: _HitList(
              result: _result,
              selected: _selected,
              state: widget.state,
              onTap: _tapRow,
              onDetails: (h) => showHitSheet(context, h, widget.state),
              onZoomOut: _selected == null ? null : _zoomOut,
            ),
          ),
        ],
      );
    });
  }

  Widget _photo(Size size) => LayoutBuilder(builder: (context, box) {
        _viewport = box.biggest;
        final fit = math.min(box.maxWidth / size.width, box.maxHeight / size.height);
        return ClipRect(
          child: InteractiveViewer(
            transformationController: _zoom,
            maxScale: 8,
            child: SizedBox(
              width: box.maxWidth,
              height: box.maxHeight,
              child: FittedBox(
                child: SizedBox(
                  width: size.width,
                  height: size.height,
                  child: GestureDetector(
                    onTapUp: (d) => _tapPhoto(d.localPosition),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.file(File(widget.imagePath), fit: BoxFit.fill, cacheWidth: 2400, gaplessPlayback: true),
                        CustomPaint(
                          painter: RingPainter(
                            hits: _result?.hits ?? const [],
                            selected: _selected,
                            imageSize: size,
                            reveal: _reveal,
                            reading: _result == null ? _reading : null,
                            zoom: _zoom,
                            fit: fit,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      });
}

/// The photo's size the way it is shown: a phone held upright writes a
/// landscape JPEG plus an EXIF note to turn it, and both ML Kit and
/// Flutter apply that note. The header alone gives the unturned size, so a
/// tiny decode tells whether to swap it.
Future<Size> orientedImageSize(String path) async {
  final buffer = await ui.ImmutableBuffer.fromFilePath(path);
  final descriptor = await ui.ImageDescriptor.encoded(buffer);
  final raw = Size(descriptor.width.toDouble(), descriptor.height.toDouble());
  final codec = await descriptor.instantiateCodec(targetWidth: 48);
  final frame = await codec.getNextFrame();
  final shownWide = frame.image.width >= frame.image.height;
  frame.image.dispose();
  codec.dispose();
  descriptor.dispose();
  buffer.dispose();
  final rawWide = raw.width >= raw.height;
  return shownWide == rawWide || raw.width == raw.height ? raw : raw.flipped;
}

/// Where a hit's ring sits, in image pixels.
({Offset center, double radius}) ringFor(Hit h, Size image) {
  final b = h.box;
  final long = math.max(b.width, b.height), short = math.min(b.width, b.height);
  final r = math.max(long / 2 + short * 1.2, image.shortestSide * 0.035);
  return (center: b.center, radius: r);
}

class RingPainter extends CustomPainter {
  RingPainter({
    required this.hits,
    required this.selected,
    required this.imageSize,
    required this.reveal,
    required this.reading,
    required this.zoom,
    required this.fit,
  }) : super(repaint: Listenable.merge([reveal, zoom, ?reading]));

  final List<Hit> hits;
  final Hit? selected;
  final Size imageSize;
  final Animation<double> reveal;
  final Animation<double>? reading;
  final TransformationController zoom;

  /// Screen points per image pixel before any pinch zoom.
  final double fit;

  @override
  void paint(Canvas canvas, Size size) {
    // The canvas is in image pixels; strokes and labels stay a fixed size
    // on screen however far the photo is zoomed.
    final px = 1 / (fit * zoom.value.getMaxScaleOnAxis());
    final full = Offset.zero & size;

    final scan = reading;
    if (scan != null) {
      _paintReading(canvas, size, scan.value, px);
      return;
    }
    if (hits.isEmpty) return;

    final t = Curves.easeOut.transform(reveal.value);
    final rings = [for (final h in hits) ringFor(h, imageSize)];

    final holes = Path();
    for (final r in rings) {
      holes.addOval(Rect.fromCircle(center: r.center, radius: r.radius));
    }
    final scrim = Path.combine(PathOperation.difference, Path()..addRect(full), holes);
    canvas.drawPath(scrim, Paint()..color = Colors.black.withValues(alpha: 0.62 * t));

    for (var i = 0; i < hits.length; i++) {
      final start = i * 0.08;
      final p = ((reveal.value - start) / 0.55).clamp(0.0, 1.0);
      if (p <= 0) continue;
      final faded = selected != null && selected != hits[i];
      _paintRing(canvas, hits[i], rings[i].center, rings[i].radius, Curves.easeInOutCubic.transform(p), px,
          bold: selected == hits[i], faded: faded, bounds: full);
    }
  }

  void _paintReading(Canvas canvas, Size size, double t, double px) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black.withValues(alpha: 0.35));
    final y = size.height * t;
    canvas.drawRect(
      Rect.fromLTWH(0, y - 1.5 * px, size.width, 3 * px),
      Paint()..color = Tone.gold.withValues(alpha: 0.9),
    );
  }

  void _paintRing(Canvas canvas, Hit hit, Offset c, double r, double p, double px,
      {required bool bold, required bool faded, required Rect bounds}) {
    final color = Tone.of(hit.kind).withValues(alpha: faded ? 0.35 : 1);
    final width = (hit.certainty == Certainty.possible ? 2.5 : 3.5) * (bold ? 1.6 : 1);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width * px
      ..strokeCap = StrokeCap.round;
    final rect = Rect.fromCircle(center: c, radius: r);
    const top = -math.pi / 2;
    final sweep = 2 * math.pi * p;
    if (hit.certainty == Certainty.possible) {
      const dashes = 28;
      const slot = 2 * math.pi / dashes;
      for (var i = 0; i < dashes; i++) {
        final a = i * slot;
        if (a > sweep) break;
        canvas.drawArc(rect, top + a, math.min(slot * 0.55, sweep - a), false, stroke);
      }
    } else {
      canvas.drawArc(rect, top, sweep, false, stroke);
    }
    if (p < 1) return;

    final label = hit.certainty == Certainty.possible ? '${hit.kind.short}?' : hit.kind.short;
    final tp = TextPainter(
      text: TextSpan(text: label, style: mono(11 * px, bold: true, color: Tone.black, letterSpacing: 0.8 * px)),
      textDirection: TextDirection.ltr,
    )..layout();
    final pad = EdgeInsets.symmetric(horizontal: 6 * px, vertical: 2 * px);
    final w = tp.width + pad.horizontal, h = tp.height + pad.vertical;
    // Top right of the ring, flipped to the left or below when that would
    // run off the photo.
    const d = 0.7071;
    var x = c.dx + d * r, y = c.dy - d * r - h;
    if (x + w > bounds.right) x = c.dx - d * r - w;
    if (y < bounds.top) y = c.dy + d * r;
    x = x.clamp(bounds.left, math.max(bounds.left, bounds.right - w));
    final pill = Rect.fromLTWH(x, y, w, h);
    canvas.drawRect(pill, Paint()..color = color);
    tp.paint(canvas, Offset(pill.left + pad.left, pill.top + pad.top));
  }

  @override
  bool shouldRepaint(RingPainter old) =>
      old.hits != hits || old.reading != reading || old.fit != fit || old.selected != selected;
}

class _HitList extends StatelessWidget {
  const _HitList({
    required this.result,
    required this.selected,
    required this.state,
    required this.onTap,
    required this.onDetails,
    required this.onZoomOut,
  });

  final MatchResult? result;
  final Hit? selected;
  final AppState state;
  final ValueChanged<Hit> onTap;
  final ValueChanged<Hit> onDetails;
  final VoidCallback? onZoomOut;

  @override
  Widget build(BuildContext context) {
    final r = result;
    final bottom = MediaQuery.paddingOf(context).bottom;
    if (r == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
        child: Align(alignment: Alignment.topLeft, child: Text('READING THE CARDS', style: mono(11, color: Tone.bone))),
      );
    }
    if (r.hits.isEmpty) {
      return Padding(
        padding: EdgeInsets.fromLTRB(20, 22, 20, bottom + 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(r.cardsRead > 0 ? 'Nothing on the list.' : 'Nothing read.', style: syne(30)),
            const SizedBox(height: 12),
            Text(_summary(r), style: mono(11, color: Tone.bone)),
          ],
        ),
      );
    }
    return ListView(
      padding: EdgeInsets.fromLTRB(0, 6, 0, bottom + 16),
      children: [
        for (final h in r.hits)
          _HitRow(hit: h, selected: h == selected, onTap: () => onTap(h), onDetails: () => onDetails(h)),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Row(
            children: [
              Expanded(child: Text(_summary(r), style: mono(10))),
              if (onZoomOut != null)
                GestureDetector(
                  onTap: onZoomOut,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Text('SHOW ALL', style: mono(11, bold: true, color: Tone.bone)),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  static String _summary(MatchResult r) {
    final cards = r.cardsRead;
    if (r.hits.isNotEmpty) {
      return 'READ $cards ${cards == 1 ? 'CARD' : 'CARDS'}. TAP A ROW TO FIND IT, AGAIN FOR DETAILS.';
    }
    if (cards > 0) return 'READ $cards ${cards == 1 ? 'CARD NUMBER' : 'CARD NUMBERS'}. NONE ARE TREASURE HUNTS IN THE YEARS YOU SCAN.';
    if (r.linesRead > 0) return 'SAW TEXT BUT NO CARD NUMBERS. STEP CLOSER SO THE NUMBERS ARE SHARP.';
    return 'NO TEXT IN THIS PHOTO. MORE LIGHT, AND STEP CLOSER.';
  }
}

class _HitRow extends StatelessWidget {
  const _HitRow({required this.hit, required this.selected, required this.onTap, required this.onDetails});
  final Hit hit;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    final color = Tone.of(hit.kind);
    final first = hit.candidates.isEmpty ? null : hit.candidates.first;
    final title = first?.name ?? 'Premium chase';
    final more = hit.candidates.length - 1;
    final meta = first == null
        ? 'SET NUMBER 0, READ OFF THE CARD'
        : '${first.year}  ·  ${first.numberLabel}${more > 0 ? '  ·  OR $more MORE' : ''}';
    final certainty = switch (hit.certainty) {
      Certainty.confirmed => 'CONFIRMED',
      Certainty.likely => 'LIKELY',
      Certainty.possible => 'POSSIBLE',
    };
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        color: selected ? Tone.raised : Colors.transparent,
        padding: const EdgeInsets.fromLTRB(20, 12, 4, 12),
        child: Row(
          children: [
            SizedBox(
              width: 62,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(hit.kind.short, style: mono(13, bold: true, color: color)),
                  Text(certainty, style: mono(8, color: color)),
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: manrope(16, weight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(meta, style: mono(10)),
                ],
              ),
            ),
            Semantics(
              button: true,
              label: 'What to check',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onDetails,
                child: const SizedBox.square(
                  dimension: 48,
                  child: Icon(Icons.chevron_right, color: Tone.dim),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count({required this.kind, required this.count});
  final HuntKind kind;
  final int count;

  @override
  Widget build(BuildContext context) => Semantics(
        label: '$count ${kind.label}',
        child: SizedBox(
          width: railWidth,
          height: 56,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('$count', style: manrope(24, weight: FontWeight.w800, color: Tone.of(kind), height: 1)),
              const SizedBox(height: 3),
              Text(kind.short, style: mono(9, bold: true, color: Tone.of(kind))),
            ],
          ),
        ),
      );
}

class _Note extends StatelessWidget {
  const _Note({required this.title, required this.body});
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: syne(30)),
            const SizedBox(height: 12),
            Text(body, style: mono(12)),
            const SizedBox(height: 60),
          ],
        ),
      );
}
