import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:peghunt/data/hunt_book.dart';
import 'package:peghunt/scan/matcher.dart';
import 'package:peghunt/scan/text_match.dart';

final book = HuntBook.fromJsonString(File('assets/hunts.json').readAsStringSync());
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

    test('the longer name wins', () {
      final r = matchLines([line("'73 HONDA CIVIC CUSTOM", 0, 0)], book, all);
      expect(r.hits.single.candidates.single.year, 2025);
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
        expect(cars.every((e) => e.number >= 1 && e.number <= 250), isTrue);
      }
    });

    test('ids are unique and resolve', () {
      final ids = book.entries.map((e) => e.id).toSet();
      expect(ids, hasLength(book.entries.length));
      expect(book.byId('2026-sth-176')!.name, 'Subaru Impreza');
    });
  });
}
