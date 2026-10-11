import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:peghunt/data/hunt_book.dart';
import 'package:peghunt/scan/matcher.dart';
import 'package:peghunt/scan/text_match.dart';

final book = HuntBook.fromJsonString(
  File('assets/hunts.json').readAsStringSync(),
  castings: File('assets/castings.json').readAsStringSync(),
);
const all = {2024, 2025, 2026};

/// A line of text at (x, y), 40 px tall, roughly 20 px a character.
OcrLine line(String text, double x, double y, {int block = 0}) =>
    OcrLine(text, Rect.fromLTWH(x, y, text.length * 20.0, 40), block: block);

void main() {
  group('text helpers', () {
    test('collector numbers survive OCR lookalikes', () {
      expect(collectorNumbers('176/250'), [176]);
      expect(collectorNumbers('#176 / 250'), [176]);
      expect(collectorNumbers('1O7/2S0'), [107]);
      expect(collectorNumbers('HW J-IMPORTS 7/10'), isEmpty);
      expect(collectorNumbers('251/250'), isEmpty);
      expect(collectorNumbers('1176/250'), isEmpty);
    });

    test('chase number is the zero slot of a set', () {
      expect(hasChaseNumber('CAR CULTURE 0/5'), isTrue);
      expect(hasChaseNumber('O/5'), isTrue);
      expect(hasChaseNumber('3/5'), isFalse);
      expect(hasChaseNumber('10/10'), isFalse);
      expect(hasChaseNumber('120/250'), isFalse);
    });

    test('names compare like a person reads them', () {
      expect(normalize("'64 Impala"), '64 IMPALA');
      expect(normalize('Lamborghini Huracán'), 'LAMBORGHINI HURACAN');
      expect(allTokensSeen(requiredTokens('Nissan Maxima Drift Car'), tokenize('NISSAN MAXIMA DRIFT CAR')), isTrue);
      expect(allTokensSeen(requiredTokens('Nissan Maxima Drift Car'), tokenize('NISSAN MAXlMA DRIFT CAR')), isTrue);
      expect(allTokensSeen(requiredTokens("'64 Impala"), tokenize("'59 CHEVY IMPALA")), isFalse);
      expect(hasDistinctiveToken(requiredTokens('2 Jet Z')), isFalse);
      expect(hasDistinctiveToken(requiredTokens('Custom Otto')), isTrue);
    });

    test('treasure hunt line on the card back', () {
      final t = treasurePhrase(tokenize('just found a collectible treasure-hunt vehicle!'));
      expect(t.th, isTrue);
      expect(t.sth, isFalse);
      expect(treasurePhrase(tokenize('HW TREASURE ISLAND')).th, isFalse);
    });
  });

  group('matchLines', () {
    test('a regular Treasure Hunt by its number', () {
      final r = matchLines([line('009/250', 100, 100)], book, {2026});
      expect(r.hits, hasLength(1));
      expect(r.hits.single.kind, HuntKind.th);
      expect(r.hits.single.certainty, Certainty.possible);
      expect(r.hits.single.candidates.single.name, "'87 Buick Regal GNX");
    });

    test('number plus series on the same card is likely', () {
      final r = matchLines([
        line('176/250', 100, 100),
        line('HW J-IMPORTS 7/10', 100, 150),
      ], book, all);
      expect(r.hits, hasLength(1));
      final h = r.hits.single;
      expect(h.kind, HuntKind.sth);
      expect(h.certainty, Certainty.likely);
      expect(h.candidates.single.name, 'Subaru Impreza');
    });

    test('the series picks the year when a number repeats across years', () {
      // 249 is a 2026 STH, a 2025 TH and a 2024 STH.
      final alone = matchLines([line('249/250', 0, 0)], book, all);
      expect(alone.hits.single.candidates, hasLength(3));
      expect(alone.hits.single.certainty, Certainty.possible);

      final withSeries = matchLines([line('249/250', 0, 0), line('COOL CLASSICS', 0, 50)], book, all);
      expect(withSeries.hits.single.candidates.single.year, 2026);
      expect(withSeries.hits.single.certainty, Certainty.likely);
    });

    test('the years setting narrows the book', () {
      final r = matchLines([line('249/250', 0, 0)], book, {2025});
      expect(r.hits.single.kind, HuntKind.th);
      expect(r.hits.single.candidates.single.name, 'Triumph TR6');
    });

    test('ordinary cards are read but not ringed', () {
      final r = matchLines([
        line('123/250', 0, 0),
        line('HW DIRT 3/10', 0, 50),
        line('200/250', 2000, 0),
      ], book, {2026});
      expect(r.hits, isEmpty);
      expect(r.cardsRead, 2);
    });

    test('two cards side by side stay two hits', () {
      final r = matchLines([
        line('009/250', 0, 0),
        line('NIGHTSPEED 1/10', 0, 50),
        line('013/250', 600, 0),
        line("TRUCKIN' ALONG 1/10", 600, 50),
      ], book, {2026});
      expect(r.hits, hasLength(2));
      expect(r.hits.map((h) => h.kind).toSet(), {HuntKind.th, HuntKind.sth});
      expect(r.hits.every((h) => h.certainty == Certainty.likely), isTrue);
      // STH sorts first at the same certainty.
      expect(r.hits.first.kind, HuntKind.sth);
    });

    test('a common casting with a number off the list is not a hit', () {
      // Bone Shaker was the 2024 K case TH, but it is released every year.
      final r = matchLines([line('BONE SHAKER', 0, 0), line('087/250', 0, 50)], book, all);
      expect(r.hits, isEmpty);
    });

    test('a name with no number near it is a possible hit', () {
      final r = matchLines([line('NISSAN MAXIMA', 0, 0, block: 3), line('DRIFT CAR', 0, 45, block: 3)], book, all);
      expect(r.hits, hasLength(1));
      expect(r.hits.single.kind, HuntKind.sth);
      expect(r.hits.single.certainty, Certainty.possible);
    });

    test('the longer name wins, and the series picks the year', () {
      // '73 Honda Civic Custom is the 2025 M case STH and an ordinary 2024
      // Compact Kings car. Its name also contains the 2026 STH Honda Civic Custom.
      // Alone, the newer car wins: worth a look as the 2025 STH.
      final alone = matchLines([line("'73 HONDA CIVIC CUSTOM", 0, 0)], book, all);
      expect(alone.hits.single.certainty, Certainty.possible);
      expect(alone.hits.single.candidates.single.year, 2025);

      final older = matchLines([line("'73 HONDA CIVIC CUSTOM", 0, 0), line('COMPACT KINGS', 0, 50)], book, all);
      expect(older.hits, isEmpty);

      final r = matchLines([line("'73 HONDA CIVIC CUSTOM", 0, 0), line('THEN AND NOW', 0, 50)], book, all);
      expect(r.hits.single.candidates.single.toString(), "2025 STH #231 '73 Honda Civic Custom");
      expect(r.hits.single.certainty, Certainty.likely);
    });

    test('a number shared with ordinary cars of other years is not a hit', () {
      // 182 is the 2025 STH '62 Corvette Gasser, but also Chop 'n Bloc in
      // 2026 and a Chrysler Pacifica in 2024. Read off a real shop photo.
      expect(matchLines([line('I82/250', 0, 0)], book, all).hits, isEmpty);
      expect(matchLines([line('182/250', 0, 0)], book, {2025}).hits.single.kind, HuntKind.sth);
    });
  });

  group('chase', () {
    test('the BMW M1 Procar on his mat is the 2025 Hot Ones chase', () {
      // As ML Kit read it off the photo: name, and 8/8 under the series tab.
      final r = matchLines([
        line('BMW M1 PROGAR', 369, 682),
        line('8/8', 699, 778),
      ], book, all);
      expect(r.hits.single.kind, HuntKind.chase);
      expect(r.hits.single.certainty, Certainty.likely);
      expect(r.hits.single.candidates.single.toString(), '2025 CHASE 8/8 BMW M1 Procar');
    });

    test('a chase name no mainline car shares is worth a look on its own', () {
      // Off the same photo: the name runs up the card's side and its 8/8 sits
      // at the far edge, out of reach.
      final r = matchLines([
        const OcrLine('BMW M1 PROGAR', Rect.fromLTRB(369, 682, 378, 761)),
        const OcrLine('8/8', Rect.fromLTRB(699, 778, 710, 800)),
      ], book, all);
      expect(r.hits.single.kind, HuntKind.chase);
      expect(r.hits.single.certainty, Certainty.possible);
    });

    test('a Car Culture chase is decided by its set number', () {
      // The Hammer Drop Stratos Zero is both 2/5 and the 0/5 chase.
      List<Hit> card(String slot) => matchLines([
            line('LANCIA STRATOS ZERO', 0, 0),
            line('HAMMER DROP', 0, 50),
            line(slot, 400, 50),
          ], book, all).hits;
      expect(card('2/5'), isEmpty);
      expect(card('0/5').single.certainty, Certainty.likely);
      expect(card('0/5').single.candidates.single.name, 'Lancia Stratos Zero');

      // No number read: worth a look, no more.
      final unread = matchLines([line('LANCIA STRATOS ZERO', 0, 0), line('CAR CULTURE', 0, 50)], book, all);
      expect(unread.hits.single.kind, HuntKind.chase);
      expect(unread.hits.single.certainty, Certainty.possible);
    });

    test('a twin chase is only ever worth a look', () {
      final r = matchLines([line("'95 MITSUBISHI ECLIPSE", 0, 0), line('FAST & FURIOUS', 0, 50), line('1/5', 400, 50)],
          book, all);
      expect(r.hits.single.kind, HuntKind.chase);
      expect(r.hits.single.certainty, Certainty.possible);
    });

    test('a mainline card of a chase casting is not a chase', () {
      // Bugatti Bolide: the 2025 Eurospeed chase, and an ordinary 2026 HW Starting Grid car.
      expect(matchLines([line('BUGATTI BOLIDE', 0, 0), line('HW STARTING GRID', 0, 50)], book, all).hits, isEmpty);
      expect(matchLines([line('BUGATTI BOLIDE', 0, 0)], book, all).hits, isEmpty);
    });
  });

  // Lines as ML Kit really read them off Mosam's photos, 2026-10-12.
  group('real cards', () {
    test('Cone Shaker on its HW Starting Grid card is the 2026 TH', () {
      final r = matchLines([
        line('CONE SHAXER', 105, 112),
        line('EW STARTING GRID', 22, 150),
        line('8/10', 12, 253),
      ], book, all);
      expect(r.hits.single.candidates.single.toString(), '2026 TH #122 Cone Shaker');
      expect(r.hits.single.certainty, Certainty.likely);
    });

    test('the ordinary 2025 Cone Shaker is not', () {
      final r = matchLines([line('CONE SHAKER', 0, 0), line('HW METRO', 0, 50)], book, all);
      expect(r.hits, isEmpty);
    });

    test('a bilingual name with the French in the middle', () {
      final r = matchLines([
        line('FORD MOOL A CUSTOVPERSONNALISE SI 3', 1004, 484),
        line('ROD SQUAD', 970, 511),
      ], book, all);
      expect(r.hits.single.candidates.single.toString(), "2026 TH #229 Ford Model A Custom '31");
      expect(r.hits.single.certainty, Certainty.likely);
    });

    test('Bone Shaker: ordinary in 2026, the TH on its 2024 card', () {
      expect(matchLines([line('BONE SHAKER', 0, 0)], book, all).hits, isEmpty);
      expect(matchLines([line('BONE SHAKER', 0, 0), line('HW FAN DRIVEN', 0, 50)], book, all).hits, isEmpty);
      final th = matchLines([line('BONE SHAKER', 0, 0), line('HW TRACK CHAMPS', 0, 50)], book, all);
      expect(th.hits.single.candidates.single.toString(), '2024 TH #183 Bone Shaker');
    });

    test('near misses stay apart', () {
      // Speed Driver is an ordinary 2025 car, Sweet Driver the 2026 K case TH.
      expect(matchLines([line('SPEED DRIVER', 0, 0)], book, all).hits, isEmpty);
      // The logo on every card is not Hot Wheengs, the 2026 D case TH.
      expect(matchLines([line('HOT WHEELS', 0, 0)], book, all).hits, isEmpty);
      // Nor is the 2024 '98 Subaru Impreza 22B the 2026 STH Subaru Impreza.
      expect(matchLines([line("'98 SUBARU IMPREZA 22B STI-VERSION", 0, 0)], book, all).hits, isEmpty);
    });

    test('a premium card sharing a name with an STH is not one', () {
      // The Summit Surge McLaren Speedtail, next to its SILVER SERIES logo.
      final r = matchLines([
        line('MeLAREN SPEEDTAIL', 443, 480),
        line('SILVER SERIES', 531, 540),
      ], book, all);
      expect(r.hits, isEmpty);
      // The same name with no premium words near it is worth a look.
      expect(matchLines([line('MeLAREN SPEEDTAIL', 443, 480)], book, all).hits.single.kind, HuntKind.sth);
    });

    test('a card read by its number and by its name is one hit', () {
      // Fast Fish off the test wall, as ML Kit placed it: number at the top,
      // series up the side, name strip at the bottom.
      final r = matchLines([
        const OcrLine('238/250', Rect.fromLTRB(1712, 3246, 1831, 3271), block: 1),
        const OcrLine('TEAM WHEELS', Rect.fromLTRB(1841, 3483, 1894, 3813), block: 2),
        const OcrLine('FAST FISH', Rect.fromLTRB(1214, 3864, 1465, 3902), block: 3),
      ], book, all);
      expect(r.hits, hasLength(1));
      expect(r.hits.single.certainty, Certainty.likely);
      expect(r.hits.single.box, const Rect.fromLTRB(1214, 3246, 1894, 3902));
      expect(r.cardsRead, 1);
    });

    test('two halves that are ambiguous alone settle each other', () {
      // 122 is Cone Shaker in 2026 but other cars in 2025 and 2024; the name
      // Cone Shaker is also an ordinary 2025 car. Only one car is both.
      final number = matchLines([const OcrLine('122/250', Rect.fromLTRB(2714, 246, 2831, 271))], book, all);
      final name = matchLines([const OcrLine('CONE SHAKER', Rect.fromLTRB(2121, 864, 2577, 902))], book, all);
      // The number alone is never enough; the name alone is worth a look,
      // because the hunt is the newer of the two Cone Shakers.
      expect(number.hits, isEmpty);
      expect(name.hits.single.certainty, Certainty.possible);

      final r = matchLines([
        const OcrLine('122/250', Rect.fromLTRB(2714, 246, 2831, 271), block: 1),
        const OcrLine('CONE SHAKER', Rect.fromLTRB(2121, 864, 2577, 902), block: 2),
      ], book, all);
      expect(r.hits.single.candidates.single.toString(), '2026 TH #122 Cone Shaker');
      expect(r.hits.single.certainty, Certainty.likely);
    });

    test('stacked copies of one Treasure Hunt keep a ring each', () {
      final r = matchLines([
        for (var i = 0; i < 3; i++) OcrLine('FAST FISH', Rect.fromLTWH(0, i * 300.0, 250, 38), block: i),
      ], book, all);
      expect(r.hits, hasLength(3));
    });

    test('a stacked shop wall rings only the STH casting', () {
      final r = matchLines([
        for (var i = 0; i < 4; i++) line('FORD ESCORT', 0, i * 200.0),
        for (var i = 0; i < 4; i++) line('BMW M3 WAGON / REMORQUE', 600, i * 200.0),
        for (var i = 0; i < 4; i++) line('RODGER DODGER 2.0', 1200, i * 200.0),
      ], book, all);
      // BMW M3 Wagon is the 2025 P case STH; its only ordinary twin is
      // older (2024 HW Modified), so each copy is worth a look. The rest
      // are ordinary cars and stay dark.
      expect(r.hits, hasLength(4));
      expect(r.hits.every((h) => h.kind == HuntKind.sth && h.certainty == Certainty.possible), isTrue);
      expect(r.hits.every((h) => h.candidates.single.name == 'BMW M3 Wagon'), isTrue);
      expect(r.cardsRead, 12);
    });

    test('card back with the treasure hunt line is confirmed', () {
      final r = matchLines([
        line('Congratulations! This symbol means you', 0, 0, block: 1),
        line('just found a collectible treasure-hunt vehicle!', 0, 45, block: 1),
        line('TOONED VOLKSWAGEN GOLF MK1', 0, 140, block: 2),
      ], book, all);
      expect(r.hits, hasLength(1));
      expect(r.hits.single.kind, HuntKind.th);
      expect(r.hits.single.certainty, Certainty.confirmed);
    });

    test('a 0/5 premium card is a chase', () {
      final r = matchLines([line('CAR CULTURE', 0, 0), line('0/5', 0, 50)], book, all);
      expect(r.hits.single.kind, HuntKind.chase);
      expect(r.hits.single.certainty, Certainty.likely);
    });

    test('the ring covers every line that matched', () {
      final r = matchLines([line('176/250', 100, 100), line('HW J-IMPORTS 7/10', 100, 150)], book, all);
      final b = r.hits.single.box;
      expect(b.top, 100);
      expect(b.bottom, 190);
    });
  });

  group('hunt book', () {
    test('every year has 15 TH and 15 STH, numbers unique per kind', () {
      for (final y in book.years) {
        final cars = book.forYear(y);
        for (final k in [HuntKind.th, HuntKind.sth]) {
          final ofKind = cars.where((e) => e.kind == k).toList();
          expect(ofKind, hasLength(15), reason: '$y ${k.short}');
          expect(ofKind.map((e) => e.number).toSet(), hasLength(15), reason: '$y ${k.short} numbers');
          expect(ofKind.map((e) => e.caseLetter).toSet(), hasLength(15), reason: '$y ${k.short} cases');
        }
        expect(cars.where((e) => !e.isChase).every((e) => e.number! >= 1 && e.number! <= 250), isTrue);
        // A chase is found by its set number, or (a twin) by its paint.
        for (final c in cars.where((e) => e.isChase)) {
          expect(c.line, isNotNull, reason: '$c');
          expect(c.slot != null || c.twin, isTrue, reason: '$c');
        }
      }
    });

    test('ids are unique and resolve', () {
      final ids = book.entries.map((e) => e.id).toSet();
      expect(ids, hasLength(book.entries.length));
      expect(book.byId('2026-sth-176')!.name, 'Subaru Impreza');
    });
  });
}
