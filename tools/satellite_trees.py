"""Compares the tree cover of the game's Micro 15 with the real one seen
from above, and plants the missing trees where the real canopy is.

The satellite picture is not in the repository (its licence does not allow
it); it is in reference/satellite/ on Johnny's PC, made by the research step
(see reference/micro15_observations.md). Run from the repository root:

    python tools/satellite_trees.py                 # report only
    python tools/satellite_trees.py --apply         # add the trees to props.json
    python tools/satellite_trees.py --apply --png out.png
    python tools/satellite_trees.py --remove        # take them all out again

How: the picture is resampled onto the game's metre grid (x east, z south;
the same projection as blender/build_world.py). Canopy is the darker,
green-dominant part of it. The game's canopy is the crowns of every tree in
props.json and placed.tscn (crown radius by model and scale). Real canopy
the game lacks, away from buildings, roads and paths and inside the play
area, gets trees: tree_a / tree_b / tree_c spaced like a courtyard's.

The trees it adds are listed in game/levels/micro15/props_satellite.json;
running --apply again takes those out first, so it can be re-run safely.
The map editor treats them like any other tree (remove, move).
"""
import argparse
import json
import math
import os
import re

import numpy as np
from PIL import Image

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
LEVEL = os.path.join(ROOT, "game", "levels", "micro15")
LAT0, LON0 = 47.7816296, 22.8595870
KX = math.cos(math.radians(LAT0)) * 111320.0
KY = 110540.0
CELL = 1.0
CROWN = {"tree_a": 3.9, "tree_b": 4.8, "tree_c": 2.9, "poplar": 1.35, "tree_birch": 2.5, "tree_pine": 2.4}
ROAD_HALF = {"primary": 7.5, "primary_link": 4.0, "secondary": 6.0, "tertiary": 5.0, "residential": 3.5,
             "living_street": 3.0, "service": 2.5}


def merc(lat):
    return np.log(np.tan(np.pi / 4 + np.radians(lat) / 2))


def inside(poly, x, z):
    """Point-in-polygon for grids (even-odd)."""
    res = np.zeros(x.shape, bool)
    n = len(poly)
    for i in range(n):
        x1, z1 = poly[i]
        x2, z2 = poly[(i + 1) % n]
        cond = ((z1 > z) != (z2 > z)) & (x < (x2 - x1) * (z - z1) / (z2 - z1 + 1e-12) + x1)
        res ^= cond
    return res


def stamp_disc(mask, gx, gz, cx, cz, r):
    i0, i1 = np.searchsorted(gx, cx - r), np.searchsorted(gx, cx + r)
    j0, j1 = np.searchsorted(gz, cz - r), np.searchsorted(gz, cz + r)
    if i1 <= i0 or j1 <= j0:
        return
    xx, zz = np.meshgrid(gx[i0:i1], gz[j0:j1])
    mask[j0:j1, i0:i1] |= (xx - cx) ** 2 + (zz - cz) ** 2 <= r * r


def stamp_segment(mask, gx, gz, a, b, half):
    lo_x, hi_x = min(a[0], b[0]) - half, max(a[0], b[0]) + half
    lo_z, hi_z = min(a[1], b[1]) - half, max(a[1], b[1]) + half
    i0, i1 = np.searchsorted(gx, lo_x), np.searchsorted(gx, hi_x)
    j0, j1 = np.searchsorted(gz, lo_z), np.searchsorted(gz, hi_z)
    if i1 <= i0 or j1 <= j0:
        return
    xx, zz = np.meshgrid(gx[i0:i1], gz[j0:j1])
    ax, az = a
    dx, dz = b[0] - ax, b[1] - az
    L = dx * dx + dz * dz + 1e-9
    t = np.clip(((xx - ax) * dx + (zz - az) * dz) / L, 0, 1)
    d2 = (xx - ax - t * dx) ** 2 + (zz - az - t * dz) ** 2
    mask[j0:j1, i0:i1] |= d2 <= half * half


def box_blur(a, k):
    p = np.pad(a, k // 2, mode="edge")
    c = np.cumsum(np.cumsum(p, 0), 1)
    c = np.pad(c, ((1, 0), (1, 0)))
    return (c[k:, k:] - c[:-k, k:] - c[k:, :-k] + c[:-k, :-k]) / (k * k)


def placed_trees():
    """[proto, x, z, scale] of the trees placed with the map editor."""
    path = os.path.join(LEVEL, "placed.tscn")
    if not os.path.exists(path):
        return []
    s = open(path, encoding="utf-8").read()
    ext = {i: p for p, i in re.findall(r'\[ext_resource [^\]]*path="([^"]+)" id="([^"]+)"\]', s)}
    out = []
    for res_id, xf in re.findall(r'instance=ExtResource\("([^"]+)"\)\]\ntransform = Transform3D\(([^)]*)\)', s):
        proto = os.path.basename(ext.get(res_id, "")).replace(".tscn", "")
        if proto in CROWN:
            v = [float(t) for t in xf.split(",")]
            sc = math.sqrt(v[0] ** 2 + v[3] ** 2 + v[6] ** 2)
            out.append([proto, v[9], v[11], sc])
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--satellite", default=os.path.join(ROOT, "reference", "satellite", "micro15_z18.png"))
    ap.add_argument("--bounds", default=os.path.join(ROOT, "reference", "satellite", "bounds.json"))
    ap.add_argument("--apply", action="store_true", help="write the new trees into props.json")
    ap.add_argument("--remove", action="store_true", help="take the trees this tool added out again")
    ap.add_argument("--png", default="", help="save a comparison picture here")
    ap.add_argument("--spacing", type=float, default=9.0, help="metres between added trees")
    ap.add_argument("--scale", type=float, nargs=2, default=[1.05, 1.35],
                    help="size range of added trees (real yard crowns are 10-15 m across)")
    args = ap.parse_args()

    img = np.asarray(Image.open(args.satellite).convert("RGB")).astype(np.float32)
    H, W, _ = img.shape
    b = json.load(open(args.bounds))
    m_n, m_s = merc(b["north"]), merc(b["south"])
    area = json.load(open(os.path.join(LEVEL, "play_area.json")))["corners"]
    xs = [p[0] for p in area]
    zs = [p[1] for p in area]
    gx = np.arange(min(xs), max(xs), CELL)
    gz = np.arange(min(zs), max(zs), CELL)
    X, Z = np.meshgrid(gx, gz)
    u = ((LON0 + X / KX) - b["west"]) / (b["east"] - b["west"]) * W
    v = (m_n - merc(LAT0 - Z / KY)) / (m_n - m_s) * H
    seen = (u >= 0) & (u < W - 1) & (v >= 0) & (v < H - 1)
    ui = np.clip(u.astype(int), 0, W - 1)
    vi = np.clip(v.astype(int), 0, H - 1)
    blur = [box_blur(img[..., c], 5) for c in range(3)]
    R, G, B = (c[vi, ui] for c in blur)
    lum = (R + G + B) / 3.0
    canopy = (G > R * 1.03) & (G > B * 1.02) & (lum < 92) & seen
    play = inside(area, X, Z) & seen

    # the game's canopy
    props = json.load(open(os.path.join(LEVEL, "props.json")))
    sidecar_path = os.path.join(LEVEL, "props_satellite.json")
    previous = json.load(open(sidecar_path)) if os.path.exists(sidecar_path) else {}
    prev_keys = {(p, round(e[0], 2), round(e[1], 2)) for p, lst in previous.items() for e in lst}
    removed = json.load(open(os.path.join(LEVEL, "removed_props.json")))
    gone = {(p, round(e[0], 2), round(e[1], 2)) for p, lst in removed.items() for e in lst}
    game = np.zeros_like(canopy)
    trees = 0
    for proto, lst in props.items():
        if proto not in CROWN:
            continue
        for e in lst:
            key = (proto, round(e[0], 2), round(e[1], 2))
            if key in gone or key in prev_keys:
                continue
            stamp_disc(game, gx, gz, e[0], e[1], CROWN[proto] * e[3])
            trees += 1
    for proto, x, z, sc in placed_trees():
        stamp_disc(game, gx, gz, x, z, CROWN[proto] * sc)
        trees += 1

    # where trunks may not go
    blocked = np.zeros_like(canopy)
    for ring in json.load(open(os.path.join(LEVEL, "footprints.json"))).values():
        for i in range(len(ring)):
            stamp_segment(blocked, gx, gz, ring[i], ring[(i + 1) % len(ring)], 2.0)
        poly = np.array(ring)
        if (poly[:, 0].max() >= gx[0]) and (poly[:, 0].min() <= gx[-1]):
            blocked |= inside(ring, X, Z)
    osm = json.load(open(os.path.join(ROOT, "reference", "micro15_osm.json")))["elements"]
    nodes = {e["id"]: ((e["lon"] - LON0) * KX, -(e["lat"] - LAT0) * KY) for e in osm if e["type"] == "node"}
    for w in osm:
        hw = w.get("tags", {}).get("highway")
        if w["type"] != "way" or hw not in ROAD_HALF:
            continue
        pts = [nodes[n] for n in w["nodes"] if n in nodes]
        for a, c in zip(pts, pts[1:]):
            stamp_segment(blocked, gx, gz, a, c, ROAD_HALF[hw] + 1.0)
    for p in json.load(open(os.path.join(LEVEL, "paths.json"))):
        pts = p["points"]
        for a, c in zip(pts, pts[1:]):
            stamp_segment(blocked, gx, gz, a, c, p.get("width", 1.5) / 2 + 1.0)

    real = canopy & play
    have = game & play
    n_play = play.sum()
    print("play area seen from above: %.0f m2" % (n_play * CELL * CELL))
    print("real tree canopy: %.1f %% of it" % (100.0 * real.sum() / n_play))
    print("game tree canopy: %.1f %% (%d trees)" % (100.0 * have.sum() / n_play, trees))
    print("real canopy the game has too: %.1f %%" % (100.0 * (real & have).sum() / max(real.sum(), 1)))

    # plant the missing canopy
    missing = real & ~game & ~blocked
    rng = np.random.default_rng(15)
    added = {"tree_a": [], "tree_b": [], "tree_c": []}
    cover = game.copy()
    cand = np.argwhere(missing)
    rng.shuffle(cand)
    taken = []
    sp2 = args.spacing ** 2
    for j, i in cand:
        x, z = gx[i] + rng.uniform(-0.4, 0.4), gz[j] + rng.uniform(-0.4, 0.4)
        if cover[j, i]:
            continue
        if any((x - a) ** 2 + (z - c) ** 2 < sp2 for a, c in taken[-400:]):
            continue
        # most of a 3 m disc round it must be real canopy the game lacks
        r = 3
        win = missing[max(0, j - r):j + r + 1, max(0, i - r):i + r + 1]
        if win.mean() < 0.55:
            continue
        proto = rng.choice(["tree_a", "tree_b", "tree_c"], p=[0.4, 0.4, 0.2])
        sc = float(rng.uniform(*args.scale))
        added[proto].append([round(float(x), 2), round(float(z), 2), round(float(rng.uniform(0, 2 * math.pi)), 3),
                             round(sc, 2)])
        taken.append((x, z))
        stamp_disc(cover, gx, gz, x, z, CROWN[proto] * sc)
    total = sum(len(v) for v in added.values())
    after = cover & play
    print("trees to add: %d -> game canopy %.1f %%, real canopy covered %.1f %%" % (
        total, 100.0 * after.sum() / n_play, 100.0 * (real & after).sum() / max(real.sum(), 1)))

    if args.png:
        pic = np.zeros(canopy.shape + (3,), np.uint8) + 40
        pic[play] = (70, 70, 70)
        pic[blocked & play] = (110, 110, 120)
        pic[real] = (40, 140, 60)
        pic[have & ~real] = (60, 90, 170)
        pic[have & real] = (120, 200, 120)
        pic[(cover & ~game) & play] = (220, 120, 60)
        Image.fromarray(pic).resize((pic.shape[1] * 2, pic.shape[0] * 2), Image.NEAREST).save(args.png)
        print("picture:", args.png, "(green real canopy, light green both, blue game only, orange added)")

    if args.remove:
        added = {}
        args.apply = True
    if args.apply:
        for proto, lst in props.items():
            if proto in previous:
                keys = {(round(e[0], 2), round(e[1], 2)) for e in previous[proto]}
                props[proto] = [e for e in lst if (round(e[0], 2), round(e[1], 2)) not in keys]
        for proto, lst in added.items():
            props.setdefault(proto, []).extend(lst)
        with open(os.path.join(LEVEL, "props.json"), "w") as f:
            json.dump(props, f, separators=(",", ":"))
        with open(sidecar_path, "w") as f:
            json.dump(added, f, indent=1)
        print("wrote props.json and props_satellite.json")


if __name__ == "__main__":
    main()
