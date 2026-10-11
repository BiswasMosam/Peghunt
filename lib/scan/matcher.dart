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

  /// Two things on the card agree on one car: its name, number or series.
  likely,

  /// One thing matched, and no ordinary car shares it. Worth a look.
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
  const MatchResult({required this.hits, required this.cardsRead, required this.linesRead, this.lines = const []});
  final List<Hit> hits;

  /// Everything OCR read, for showing what the scan saw.
  final List<OcrLine> lines;

  /// Cards whose name or number was read, hunted or not, so the app can say
  /// "read 14 cards, none rare" instead of a bare "nothing found".
  final int cardsRead;
  final int linesRead;
}

/// A car a card might be: a hunt car, or one of the ordinary mainline cars
/// that share its name, number or series. The ordinary cars are what make
/// a match mean something.
class _Car {
  _Car({this.year, this.number, required this.name, this.series, this.line, this.hunt});
  final int? year;
  final int? number;
  final String name;
  final String? series;

  /// A premium car's line, printed on its card too ("Car Culture").
  final String? line;
  final HuntEntry? hunt;

  bool get isChase => hunt?.isChase ?? false;

  /// A mainline Treasure Hunt or Super Treasure Hunt.
  bool get isMainlineHunt => hunt != null && !isChase;
}

/// Words printed on every card, listed as cars so that HOT WHEELS on the
/// logo is closer to itself than to Hot Wheengs.
const _cardFurniture = ['Hot Wheels', 'Mattel', 'Treasure Hunt', 'Real Riders'];

/// Words only premium cards carry. Premium sets reuse mainline castings
/// (a Summit Surge McLaren Speedtail is not the 2025 STH), so a name match
/// next to one of these means nothing on its own.
final _premiumWords = [
  for (final w in ['Real Riders', 'Metal Metal', 'Car Culture', 'Pop Culture', 'Boulevard', 'Silver Series', 'Premium'])
    skeleton(w),
];

List<_Car> _carsFor(HuntBook book, Set<int> years) {
  final hunts = {
    for (final e in book.entries)
      if (years.contains(e.year) && !e.isChase) (e.year, e.number): e,
  };
  final cars = <_Car>[];
  final placed = <HuntEntry>{};
  for (final c in book.castings) {
    if (!years.contains(c.year)) continue;
    final hunt = hunts[(c.year, c.number)];
    if (hunt != null) placed.add(hunt);
    cars.add(_Car(year: c.year, number: c.number, name: c.name, series: c.series, hunt: hunt));
  }
  // A hunt car missing from the full lists, or a year with no full list.
  for (final e in hunts.values) {
    if (!placed.contains(e)) {
      cars.add(_Car(year: e.year, number: e.number, name: e.name, series: e.series, hunt: e));
    }
  }
  for (final e in book.entries) {
    if (years.contains(e.year) && e.isChase) {
      cars.add(_Car(year: e.year, name: e.name, series: e.series, line: e.line, hunt: e));
    }
  }
  for (final f in _cardFurniture) {
    cars.add(_Car(name: f));
  }
  return cars;
}

enum _Field { number, otherNumber, name, series, chase, slot, phrase, superPhrase, premium }

class _Signal {
  _Signal(this.field, this.box, this.text, {this.cars = const [], this.number, this.slot});
  final _Field field;
  final Rect box;
  final String text;
  final List<_Car> cars;
  final int? number;

  /// A set number read off the card, "0/5".
  final String? slot;
}

/// How far, in heights of an anchor's own text, the rest of its card can
/// sit. Measured on real 2026 mainline cards: the series tab is about 8
/// name heights from the name strip, or 1 when printed beside it.
const cardReach = 10.0;

/// A name and a collector number this close are one card. Kept tight:
/// on a real card they sit at opposite ends, and a neighbour's number
/// must not overrule a name.
const sameCardReach = 3.0;

/// How far apart, in text heights, a card's number and its name strip can
/// be: the height of a whole card. Used only to join two hits that already
/// agree on the car.
const sameCardSpan = 30.0;

/// Turns OCR lines into hits, using the cars of [years] in [book].
MatchResult matchLines(List<OcrLine> lines, HuntBook book, Set<int> years) {
  final cars = _carsFor(book, years);
  final byNumber = <int, List<_Car>>{};
  for (final c in cars) {
    if (c.number != null) byNumber.putIfAbsent(c.number!, () => []).add(c);
  }
  final names_ = [
    for (final c in cars)
      for (final key in {...nameKeys(c.name), if (c.hunt != null) ...nameKeys(c.hunt!.name)})
        (car: c, key: key),
  ];
  // Series lines are shared by many cars, so each distinct one is matched once.
  final seriesKeys = <String, List<_Car>>{};
  for (final c in cars) {
    if (c.series != null) seriesKeys.putIfAbsent(skeleton(c.series!), () => []).add(c);
    if (c.line != null) seriesKeys.putIfAbsent(skeleton(c.line!), () => []).add(c);
  }

  final signals = <_Signal>[];

  for (final line in lines) {
    for (final n in collectorNumbers(line.text)) {
      final hits = byNumber[n];
      signals.add(hits != null
          ? _Signal(_Field.number, line.box, line.text, cars: hits, number: n)
          : _Signal(_Field.otherNumber, line.box, line.text, number: n));
    }
    for (final slot in setSlots(line.text)) {
      signals.add(_Signal(_Field.slot, line.box, line.text, slot: '${slot.top}/${slot.of}'));
      // Premium sets number their chase zero.
      if (slot.top == 0) signals.add(_Signal(_Field.chase, line.box, line.text));
    }
  }

  // Reads one stretch of text for a treasure hunt line, car names and
  // series names. Says which of the last two it found.
  ({bool named, bool series}) read(String raw, Rect box, {bool names = true, bool series = true}) {
    final seen = tokenize(raw);
    if (seen.isEmpty) return (named: false, series: false);

    final phrase = treasurePhrase(seen);
    if (phrase.th) {
      signals.add(_Signal(phrase.sth ? _Field.superPhrase : _Field.phrase, box, raw));
    }
    final text = skeleton(raw);

    if (_premiumWords.any((w) => fuzzyFind(w, text, errorBudget(w.length)) != null)) {
      signals.add(_Signal(_Field.premium, box, raw));
    }

    var foundSeries = false;
    // The longest series name the line reads as, and how well.
    var seriesLength = 0, seriesErrors = 0;
    if (series) {
      final inSeries = <_Car>[];
      for (final s in seriesKeys.entries) {
        final d = fuzzyFind(s.key, text, errorBudget(s.key.length));
        if (d == null) continue;
        inSeries.addAll(s.value);
        if (s.key.length > seriesLength) {
          seriesLength = s.key.length;
          seriesErrors = d;
        }
      }
      if (inSeries.isNotEmpty) {
        signals.add(_Signal(_Field.series, box, raw, cars: inSeries));
        foundSeries = true;
      }
    }

    var foundName = false;
    if (names) {
      // Only the closest names count: a Bone Shaker card is one letter from
      // Cone Shaker, but zero from Bone Shaker. And a series line is not a
      // car: HW TRACK CHAMPS is one letter from the HW-4-Trac.
      final named = <({_Car car, String key, int d})>[];
      for (final n in names_) {
        final d = fuzzyFind(n.key, text, errorBudget(n.key.length));
        if (d == null) continue;
        if (n.key.length <= seriesLength && d >= seriesErrors) continue;
        named.add((car: n.car, key: n.key, d: d));
      }
      if (named.isNotEmpty) {
        final closest = named.map((n) => n.d).reduce(math.min);
        final near = [for (final n in named) if (n.d == closest) n];
        // '73 Honda Civic Custom also contains Honda Civic Custom; keep the longer.
        final kept = {
          for (final a in near)
            if (!near.any((b) => b.key.length > a.key.length && b.key.contains(a.key))) a.car,
        };
        signals.add(_Signal(_Field.name, box, raw, cars: kept.toList()));
        foundName = true;
      }
    }

    return (named: foundName, series: foundSeries);
  }

  // Names and phrases can wrap onto the next line of the same block. Two
  // lines are only read together for what neither gave alone: the name
  // strips of stacked cards often land in one block, and gluing two of
  // them together would melt two cards into one.
  final alone = [for (final l in lines) read(l.text, l.box)];
  for (var i = 0; i + 1 < lines.length; i++) {
    final a = lines[i], b = lines[i + 1];
    if (a.block != b.block) continue;
    read(
      '${a.text} ${b.text}',
      a.box.expandToInclude(b.box),
      names: !alone[i].named && !alone[i + 1].named,
      series: !alone[i].series && !alone[i + 1].series,
    );
  }

  final found = <_Found>[];
  var namedCards = 0, numberedCards = 0;
  for (final group in _cluster(signals)) {
    final known = group.where((s) => _isAnchor(s) && (s.number != null || s.cars.any((c) => c.year != null)));
    final byName = known.any((s) => s.field == _Field.name);
    final byNumber = known.any((s) => s.field != _Field.name);
    if (byName) namedCards++;
    if (byNumber) numberedCards++;
    final f = _hitFor(group);
    if (f == null) continue;
    final anchors = group.where(_isAnchor);
    f
      ..byName = byName
      ..byNumber = byNumber
      ..unit = anchors.isEmpty ? _textHeight(f.hit.box) : anchors.map((s) => _textHeight(s.box)).reduce(math.min);
    found.add(f);
  }

  // A card's collector number sits at the top and its name strip at the
  // bottom: two anchors, one card. A part found by its number alone and one
  // found by its name alone that share a car and lie within a card of each
  // other are one card, and two independent clues: the number 122 is three
  // cars across three years, the name Cone Shaker two, but only one car is
  // both. Two name strips never merge, so stacked copies of one Treasure
  // Hunt each get a ring.
  final hits = <Hit>[];
  final used = <int>{};
  for (var i = 0; i < found.length; i++) {
    if (used.contains(i)) continue;
    final a = found[i];
    if (a.byNumber && !a.byName) {
      int? best;
      var bestGap = double.infinity;
      for (var j = 0; j < found.length; j++) {
        final b = found[j];
        if (j == i || used.contains(j) || !b.byName || b.byNumber) continue;
        if (!a.pool.any((c) => c.hunt != null && b.pool.contains(c))) continue;
        final g = _gap(a.hit.box, b.hit.box);
        if (g <= sameCardSpan * math.min(a.unit, b.unit) && g < bestGap) {
          best = j;
          bestGap = g;
        }
      }
      if (best != null) {
        used
          ..add(i)
          ..add(best);
        hits.add(_merge(a, found[best]));
        continue;
      }
    }
    used.add(i);
    if (a.shown) hits.add(a.hit);
  }
  hits.sort((a, b) {
    final c = a.certainty.index.compareTo(b.certainty.index);
    return c != 0 ? c : a.kind.index.compareTo(b.kind.index);
  });
  return MatchResult(
    hits: hits,
    cardsRead: math.max(namedCards, numberedCards),
    linesRead: lines.length,
    lines: lines,
  );
}

/// What one group of signals adds up to. [shown] is false for a card whose
/// clues fit a hunt car and an ordinary car equally well: not a hit by
/// itself, but the other half of its card may settle it.
class _Found {
  _Found(this.hit, this.pool, {required this.shown});
  final Hit hit;
  final Set<_Car> pool;
  final bool shown;
  bool byName = false, byNumber = false;
  double unit = 1;
}

List<HuntEntry> _ranked(Iterable<_Car> cars) => [
      for (final c in cars)
        if (c.hunt != null) c.hunt!,
    ]..sort((a, b) {
        final k = a.kind.index.compareTo(b.kind.index);
        return k != 0 ? k : b.year.compareTo(a.year);
      });

Hit _merge(_Found a, _Found b) {
  final both = a.pool.intersection(b.pool);
  final candidates = _ranked(both);
  final ordinary = both.any((c) => c.hunt == null && c.year != null);
  final better = a.hit.certainty.index <= b.hit.certainty.index ? a.hit.certainty : b.hit.certainty;
  return Hit(
    kind: candidates.first.kind,
    certainty: !ordinary && candidates.length == 1 && better != Certainty.confirmed ? Certainty.likely : better,
    box: a.hit.box.expandToInclude(b.hit.box),
    candidates: candidates,
    evidence: {...a.hit.evidence, ...b.hit.evidence}.toList(),
  );
}

_Found? _hitFor(List<_Signal> group) {
  // Mainline Treasure Hunts are matched among mainline cars; premium chases
  // apart, by their own rules, below.
  Set<_Car> of(_Field f) => {
        for (final s in group)
          if (s.field == f)
            for (final c in s.cars)
              if (!c.isChase) c,
      };

  final numbered = of(_Field.number);
  final named = of(_Field.name);
  final inSeries = of(_Field.series);
  final phrase = group.any((s) => s.field == _Field.phrase || s.field == _Field.superPhrase);
  final superPhrase = group.any((s) => s.field == _Field.superPhrase);
  final chase = group.any((s) => s.field == _Field.chase);
  final otherNumber = group.any((s) => s.field == _Field.otherNumber);
  final premium = group.any((s) => s.field == _Field.premium);
  final box = group.map((s) => s.box).reduce((a, b) => a.expandToInclude(b));

  final chaseHit = _chaseFor(group, box);
  if (chaseHit != null && !phrase) return chaseHit;

  // Two things on the card that point at the same car. A series line only
  // ever backs something up: Rod Squad alone is ten cars a year.
  final backed = {
    for (final c in numbered)
      if (named.contains(c) || inSeries.contains(c)) c,
    for (final c in named)
      if (inSeries.contains(c)) c,
  };
  // A number no list knows means the card is some other car.
  final nameOnly = otherNumber && numbered.isEmpty ? <_Car>{} : named;
  final pool = backed.isNotEmpty ? backed : {...numbered, ...nameOnly};
  final huntCars = [for (final c in pool) if (c.hunt != null) c];
  final ordinaryCars = [for (final c in pool) if (c.hunt == null && c.year != null) c];
  final ordinary = ordinaryCars.isNotEmpty;
  final candidates = _ranked(huntCars);

  final evidence = <String>[];
  for (final s in group) {
    switch (s.field) {
      case _Field.number:
        if (s.cars.any(huntCars.contains)) {
          evidence.add('Collector number ${s.number.toString().padLeft(3, '0')}/250');
        }
      case _Field.otherNumber:
      case _Field.slot:
      case _Field.premium:
        break;
      case _Field.name:
        if (s.cars.any(huntCars.contains)) evidence.add('Car name "${_withoutAgeMark(s.text)}"');
      case _Field.series:
        if (s.cars.any(huntCars.contains)) evidence.add('Series "${s.text.trim()}"');
      case _Field.chase:
        evidence.add('Set number 0, the chase slot');
      case _Field.phrase:
      case _Field.superPhrase:
        evidence.add('Card back: treasure hunt symbol line');
    }
  }

  if (phrase) {
    return _Found(
      Hit(
        kind: superPhrase ? HuntKind.sth : HuntKind.th,
        certainty: Certainty.confirmed,
        box: box,
        candidates: candidates,
        evidence: evidence.toSet().toList(),
      ),
      pool,
      shown: true,
    );
  }
  // Premium sets reuse mainline castings; their cards are not hunts.
  final premiumOnly = premium && backed.isEmpty;
  if (candidates.isEmpty || premiumOnly) {
    if (!chase) return null;
    return _Found(
      Hit(
        kind: HuntKind.chase,
        certainty: Certainty.likely,
        box: box,
        candidates: const [],
        evidence: const ['Set number 0, the chase slot'],
      ),
      const {},
      shown: true,
    );
  }
  // A hunt car and an ordinary car fit this part of the card equally well.
  // Read by name alone, the newer car wins, because that is what fills the
  // pegs: a Cone Shaker is more likely the 2026 Treasure Hunt than the
  // ordinary 2025 one, but a Bone Shaker is the ordinary 2026 car, not the
  // 2024 Treasure Hunt. A collector number is never settled this way: the
  // same number is a different car every year.
  var contested = ordinary && backed.isEmpty;
  if (contested && numbered.isEmpty) {
    final newestHunt = candidates.map((e) => e.year).reduce(math.max);
    final newestOrdinary = ordinaryCars.map((c) => c.year!).reduce(math.max);
    if (newestHunt > newestOrdinary) {
      contested = false;
      final older = ordinaryCars.firstWhere((c) => c.year == newestOrdinary);
      evidence.add('Also an ordinary $newestOrdinary car (${older.series}). '
          'The hunt says ${candidates.first.series} on the card.');
    }
  }
  return _Found(
    Hit(
      kind: candidates.first.kind,
      certainty: backed.isNotEmpty && !ordinary ? Certainty.likely : Certainty.possible,
      box: box,
      candidates: candidates,
      evidence: evidence.toSet().toList(),
    ),
    pool,
    shown: !contested,
  );
}

/// A premium chase, by its name and set number.
///
/// A Car Culture chase is a second copy of one of its own set's cars,
/// numbered 0/5 instead of, say, 2/5, so the set number decides: 0/5 makes
/// it likely, any other number makes it the regular car. With no number
/// read, the set or line name on the card makes it worth a look. A twin
/// chase (Fast & Furious 2026) shares the regular car's number too and only
/// differs in paint, so it is never more than worth a look.
_Found? _chaseFor(List<_Signal> group, Rect box) {
  final named = {
    for (final s in group)
      if (s.field == _Field.name)
        for (final c in s.cars)
          if (c.isChase) c,
  };
  if (named.isEmpty) return null;
  final inSet = {
    for (final s in group)
      if (s.field == _Field.series) ...s.cars,
  };
  final slots = {for (final s in group) if (s.field == _Field.slot) s.slot!};

  // A chase name no mainline car shares (the BMW M1 Procar) is worth a look
  // even when nothing else on its card was read; a Bugatti Bolide is also
  // an ordinary 2026 car, so it needs its 0/5.
  final sharedWithMainline = {
    for (final s in group)
      if (s.field == _Field.name && s.cars.any((c) => !c.isChase && c.year != null))
        for (final c in s.cars)
          if (c.isChase) c,
  };

  final likely = <_Car>[], possible = <_Car>[];
  for (final c in named) {
    final e = c.hunt!;
    final slotRead = e.slot != null && slots.contains(e.slot);
    if (e.slot != null && slots.isNotEmpty && !slotRead) continue;
    if (slotRead && !e.twin) {
      likely.add(c);
    } else if (slotRead || inSet.contains(c) || !sharedWithMainline.contains(c)) {
      possible.add(c);
    }
  }
  final chosen = likely.isNotEmpty ? likely : possible;
  if (chosen.isEmpty) return null;

  final evidence = <String>{};
  for (final s in group) {
    if (s.field == _Field.name && s.cars.any(chosen.contains)) {
      evidence.add('Car name "${_withoutAgeMark(s.text)}"');
    } else if (s.field == _Field.series && s.cars.any(chosen.contains)) {
      evidence.add('Set "${s.text.trim()}"');
    } else if (s.field == _Field.slot && chosen.any((c) => c.hunt!.slot == s.slot)) {
      evidence.add('Set number ${s.slot}');
    }
  }
  return _Found(
    Hit(
      kind: HuntKind.chase,
      certainty: likely.isNotEmpty ? Certainty.likely : Certainty.possible,
      box: box,
      candidates: _ranked(chosen),
      evidence: evidence.toList(),
    ),
    chosen.toSet(),
    shown: true,
  );
}

/// The name strip starts with the "3+" age mark; quoting it back is noise.
String _withoutAgeMark(String s) => s.replaceFirst(RegExp(r'^\s*3\s*[+4]\s*'), '').trim();

double _gap(Rect a, Rect b) {
  final dx = math.max(0.0, math.max(a.left, b.left) - math.min(a.right, b.right));
  final dy = math.max(0.0, math.max(a.top, b.top) - math.min(a.bottom, b.bottom));
  return math.sqrt(dx * dx + dy * dy);
}

bool _isAnchor(_Signal s) =>
    s.field == _Field.number || s.field == _Field.otherNumber || s.field == _Field.name;

/// Height of a line of text, whichever way it runs: series tabs are printed
/// up the side of the card.
double _textHeight(Rect r) => math.max(1, math.min(r.width, r.height));

/// Groups signals that sit on the same card.
///
/// A card has one collector number and one name strip, so each of those
/// anchors a group (one name read twice, alone and wrapped with the next
/// line, is one anchor). Every other signal joins the nearest anchor in
/// reach. Chaining signals together instead would let a dense wall melt
/// into one giant card. Signals with no anchor near them group among
/// themselves.
List<List<_Signal>> _cluster(List<_Signal> signals) {
  final anchors = <_Signal>[];
  final groups = <List<_Signal>>[];
  for (final s in signals) {
    if (!_isAnchor(s)) continue;
    final same = anchors.indexWhere((a) => a.field == s.field && a.box.overlaps(s.box));
    if (same >= 0) {
      groups[same].add(s);
    } else {
      anchors.add(s);
      groups.add([s]);
    }
  }

  // A name and a number right next to each other are the same card.
  final owner = List<int>.generate(anchors.length, (i) => i);
  bool isName(int i) => anchors[i].field == _Field.name;
  for (var i = 0; i < anchors.length; i++) {
    if (!isName(i)) continue;
    int? best;
    var bestGap = double.infinity;
    for (var j = 0; j < anchors.length; j++) {
      if (isName(j) || groups[j].isEmpty || groups[j].any((s) => s.field == _Field.name)) continue;
      final reach = sameCardReach * math.min(_textHeight(anchors[i].box), _textHeight(anchors[j].box));
      final g = _gap(anchors[i].box, anchors[j].box);
      if (g <= reach && g < bestGap) {
        best = j;
        bestGap = g;
      }
    }
    if (best != null) {
      groups[best].addAll(groups[i]);
      groups[i] = [];
      owner[i] = best;
    }
  }

  final loose = <_Signal>[];
  for (final s in signals) {
    if (_isAnchor(s)) continue;
    int? best;
    var bestGap = double.infinity;
    for (var i = 0; i < anchors.length; i++) {
      final g = _gap(s.box, anchors[i].box);
      if (g <= cardReach * _textHeight(anchors[i].box) && g < bestGap) {
        best = i;
        bestGap = g;
      }
    }
    if (best != null) {
      groups[owner[best]].add(s);
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
      final reach = cardReach * math.min(_textHeight(loose[i].box), _textHeight(loose[j].box));
      if (_gap(loose[i].box, loose[j].box) <= reach) parent[find(i)] = find(j);
    }
  }
  final looseGroups = <int, List<_Signal>>{};
  for (var i = 0; i < loose.length; i++) {
    looseGroups.putIfAbsent(find(i), () => []).add(loose[i]);
  }
  return [for (final g in groups) if (g.isNotEmpty) g, ...looseGroups.values];
}
