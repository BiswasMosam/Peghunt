<p align="center"><img src="docs/icon.png" width="120" alt="Peghunt mark: a wall of cards, one ringed in gold"></p>

<h1 align="center">Peghunt</h1>

<p align="center"><b>One ring on a wall of pegs.</b><br>
Point your phone at a wall of Hot Wheels cards. Peghunt rings the Treasure Hunts, Super Treasure Hunts and Chase cars in it.</p>

<p align="center"><img src="docs/screens.png" alt="Result screen with rings on a test wall, the detail sheet for a Super Treasure Hunt, and the hunt book"></p>

---

## Why

A store wall holds a hundred cars, and the ones worth hunting look almost
the same as the rest. A Super Treasure Hunt shares its card and its number
with the regular car next to it. What gives it away is a small gold flame
printed behind the car, Spectraflame paint and rubber tires. That's hard to
remember and harder to spot when you're standing in an aisle.

Brickit does this for a pile of LEGO: take one photo and it shows you where
each piece is. Peghunt does the same for a wall of diecast.

## What it does

- **Hunt.** A full-screen camera. Take one photo of the wall.
- **Rings.** The photo dims, and a ring draws itself around every card worth
  a look: **gold** for a Super Treasure Hunt, **silver** for a Treasure Hunt,
  **red** for a Chase. Solid rings are likely hits. Dashed rings are possible
  hits, where only one thing on the card matched.
- **Find it.** Every hit is also listed under the photo. Tap a row and the
  photo flies to that card. Tap it again to see what to check before you buy
  (gold flame, Spectraflame paint, Real Riders tires, TH logo).
- **Hunt book.** The 2024, 2025 and 2026 Treasure Hunt and Super Treasure
  Hunt lists, by case letter. Tick off the ones you've found, and choose which
  years a scan checks against.
- **Works offline.** Everything runs on the phone: no account, no network,
  no photos uploaded anywhere.

## How it works

```
photo ──► ML Kit text recognition (on device)
            │  lines of text + where they sit in the photo
            ▼
          matcher (lib/scan/matcher.dart)
            │  "176/250"            collector number ──┐
            │  "HW J-IMPORTS 7/10"  series line ───────┤ grouped per card
            │  "SUBARU IMPREZA"     car name ──────────┘
            │  "0/5"                chase slot
            │  "...treasure-hunt vehicle!"  card back
            ▼
          hunt book (assets/hunts.json)
            │  2026 STH, case J, #176, Subaru Impreza, HW J-Imports
            ▼
          rings, with how sure each one is
```

Each card has one collector number, so each number anchors a group, and the
series line or car name nearest to it joins that group. Then:

| Certainty | When | Ring |
|---|---|---|
| **Confirmed** | The card says so: the Treasure Hunt line printed on the back | solid |
| **Likely** | Two things agree: the number *and* the series or name match the same car | solid |
| **Possible** | One thing matched: a number shared across years, or a name with no number in reach | dashed |

The matcher also deals with what OCR gets wrong: `1O7/2S0` reads as 107,
`MAXlMA` still matches Maxima, and `'64` and `64` count as the same car. A
car that comes out every year (Bone Shaker was a 2024 Treasure Hunt) isn't
ringed when its card shows a number that isn't on any list.

Chase cars need no list at all. Premium sets number their chase car zero,
so a `0/5` on the card is enough.

## The hunt book

`assets/hunts.json` has all 90 cars: 15 Treasure Hunts and 15 Super Treasure
Hunts for each of 2024, 2025 and 2026, with case letter, collector number,
series and colour. They were compiled from collector checklists (Muncle
Mike's, Orange Track Diecast, Hot Wheels Hub, 164 Custom) and cross-checked
where the sources overlapped. Where the sources disagree, the car carries a
note. Adding a year means adding one block to that file. The tests check
that every year has 15 of each, with unique numbers and case letters.

## Build

Flutter 3.38 (Dart 3.10), Android only.

```bash
flutter pub get
flutter test                                    # 23 tests: matcher, hunt book, screens
flutter build apk --release --split-per-abi     # build/app/outputs/flutter-apk/
```

Release builds are signed with `android/key.properties` if it exists. If it
doesn't, they fall back to the debug key, so a fresh clone still builds.

**Testing without a store.** `tool/make_test_wall.py` draws a 12 MP fake
peg wall with known hunt numbers on it, plus a copy saved sideways with an
EXIF rotation tag the way a phone saves portrait photos. Push them to an
emulator and scan them from the gallery button. The screenshots above are
that wall. `tool/make_icons.py` redraws every launcher icon from the same
geometry as the in-app mark.

## Project layout

```
lib/
  data/hunt_book.dart     the lists, as Dart
  data/app_state.dart     found cars and scan years, saved on the phone
  scan/text_match.dart    OCR-tolerant reading: numbers, names, 0/5, card-back line
  scan/matcher.dart       lines of text → hits
  scan/scanner.dart       ML Kit on the phone, a fake in tests
  ui/                     hunt (camera), result (rings + list), hit sheet, book
assets/hunts.json         2024–2026 Treasure Hunts and Super Treasure Hunts
training/                 where real photos go for the next step (git-ignored)
tool/                     test wall and icon generators
```

## Next

v0.1 reads text. The next step is a small on-device detector trained on
real photos (`training/`):

1. **Tune the card reader on real cards.** How far apart the number and the
   series line sit on a real card, and which OCR misreads actually happen.
2. **Find every card** in the frame, so a ring goes round the whole card.
3. **See the flame.** Detect the silver or gold circle flame behind the car,
   which tells a Super Treasure Hunt apart from its regular twin.
4. **Loose cars.** Spectraflame paint and Real Riders tires, for tables of
   cars out of the card.

## Disclaimer

Peghunt is a fan project. It is not made by, endorsed by or affiliated with
Mattel. Hot Wheels, Treasure Hunt and Super Treasure Hunt are trademarks of
Mattel, Inc. The lists are community-sourced, so check the car itself
before you pay.

## License

MIT. See [LICENSE](LICENSE).
