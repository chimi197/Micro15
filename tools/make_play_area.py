"""Work out the playable area of the Micro 15 level from the corner pins.

The four pins noted "CORNER 1" to "CORNER 4" (placed with the map editor's
Pins tool, levels/micro15/pins.json) mark the corners. Each side is pushed
out just far enough to take in the main roads the corners stand beside
(their carriageway and sidewalks), plus a small margin, so the cut never
runs down the middle of one of them. Writes levels/micro15/play_area.json:

    {"corners": [[x, z], ...],   the pins
     "polygon": [[x, z], ...]}   the playable area (Godot x, z in metres)

blender/build_map.py cuts the map to the polygon, tools/make_grass_mask.py
keeps grass inside it and scripts/boundary.gd walls it in.

    python tools/make_play_area.py
"""
import json
import math
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LEVEL = os.path.join(ROOT, "game", "levels", "micro15")
LAT0, LON0 = 47.7816296, 22.8595870
KX = math.cos(math.radians(LAT0)) * 111320.0
KY = 110540.0
MAP_CENTRE = (140.0, 205.0)                    # build_map.MAP_CENTRE
CORRIDOR = {  # highway: road plus both sidewalks, metres (make_grass_mask.ROADS)
    "primary": 19, "primary_link": 11, "secondary": 17, "tertiary": 14, "residential": 11,
    "living_street": 8.5, "unclassified": 9,
}
NEAR_PIN = 16.0        # a road this close to a corner pin is one it stands beside
PARALLEL = 35.0        # degrees: road stretches roughly along a side push it out
MARGIN = 4.0           # metres beyond the outermost sidewalk


def corner_pins():
    pins = json.load(open(os.path.join(LEVEL, "pins.json"), encoding="utf-8"))
    corners = {}
    for p in pins:
        m = re.match(r"\s*corner\s*(\d)", p.get("note", ""), re.I)
        if m:
            corners[int(m.group(1))] = (p["x"], p["z"])
    if sorted(corners) != [1, 2, 3, 4]:
        raise SystemExit("pins.json needs pins noted CORNER 1 to CORNER 4, found %s" % sorted(corners))
    return [corners[i] for i in (1, 2, 3, 4)]


def roads():
    """[(points in Godot x, z, half corridor width)] of the drivable roads."""
    d = json.load(open(os.path.join(ROOT, "reference", "micro15_osm.json"), encoding="utf-8"))
    nodes = {e["id"]: ((e["lon"] - LON0) * KX - MAP_CENTRE[0], -((e["lat"] - LAT0) * KY - MAP_CENTRE[1]))
             for e in d["elements"] if e["type"] == "node" and "lat" in e}
    out = []
    for e in d["elements"]:
        hw = e.get("tags", {}).get("highway") if e["type"] == "way" else None
        if hw in CORRIDOR:
            pts = [nodes[i] for i in e["nodes"] if i in nodes]
            if len(pts) > 1:
                out.append((pts, CORRIDOR[hw] / 2.0, e["tags"]))
    return out


def seg_dist(p, a, b):
    sx, sz = b[0] - a[0], b[1] - a[1]
    t = max(0.0, min(1.0, ((p[0] - a[0]) * sx + (p[1] - a[1]) * sz) / (sx * sx + sz * sz or 1e-9)))
    return math.hypot(p[0] - a[0] - sx * t, p[1] - a[1] - sz * t)


def main():
    C = corner_pins()
    cx, cz = sum(p[0] for p in C) / 4, sum(p[1] for p in C) / 4
    all_roads = roads()
    # the roads the corners stand beside: by name, so the whole street counts,
    # and roundabouts next to a corner
    names = set()
    beside = []
    for pts, half, tags in all_roads:
        if min(seg_dist(c, a, b) for c in C for a, b in zip(pts, pts[1:])) <= NEAR_PIN:
            if tags.get("junction") == "roundabout":
                beside.append((pts, half, True))
            elif tags.get("name"):
                names.add(tags["name"])
    beside += [(pts, half, False) for pts, half, tags in all_roads if tags.get("name") in names]

    lines = []          # (point, direction, outward normal) of each pushed-out side
    for i in range(4):
        a, b = C[i], C[(i + 1) % 4]
        L = math.hypot(b[0] - a[0], b[1] - a[1])
        u = ((b[0] - a[0]) / L, (b[1] - a[1]) / L)
        n = (u[1], -u[0])
        if (cx - a[0]) * n[0] + (cz - a[1]) * n[1] > 0:
            n = (-n[0], -n[1])
        reach = 0.0
        for pts, half, roundabout in beside:
            for p, q in zip(pts, pts[1:]):
                sx, sz = q[0] - p[0], q[1] - p[1]
                sl = math.hypot(sx, sz)
                if sl < 1e-6:
                    continue
                if not roundabout and abs((sx * u[0] + sz * u[1]) / sl) < math.cos(math.radians(PARALLEL)):
                    continue
                for k in range(int(sl) + 1):
                    x, z = p[0] + sx * k / sl, p[1] + sz * k / sl
                    along = (x - a[0]) * u[0] + (z - a[1]) * u[1]
                    off = (x - a[0]) * n[0] + (z - a[1]) * n[1]
                    if -30.0 <= along <= L + 30.0 and -60.0 < off < 40.0:
                        reach = max(reach, off + half)
        push = reach + MARGIN
        lines.append(((a[0] + n[0] * push, a[1] + n[1] * push), u))
        print("side %d-%d pushed out %.1f m" % (i + 1, (i + 1) % 4 + 1, push))

    poly = []
    for i in range(4):               # corner i is where side i-1 meets side i
        (p, u), (q, v) = lines[i - 1], lines[i]
        det = u[0] * v[1] - u[1] * v[0]
        t = ((q[0] - p[0]) * v[1] - (q[1] - p[1]) * v[0]) / det
        poly.append([round(p[0] + u[0] * t, 2), round(p[1] + u[1] * t, 2)])
    out = {"corners": [[round(x, 2), round(z, 2)] for x, z in C], "polygon": poly,
           "roads": sorted(names)}
    path = os.path.join(LEVEL, "play_area.json")
    json.dump(out, open(path, "w"), indent=1)
    print(path, poly)


if __name__ == "__main__":
    main()
