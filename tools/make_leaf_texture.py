"""Paints the leaf-cluster textures for tree canopies, bushes and hedges
(game/style/leaf_*.png): a bunch of rounded, pointed leaves seen from the
front, lighter towards the top, each leaf edged by a thin darker line where
it overlaps the ones behind it, on a transparent background. The colour is
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


def paint(seed, n_leaves, leaf_len, cluster_r, out):
    rng = random.Random(seed)
    S = SIZE * SS
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx, cy = S * 0.5, S * 0.52
    R = S * cluster_r
    leaves = []
    for _ in range(n_leaves):
        # more leaves near the middle; tips point away from the middle
        a = rng.uniform(0, math.tau)
        r = R * math.sqrt(rng.random()) * 0.82
        bx, by = cx + math.cos(a) * r * 0.6, cy + math.sin(a) * r * 0.6
        out_angle = math.atan2(by - cy, bx - cx) if r > 1 else rng.uniform(0, math.tau)
        ang = out_angle + rng.uniform(-0.7, 0.7)
        L = S * leaf_len * rng.uniform(0.75, 1.15)
        # start a little behind the base so the middle of the bunch is covered
        bx -= math.cos(ang) * L * 0.3
        by -= math.sin(ang) * L * 0.3
        W = L * rng.uniform(0.62, 0.78)
        # depth: leaves further out and higher are drawn later (in front)
        depth = r / R + (cy - by) / R * 0.3 + rng.uniform(-0.25, 0.25)
        leaves.append((depth, bx, by, ang, L, W))
    leaves.sort()
    # a dark, lumpy backing in the middle: the shadowed inside of the bunch
    back = []
    for i in range(40):
        t = math.tau * i / 40
        rr = R * 0.5 * (1 + 0.12 * math.sin(5 * t + seed) + rng.uniform(-0.05, 0.05))
        back.append((cx + math.cos(t) * rr, cy + math.sin(t) * rr))
    d.polygon(back, fill=(140, 140, 140, 255))
    for depth, bx, by, ang, L, W in leaves:
        tip_y = by + math.sin(ang) * L
        top = 1.0 - (min(by, tip_y) - (cy - R)) / (2 * R)          # 1 at the top of the bunch
        v = 0.66 + 0.26 * max(0.0, min(1.0, top)) + rng.uniform(-0.06, 0.06)
        v = max(0.45, min(1.0, v))
        # thin darker rim first, then the leaf in two tones (lighter half)
        rim = leaf_outline((bx, by), ang, L * 1.04, W * 1.12)
        d.polygon(rim, fill=(int(255 * v * 0.72),) * 3 + (255,))
        body = leaf_outline((bx, by), ang, L, W)
        d.polygon(body, fill=(int(255 * v),) * 3 + (255,))
        half = [p for i, p in enumerate(body) if i <= len(body) // 2]
        d.polygon(half + [(bx, by)], fill=(int(255 * min(1.0, v * 1.07)),) * 3 + (255,))
        # midrib
        mx, my = bx + math.cos(ang) * L * 0.85, by + math.sin(ang) * L * 0.85
        d.line([(bx, by), (mx, my)], fill=(int(255 * v * 0.85),) * 3 + (255,), width=max(1, int(SS * 2)))
    img = img.resize((SIZE, SIZE), Image.LANCZOS)
    # keep the cut-out crisp after downsampling
    r, g, b, a = img.split()
    a = a.point(lambda x: 255 if x > 110 else 0).filter(ImageFilter.GaussianBlur(0.6))
    # spread the colour into the transparent area so mipmaps don't darken edges
    rgb = Image.merge("RGB", (r, g, b))
    bg = rgb.filter(ImageFilter.GaussianBlur(12))
    mask = a.point(lambda x: 255 if x > 0 else 0)
    filled = Image.composite(rgb, Image.new("RGB", rgb.size, (200, 200, 200)), mask)
    filled = Image.composite(rgb, bg.point(lambda x: min(255, int(x * 1.6))), mask)
    out_img = Image.merge("RGBA", (*filled.split(), a))
    out_img.save(out)
    return out


def main(root):
    style = os.path.join(root, "game", "style")
    os.makedirs(style, exist_ok=True)
    print(paint(3, 70, 0.17, 0.44, os.path.join(style, "leaf_broad.png")))
    print(paint(8, 170, 0.11, 0.45, os.path.join(style, "leaf_small.png")))


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
