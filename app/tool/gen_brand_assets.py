"""Regenerates app icon + splash PNGs in the green identity.
Run: python3 tool/gen_brand_assets.py && dart run flutter_launcher_icons && dart run flutter_native_splash:create
"""
from PIL import Image, ImageDraw

GREEN = (0x14, 0x53, 0x2D, 255)
MID = (0x16, 0x65, 0x34, 255)
EMERALD = (0x10, 0xB9, 0x81, 255)
WHITE = (255, 255, 255, 255)
CLEAR = (0, 0, 0, 0)

def ledger_glyph(d, cx, cy, s, ink=WHITE, check=EMERALD):
    """Minimal ledger: rounded book with 3 lines + emerald check badge. s = glyph size."""
    w, h = s, s * 1.12
    x0, y0 = cx - w / 2, cy - h / 2
    r = s * 0.14
    lw = max(4, int(s * 0.075))
    # book body (outline)
    d.rounded_rectangle([x0, y0, x0 + w, y0 + h], radius=r, outline=ink, width=lw)
    # spine
    sx = x0 + w * 0.22
    d.line([sx, y0 + lw / 2, sx, y0 + h - lw / 2], fill=ink, width=lw)
    # lines
    lx0, lx1 = sx + w * 0.16, x0 + w - w * 0.16
    for i, frac in enumerate((0.30, 0.50, 0.70)):
        y = y0 + h * frac
        x1 = lx1 if i < 2 else lx0 + (lx1 - lx0) * 0.55
        d.line([lx0, y, x1, y], fill=ink, width=lw)
    # emerald check badge (bottom-right)
    br = s * 0.22
    bx, by = x0 + w - br * 0.35, y0 + h - br * 0.35
    d.ellipse([bx - br, by - br, bx + br, by + br], fill=check)
    cw = max(4, int(s * 0.06))
    d.line([bx - br * 0.45, by, bx - br * 0.1, by + br * 0.35, bx + br * 0.5, by - br * 0.38], fill=WHITE, width=cw, joint="curve")

def icon(size=1024, path="assets/icon/app_icon.png"):
    im = Image.new("RGBA", (size, size), CLEAR)
    d = ImageDraw.Draw(im)
    d.rounded_rectangle([0, 0, size, size], radius=int(size * 0.22), fill=GREEN)
    ledger_glyph(d, size / 2, size / 2, size * 0.46)
    im.save(path)

def foreground(size=1024, path="assets/icon/app_icon_foreground.png"):
    # adaptive foreground: transparent, glyph inside the safe zone (~66%)
    im = Image.new("RGBA", (size, size), CLEAR)
    d = ImageDraw.Draw(im)
    ledger_glyph(d, size / 2, size / 2, size * 0.36)
    im.save(path)

def splash(size, path, glyph_frac):
    im = Image.new("RGBA", (size, size), CLEAR)
    d = ImageDraw.Draw(im)
    ledger_glyph(d, size / 2, size / 2, size * glyph_frac)
    im.save(path)

if __name__ == "__main__":
    icon()
    foreground()
    splash(512, "assets/images/splash_logo.png", 0.55)
    # Android 12 splash icon: 960px canvas, keep glyph in the inner 2/3.
    splash(960, "assets/images/splash_logo_android12.png", 0.38)
    print("brand assets written")
