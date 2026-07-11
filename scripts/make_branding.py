#!/usr/bin/env python3
"""Génère l'identité visuelle de Rubato (icône + splash) à partir d'un
monogramme « R » en serif de titrage italique, aux couleurs « Encre & Papier ».

Sorties dans assets/branding/ :
  icon.png            icône launcher pleine (fond encre, R laiton)
  icon_foreground.png calque avant pour icône adaptative (R laiton, transparent)
  splash.png          logo splash clair  (R encre, transparent → fond papier)
  splash_dark.png     logo splash sombre (R laiton, transparent → fond encre)

Consommé ensuite par flutter_launcher_icons et flutter_native_splash.
Usage : python3 scripts/make_branding.py
"""
import os

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "branding")

INK = (32, 29, 24, 255)       # #201D18 encre
INK_BG = (20, 17, 12, 255)    # #14110C fond encre
BRASS = (201, 162, 91, 255)   # #C9A25B laiton (lumineux, sur fond sombre)

FONTS = [
    "/usr/share/fonts/truetype/noto/NotoSerifDisplay-BoldItalic.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf",
]


def font(size):
    for f in FONTS:
        if os.path.exists(f):
            return ImageFont.truetype(f, size)
    return ImageFont.load_default()


def glyph(size, char, color, bg=None, frac=0.6):
    """Dessine `char` centré sur un carré `size`, occupant ~frac de la hauteur."""
    img = Image.new("RGBA", (size, size), bg or (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    fs = int(size * frac * 1.5)
    fnt = font(fs)
    box = d.textbbox((0, 0), char, font=fnt)
    h = box[3] - box[1]
    fnt = font(max(8, int(fs * (size * frac) / h)))
    box = d.textbbox((0, 0), char, font=fnt)
    w, h = box[2] - box[0], box[3] - box[1]
    d.text(((size - w) / 2 - box[0], (size - h) / 2 - box[1]),
           char, font=fnt, fill=color)
    return img


def main():
    os.makedirs(OUT, exist_ok=True)

    glyph(1024, "R", BRASS, bg=INK_BG, frac=0.6) \
        .convert("RGB").save(os.path.join(OUT, "icon.png"))
    glyph(1024, "R", BRASS, frac=0.44).save(os.path.join(OUT, "icon_foreground.png"))
    glyph(1024, "R", INK, frac=0.5).save(os.path.join(OUT, "splash.png"))
    glyph(1024, "R", BRASS, frac=0.5).save(os.path.join(OUT, "splash_dark.png"))

    print("Identité visuelle générée dans assets/branding/")


if __name__ == "__main__":
    main()
