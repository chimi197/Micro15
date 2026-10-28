"""Rasterise where 3D grass may grow in a Godot level.

White = lawn, black = buildings, roads, sidewalks, paths, parking, sand,
and everything outside the level's play_area.json if it has one.
Pixel (0, 0) is the north-west corner; 1 px = 0.5 m; the image covers a
square of SIZE metres centred on the level's Godot origin.

    python tools/make_grass_mask.py            # whole map (levels/micro15)
    python tools/make_grass_mask.py corner     # 3D corner test (levels/corner)
"""
import json
import math
import os

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LAT0, LON0 = 47.7816296, 22.8595870
KX = math.cos(math.radians(LAT0)) * 111320.0
KY = 110540.0
LEVELS = {  # level: (centre in OSM metres, size in metres)
    "micro15": ((140.0, 205.0), 1280.0),      # build_map.MAP_CENTRE
    "corner": ((250.0, 560.0), 350.0),        # build_corner_3d.CENTRE
}
RES = 0.5
ROADS = {  # highway: corridor width in metres (road + both sidewalks)
    "primary": 19, "primary_link": 11, "secondary": 17, "tertiary": 14, "residential": 11,
    "living_street": 8.5, "unclassified": 9, "service": 4.5, "footway": 2.2, "pedestrian": 4,
    "path": 1.8, "cycleway": 2, "steps": 2,
}


def main(level="micro15"):
    CENTRE, SIZE = LEVELS[level]
    d = json.load(open(os.path.join(ROOT, "reference", "micro15_osm.json"), encoding="utf-8"))
    nodes = {e["id"]: ((e["lon"] - LON0) * KX, (e["lat"] - LAT0) * KY)
             for e in d["elements"] if e["type"] == "node" and "lat" in e}
    n = int(SIZE / RES)
    img = Image.new("L", (n, n), 255)
    dr = ImageDraw.Draw(img)

    def px(p):
        x = (p[0] - CENTRE[0] + SIZE / 2) / RES
        y = (SIZE / 2 - (p[1] - CENTRE[1])) / RES
        return (x, y)

    for e in d["elements"]:
        if e["type"] != "way":
            continue
        t = e.get("tags", {})
        pts = [px(nodes[i]) for i in e["nodes"] if i in nodes]
        if len(pts) < 2:
            continue
        if "building" in t:
            dr.polygon(pts, fill=0, outline=0, width=int(1.5 / RES))
        elif t.get("amenity") in ("parking", "fuel") or t.get("leisure") in ("playground", "pitch") \
                or t.get("amenity") == "kindergarten":
            dr.polygon(pts, fill=0)
        elif t.get("highway") in ROADS and t.get("area") != "yes":
            w = max(1, int((ROADS[t["highway"]] + 0.6) / RES))
            dr.line(pts, fill=0, width=w, joint="curve")
            r = w / 2
            for x, y in (pts[0], pts[-1]):
                dr.ellipse((x - r, y - r, x + r, y + r), fill=0)
    # nothing grows outside the playable area (tools/make_play_area.py)
    area = os.path.join(ROOT, "game", "levels", level, "play_area.json")
    if os.path.exists(area):
        poly = [px((x + CENTRE[0], CENTRE[1] - z)) for x, z in json.load(open(area))["polygon"]]
        keep = Image.new("L", (n, n), 0)
        ImageDraw.Draw(keep).polygon(poly, fill=255)
        img.paste(0, mask=Image.eval(keep, lambda v: 255 - v))
    out = os.path.join(ROOT, "game", "levels", level, "grass_mask.png")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    img.save(out)
    print(out, img.size)


if __name__ == "__main__":
    import sys
    main(*sys.argv[1:2])
