"""Generate the hand-inked vector art for Micro 15 as SVG + PNG.

Everything is drawn procedurally so it can be regenerated or tweaked:
thick dark ink outlines with a slight wobble, flat fills, one shadow and one
highlight tone per shape (the Flash / Neopets look).

    python tools/art/make_art.py            # writes game/art/**

Output:
    game/art/sprites/*.png   trees, bushes, lamp, bench (billboard sprites)
    game/art/textures/*.png  facades, roof, grass, asphalt, pavement (tiling)
    tools/art/svg/*.svg      the source vector files (open in Inkscape)
"""
import math
import os
import random

import cairosvg

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT_SPR = os.path.join(ROOT, "game", "art", "sprites")
OUT_TEX = os.path.join(ROOT, "game", "art", "textures")
OUT_SVG = os.path.join(ROOT, "tools", "art", "svg")

INK = "#1d1a26"


# ----------------------------------------------------------------------------
# Wobbly ink helpers
# ----------------------------------------------------------------------------
def wobble(points, rng, amp=1.5, step=14.0, closed=True):
    """Subdivide a polyline and push points sideways by smooth noise."""
    pts = list(points) + ([points[0]] if closed else [])
    out = []
    phase = rng.uniform(0, 10)
    for i in range(len(pts) - 1):
        (x1, y1), (x2, y2) = pts[i], pts[i + 1]
        L = math.hypot(x2 - x1, y2 - y1)
        n = max(1, int(L / step))
        nx, ny = (-(y2 - y1) / (L or 1), (x2 - x1) / (L or 1))
        for k in range(n):
            t = k / n
            phase += 0.9
            off = amp * (math.sin(phase) * 0.6 + rng.uniform(-0.4, 0.4))
            out.append((x1 + (x2 - x1) * t + nx * off, y1 + (y2 - y1) * t + ny * off))
    if not closed:
        out.append(pts[-1])
    return out


def path_d(points, closed=True):
    """Smooth path through points (Catmull-Rom converted to cubic Beziers)."""
    p = points
    n = len(p)
    if n < 3:
        return "M%.1f,%.1f " % p[0] + " ".join("L%.1f,%.1f" % q for q in p[1:])
    d = ["M%.1f,%.1f" % p[0]]
    rng_ = range(n) if closed else range(n - 1)
    for i in rng_:
        p0 = p[(i - 1) % n] if closed or i > 0 else p[i]
        p1 = p[i]
        p2 = p[(i + 1) % n]
        p3 = p[(i + 2) % n] if closed or i + 2 < n else p2
        c1 = (p1[0] + (p2[0] - p0[0]) / 6, p1[1] + (p2[1] - p0[1]) / 6)
        c2 = (p2[0] - (p3[0] - p1[0]) / 6, p2[1] - (p3[1] - p1[1]) / 6)
        d.append("C%.1f,%.1f %.1f,%.1f %.1f,%.1f" % (c1 + c2 + p2))
    if closed:
        d.append("Z")
    return " ".join(d)


def shape(points, fill, rng, ink=INK, width=5.0, amp=1.4, closed=True, extra=""):
    pts = wobble(points, rng, amp=amp, closed=closed)
    stroke = 'stroke="%s" stroke-width="%.1f" stroke-linejoin="round" stroke-linecap="round"' % (
        ink, width) if width else ""
    return '<path d="%s" fill="%s" %s %s/>' % (path_d(pts, closed), fill, stroke, extra)


def rect_pts(x, y, w, h):
    return [(x, y), (x + w, y), (x + w, y + h), (x, y + h)]


def line(x1, y1, x2, y2, rng, width=3.0, ink=INK, amp=0.8):
    pts = wobble([(x1, y1), (x2, y2)], rng, amp=amp, step=18, closed=False)
    return '<path d="%s" fill="none" stroke="%s" stroke-width="%.1f" stroke-linecap="round"/>' % (
        path_d(pts, False), ink, width)


def blob(cx, cy, r, rng, lumps=9, irregular=0.18):
    """Cloud-like closed outline (tree canopies, bushes)."""
    pts = []
    for i in range(lumps * 4):
        a = 2 * math.pi * i / (lumps * 4)
        lump = abs(math.sin(a * lumps / 2 + rng.uniform(-0.1, 0.1))) ** 0.45   # round scallops
        rr = r * (1 - irregular + irregular * lump * 1.6) * rng.uniform(0.97, 1.03)
        pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr * 0.92))
    return pts


def svg(w, h, body, bg=None):
    b = '<rect width="100%%" height="100%%" fill="%s"/>' % bg if bg else ""
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">%s%s</svg>'
            % (w, h, w, h, b, body))


def save(name, content, out_dir, scale=1.0):
    os.makedirs(out_dir, exist_ok=True)
    os.makedirs(OUT_SVG, exist_ok=True)
    open(os.path.join(OUT_SVG, name + ".svg"), "w").write(content)
    cairosvg.svg2png(bytestring=content.encode(), write_to=os.path.join(out_dir, name + ".png"), scale=scale)


# ----------------------------------------------------------------------------
# Sprites
# ----------------------------------------------------------------------------
def tree_round(name, seed, leaf, leaf_dark, leaf_light, w=512, h=640):
    rng = random.Random(seed)
    cx = w / 2
    body = []
    # trunk
    tw = 30
    trunk = [(cx - tw, h - 18), (cx - tw * 0.55, h - 210), (cx - 60, h - 300), (cx - 40, h - 310),
             (cx - 8, h - 250), (cx + 30, h - 320), (cx + 50, h - 308), (cx + tw * 0.6, h - 200),
             (cx + tw, h - 18)]
    body.append(shape(trunk, "#8a5a3b", rng, width=6))
    body.append(shape([(cx + 4, h - 30), (cx + tw * 0.7, h - 30), (cx + tw * 0.45, h - 200), (cx + 10, h - 210)],
                      "#6b4029", rng, width=0))
    # canopy
    cy = 255
    r = 205
    body.append(shape(blob(cx, cy, r, rng, lumps=rng.choice([8, 9, 10])), leaf, rng, width=7, amp=1.0))
    # shadow underside (clipped to canopy by drawing a smaller offset blob)
    body.append('<clipPath id="c%d"><path d="%s"/></clipPath>' % (seed, path_d(blob(cx, cy, r - 4, random.Random(seed), 9))))
    body.append('<g clip-path="url(#c%d)">' % seed)
    body.append(shape(blob(cx + 40, cy + 150, r * 0.95, rng, 10), leaf_dark, rng, width=0))
    for _ in range(6):
        a = rng.uniform(math.pi * 1.1, math.pi * 1.9)
        x, y = cx + math.cos(a) * r * 0.55, cy + math.sin(a) * r * 0.5
        body.append(shape(blob(x, y, rng.uniform(30, 55), rng, 6, 0.25), leaf_light, rng, width=0))
    body.append('</g>')
    # leaf strokes
    for _ in range(14):
        a = rng.uniform(0, math.tau)
        rr = rng.uniform(0.2, 0.75) * r
        x, y = cx + math.cos(a) * rr, cy + math.sin(a) * rr * 0.9
        body.append(line(x, y, x + rng.uniform(-14, 14), y + rng.uniform(10, 22), rng, width=3.5, amp=0.5))
    save(name, svg(w, h, "".join(body)), OUT_SPR)


def tree_poplar(name, seed, w=320, h=900):
    rng = random.Random(seed)
    cx = w / 2
    body = []
    body.append(shape([(cx - 16, h - 14), (cx - 10, h - 170), (cx + 10, h - 170), (cx + 16, h - 14)],
                      "#8a5a3b", rng, width=6))
    pts = []
    n = 40
    for i in range(n):
        a = 2 * math.pi * i / n
        lump = 1 + 0.07 * math.sin(a * 9 + rng.uniform(0, 0.3))
        pts.append((cx + math.cos(a) * 118 * lump, 400 + math.sin(a) * 375 * lump))
    body.append(shape(pts, "#3f9447", rng, width=7, amp=1.2))
    body.append('<clipPath id="p%d"><path d="%s"/></clipPath><g clip-path="url(#p%d)">' % (seed, path_d(pts), seed))
    body.append(shape([(cx + 20, 20), (cx + 160, 300), (cx + 160, 800), (cx - 40, 800), (cx + 50, 500)],
                      "#2f7a3b", rng, width=0))
    for _ in range(5):
        body.append(shape(blob(cx - 50 + rng.uniform(-10, 20), rng.uniform(140, 520), rng.uniform(18, 32), rng, 5, 0.25),
                          "#5fb553", rng, width=0))
    body.append('</g>')
    for _ in range(12):
        x, y = cx + rng.uniform(-70, 70), rng.uniform(100, 720)
        body.append(line(x, y, x + rng.uniform(-6, 6), y + rng.uniform(16, 30), rng, width=3.5, amp=0.4))
    save(name, svg(w, h, "".join(body)), OUT_SPR)


def bush(name, seed, w=420, h=260):
    rng = random.Random(seed)
    body = []
    pts = blob(w / 2, h * 0.6, 170, rng, 7, 0.22)
    pts = [(x, min(y, h - 16)) for x, y in pts]          # flat bottom on the ground
    body.append(shape(pts, "#5aae45", rng, width=6))
    body.append('<clipPath id="b%d"><path d="%s"/></clipPath><g clip-path="url(#b%d)">' % (seed, path_d(pts), seed))
    body.append(shape(blob(w / 2 + 40, h + 30, 170, rng, 8), "#3f8f3a", rng, width=0))
    for _ in range(4):
        body.append(shape(blob(rng.uniform(100, 260), rng.uniform(70, 120), rng.uniform(16, 28), rng, 5),
                          "#7ccc5c", rng, width=0))
    body.append('</g>')
    for _ in range(4):   # little flowers
        x, y = rng.uniform(90, 330), rng.uniform(90, 200)
        body.append('<circle cx="%.0f" cy="%.0f" r="9" fill="#f6d55c" stroke="%s" stroke-width="3"/>' % (x, y, INK))
    save(name, svg(w, h, "".join(body)), OUT_SPR)


def lamp(name="lamp", w=256, h=1024):
    rng = random.Random(7)
    cx = 70
    body = []
    body.append(shape([(cx - 14, h - 10), (cx - 8, 120), (cx + 8, 120), (cx + 14, h - 10)], "#4a4e57", rng, width=6))
    body.append(shape([(cx - 26, h - 10), (cx - 22, h - 70), (cx + 22, h - 70), (cx + 26, h - 10)], "#3a3d45", rng, width=6))
    body.append(shape([(cx - 4, 130), (cx + 30, 70), (cx + 150, 60), (cx + 150, 80), (cx + 36, 92), (cx + 8, 140)],
                      "#4a4e57", rng, width=6))
    body.append(shape([(cx + 100, 64), (cx + 200, 58), (cx + 210, 92), (cx + 96, 96)], "#5b606b", rng, width=6))
    body.append(shape([(cx + 106, 95), (cx + 204, 92), (cx + 196, 108), (cx + 112, 110)], "#fff2b3", rng, width=5))
    save(name, svg(w, h, "".join(body)), OUT_SPR)


def bench(name="bench", w=512, h=256):
    rng = random.Random(9)
    body = []
    for x in (70, 420):
        body.append(shape([(x, h - 10), (x, 120), (x + 22, 120), (x + 22, h - 10)], "#4a4e57", rng, width=6))
    for y in (40, 82):
        body.append(shape(rect_pts(30, y, 450, 30), "#c98b55", rng, width=6))
    body.append(shape(rect_pts(20, 140, 470, 34), "#b07a4a", rng, width=6))
    body.append(line(40, 156, 470, 156, rng, width=2.5))
    save(name, svg(w, h, "".join(body)), OUT_SPR)


# ----------------------------------------------------------------------------
# Facade of a P+4 prefab block: 4 bays x 3 floors, tiles in both directions.
# 1 m = 128 px, bay = 3.2 m (410 px), floor = 2.8 m (358 px)
# ----------------------------------------------------------------------------
BAY, FLOOR = 410, 358


def facade(name, wall, wall_dark, seed):
    rng = random.Random(seed)
    w, h = BAY * 4, FLOOR * 3
    body = []
    curtains = ["#f28b82", "#f6c26b", "#9fd3e8", "#c7a4e0", "#fbfbf6"]
    for f in range(3):
        y0 = f * FLOOR
        for b in range(4):
            x0 = b * BAY
            # prefab panel joints
            body.append(line(x0 + 3, y0 + 3, x0 + BAY - 3, y0 + 3, rng, width=2.5, ink=wall_dark))
            body.append(line(x0 + 3, y0 + 3, x0 + 3, y0 + FLOOR - 3, rng, width=2.5, ink=wall_dark))
            kind = rng.choices(["window", "balcony", "window2"], [0.45, 0.35, 0.2])[0]
            if kind == "balcony":
                # door + window behind, balcony slab in front with drawn shadow
                body.append(shape(rect_pts(x0 + 60, y0 + 40, 300, 280), wall_dark, rng, width=0))
                body.append(_window(x0 + 80, y0 + 60, 120, 230, rng, curtains, door=True))
                body.append(_window(x0 + 220, y0 + 60, 120, 140, rng, curtains))
                rail_y = y0 + 200
                body.append(shape(rect_pts(x0 + 40, rail_y, 330, 140), "#efeae0", rng, width=6))
                body.append(shape(rect_pts(x0 + 40, rail_y + 118, 330, 22), "#d4cdbf", rng, width=0))
                for k in range(1, 6):
                    body.append(line(x0 + 40 + k * 55, rail_y + 12, x0 + 40 + k * 55, rail_y + 112, rng,
                                     width=2, ink="#c9c1b0"))
                extra = rng.random()
                if extra < 0.35:   # flower box
                    body.append(shape(rect_pts(x0 + 80, rail_y - 26, 110, 30), "#c45a3c", rng, width=4))
                    for k in range(5):
                        body.append('<circle cx="%d" cy="%d" r="11" fill="%s" stroke="%s" stroke-width="3"/>' % (
                            x0 + 95 + k * 20, rail_y - 34, rng.choice(["#f25c54", "#f7b32b", "#ffffff"]), INK))
                elif extra < 0.6:  # laundry line
                    body.append(line(x0 + 60, rail_y - 60, x0 + 350, rail_y - 50, rng, width=2))
                    for k in range(3):
                        cx = x0 + 100 + k * 80
                        body.append(shape(rect_pts(cx, rail_y - 58, 50, 60), rng.choice(curtains), rng, width=4))
            else:
                body.append(_window(x0 + 95, y0 + 70, 220, 170, rng, curtains, wide=kind == "window2"))
                # sill shadow
                body.append(shape(rect_pts(x0 + 85, y0 + 246, 240, 14), "#e9e4d8", rng, width=4))
                if rng.random() < 0.2:   # AC unit
                    body.append(shape(rect_pts(x0 + 300, y0 + 200, 80, 60), "#f4f4f0", rng, width=5))
                    body.append('<circle cx="%d" cy="%d" r="20" fill="none" stroke="%s" stroke-width="3"/>' % (
                        x0 + 340, y0 + 230, INK))
                elif rng.random() < 0.12:  # satellite dish
                    body.append(shape(blob(x0 + 350, y0 + 110, 34, rng, 4, 0.05), "#f4f4f0", rng, width=5))
                    body.append(line(x0 + 350, y0 + 110, x0 + 375, y0 + 150, rng, width=4))
            # grime streaks
            if rng.random() < 0.3:
                gx = x0 + rng.uniform(30, BAY - 30)
                body.append(line(gx, y0 + FLOOR * 0.75, gx + rng.uniform(-5, 5), y0 + FLOOR - 5, rng, width=6,
                                 ink=wall_dark))
    save(name, svg(w, h, "".join(body), bg=wall), OUT_TEX, scale=0.5)


def _window(x, y, w, h, rng, curtains, door=False, wide=False):
    out = [shape(rect_pts(x - 12, y - 12, w + 24, h + 24), "#f7f4ec", rng, width=5)]
    out.append(shape(rect_pts(x, y, w, h), "#3d5f8f", rng, width=5))
    # reflection
    out.append(shape([(x + w * 0.15, y + h * 0.9), (x + w * 0.55, y + h * 0.1), (x + w * 0.72, y + h * 0.1),
                      (x + w * 0.32, y + h * 0.9)], "#6f93c4", rng, width=0))
    if rng.random() < 0.55:
        c = rng.choice(curtains)
        out.append(shape([(x + 4, y + 4), (x + w * 0.32, y + 4), (x + w * 0.18, y + h - 4), (x + 4, y + h - 4)], c, rng,
                         width=4))
    if not door:
        out.append(line(x + w / 2, y, x + w / 2, y + h, rng, width=5))
        if not wide:
            out.append(line(x, y + h * 0.35, x + w, y + h * 0.35, rng, width=4))
    return "".join(out)


def entrance(name="facade_entrance", wall="#a8d8b9", wall_dark="#8cc0a0"):
    """Ground floor stairwell entrance bay, used as a decal."""
    rng = random.Random(3)
    w, h = BAY, FLOOR
    body = [shape(rect_pts(60, 110, 290, 250), wall_dark, rng, width=0),
            shape(rect_pts(30, 70, 350, 40), "#e2504c", rng, width=6),           # canopy
            shape(rect_pts(110, 130, 190, 230), "#7a4b2f", rng, width=6),         # door
            shape(rect_pts(130, 150, 70, 120), "#3d5f8f", rng, width=4),
            shape(rect_pts(210, 150, 70, 120), "#3d5f8f", rng, width=4),
            '<circle cx="270" cy="300" r="7" fill="#f6d55c" stroke="%s" stroke-width="3"/>' % INK,
            shape(rect_pts(150, 20, 110, 36), "#fbfbf6", rng, width=4)]           # block number plate
    body.append('<text x="205" y="48" font-family="Arial Black,Arial" font-weight="900" font-size="28" '
                'text-anchor="middle" fill="%s">B7</text>' % INK)
    save(name, svg(w, h, "".join(body)), OUT_TEX, scale=0.5)


# ----------------------------------------------------------------------------
# Ground textures (tile seamlessly: every mark is drawn with wrap copies)
# ----------------------------------------------------------------------------
def _wrapped(w, h, draw):
    out = []
    for dx in (-w, 0, w):
        for dy in (-h, 0, h):
            out.append('<g transform="translate(%d,%d)">%s</g>' % (dx, dy, draw))
    return "".join(out)


def grass(name="grass", size=1024, seed=11):
    rng = random.Random(seed)
    marks = []
    for _ in range(26):   # lighter patches
        marks.append(shape(blob(rng.uniform(0, size), rng.uniform(0, size), rng.uniform(40, 90), rng, 6, 0.2),
                           "#a9d466", rng, width=0))
    for _ in range(70):   # tufts
        x, y = rng.uniform(0, size), rng.uniform(0, size)
        for k in (-1, 0, 1):
            marks.append(line(x, y, x + k * 9 + rng.uniform(-3, 3), y - rng.uniform(16, 26), rng, width=3.5,
                              ink="#5d9a3a", amp=0.3))
    for _ in range(10):   # daisies
        x, y = rng.uniform(0, size), rng.uniform(0, size)
        marks.append('<circle cx="%.0f" cy="%.0f" r="6" fill="#ffffff" stroke="%s" stroke-width="2"/>' % (x, y, INK))
    save(name, svg(size, size, _wrapped(size, size, "".join(marks)), bg="#97c95a"), OUT_TEX)


def asphalt(name="asphalt", size=1024, seed=12):
    rng = random.Random(seed)
    marks = []
    for _ in range(300):
        marks.append('<circle cx="%.0f" cy="%.0f" r="%.1f" fill="%s"/>' % (
            rng.uniform(0, size), rng.uniform(0, size), rng.uniform(1.5, 4), rng.choice(["#555c68", "#6e7581"])))
    for _ in range(5):    # cracks
        x, y = rng.uniform(0, size), rng.uniform(0, size)
        pts = [(x, y)]
        for _ in range(5):
            x += rng.uniform(-40, 40)
            y += rng.uniform(15, 45)
            pts.append((x, y))
        marks.append('<path d="%s" fill="none" stroke="#3c414b" stroke-width="3" stroke-linecap="round"/>' %
                     path_d(pts, False))
    for _ in range(3):    # patches
        x, y = rng.uniform(0, size), rng.uniform(0, size)
        marks.append(shape(rect_pts(x, y, rng.uniform(80, 160), rng.uniform(60, 120)), "#535a66", rng,
                           ink="#454b56", width=3))
    save(name, svg(size, size, _wrapped(size, size, "".join(marks)), bg="#5f6673"), OUT_TEX)


def pavement(name="pavement", size=1024, seed=13):
    rng = random.Random(seed)
    tile = size / 4            # 4 slabs per texture
    marks = []
    for i in range(4):
        for j in range(4):
            c = rng.choice(["#dcd5c6", "#d6cebd", "#e2dccf"])
            marks.append(shape(rect_pts(i * tile + 4, j * tile + 4, tile - 8, tile - 8), c, rng, ink="#b8ae9a",
                               width=4, amp=0.8))
            if rng.random() < 0.15:
                marks.append(line(i * tile + 20, j * tile + 30, i * tile + 120, j * tile + 140, rng, width=2.5,
                                  ink="#a69c88"))
    save(name, svg(size, size, "".join(marks), bg="#c9c0ad"), OUT_TEX)


def roof(name="roof", size=512, seed=14):
    rng = random.Random(seed)
    marks = []
    for _ in range(220):
        marks.append('<circle cx="%.0f" cy="%.0f" r="%.1f" fill="%s"/>' % (
            rng.uniform(0, size), rng.uniform(0, size), rng.uniform(1.5, 3.5), rng.choice(["#7d7a76", "#9d9a95"])))
    for _ in range(3):
        x, y = rng.uniform(0, size), rng.uniform(0, size)
        marks.append(shape(blob(x, y, rng.uniform(30, 60), rng, 5, 0.3), "#86837f", rng, width=0))
    save(name, svg(size, size, _wrapped(size, size, "".join(marks)), bg="#8e8b87"), OUT_TEX)


BLOCK_WALLS = {   # name: (wall, shade)
    "mint": ("#a8d8b9", "#8fc4a3"),
    "peach": ("#f4b183", "#e19a6b"),
    "lemon": ("#f7d774", "#e6c25c"),
    "sky": ("#9ec9e2", "#86b4cf"),
    "cream": ("#f2e3b3", "#ddcd99"),
    "lilac": ("#c9b6e4", "#b39fd0"),
}

if __name__ == "__main__":
    tree_round("tree_round_a", 1, "#4fa843", "#3a8a37", "#79c95a")
    tree_round("tree_round_b", 2, "#6cbf48", "#4f9f3a", "#97d86a")
    tree_round("tree_round_c", 3, "#3e8e3e", "#2f7433", "#5fae4f")
    tree_poplar("tree_poplar", 4)
    bush("bush_a", 5)
    bush("bush_b", 6)
    lamp()
    bench()
    for i, (n, (wall, dark)) in enumerate(BLOCK_WALLS.items()):
        facade("facade_" + n, wall, dark, 100 + i)
    entrance()
    grass()
    asphalt()
    pavement()
    roof()
    print("art written to", os.path.join(ROOT, "game", "art"))
