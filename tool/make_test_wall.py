"""Draws a fake peg wall for testing the scan path end to end.

Twelve cards in a 3000x4000 image (a 12 MP phone photo), each with a
collector number and a series line the way OCR would meet them. A few carry
real numbers from assets/hunts.json so the app has something to ring:

    176/250  HW J-IMPORTS 7/10    2026 Super Treasure Hunt, Subaru Impreza
    009/250  NIGHTSPEED 1/10      2026 Treasure Hunt, '87 Buick Regal GNX
    CAR CULTURE 0/5               a premium chase
    249/250  (no series)          three years share this number: possible

The rest are ordinary cards. Two files are written:

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

CARDS = [
    ("123/250", "HW DIRT 3/10"),
    ("176/250", "HW J-IMPORTS 7/10"),
    ("088/250", "HW METRO 2/10"),
    ("041/250", "ROD SQUAD 4/10"),
    ("200/250", "HW EXOTICS 6/10"),
    ("009/250", "NIGHTSPEED 1/10"),
    (None, "CAR CULTURE 0/5"),
    ("150/250", "FACTORY FRESH 9/10"),
    ("249/250", None),
    ("077/250", "HW TURBO 5/10"),
    ("190/250", "HW MODS 8/10"),
    ("102/250", "TOONED 1/5"),
]


def draw_wall() -> Image.Image:
    img = Image.new("RGB", (W, H), (205, 200, 192))
    d = ImageDraw.Draw(img)
    big = ImageFont.truetype(FONT, 70)
    small = ImageFont.truetype(FONT, 54)
    logo = ImageFont.truetype(FONT, 110)
    cw, ch = W / COLS, H / ROWS
    for i, (number, series) in enumerate(CARDS):
        c, r = i % COLS, i // COLS
        x0, y0 = c * cw + 70, r * ch + 60
        x1, y1 = (c + 1) * cw - 70, (r + 1) * ch - 60
        d.rounded_rectangle((x0, y0, x1, y1), radius=30, fill=(28, 72, 160))
        d.rectangle((x0 + 30, y0 + 30, x1 - 30, y0 + 170), fill=(232, 90, 30))
        d.text((x0 + 60, y0 + 40), "PEG CARS", font=logo, fill=(255, 245, 230))
        # A car-shaped blob in the blister.
        d.rounded_rectangle((x0 + 120, y0 + 330, x1 - 120, y0 + 560), radius=60, fill=(180, 30, 40))
        d.ellipse((x0 + 170, y0 + 520, x0 + 290, y0 + 640), fill=(20, 20, 20))
        d.ellipse((x1 - 290, y0 + 520, x1 - 170, y0 + 640), fill=(20, 20, 20))
        if number:
            d.rectangle((x1 - 330, y0 + 200, x1 - 40, y0 + 290), fill=(250, 250, 250))
            d.text((x1 - 315, y0 + 208), number, font=big, fill=(10, 10, 10))
        if series:
            d.text((x0 + 60, y1 - 110), series, font=small, fill=(255, 255, 255))
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
