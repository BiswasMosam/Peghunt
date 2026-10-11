"""Draws a fake peg wall for testing the scan path end to end.

Twelve cards in a 3000x4000 image (a 12 MP phone photo), laid out like a
2026 mainline card: the car's name in a strip along the bottom, the series
printed up the side tab with its set number, the collector number small at
the top. Real names, so the app has to tell them apart:

    SUBARU IMPREZA        HW J-IMPORTS 7/10       2026 STH (case J)
    CONE SHAKER           HW STARTING GRID 8/10   2026 TH (case E)
    '87 BUICK REGAL GNX   NIGHTSPEED 1/10         2026 TH (case A)
    CUSTOM OTTO           MATTEL 5/10             2026 STH (case G)
    FAST FISH             TEAM WHEELS 5/10        2026 TH (case N)
    CAR CULTURE  0/5                              a premium chase
    BONE SHAKER           HW FAN DRIVEN 4/10      ordinary in 2026 (it was the 2024 TH)

and five ordinary cars. Two files are written:

    wall.jpg          upright pixels
    wall_exif6.jpg    the same wall stored sideways with EXIF orientation 6,
                      the way a phone held upright writes its photos

Usage: python tool/make_test_wall.py OUT_DIR
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

W, H = 3000, 4000
COLS, ROWS = 3, 4
FONT = "C:/Windows/Fonts/arialbd.ttf"

# (name, series, set number, collector number)
CARDS = [
    ("SUBARU IMPREZA", "HW J-IMPORTS", "7/10", "176/250"),
    ("MAZDA RX-7", "HW J-IMPORTS", "2/10", "061/250"),
    ("CONE SHAKER", "HW STARTING GRID", "8/10", "122/250"),
    ("BONE SHAKER", "HW FAN DRIVEN", "4/10", "139/250"),
    ("'87 BUICK REGAL GNX", "NIGHTSPEED", "1/10", "009/250"),
    ("'20 TOYOTA GR SUPRA", "THEN AND NOW", "2/10", "157/250"),
    ("NISSAN SKYLINE GT-R", "CAR CULTURE", "0/5", None),
    ("CUSTOM OTTO", "MATTEL", "5/10", "156/250"),
    ("LOTUS CORTINA", "HW EURO", "3/10", "067/250"),
    ("DATSUN 240Z", "THEN AND NOW", "5/10", "072/250"),
    ("FAST FISH", "TEAM WHEELS", "5/10", "238/250"),
    ("MAD DRIP", "SWEET RIDES", "6/10", "197/250"),
]


def draw_wall() -> Image.Image:
    img = Image.new("RGB", (W, H), (205, 200, 192))
    d = ImageDraw.Draw(img)
    name_f = ImageFont.truetype(FONT, 50)
    tab_f = ImageFont.truetype(FONT, 46)
    small = ImageFont.truetype(FONT, 34)
    logo = ImageFont.truetype(FONT, 110)
    cw, ch = W / COLS, H / ROWS
    for i, (name, series, setno, number) in enumerate(CARDS):
        c, r = i % COLS, i // COLS
        x0, y0 = c * cw + 60, r * ch + 50
        x1, y1 = (c + 1) * cw - 60, (r + 1) * ch - 50
        d.rounded_rectangle((x0, y0, x1, y1), radius=30, fill=(28, 72, 160))
        d.rectangle((x0 + 30, y0 + 30, x1 - 130, y0 + 170), fill=(232, 90, 30))
        d.text((x0 + 60, y0 + 40), "PEG CARS", font=logo, fill=(255, 245, 230))
        if number:
            d.text((x1 - 230, y0 + 190), number, font=small, fill=(255, 255, 255))
        # The blister with a car-shaped blob.
        d.rounded_rectangle((x0 + 40, y0 + 470, x1 - 130, y1 - 110), radius=20, fill=(238, 238, 236))
        d.rounded_rectangle((x0 + 110, y0 + 560, x1 - 220, y0 + 700), radius=50, fill=(180, 30, 40))
        d.ellipse((x0 + 150, y0 + 680, x0 + 240, y0 + 770), fill=(20, 20, 20))
        d.ellipse((x1 - 330, y0 + 680, x1 - 240, y0 + 770), fill=(20, 20, 20))
        # Name strip along the bottom, like the real cards.
        d.rectangle((x0 + 40, y1 - 100, x1 - 130, y1 - 30), fill=(250, 250, 250))
        d.text((x0 + 60, y1 - 92), "3+", font=small, fill=(40, 40, 40))
        d.text((x0 + 150, y1 - 95), name, font=name_f, fill=(25, 45, 120))
        # Series tab up the right side, set number under it.
        tab = Image.new("RGB", (560, 90), (240, 210, 40))
        ImageDraw.Draw(tab).text((14, 18), series, font=tab_f, fill=(20, 20, 20))
        tab = tab.rotate(90, expand=True)
        img.paste(tab, (int(x1 - 110), int(y1 - 30 - tab.height - 70)))
        d.text((x1 - 110, y1 - 90), setno, font=small, fill=(255, 255, 255))
    return img


def main(out: Path) -> None:
    out.mkdir(parents=True, exist_ok=True)
    wall = draw_wall()
    wall.save(out / "wall.jpg", quality=92)
    # Orientation 6 means "rotate 90 degrees clockwise to view". Store the
    # pixels turned the other way so the viewer turns them back upright.
    sideways = wall.transpose(Image.Transpose.ROTATE_90)
    exif = Image.Exif()
    exif[0x0112] = 6
    sideways.save(out / "wall_exif6.jpg", quality=92, exif=exif.tobytes())
    print(f"wrote {out / 'wall.jpg'} and {out / 'wall_exif6.jpg'}")


if __name__ == "__main__":
    main(Path(sys.argv[1] if len(sys.argv) > 1 else "."))
