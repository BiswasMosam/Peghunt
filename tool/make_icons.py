"""Draws the Peghunt mark (a wall of cards, one ringed in gold) into every
Android launcher icon size, plus the adaptive and themed vector icons.

Run from the repo root with any Python that has Pillow:
    python tool/make_icons.py
"""
from pathlib import Path
from PIL import Image, ImageDraw

BLACK = "#0B0B0C"
FAINT = "#4A4A50"
BONE = "#F2F0EA"
GOLD = "#E8B649"
RES = Path("android/app/src/main/res")


def cards(origin, size):
    """Yields (rect, hunted) for the 3x3 wall, matching lib/ui/mark.dart."""
    cell = size / 3
    w, h = cell * 0.52, cell * 0.70
    for r in range(3):
        for c in range(3):
            cx = origin[0] + cell * (c + 0.5)
            cy = origin[1] + cell * (r + 0.5)
            yield (cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2), (r == 1 and c == 1)


def png(px, mark_frac=0.62):
    scale = 4
    S = px * scale
    img = Image.new("RGB", (S, S), BLACK)
    d = ImageDraw.Draw(img)
    size = S * mark_frac
    o = ((S - size) / 2, (S - size) / 2)
    cell = size / 3
    for rect, hunted in cards(o, size):
        d.rounded_rectangle(rect, radius=cell * 0.06, fill=BONE if hunted else FAINT)
    c = S / 2
    r = cell * 0.54
    sw = size * 0.055
    d.ellipse((c - r - sw / 2, c - r - sw / 2, c + r + sw / 2, c + r + sw / 2), outline=GOLD, width=round(sw))
    return img.resize((px, px), Image.LANCZOS)


def rrect_path(x0, y0, x1, y1, rad):
    return (f"M{x0 + rad:.2f},{y0:.2f} H{x1 - rad:.2f} A{rad:.2f},{rad:.2f} 0 0 1 {x1:.2f},{y0 + rad:.2f} "
            f"V{y1 - rad:.2f} A{rad:.2f},{rad:.2f} 0 0 1 {x1 - rad:.2f},{y1:.2f} H{x0 + rad:.2f} "
            f"A{rad:.2f},{rad:.2f} 0 0 1 {x0:.2f},{y1 - rad:.2f} V{y0 + rad:.2f} "
            f"A{rad:.2f},{rad:.2f} 0 0 1 {x0 + rad:.2f},{y0:.2f} Z")


def vector(mono=False):
    # 108dp adaptive canvas; the safe zone is the middle 66dp.
    size = 58.0
    o = ((108 - size) / 2, (108 - size) / 2)
    cell = size / 3
    paths = []
    for (x0, y0, x1, y1), hunted in cards(o, size):
        color = BONE if (hunted or mono) else FAINT
        alpha = "" if (hunted or not mono) else ' android:fillAlpha="0.45"'
        paths.append(f'    <path android:fillColor="{color}"{alpha} android:pathData="{rrect_path(x0, y0, x1, y1, cell * 0.06)}"/>')
    r = cell * 0.54
    c = 54.0
    ring = (f"M{c - r:.2f},{c:.2f} A{r:.2f},{r:.2f} 0 1 1 {c + r:.2f},{c:.2f} "
            f"A{r:.2f},{r:.2f} 0 1 1 {c - r:.2f},{c:.2f} Z")
    paths.append(f'    <path android:strokeColor="{BONE if mono else GOLD}" android:strokeWidth="{size * 0.055:.2f}" '
                 f'android:fillColor="#00000000" android:pathData="{ring}"/>')
    return ('<?xml version="1.0" encoding="utf-8"?>\n'
            '<vector xmlns:android="http://schemas.android.com/apk/res/android"\n'
            '    android:width="108dp" android:height="108dp"\n'
            '    android:viewportWidth="108" android:viewportHeight="108">\n'
            + "\n".join(paths) + "\n</vector>\n")


for folder, px in {"mipmap-mdpi": 48, "mipmap-hdpi": 72, "mipmap-xhdpi": 96,
                   "mipmap-xxhdpi": 144, "mipmap-xxxhdpi": 192}.items():
    png(px).save(RES / folder / "ic_launcher.png")

(RES / "drawable" / "ic_launcher_foreground.xml").write_text(vector(), encoding="utf-8")
(RES / "drawable" / "ic_launcher_monochrome.xml").write_text(vector(mono=True), encoding="utf-8")
(RES / "mipmap-anydpi-v26").mkdir(exist_ok=True)
(RES / "mipmap-anydpi-v26" / "ic_launcher.xml").write_text(
    '<?xml version="1.0" encoding="utf-8"?>\n'
    '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
    '    <background android:drawable="@color/peghunt_black"/>\n'
    '    <foreground android:drawable="@drawable/ic_launcher_foreground"/>\n'
    '    <monochrome android:drawable="@drawable/ic_launcher_monochrome"/>\n'
    '</adaptive-icon>\n', encoding="utf-8")

# A large copy for the README.
Path("docs").mkdir(exist_ok=True)
png(512, mark_frac=0.66).save("docs/icon.png")
print("icons written")
