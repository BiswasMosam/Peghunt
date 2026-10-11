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

## What the first photos showed (2026-10-12)

19 photos: a collection on a mat, shop walls, premium sets. Read on the
emulator with `tool/ocr_dump.dart`.

- They were small (about 1300 px, WhatsApp copies), so most small text was
  lost. Tiling now gets 2.5 times more words out of photos like these.
- The name strip at the bottom of the card is what reads best; collector
  numbers almost never did.
- Real Treasure Hunts in them: a 2026 Cone Shaker (two photos) and a 2026
  Ford Model A Custom '31. Both are now found, as likely.

## What helps next

1. **Originals, straight from the phone camera** (or shot with Peghunt
   itself). Full size, not sent through WhatsApp.
2. **Say which cards are hunts.** Put a photo in `th/` or `sth/` when it
   has one, so a miss can be told from a correct "nothing here".
3. **More shop walls** in `walls/`, the way they are really stacked.

## What the photos are for

1. **Tuning the card reader.** Every rule in `lib/scan/matcher.dart` that
   says "real cards" was measured on these photos.
2. **Training a detector (a few hundred photos).** Text can't tell a Super
   Treasure Hunt from its regular twin: same card, same number. A small
   on-device model can look for the gold or silver circle flame printed
   behind the car. Loose cars come later: Spectraflame paint and Real
   Riders tires.
