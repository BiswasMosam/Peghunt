import 'dart:math' as math;
import 'dart:ui';

import '../data/hunt_book.dart';
import 'text_match.dart';

/// One line of text OCR found in the photo, in image pixels.
class OcrLine {
  const OcrLine(this.text, this.box, {this.block = 0});
  final String text;
  final Rect box;

  /// Lines OCR grouped together. A car name split over two lines of a card
  /// stays inside one block.
  final int block;
}

/// How sure Peghunt is about a hit.
enum Certainty {
  /// The card says so (the treasure hunt line on the back).
  confirmed,

  /// Two things on the card agree: its number and its series or name.
  likely,

  /// One thing matched. Worth a look, not worth a cheer.
  possible,
}

/// A spot in the photo worth a closer look.
class Hit {
  Hit({
    required this.kind,
    required this.certainty,
    required this.box,
    required this.candidates,
    required this.evidence,
  });

  final HuntKind kind;
  final Certainty certainty;

  /// Where the evidence sits in the photo, in image pixels.
  final Rect box;

  /// Cars from the hunt book this could be, best first. Empty for a chase
  /// spotted by its 0/5 number, which needs no list.
  final List<HuntEntry> candidates;

  /// What was read off the card, in plain words.
  final List<String> evidence;
}

class MatchResult {
  const MatchResult({required this.hits, required this.cardsRead, required this.linesRead});
  final List<Hit> hits;

  /// Collector numbers read anywhere in the photo, so the app can say
  /// "read 14 cards, none rare" instead of a bare "nothing found".
  final int cardsRead;
  final int linesRead;
}

enum _Field { number, otherNumber, name, series, chase, phrase, superPhrase }

class _Signal {
  _Signal(this.field, this.box, this.text, {this.entries = const [], this.number});
  final _Field field;
  final Rect box;
  final String text;
  final List<HuntEntry> entries;
  final int? number;
}

/// Signals closer than this many line heights belong to the same card.
/// A first guess until real peg wall photos tune it.
const cardReach = 3.0;

/// Turns OCR lines into hits, using the cars of [years] in [book].
MatchResult matchLines(List<OcrLine> lines, HuntBook book, Set<int> years) {
  final pool = [for (final e in book.entries) if (years.contains(e.year)) e];
  final byNumber = <int, List<HuntEntry>>{};
  for (final e in pool) {
    byNumber.putIfAbsent(e.number, () => []).add(e);
  }
  final names = [
    for (final e in pool) (entry: e, tokens: requiredTokens(e.name)),
  ];
  final seriesNames = [
    for (final e in pool) (entry: e, tokens: requiredTokens(e.series)),
  ];

  final signals = <_Signal>[];
  var cardsRead = 0;

  for (final line in lines) {
    for (final n in collectorNumbers(line.text)) {
      cardsRead++;
      final hits = byNumber[n];
      signals.add(hits != null
          ? _Signal(_Field.number, line.box, line.text, entries: hits, number: n)
          : _Signal(_Field.otherNumber, line.box, line.text, number: n));
    }
    if (hasChaseNumber(line.text)) {
      signals.add(_Signal(_Field.chase, line.box, line.text));
    }
  }

  // Names and phrases can wrap, so read each line alone and with the line
  // after it in the same block.
  for (final w in _windows(lines)) {
    final seen = tokenize(w.text);
    if (seen.isEmpty) continue;

    final phrase = treasurePhrase(seen);
    if (phrase.th) {
      signals.add(_Signal(phrase.sth ? _Field.superPhrase : _Field.phrase, w.box, w.text));
    }

    final named = [
      for (final n in names)
        if (hasDistinctiveToken(n.tokens) && allTokensSeen(n.tokens, seen)) n,
    ];
    // '73 Honda Civic Custom also contains Honda Civic Custom; keep the longer.
    final kept = [
      for (final a in named)
        if (!named.any((b) =>
            b.tokens.length > a.tokens.length && a.tokens.every((t) => b.tokens.contains(t))))
          a.entry,
    ];
    if (kept.isNotEmpty) signals.add(_Signal(_Field.name, w.box, w.text, entries: kept));

    final series = [
      for (final s in seriesNames)
        if (allTokensSeen(s.tokens, seen)) s.entry,
    ];
    if (series.isNotEmpty) signals.add(_Signal(_Field.series, w.box, w.text, entries: series));
  }

  final hits = <Hit>[];
  for (final group in _cluster(signals, _typicalLineHeight(lines))) {
    final hit = _hitFor(group);
    if (hit != null) hits.add(hit);
  }
  hits.sort((a, b) {
    final c = a.certainty.index.compareTo(b.certainty.index);
    return c != 0 ? c : a.kind.index.compareTo(b.kind.index);
  });
  return MatchResult(hits: hits, cardsRead: cardsRead, linesRead: lines.length);
}

Hit? _hitFor(List<_Signal> group) {
  Set<HuntEntry> of(_Field f) => {
        for (final s in group)
          if (s.field == f) ...s.entries,
      };

  final numbered = of(_Field.number);
  final named = of(_Field.name);
  final inSeries = of(_Field.series);
  final phrase = group.any((s) => s.field == _Field.phrase || s.field == _Field.superPhrase);
  final superPhrase = group.any((s) => s.field == _Field.superPhrase);
  final chase = group.any((s) => s.field == _Field.chase);
  final otherNumber = group.any((s) => s.field == _Field.otherNumber);

  // A card's series line only backs up its number or name, it never names a
  // car by itself: Rod Squad alone has ten cars a year.
  final backed = {
    for (final e in numbered)
      if (named.contains(e) || inSeries.contains(e)) e,
    for (final e in named)
      if (inSeries.contains(e)) e,
  };
  // Bone Shaker was a 2024 Treasure Hunt and comes out every year. A Bone
  // Shaker card whose number is not on any list is just a Bone Shaker.
  final nameOnly = otherNumber && numbered.isEmpty && !phrase ? <HuntEntry>{} : named;
  final candidates = backed.isNotEmpty ? backed.toList() : {...numbered, ...nameOnly}.toList();
  candidates.sort((a, b) {
    final k = a.kind.index.compareTo(b.kind.index);
    return k != 0 ? k : b.year.compareTo(a.year);
  });

  final evidence = <String>[];
  for (final s in group) {
    switch (s.field) {
      case _Field.number:
        evidence.add('Collector number ${s.number.toString().padLeft(3, '0')}/250');
      case _Field.otherNumber:
        break;
      case _Field.name:
        evidence.add('Car name "${s.text.trim()}"');
      case _Field.series:
        if (candidates.any(s.entries.contains)) evidence.add('Series "${s.text.trim()}"');
      case _Field.chase:
        evidence.add('Series number 0/N, the chase slot');
      case _Field.phrase:
      case _Field.superPhrase:
        evidence.add('Card back: treasure hunt symbol line');
    }
  }
  final box = group.map((s) => s.box).reduce((a, b) => a.expandToInclude(b));

  if (phrase) {
    return Hit(
      kind: superPhrase ? HuntKind.sth : HuntKind.th,
      certainty: Certainty.confirmed,
      box: box,
      candidates: candidates,
      evidence: evidence.toSet().toList(),
    );
  }
  if (candidates.isEmpty) {
    if (!chase) return null;
    return Hit(
      kind: HuntKind.chase,
      certainty: Certainty.likely,
      box: box,
      candidates: const [],
      evidence: evidence.toSet().toList(),
    );
  }
  return Hit(
    kind: candidates.first.kind,
    certainty: backed.isNotEmpty ? Certainty.likely : Certainty.possible,
    box: box,
    candidates: candidates,
    evidence: evidence.toSet().toList(),
  );
}

Iterable<({String text, Rect box})> _windows(List<OcrLine> lines) sync* {
  for (var i = 0; i < lines.length; i++) {
    yield (text: lines[i].text, box: lines[i].box);
    if (i + 1 < lines.length && lines[i + 1].block == lines[i].block) {
      yield (
        text: '${lines[i].text} ${lines[i + 1].text}',
        box: lines[i].box.expandToInclude(lines[i + 1].box),
      );
    }
  }
}

double _typicalLineHeight(List<OcrLine> lines) {
  if (lines.isEmpty) return 1;
  final hs = [for (final l in lines) math.min(l.box.width, l.box.height)]..sort();
  return math.max(1, hs[hs.length ~/ 2]);
}

double _gap(Rect a, Rect b) {
  final dx = math.max(0.0, math.max(a.left, b.left) - math.min(a.right, b.right));
  final dy = math.max(0.0, math.max(a.top, b.top) - math.min(a.bottom, b.bottom));
  return math.sqrt(dx * dx + dy * dy);
}

bool _isNumber(_Signal s) => s.field == _Field.number || s.field == _Field.otherNumber;

/// Groups signals that sit on the same card.
///
/// A card has one collector number, so each number anchors its own group and
/// every other signal joins the nearest number in reach. Chaining signals
/// together instead would let a dense wall melt into one giant card.
/// Signals with no number near them group among themselves.
List<List<_Signal>> _cluster(List<_Signal> signals, double lineHeight) {
  final reach = cardReach * lineHeight;
  final anchors = [for (final s in signals) if (_isNumber(s)) s];
  final groups = [for (final a in anchors) <_Signal>[a]];
  final loose = <_Signal>[];

  for (final s in signals) {
    if (_isNumber(s)) continue;
    int? best;
    var bestGap = reach;
    for (var i = 0; i < anchors.length; i++) {
      final g = _gap(s.box, anchors[i].box);
      if (g <= bestGap) {
        best = i;
        bestGap = g;
      }
    }
    if (best != null) {
      groups[best].add(s);
    } else {
      loose.add(s);
    }
  }

  final parent = List<int>.generate(loose.length, (i) => i);
  int find(int i) {
    while (parent[i] != i) {
      parent[i] = parent[parent[i]];
      i = parent[i];
    }
    return i;
  }

  for (var i = 0; i < loose.length; i++) {
    for (var j = i + 1; j < loose.length; j++) {
      if (_gap(loose[i].box, loose[j].box) <= reach) parent[find(i)] = find(j);
    }
  }
  final looseGroups = <int, List<_Signal>>{};
  for (var i = 0; i < loose.length; i++) {
    looseGroups.putIfAbsent(find(i), () => []).add(loose[i]);
  }
  return [...groups, ...looseGroups.values];
}
