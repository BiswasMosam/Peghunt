# Training photos

Drop real photos here. They never leave this machine: everything under
`training/photos/` except the empty folders is git-ignored.

## Where to put them

| Folder | What goes in it |
|---|---|
| `photos/walls/` | Whole peg walls, dump bins, tables of cards. Shoot them the way you would in a store. This is what the app sees. |
| `photos/th/` | A card you know is a regular Treasure Hunt. Front, and the back if you can. |
| `photos/sth/` | A card you know is a Super Treasure Hunt. Front, back, and a close-up of the car (paint, tires). |
| `photos/chase/` | Premium chase cards (the 0/5 ones). |
| `photos/loose/` | Loose cars on a table, out of the card. |

Not sure where something goes? Put it straight into `photos/`. Any file name
is fine. JPG from the phone camera is best: keep the full resolution and
don't crop or compress it.

## What helps most

- **Lots of ordinary walls.** Most of what the app sees is normal cars. It
  needs to learn what *not* to ring as much as what to ring.
- **Every Treasure Hunt you find**, even ones you already own. A handful of
  real examples is worth hundreds of guesses.
- **Different light**: store tube lights, phone torch, daylight.
- **Different distances**: a whole wall, half a wall, three cards.
- Try to keep people out of the frame.

## What the photos are for

1. **Tuning the card reader (a few photos is enough).** Peghunt v0.1 reads
   the collector number (`176/250`) and the series line off each card and
   checks them against the year's lists. The rules for how far apart those
   two can sit on one card are a guess until they meet real cards
   (`cardReach` in `lib/scan/matcher.dart`).
2. **Training a detector (a few hundred photos).** The next step is a small
   on-device model that finds every card in the frame and the silver or gold
   circle flame printed behind a hunted car, so a ring can go round the whole
   card even when its number is too small to read. Loose cars come later:
   Spectraflame paint and Real Riders tires.
