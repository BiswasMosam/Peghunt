import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';

import '../data/app_state.dart';
import '../data/hunt_book.dart';
import '../scan/matcher.dart';
import '../scan/image_size.dart';
import '../scan/scanner.dart';
import '../scan/tiled_ocr.dart';
import '../theme.dart';
import 'hit_sheet.dart';
import 'rail.dart';

/// Builds the scanner a result screen uses. Tests swap in a fake OCR.
typedef ScannerFactory = Scanner Function();

Scanner defaultScanner() => Scanner(TiledOcr(MlKitOcr()));

/// The photo, dimmed, with a ring around every card worth a look, and the
/// same hits as a list underneath. Tapping a row flies the photo to its card.
class ResultScreen extends StatefulWidget {
  const ResultScreen({
    super.key,
    required this.imagePath,
    required this.state,
    this.scanner = defaultScanner,
    this.fromCamera = false,
  });

  final String imagePath;
  final AppState state;
  final ScannerFactory scanner;

  /// A photo just taken, which only exists in the app until it is saved.
  final bool fromCamera;

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
  var _showReading = false;
  var _saved = false;

  /// Saves the full size photo to the gallery, so a scan that missed a car
  /// can be sent over for tuning without WhatsApp shrinking it.
  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (!await Gal.hasAccess(toAlbum: true)) await Gal.requestAccess(toAlbum: true);
      await Gal.putImage(widget.imagePath, album: 'Peghunt');
      if (!mounted) return;
      setState(() => _saved = true);
      messenger.showSnackBar(const SnackBar(content: Text('Saved to the Peghunt album, full size.')));
    } on GalException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not save the photo (${e.type.message}).')));
    }
  }

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
    // The smallest ring under the finger, so a ring inside a bigger one
    // can still be picked.
    Hit? best;
    var bestArea = double.infinity;
    for (final h in result.hits) {
      final ring = ringFor(h, size);
      final area = ring.width * ring.height;
      if (ring.inflate(ring.shortestSide * 0.1).contains(imagePoint) && area < bestArea) {
        best = h;
        bestArea = area;
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
    final s = (math.min(vw, vh) * 0.6 / (ring.longestSide * fit)).clamp(1.5, 6.0);
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
              RailButton(
                icon: Icons.text_fields,
                tooltip: _showReading ? 'Hide what it read' : 'Show what it read',
                active: _showReading,
                onTap: _result == null ? null : () => setState(() => _showReading = !_showReading),
              ),
              if (widget.fromCamera)
                RailButton(
                  icon: _saved ? Icons.check : Icons.save_alt,
                  tooltip: _saved ? 'Saved' : 'Save photo',
                  active: _saved,
                  onTap: _saved ? null : _save,
                ),
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
                            reading: _showReading ? _result?.lines ?? const [] : const [],
                            selected: _selected,
                            imageSize: size,
                            reveal: _reveal,
                            scanning: _result == null ? _reading : null,
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

/// Where a hit's ring sits, in image pixels: a pill hugging what was read
/// off the card (name strip, number, series tab). A circle round a card
/// spills onto its neighbours; this keeps to the card. Never smaller than
/// a fingertip on a whole-wall photo.
Rect ringFor(Hit h, Size image) {
  final b = h.box;
  final pad = math.min(b.width, b.height) * 0.3 + image.shortestSide * 0.008;
  final least = image.shortestSide * 0.06;
  return Rect.fromCenter(
    center: b.center,
    width: math.max(b.width + 2 * pad, least),
    height: math.max(b.height + 2 * pad, least),
  );
}

RRect _pill(Rect r) => RRect.fromRectAndRadius(r, Radius.circular(math.min(r.width, r.height) / 2));

class RingPainter extends CustomPainter {
  RingPainter({
    required this.hits,
    this.reading = const [],
    required this.selected,
    required this.imageSize,
    required this.reveal,
    required this.scanning,
    required this.zoom,
    required this.fit,
  }) : super(repaint: Listenable.merge([reveal, zoom, ?scanning]));

  final List<Hit> hits;

  /// Every line OCR read, outlined, when the collector asks to see it.
  final List<OcrLine> reading;
  final Hit? selected;
  final Size imageSize;
  final Animation<double> reveal;
  final Animation<double>? scanning;
  final TransformationController zoom;

  /// Screen points per image pixel before any pinch zoom.
  final double fit;

  @override
  void paint(Canvas canvas, Size size) {
    // The canvas is in image pixels; strokes and labels stay a fixed size
    // on screen however far the photo is zoomed.
    final px = 1 / (fit * zoom.value.getMaxScaleOnAxis());
    final full = Offset.zero & size;

    final scan = scanning;
    if (scan != null) {
      _paintScanning(canvas, size, scan.value, px);
      return;
    }
    _paintRings(canvas, size, full, px);
    if (reading.isNotEmpty) _paintRead(canvas, px);
  }

  /// What OCR read: each line outlined, its text above it.
  void _paintRead(Canvas canvas, double px) {
    final box = Paint()
      ..color = Tone.bone.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2 * px;
    for (final l in reading) {
      canvas.drawRect(l.box, box);
      final tp = TextPainter(
        text: TextSpan(text: l.text, style: mono(9 * px, color: Tone.black, letterSpacing: 0)),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: math.max(l.box.width, 140 * px));
      final at = Offset(l.box.left, l.box.top - tp.height - 2 * px);
      canvas.drawRect((at - Offset(2 * px, 0)) & Size(tp.width + 4 * px, tp.height), Paint()..color = Tone.bone);
      tp.paint(canvas, at);
    }
  }

  void _paintRings(Canvas canvas, Size size, Rect full, double px) {
    if (hits.isEmpty) return;

    final t = Curves.easeOut.transform(reveal.value);
    final rings = [for (final h in hits) ringFor(h, imageSize)];

    final holes = Path();
    for (final r in rings) {
      holes.addRRect(_pill(r));
    }
    final scrim = Path.combine(PathOperation.difference, Path()..addRect(full), holes);
    canvas.drawPath(scrim, Paint()..color = Colors.black.withValues(alpha: 0.62 * t));

    for (var i = 0; i < hits.length; i++) {
      final start = i * 0.08;
      final p = ((reveal.value - start) / 0.55).clamp(0.0, 1.0);
      if (p <= 0) continue;
      final faded = selected != null && selected != hits[i];
      _paintRing(canvas, hits[i], rings[i], Curves.easeInOutCubic.transform(p), px,
          bold: selected == hits[i], faded: faded, bounds: full);
    }
  }

  void _paintScanning(Canvas canvas, Size size, double t, double px) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black.withValues(alpha: 0.35));
    final y = size.height * t;
    canvas.drawRect(
      Rect.fromLTWH(0, y - 1.5 * px, size.width, 3 * px),
      Paint()..color = Tone.gold.withValues(alpha: 0.9),
    );
  }

  void _paintRing(Canvas canvas, Hit hit, Rect rect, double p, double px,
      {required bool bold, required bool faded, required Rect bounds}) {
    final color = Tone.of(hit.kind).withValues(alpha: faded ? 0.35 : 1);
    final width = (hit.certainty == Certainty.possible ? 2.5 : 3.5) * (bold ? 1.6 : 1);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width * px
      ..strokeCap = StrokeCap.round;
    // The ring draws itself in, solid when two clues agree, dashed when one
    // matched.
    final metric = (Path()..addRRect(_pill(rect))).computeMetrics().first;
    final drawn = metric.length * p;
    if (hit.certainty == Certainty.possible) {
      final dash = 10 * px, gap = 7 * px;
      for (var d = 0.0; d < drawn; d += dash + gap) {
        canvas.drawPath(metric.extractPath(d, math.min(d + dash, drawn)), stroke);
      }
    } else {
      canvas.drawPath(metric.extractPath(0, drawn), stroke);
    }
    if (p < 1) return;

    final label = hit.certainty == Certainty.possible ? '${hit.kind.short}?' : hit.kind.short;
    final tp = TextPainter(
      text: TextSpan(text: label, style: mono(11 * px, bold: true, color: Tone.black, letterSpacing: 0.8 * px)),
      textDirection: TextDirection.ltr,
    )..layout();
    final pad = EdgeInsets.symmetric(horizontal: 6 * px, vertical: 2 * px);
    final w = tp.width + pad.horizontal, h = tp.height + pad.vertical;
    // On the ring's top edge at the right, or its bottom edge when the top
    // is off the photo.
    var x = rect.right - w - rect.shortestSide * 0.3, y = rect.top - h / 2;
    if (y < bounds.top) y = rect.bottom - h / 2;
    x = x.clamp(bounds.left, math.max(bounds.left, bounds.right - w));
    y = y.clamp(bounds.top, math.max(bounds.top, bounds.bottom - h));
    final pill = Rect.fromLTWH(x, y, w, h);
    canvas.drawRect(pill, Paint()..color = color);
    tp.paint(canvas, Offset(pill.left + pad.left, pill.top + pad.top));
  }

  @override
  bool shouldRepaint(RingPainter old) =>
      old.hits != hits ||
      old.scanning != scanning ||
      old.reading != reading ||
      old.fit != fit ||
      old.selected != selected;
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
    if (cards > 0) return 'READ $cards ${cards == 1 ? 'CARD' : 'CARDS'}. NONE ARE TREASURE HUNTS IN THE YEARS YOU SCAN.';
    if (r.linesRead > 0) return 'SAW TEXT BUT NO CAR NAMES. STEP CLOSER SO THE NAME STRIPS ARE SHARP.';
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
