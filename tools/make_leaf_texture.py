"""Paints the leaf-cluster textures for tree canopies, bushes and hedges
(game/style/leaf_*.png): a lumpy patch of rounded, pointed leaves seen from
the side, hanging outwards and down, lighter towards the top, each leaf
edged by a faint darker line where it overlaps the ones behind it, on a
transparent background. The colour is
greyscale (the foliage shader tints it); alpha cuts the leaves out.

    python tools/make_leaf_texture.py

broad   street trees, poplars, bushes: big rounded leaves (lime, maple)
small   birch and hedges: small, finer leaves
"""
import math
import os
import random
import sys

from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
SS = 2                     # supersampling


def leaf_outline(base, angle, length, width, n=24):
    """A leaf: rounded body, slightly pointed tip, narrow stalk end."""
    ca, sa = math.cos(angle), math.sin(angle)
    left, right = [], []
    for i in range(n + 1):
        t = i / n
        w = width * (math.sin(math.pi * t) ** 0.75) * (1.0 - 0.35 * t ** 2)
        x = t * length
        for side, out in ((1, left), (-1, right)):
            px, py = x, side * w / 2
            out.append((base[0] + px * ca - py * sa, base[1] + px * sa + py * ca))
    return left + right[::-1]


def _blob(rng, cx, cy, R):
    """A lumpy patch made of a few overlapping circles: (x, y, r) each."""
    circles = [(cx, cy, R * 0.62)]
    for i in range(6):
        a = math.tau * i / 6 + rng.uniform(-0.4, 0.4)
        d = R * rng.uniform(0.3, 0.42)
        circles.append((cx + math.cos(a) * d, cy + math.sin(a) * d, R * rng.uniform(0.4, 0.55)))
    return circles


def _inside(circles, x, y, shrink=1.0):
    return any((x - cx) ** 2 + (y - cy) ** 2 <= (r * shrink) ** 2 for cx, cy, r in circles)


def paint(seed, n_leaves, leaf_len, cluster_r, out):
    """A patch of foliage as seen from the side: leaves hang outwards and
    down from a lumpy middle, upper ones overlapping lower ones, lighter on
    top. The middle is backed by a dark fill (the shade inside the bush)."""
    rng = random.Random(seed)
    S = SIZE * SS
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx, cy = S * 0.5, S * 0.5
    R = S * cluster_r
    circles = _blob(rng, cx, cy, R * 0.82)
    for x, y, r in circles:                      # dark inside
        r *= 0.86
        d.ellipse((x - r, y - r, x + r, y + r), fill=(118, 118, 118, 255))
    leaves = []
    while len(leaves) < n_leaves:
        x, y = cx + rng.uniform(-R, R), cy + rng.uniform(-R, R)
        if not _inside(circles, x, y):
            continue
        out_a = math.atan2(y - cy, x - cx)
        # outwards, pulled towards hanging down (+y), with some scatter
        ang = math.atan2(math.sin(out_a) + 0.9, math.cos(out_a)) + rng.uniform(-0.7, 0.7)
        L = S * leaf_len * rng.uniform(0.75, 1.2)
        W = L * rng.uniform(0.55, 0.7)
        bx, by = x - math.cos(ang) * L * 0.45, y - math.sin(ang) * L * 0.45
        leaves.append((y + rng.uniform(-0.15, 0.15) * R, bx, by, ang, L, W))
    leaves.sort(key=lambda l: -l[0])             # lower leaves first, upper ones on top
    for _, bx, by, ang, L, W in leaves:
        mid_y = by + math.sin(ang) * L * 0.5
        top = 1.0 - (mid_y - (cy - R)) / (2 * R)  # 1 at the top of the patch
        v = 0.62 + 0.34 * max(0.0, min(1.0, top)) + rng.uniform(-0.07, 0.07)
        v = max(0.42, min(1.0, v))
        rim = leaf_outline((bx, by), ang, L * 1.03, W * 1.1)
        d.polygon(rim, fill=(int(255 * v * 0.84),) * 3 + (255,))
        body = leaf_outline((bx, by), ang, L, W)
        d.polygon(body, fill=(int(255 * v),) * 3 + (255,))
        # the lit half (upper side) a little lighter
        n = len(body) // 2
        half = body[:n + 1] if math.cos(ang) >= 0 else body[n:] + body[:1]
        d.polygon(half + [(bx, by)], fill=(int(255 * min(1.0, v * 1.06)),) * 3 + (255,))
        mx, my = bx + math.cos(ang) * L * 0.8, by + math.sin(ang) * L * 0.8
        d.line([(bx, by), (mx, my)], fill=(int(255 * v * 0.9),) * 3 + (255,), width=max(1, int(SS * 1.5)))
    img = img.resize((SIZE, SIZE), Image.LANCZOS)
    # keep the cut-out crisp after downsampling
    r, g, b, a = img.split()
    a = a.point(lambda x: 255 if x > 110 else 0).filter(ImageFilter.GaussianBlur(0.6))
    # spread the colour into the transparent area so mipmaps don't darken edges
    rgb = Image.merge("RGB", (r, g, b))
    bg = rgb.filter(ImageFilter.GaussianBlur(12))
    mask = a.point(lambda x: 255 if x > 0 else 0)
    filled = Image.composite(rgb, bg.point(lambda x: min(255, int(x * 1.6))), mask)
    out_img = Image.merge("RGBA", (*filled.split(), a))
    out_img.save(out)
    return out


def main(root):
    style = os.path.join(root, "game", "style")
    os.makedirs(style, exist_ok=True)
    print(paint(3, 120, 0.13, 0.44, os.path.join(style, "leaf_broad.png")))
    print(paint(8, 300, 0.08, 0.45, os.path.join(style, "leaf_small.png")))


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
