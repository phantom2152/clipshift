#!/usr/bin/env python3
"""Renders the ClipShift app icon (1024px PNG + .icns) and a preview sheet.

Usage: python3 Tools/make_icon.py        (needs: pip install pillow numpy)

Writes AppIcon.icns, AppIcon-1024.png and icon-preview.png into ../Resources.
build.sh copies Resources/AppIcon.icns into the app bundle automatically.

Design: a video frame with a play button cut out of it, a ghost copy of the frame behind
it (the "shift" from one file to another) and an amber badge with a download arrow.
"""

import os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "Resources")
K = 2  # supersampling factor
S = 1024 * K

VIOLET = (124, 92, 255)  # background gradient, top left
INDIGO = (22, 28, 116)  # background gradient, bottom right
AMBER = (255, 189, 46)  # download badge
ARROW = (46, 30, 120)  # arrow on the badge


def px(v):
    return int(round(v * K))


def rrect(draw, x0, y0, x1, y1, r, fill):
    draw.rounded_rectangle([px(x0), px(y0), px(x1), px(y1)], radius=px(r), fill=fill)


def gradient(size, c0, c1):
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    t = ((xx + yy) / (2 * (size - 1)))[..., None]
    a = np.array(c0, np.float32)
    b = np.array(c1, np.float32)
    rgb = a + (b - a) * t
    img = np.dstack([rgb, np.full((size, size, 1), 255, np.float32)])
    return Image.fromarray(img.astype(np.uint8), "RGBA")


def smooth(mask, radius):
    """Rounds the corners of a hard-edged mask and keeps the edge anti-aliased."""
    blurred = mask.filter(ImageFilter.GaussianBlur(px(radius)))
    return blurred.point(lambda v: int(max(0, min(255, (v - 120) * 10))))


def punch(layer, mask):
    """Makes the part of `layer` under `mask` transparent."""
    a = np.array(layer)
    m = np.array(mask).astype(np.float32) / 255
    a[..., 3] = (a[..., 3] * (1 - m)).astype(np.uint8)
    return Image.fromarray(a, "RGBA")


def shape_mask(draw_fn):
    m = Image.new("L", (S, S), 0)
    draw_fn(ImageDraw.Draw(m))
    return m


def app_icon():
    # --- background squircle (macOS grid: 824px artwork inside the 1024 canvas)
    art = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    bg = gradient(S, VIOLET, INDIGO)
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [px(100), px(100), px(924), px(924)], radius=px(188), fill=255
    )
    art.paste(bg, (0, 0), mask)

    # soft top highlight
    ys = np.linspace(0, 1, S, dtype=np.float32)[:, None]
    hd = np.zeros((S, S, 4), np.uint8)
    hd[..., :3] = 255
    hd[..., 3] = (np.clip(1 - ys / 0.55, 0, 1) * 34).astype(np.uint8).repeat(S, axis=1)
    hl = Image.fromarray(hd, "RGBA")
    clipped = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    clipped.paste(hl, (0, 0), mask)
    art = Image.alpha_composite(art, clipped)

    # --- glyph
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    white = (255, 255, 255, 255)

    fx0, fy0, fx1, fy1 = 300, 390, 780, 690  # front frame (16:10)
    rrect(
        d, fx0 - 56, fy0 - 56, fx1 - 56, fy1 - 56, 54, (255, 255, 255, 100)
    )  # ghost copy
    rrect(d, fx0, fy0, fx1, fy1, 54, white)  # frame

    # play button cut out of the frame, so the gradient shows through
    tx0, tx1, ty0, ty1 = 488, 612, 468, 612
    tri = shape_mask(
        lambda dr: dr.polygon(
            [(px(tx0), px(ty0)), (px(tx0), px(ty1)), (px(tx1), px((ty0 + ty1) / 2))],
            fill=255,
        )
    )
    layer = punch(layer, smooth(tri, 9))

    # download badge on the frame's lower right corner, with a gap around it
    bx, by, br = 770, 684, 108
    ring = shape_mask(
        lambda dr: dr.ellipse(
            [px(bx - br - 20), px(by - br - 20), px(bx + br + 20), px(by + br + 20)],
            fill=255,
        )
    )
    layer = punch(layer, ring)

    d = ImageDraw.Draw(layer)
    d.ellipse([px(bx - br), px(by - br), px(bx + br), px(by + br)], fill=AMBER + (255,))
    rrect(d, bx - 17, by - 66, bx + 17, by + 6, 17, ARROW + (255,))  # shaft
    head = shape_mask(
        lambda dr: dr.polygon(
            [
                (px(bx - 50), px(by - 10)),
                (px(bx + 50), px(by - 10)),
                (px(bx), px(by + 44)),
            ],
            fill=255,
        )
    )
    head = np.array(smooth(head, 5))
    h = np.array(layer)
    over = head.astype(np.float32) / 255
    for c, v in enumerate(ARROW):
        h[..., c] = (h[..., c] * (1 - over) + v * over).astype(np.uint8)
    h[..., 3] = np.maximum(h[..., 3], head)
    layer = Image.fromarray(h, "RGBA")
    d = ImageDraw.Draw(layer)
    rrect(d, bx - 60, by + 60, bx + 60, by + 82, 11, ARROW + (255,))  # tray

    # drop shadow under the glyph
    shadow = layer.filter(ImageFilter.GaussianBlur(px(14)))
    sh = np.array(shadow)
    sh[..., :3] = 6
    sh[..., 3] = (sh[..., 3] * 0.35).astype(np.uint8)
    shadow = Image.fromarray(sh, "RGBA")
    shifted = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    shifted.paste(shadow, (0, px(10)))
    art = Image.alpha_composite(art, shifted)
    art = Image.alpha_composite(art, layer)

    # --- outer drop shadow of the whole tile
    sm = mask.filter(ImageFilter.GaussianBlur(px(18)))
    blk = Image.new("RGBA", (S, S), (0, 0, 0, 90))
    sb = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    sb.paste(blk, (0, px(14)), sm)
    base = Image.alpha_composite(Image.new("RGBA", (S, S), (0, 0, 0, 0)), sb)
    base = Image.alpha_composite(base, art)
    return base.resize((1024, 1024), Image.LANCZOS)


def preview(icon):
    sheet = Image.new("RGBA", (1100, 640), (24, 26, 30, 255))
    sheet.alpha_composite(icon.resize((512, 512), Image.LANCZOS), (50, 64))
    d = ImageDraw.Draw(sheet)
    # small sizes on a dark and a light card
    for i, color in enumerate(((44, 46, 54, 255), (238, 240, 244, 255))):
        y = 64 + i * 270
        d.rounded_rectangle([620, y, 1050, y + 240], radius=18, fill=color)
        for j, size in enumerate((128, 64, 32, 16)):
            sheet.alpha_composite(
                icon.resize((size, size), Image.LANCZOS),
                (650 + [0, 150, 240, 300][j], y + 56),
            )
    d.text((50, 590), "ClipShift", fill=(255, 255, 255, 255))
    return sheet


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    icon = app_icon()
    icon.save(os.path.join(OUT, "AppIcon-1024.png"))
    icon.save(
        os.path.join(OUT, "AppIcon.icns"),
        format="ICNS",
        sizes=[
            (16, 16),
            (32, 32),
            (64, 64),
            (128, 128),
            (256, 256),
            (512, 512),
            (1024, 1024),
        ],
    )
    preview(icon).convert("RGB").save(os.path.join(OUT, "icon-preview.png"))
    print("ok")
