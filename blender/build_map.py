"""Whole Micro 15 map for Godot, in full 3D.

Buildings are exported as light "shells" (walls, plinth, roof, parapet,
roofs of houses and churches) and every repeated detail (windows, balcony
doors, balconies, entrances, AC units, satellite dishes, drainpipes, roof
huts, antennas, basement vents, shop fronts, garage doors) is exported once
as a prototype and placed many times. Godot draws each detail type with a
MultiMesh, which keeps a 340-building neighbourhood fast and small on disk.

Writes into game/levels/micro15/:
    buildings.glb   building shells (one mesh per building)
    ground.glb      lawn base, land use areas, roads, sidewalks, paths
    details.glb     building detail prototypes (local frame: width along X,
                    outward along -Y, up Z, origin on the wall at the bottom)
    props.glb       trees, poplars, bushes (each also as a lighter "_far"
                    version for distance), lamps, benches
    details.json    {prototype: [[x, y, z, yaw, sx, sy, sz, r, g, b], ...]}
    props.json      {prop: [[x, z, yaw, scale], ...]}
    footprints.json {building: [[x, z], ...]}
All positions are in Godot space (x, up, z = -north), centred on MAP_CENTRE.

The whole neighbourhood is built, so the streets carry on past the edge of
the playable area (levels/micro15/play_area.json, from the map editor's
corner pins; scripts/boundary.gd stops the player there). Inside the area
the ground is cut into 32 m chunks named g_<i>_<j> (chunk i, j covers
x 32i..32i+32, z 32j..32j+32) and diced into 2 m cells split along their
x - z diagonal, so the map editor's terrain tool (scripts/terrain.gd) can
raise and lower it smoothly; the rest is "ground_outer". footprints.json
lists every building's outline ({"bld_<id>": [[x, z], ...]}), so the
terrain stays flat under the buildings.

    import sys; sys.path.insert(0, r"<repo>/blender")
    import build_map; build_map.run(r"<repo>")
"""
import bmesh
import bpy
import json
import math
import os
import random
from mathutils import Matrix, Vector

import build_world as bw
import build_corner_3d as c3
from build_corner_3d import Builder, Wall, UP

MAP_CENTRE = (140.0, 205.0)
FLOOR = 2.8
PLINTH = 1.0

HOUSE_WALLS = ["#f6e7c1", "#f2c59a", "#e8f0d0", "#f5d5d5", "#d6e8f2", "#fbe9a0", "#ffffff"]
GLASS_TINTS = [(1.0, 1.0, 1.0), (1.12, 1.1, 1.05), (0.85, 0.88, 0.95), (1.0, 1.05, 1.15)]
CURTAINS = [(0.95, 0.55, 0.51), (0.96, 0.76, 0.42), (0.98, 0.98, 0.96), (0.62, 0.83, 0.91), (0.78, 0.64, 0.88)]


def play_area(root):
    """The playable area as an OSM-metre polygon, or None for the whole map."""
    path = os.path.join(root, "game", "levels", "micro15", "play_area.json")
    if not os.path.exists(path):
        return None
    poly = json.load(open(path))["polygon"]
    return [(x + MAP_CENTRE[0], MAP_CENTRE[1] - z) for x, z in poly]


def to_game(x, y):
    return x - MAP_CENTRE[0], -(y - MAP_CENTRE[1])


def _bisect(bm, co, no, clear_outer=False, clear_inner=False):
    geom = list(bm.verts) + list(bm.edges) + list(bm.faces)
    bmesh.ops.bisect_plane(bm, geom=geom, dist=0.0005, plane_co=Vector(co), plane_no=Vector(no),
                           clear_outer=clear_outer, clear_inner=clear_inner)


def _edges_out(poly):
    """[(point, outward normal)] of a convex polygon's edges (OSM metres)."""
    cx = sum(p[0] for p in poly) / len(poly)
    cy = sum(p[1] for p in poly) / len(poly)
    out = []
    for (ax, ay), (bx, by) in zip(poly, poly[1:] + poly[:1]):
        n = Vector((by - ay, -(bx - ax), 0)).normalized()
        if n.dot(Vector((cx - ax, cy - ay, 0))) > 0:
            n = -n
        out.append(((ax, ay, 0), n))
    return out


def _copy_faces(src, faces):
    """A new bmesh holding copies of some faces of src (materials, smooth, UVs)."""
    dst = bmesh.new()
    vmap = {}
    s_uv = src.loops.layers.uv.active
    d_uv = dst.loops.layers.uv.verify() if s_uv else None
    for f in faces:
        vs = []
        for v in f.verts:
            if v not in vmap:
                vmap[v] = dst.verts.new(v.co)
            vs.append(vmap[v])
        try:
            nf = dst.faces.new(vs)
        except ValueError:
            continue
        nf.material_index = f.material_index
        nf.smooth = f.smooth
        if s_uv:
            for a, b in zip(f.loops, nf.loops):
                b[d_uv].uv = a[s_uv].uv
    return dst


def split_ground(objs, poly, col, chunk=32.0, cell=2.0):
    """Joins the ground objects into "ground_outer" (outside the polygon)
    and diced chunks g_<i>_<j> inside it (see the module docstring)."""
    mats = []
    big = bmesh.new()
    for ob in objs:
        offset = len(big.faces)
        me = ob.data
        idx = []
        for m in me.materials:
            if m not in mats:
                mats.append(m)
            idx.append(mats.index(m))
        tmp = bmesh.new()
        tmp.from_mesh(me)
        for f in tmp.faces:
            f.material_index = idx[f.material_index] if idx else 0
        part = _copy_faces(tmp, list(tmp.faces))
        tmp.free()
        tmp_me = bpy.data.meshes.new("tmp")
        part.to_mesh(tmp_me)
        part.free()
        big.from_mesh(tmp_me)
        bpy.data.meshes.remove(tmp_me)
    for ob in objs:
        bpy.data.objects.remove(ob, do_unlink=True)

    def make(name, bm):
        me = bpy.data.meshes.new(name)
        bm.to_mesh(me)
        bm.free()
        for m in mats:
            me.materials.append(m)
        ob = bpy.data.objects.new(name, me)
        col.objects.link(ob)
        return ob

    edges = _edges_out(poly)
    # outside: for edge i, the part beyond edge i and inside every edge before it
    outer = bmesh.new()
    for i, (co, n) in enumerate(edges):
        bm = big.copy()
        _bisect(bm, co, n, clear_inner=True)
        for co2, n2 in edges[:i]:
            _bisect(bm, co2, n2, clear_outer=True)
        tmp_me = bpy.data.meshes.new("tmp")
        bm.to_mesh(tmp_me)
        bm.free()
        outer.from_mesh(tmp_me)
        bpy.data.meshes.remove(tmp_me)
    make("ground_outer", outer)
    inner = big
    for co, n in edges:
        _bisect(inner, co, n, clear_outer=True)
    # chunks, in game coordinates (x east, z south)
    xs = [to_game(*p)[0] for p in poly]
    zs = [to_game(*p)[1] for p in poly]
    for i in range(math.floor(min(xs) / chunk) + 1, math.ceil(max(xs) / chunk)):
        _bisect(inner, (i * chunk + MAP_CENTRE[0], 0, 0), (1, 0, 0))
    for j in range(math.floor(min(zs) / chunk) + 1, math.ceil(max(zs) / chunk)):
        _bisect(inner, (0, MAP_CENTRE[1] - j * chunk, 0), (0, 1, 0))
    groups = {}
    for f in inner.faces:
        c = f.calc_center_median()
        gx, gz = to_game(c.x, c.y)
        groups.setdefault((math.floor(gx / chunk), math.floor(gz / chunk)), []).append(f)
    n = 0
    k = int(round(chunk / cell))
    for (i, j), faces in sorted(groups.items()):
        bm = _copy_faces(inner, faces)
        x0, z0 = i * chunk, j * chunk
        for a in range(1, k):
            _bisect(bm, (x0 + a * cell + MAP_CENTRE[0], 0, 0), (1, 0, 0))
            _bisect(bm, (0, MAP_CENTRE[1] - (z0 + a * cell), 0), (0, 1, 0))
        # diagonals x - z = const, i.e. in OSM metres x + y = const
        for a in range(-k + 1, k):
            gx, gz = x0 + a * cell, z0                  # a point on the line x - z = x0 - z0 + a*cell
            _bisect(bm, (gx + MAP_CENTRE[0], MAP_CENTRE[1] - gz, 0), (1, 1, 0))
        bmesh.ops.triangulate(bm, faces=list(bm.faces))
        make("g_%d_%d" % (i, j), bm)
        n += 1
    inner.free()
    return n


class Details:
    """Collects placements of detail prototypes."""

    def __init__(self):
        self.items = {}

    def add(self, proto, w, u, z, out=0.0, sx=1.0, sy=1.0, sz=1.0, rgb=(1.0, 1.0, 1.0)):
        p = w.p(u, z, out)
        self.put(proto, p, math.atan2(w.d.y, w.d.x), sx, sy, sz, rgb)

    def put(self, proto, p, yaw, sx=1.0, sy=1.0, sz=1.0, rgb=(1.0, 1.0, 1.0)):
        gx, gy, gz = p.x - MAP_CENTRE[0], p.z, -(p.y - MAP_CENTRE[1])
        # Blender local (X width, Y depth, Z up) -> Godot local (X, Y up, Z depth)
        self.items.setdefault(proto, []).append(
            [round(gx, 3), round(gy, 3), round(gz, 3), round(yaw, 4), round(sx, 3), round(sz, 3), round(sy, 3),
             round(rgb[0], 3), round(rgb[1], 3), round(rgb[2], 3)])


# ----------------------------------------------------------------------------
# Building shells + detail placement
# ----------------------------------------------------------------------------
def roof_with_parapet(B, ring, H, m_cap, m_roof, m_inner):
    tops = [B.bm.verts.new((x, y, H)) for x, y in ring]
    roof = B.bm.faces.new(tops)
    roof.material_index = m_cap
    roof.normal_update()
    if roof.normal.z < 0:
        roof.normal_flip()
    bmesh.ops.inset_region(B.bm, faces=[roof], thickness=0.3, depth=0.0)
    r = bmesh.ops.extrude_face_region(B.bm, geom=[roof])
    nv = [v for v in r["geom"] if isinstance(v, bmesh.types.BMVert)]
    bmesh.ops.translate(B.bm, verts=nv, vec=(0, 0, -0.45))
    cx = sum(p[0] for p in ring) / len(ring)
    cy = sum(p[1] for p in ring) / len(ring)
    for f in {f for v in nv for f in v.link_faces}:
        f.normal_update()
        if abs(f.normal.z) > 0.5:
            f.material_index = m_roof
            if f.normal.z < 0:
                f.normal_flip()
        else:
            f.material_index = m_inner
            if f.normal.dot(Vector((cx, cy, 0)) - f.calc_center_median()) < 0:
                f.normal_flip()


def min_rect(ring):
    """Corners of the minimum-area rectangle around a ring, and how much of
    it the ring fills (1.0 for a rectangle)."""
    best = None
    for i in range(len(ring)):
        (x1, y1), (x2, y2) = ring[i], ring[(i + 1) % len(ring)]
        ang = math.atan2(y2 - y1, x2 - x1)
        c, s_ = math.cos(-ang), math.sin(-ang)
        us = [x * c - y * s_ for x, y in ring]
        vs = [x * s_ + y * c for x, y in ring]
        box = (min(us), max(us), min(vs), max(vs))
        a = (box[1] - box[0]) * (box[3] - box[2])
        if best is None or a < best[0]:
            best = (a, ang, box)
    a, ang, (u0, u1, v0, v1) = best
    c, s_ = math.cos(ang), math.sin(ang)
    corners = [(u * c - v * s_, u * s_ + v * c) for u, v in ((u0, v0), (u1, v0), (u1, v1), (u0, v1))]
    return corners, abs(bw.polygon_area(ring)) / max(a, 1e-6)


def pitched_roof(B, ring, H, rise, m_roof, m_eave, m_wall):
    """A hip roof when the outline is (nearly) a rectangle; L-, T- and
    U-shaped outlines get a flat roof with a parapet instead, since one hip
    roof over them would hang in the air over the inner corners."""
    rect, fill = min_rect(ring)
    if len(ring) >= 4 and fill >= 0.92:
        hip_roof(B, rect, H, rise, m_roof, m_eave)
    else:
        roof_with_parapet(B, ring, H, B.mi("slab"), B.mi("roof"), m_wall)


def hip_roof(B, ring, H, rise, m_roof, m_eave):
    """Hip roof with a small overhang."""
    cx = sum(p[0] for p in ring) / len(ring)
    cy = sum(p[1] for p in ring) / len(ring)
    eave = [(cx + (x - cx) * 1.0 + (x - cx) / max(math.hypot(x - cx, y - cy), 0.01) * 0.4,
             cy + (y - cy) * 1.0 + (y - cy) / max(math.hypot(x - cx, y - cy), 0.01) * 0.4) for x, y in ring]
    vs = [B.bm.verts.new((x, y, H)) for x, y in eave]
    f = B.bm.faces.new(vs)
    f.material_index = m_roof
    f.normal_update()
    if f.normal.z < 0:
        f.normal_flip()
    under = B.bm.faces.new([B.bm.verts.new((x, y, H - 0.02)) for x, y in reversed(eave)])
    under.material_index = m_eave
    wmin, _ = bw.min_rect_dims(ring)
    r = bmesh.ops.inset_region(B.bm, faces=[f], thickness=wmin * 0.48 + 0.4, depth=0.0)
    for g in r["faces"]:
        g.material_index = m_roof
    bmesh.ops.translate(B.bm, verts=list(f.verts), vec=(0, 0, rise))


def walls_shell(B, walls, H, m_wall, m_plinth, plinth=PLINTH):
    for w in walls:
        if plinth > 0:
            B.face([w.p(0, 0), w.p(w.L, 0), w.p(w.L, plinth), w.p(0, plinth)], m_plinth, w.n)
        B.face([w.p(0, plinth), w.p(w.L, plinth), w.p(w.L, H), w.p(0, H)], m_wall, w.n)


def window(D, w, u, z0, width, height, rng, brown=None):
    brown = rng.random() < 0.2 if brown is None else brown
    D.add("win_brown" if brown else "win", w, u, z0, sx=width / 1.6, sz=height / 1.4,
          rgb=rng.choice(GLASS_TINTS))
    if rng.random() < 0.45:
        cw = width * rng.uniform(0.22, 0.34)
        side = -1 if rng.random() < 0.5 else 1
        D.add("curtain", w, u + side * (width / 2 - cw / 2 - 0.08), z0 + 0.08, out=-0.005, sx=cw,
              sz=height - 0.16, rgb=rng.choice(CURTAINS))


def bays(w, bay_w=3.2, margin=0.7):
    if w.L < 2 * margin + 1.5:
        return 0, 0.0, margin
    n = max(1, round((w.L - 2 * margin) / bay_w))
    return n, (w.L - 2 * margin) / n, margin


def build_apartments(B, D, ring, floors, rng, wall_hex, tower):
    walls = [Wall(ring[i], ring[(i + 1) % len(ring)]) for i in range(len(ring))]
    top = PLINTH + floors * FLOOR
    H = top + 0.5
    m_wall = B.mi("wall_" + wall_hex[1:], wall_hex)
    walls_shell(B, walls, H, m_wall, B.mi("plinth"))
    roof_with_parapet(B, ring, H, B.mi("slab"), B.mi("roof"), m_wall)

    long_walls = sorted([i for i, w in enumerate(walls) if w.L > 14], key=lambda i: -walls[i].L)
    if tower:
        balcony_side = {i for i, w in enumerate(walls) if w.L > 9}
        entrance_side = set(long_walls[:1]) or {max(range(len(walls)), key=lambda i: walls[i].L)}
    else:
        balcony_side = set(long_walls[0::2])
        entrance_side = set(long_walls[1::2]) or set(long_walls[:1])
    enclosed_bias = rng.uniform(0.2, 0.6)
    parapet_rgb = (1, 1, 1) if rng.random() < 0.6 else (0.8, 0.8, 0.78)
    for wi, w in enumerate(walls):
        n, bay, margin = bays(w)
        if n == 0:
            continue
        stairs = set()
        if wi in entrance_side and n >= 3:
            ne = max(1, round(w.L / 26))
            stairs = {min(n - 1, int((k + 0.5) * n / ne)) for k in range(ne)}
        every = 2 if wi in balcony_side else (3 if wi in entrance_side else 0)
        for c in range(n):
            uc = margin + (c + 0.5) * bay
            if c in stairs:
                D.add("entrance", w, uc, 0.0)
                for f in range(1, floors):
                    window(D, w, uc, PLINTH + f * FLOOR + 0.4, 1.0, 1.1, rng, brown=False)
                D.put("roof_hut", w.p(uc, H - 0.45, -4.0), math.atan2(w.d.y, w.d.x))
                if rng.random() < 0.6:
                    D.put("antenna", w.p(uc + 1.0, H + 2.35, -4.0), math.atan2(w.d.y, w.d.x))
                continue
            D.add("vent", w, uc, 0.35)
            for f in range(floors):
                zf = PLINTH + f * FLOOR
                if every and c % every == 1:
                    D.add("baldoor", w, uc - bay / 2 + 0.7, zf, rgb=rng.choice(GLASS_TINTS))
                    window(D, w, uc + 0.45, zf + 0.9, min(1.4, bay - 1.7), 1.4, rng)
                    enclosed = rng.random() < enclosed_bias
                    D.add("balcony_closed" if enclosed else "balcony_open", w, uc, zf, sx=(bay - 0.15) / 3.0,
                          rgb=parapet_rgb)
                    if not enclosed:
                        x = rng.random()
                        if x < 0.25:
                            D.add("pots", w, uc, zf + 1.1, out=1.1, sx=(bay - 0.4) / 2.6)
                        elif x < 0.35:
                            D.add("dish", w, uc + bay / 2 - 0.45, zf + 1.15, out=1.2)
                else:
                    width = 1.6 if bay > 2.6 else bay * 0.6
                    window(D, w, uc, zf + 0.9, width, 1.4, rng)
                    if rng.random() < 0.1:
                        D.add("ac", w, uc + width / 2 + 0.55, zf + 1.0)
    # drainpipes
    for i, p in enumerate(ring):
        w0, w1 = walls[i - 1], walls[i]
        if w0.L < 2 or w1.L < 2:
            continue
        out = w0.n + w1.n
        if out.length < 0.1:
            continue
        out.normalize()
        base = Vector((p[0], p[1], 0)) + out * 0.2
        D.put("pipe", Vector((base.x, base.y, 0.0)), 0.0, sz=H - 0.1)


def build_generic(B, D, ring, kind, levels, rng, t):
    """Schools, hospital, houses, garages, churches, shops, sheds."""
    walls = [Wall(ring[i], ring[(i + 1) % len(ring)]) for i in range(len(ring))]
    area = abs(bw.polygon_area(ring))
    if kind == "house":
        hexc = HOUSE_WALLS[rng.randrange(len(HOUSE_WALLS))]
        H = levels * 3.0
        m_wall = B.mi("house_" + hexc[1:], hexc)
        walls_shell(B, walls, H, m_wall, B.mi("plinth"), plinth=0.5)
        pitched_roof(B, ring, H, rng.uniform(2.0, 3.0), B.mi("roof_tile", "#c8553d"), B.mi("slab"), m_wall)
        for w in walls:
            n, bay, m = bays(w, 3.6, 0.9)
            for c in range(n):
                for f in range(levels):
                    window(D, w, m + (c + 0.5) * bay, 0.9 + f * 3.0, 1.2, 1.2, rng, brown=rng.random() < 0.5)
        return
    if kind == "garage":
        H = 2.6
        walls_shell(B, walls, H, B.mi("garage_wall", "#a9b4c2"), B.mi("plinth"), plinth=0)
        roof_with_parapet(B, ring, H, B.mi("slab"), B.mi("roof_dark", "#6e4a3c"), B.mi("garage_wall", "#a9b4c2"))
        w = max(walls, key=lambda q: q.L)
        n, bay, m = bays(w, 3.0, 0.3)
        for c in range(n):
            D.add("garage_door", w, m + (c + 0.5) * bay, 0.0, sx=(bay - 0.4) / 2.5,
                  rgb=rng.choice([(0.8, 0.85, 0.9), (0.55, 0.65, 0.5), (0.7, 0.45, 0.35), (0.9, 0.9, 0.85)]))
        return
    if kind == "church":
        H = 9.0
        m_wall = B.mi("church", "#f3ebd9")
        walls_shell(B, walls, H, m_wall, B.mi("plinth"), plinth=0.6)
        pitched_roof(B, ring, H, 5.0, B.mi("church_roof", "#3f6e8c"), B.mi("slab"), m_wall)
        for w in walls:
            n, bay, m = bays(w, 4.0, 1.5)
            for c in range(n):
                window(D, w, m + (c + 0.5) * bay, 2.5, 1.1, 3.6, rng, brown=True)
        # bell tower with an onion dome on the west end
        xs = [p[0] for p in ring]
        ys = [p[1] for p in ring]
        tx, ty = min(xs) + 4.0, (min(ys) + max(ys)) / 2
        sq = [(tx - 3, ty - 3), (tx + 3, ty - 3), (tx + 3, ty + 3), (tx - 3, ty + 3)]
        tw = [Wall(sq[i], sq[(i + 1) % 4]) for i in range(4)]
        walls_shell(B, tw, 22.0, m_wall, B.mi("plinth"), plinth=0.6)
        roof_with_parapet(B, sq, 22.0, B.mi("slab"), B.mi("church_roof", "#3f6e8c"), m_wall)
        B.cylinder(Vector((tx, ty, 21.5)), 2.2, 2.0, m_wall, 12)
        r = bmesh.ops.create_uvsphere(B.bm, u_segments=16, v_segments=10, radius=2.4,
                                      matrix=Matrix.Translation((tx, ty, 25.0)) @ Matrix.Diagonal((1, 1, 1.25, 1)))
        for f in {f for v in r["verts"] for f in v.link_faces}:
            f.material_index = B.mi("gold", "#e8b93a")
        B.cylinder(Vector((tx, ty, 27.8)), 0.15, 2.8, B.mi("gold", "#e8b93a"), 6, r_top=0.02)
        for w in tw:
            window(D, w, 3.0, 15.0, 1.0, 3.0, rng, brown=True)
        return
    if kind in ("school", "hospital"):
        H = levels * 3.5 + 0.8
        hexc = "#f2c14e" if kind == "school" else "#f5f5f0"
        m_wall = B.mi(kind, hexc)
        walls_shell(B, walls, H, m_wall, B.mi("plinth"), plinth=0.8)
        roof_with_parapet(B, ring, H, B.mi("slab"), B.mi("roof"), m_wall)
        door_wall = max(walls, key=lambda q: q.L)
        for w in walls:
            n, bay, m = bays(w, 3.6, 1.0)
            for c in range(n):
                uc = m + (c + 0.5) * bay
                if w is door_wall and c == n // 2:
                    D.add("entrance", w, uc, 0.0)
                    continue
                for f in range(levels):
                    window(D, w, uc, 0.8 + f * 3.5 + 0.9, 2.4, 1.7, rng, brown=False)
        return
    if kind == "retail":
        H = 7.0 if area < 5000 else 9.0
        m_wall = B.mi("retail", "#e9eef2")
        walls_shell(B, walls, H, m_wall, B.mi("plinth"), plinth=0.3)
        roof_with_parapet(B, ring, H, B.mi("retail_band", "#e2504c"), B.mi("roof"), m_wall)
        for w in walls:
            if w.L < 8:
                continue
            n, bay, m = bays(w, 4.0, 1.0)
            for c in range(n):
                D.add("shopfront", w, m + (c + 0.5) * bay, 0.3, sx=(bay - 0.2) / 3.8)
        return
    # sheds, small and unknown buildings
    H = max(1, levels) * 3.0
    hexc = HOUSE_WALLS[rng.randrange(len(HOUSE_WALLS))]
    m_wall = B.mi("house_" + hexc[1:], hexc)
    walls_shell(B, walls, H, m_wall, B.mi("plinth"), plinth=0.4)
    roof_with_parapet(B, ring, H, B.mi("slab"), B.mi("roof"), m_wall)
    for w in walls:
        n, bay, m = bays(w, 3.8, 0.9)
        for c in range(n):
            for f in range(max(1, levels)):
                window(D, w, m + (c + 0.5) * bay, 0.9 + f * 3.0, 1.3, 1.2, rng)


# ----------------------------------------------------------------------------
# Detail prototypes (local frame: wall plane y = 0, outward -Y, width along X)
# ----------------------------------------------------------------------------
def _w(width):
    return Wall((-width / 2, 0.0), (width / 2, 0.0))


def proto_window(B, width, height, frame, sill=True, transom=True):
    """Window surround protruding from the wall, glass slightly inset."""
    w = _w(width)
    t = 0.09
    out = 0.12
    g = B.mi("glass")
    # glass pane
    B.face([w.p(t, t, 0.02), w.p(width - t, t, 0.02), w.p(width - t, height - t, 0.02), w.p(t, height - t, 0.02)],
           g, w.n)
    fr = B.mi(frame)
    B.box(w.p(width / 2, 0, out / 2), w.d, w.n, width, out, 0.0, t, fr)
    B.box(w.p(width / 2, 0, out / 2), w.d, w.n, width, out, height - t, height, fr)
    B.box(w.p(t / 2, 0, out / 2), w.d, w.n, t, out, t, height - t, fr)
    B.box(w.p(width - t / 2, 0, out / 2), w.d, w.n, t, out, t, height - t, fr)
    B.box(w.p(width / 2, 0, 0.05), w.d, w.n, 0.06, 0.06, t, height - t, fr)
    if transom:
        zt = height * 0.68
        B.box(w.p(width / 2, 0, 0.05), w.d, w.n, width - 2 * t, 0.06, zt - 0.03, zt + 0.03, fr)
    if sill:
        B.box(w.p(width / 2, 0, 0.13), w.d, w.n, width + 0.14, 0.26, -0.06, 0.0, B.mi("slab"))


def proto_balcony(B, enclosed):
    width, depth, ph, pt = 3.0, 1.15, 1.05, 0.08
    w = _w(width)
    slab, par = B.mi("slab"), B.mi("parapet_white")
    B.box(w.p(width / 2, 0, depth / 2), w.d, w.n, width, depth, -0.16, 0.0, slab)
    B.box(w.p(width / 2, 0, depth - pt / 2), w.d, w.n, width, pt, 0.0, ph, par)
    for s in (pt / 2, width - pt / 2):
        B.box(w.p(s, 0, depth / 2), w.d, w.n, pt, depth - pt, 0.0, ph, par)
    B.box(w.p(width / 2, 0, depth - pt / 2), w.d, w.n, width + 0.04, pt + 0.06, ph, ph + 0.05, slab)
    if enclosed:
        top = FLOOR - 0.25
        g = B.mi("glass_b")
        fr = B.mi("frame_white")
        B.face([w.p(0, ph, depth - 0.05), w.p(width, ph, depth - 0.05), w.p(width, top, depth - 0.05),
                w.p(0, top, depth - 0.05)], g, w.n)
        for s, nrm in ((0.0, -w.d), (width, w.d)):
            B.face([w.p(s, ph, 0), w.p(s, ph, depth - 0.05), w.p(s, top, depth - 0.05), w.p(s, top, 0)], g, nrm)
        for k in range(4):
            B.box(w.p(width * k / 3, 0, depth - 0.04), w.d, w.n, 0.06, 0.08, ph, top, fr)
        B.box(w.p(width / 2, 0, depth - 0.04), w.d, w.n, width, 0.08, top - 0.06, top, fr)
        B.box(w.p(width / 2, 0, depth / 2), w.d, w.n, width, depth, top, top + 0.05, slab)


def proto_entrance(B):
    w = _w(3.0)
    B.face([w.p(0.75, 0.45, 0.01), w.p(2.25, 0.45, 0.01), w.p(2.25, 2.75, 0.01), w.p(0.75, 2.75, 0.01)], B.mi("door"), w.n)
    fr = B.mi("frame_brown")
    B.box(w.p(1.5, 0, 0.06), w.d, w.n, 1.7, 0.12, 2.75, 2.85, fr)
    for s in (0.7, 2.3):
        B.box(w.p(s, 0, 0.06), w.d, w.n, 0.1, 0.12, 0.45, 2.85, fr)
    B.box(w.p(1.5, 0, 0.05), w.d, w.n, 0.06, 0.08, 0.45, 2.75, fr)
    B.face([w.p(0.9, 1.6, 0.02), w.p(1.42, 1.6, 0.02), w.p(1.42, 2.6, 0.02), w.p(0.9, 2.6, 0.02)], B.mi("glass"), w.n)
    B.face([w.p(1.58, 1.6, 0.02), w.p(2.1, 1.6, 0.02), w.p(2.1, 2.6, 0.02), w.p(1.58, 2.6, 0.02)], B.mi("glass"), w.n)
    B.box(w.p(1.5, 0, 0.9), w.d, w.n, 2.6, 1.8, 2.95, 3.15, B.mi("canopy"))
    st = B.mi("step")
    B.box(w.p(1.5, 0, 0.6), w.d, w.n, 2.0, 1.2, 0.0, 0.15, st)
    B.box(w.p(1.5, 0, 0.45), w.d, w.n, 2.0, 0.9, 0.15, 0.3, st)
    B.box(w.p(1.5, 0, 0.3), w.d, w.n, 2.0, 0.6, 0.3, 0.45, st)
    B.face([w.p(1.0, 3.3, 0.01), w.p(2.0, 3.3, 0.01), w.p(2.0, 3.65, 0.01), w.p(1.0, 3.65, 0.01)], B.mi("frame_white"), w.n)


def build_prototypes(col):
    """Returns the list of prototype objects (named as in details.json)."""
    objs = []

    def make(name, fn, *a):
        B = Builder()
        fn(B, *a)
        objs.append(B.finish(name, col))

    make("win", proto_window, 1.6, 1.4, "frame_white")
    make("win_brown", proto_window, 1.6, 1.4, "frame_brown")
    make("baldoor", lambda B: proto_window(B, 0.9, 2.2, "frame_white", sill=False, transom=False))
    make("balcony_open", proto_balcony, False)
    make("balcony_closed", proto_balcony, True)
    make("entrance", proto_entrance)

    def curtain(B):
        w = _w(1.0)
        B.face([w.p(0, 0, 0.0), w.p(1, 0, 0.0), w.p(1, 1, 0.0), w.p(0, 1, 0.0)], B.mi("curtain_c"), w.n)
    make("curtain", curtain)

    def ac(B):
        w = _w(0.8)
        B.box(w.p(0.4, 0, 0.16), w.d, w.n, 0.8, 0.3, 0.0, 0.55, B.mi("ac"))
        B.box(w.p(0.4, 0, 0.32), w.d, w.n, 0.45, 0.02, 0.08, 0.47, B.mi("metal"))       # fan grille
    make("ac", ac)

    def dish(B):
        w = _w(0.8)
        B.box(w.p(0.4, 0, 0.0), w.d, w.n, 0.06, 0.06, -0.4, 0.3, B.mi("metal"))
        r = bmesh.ops.create_cone(B.bm, cap_ends=True, segments=12, radius1=0.38, radius2=0.04, depth=0.16,
                                  matrix=Matrix.Translation(w.p(0.4, 0.45, 0.15)) @ Matrix.Rotation(math.pi / 2, 4, "X"))
        for f in {f for v in r["verts"] for f in v.link_faces}:
            f.material_index = B.mi("dish")
    make("dish", dish)

    def pots(B):
        w = _w(2.6)
        for k in range(3):
            u = 0.4 + k * 0.9
            B.box(w.p(u, 0, 0.0), w.d, w.n, 0.36, 0.2, 0.0, 0.2, B.mi("door"))
            res = bmesh.ops.create_icosphere(B.bm, subdivisions=1, radius=0.22,
                                             matrix=Matrix.Translation(w.p(u, 0.33, 0.0)))
            for f in {f for v in res["verts"] for f in v.link_faces}:
                f.material_index = B.mi("plant" if k != 1 else "flower")
    make("pots", pots)

    def vent(B):
        w = _w(0.6)
        B.box(w.p(0.3, 0, 0.02), w.d, w.n, 0.6, 0.04, 0.0, 0.3, B.mi("metal"))
    make("vent", vent)

    def pipe(B):
        B.cylinder(Vector((0, 0, 0)), 0.06, 1.0, B.mi("metal"), 6)
    make("pipe", pipe)

    def roof_hut(B):
        w = _w(3.0)
        B.box(w.p(1.5, 0, 0), w.d, w.n, 3.0, 3.2, 0.0, 2.65, B.mi("roof_box"))
        B.box(w.p(1.5, 0, 0), w.d, w.n, 3.3, 3.5, 2.65, 2.8, B.mi("slab"))
        B.face([w.p(1.0, 0.1, 1.61), w.p(2.0, 0.1, 1.61), w.p(2.0, 2.1, 1.61), w.p(1.0, 2.1, 1.61)], B.mi("door_metal"), w.n)
    make("roof_hut", roof_hut)

    def antenna(B):
        m = B.mi("metal")
        B.cylinder(Vector((0, 0, 0)), 0.04, 2.6, m, 6)
        for k, L in enumerate((1.4, 1.1, 0.8)):
            B.box(Vector((0, 0, 0)), Vector((1, 0, 0)), Vector((0, 1, 0)), L, 0.04, 1.9 + k * 0.25, 1.94 + k * 0.25, m)
    make("antenna", antenna)

    def garage_door(B):
        w = _w(2.5)
        B.face([w.p(0, 0, 0.02), w.p(2.5, 0, 0.02), w.p(2.5, 2.1, 0.02), w.p(0, 2.1, 0.02)], B.mi("garage_door", "#d9dde2"), w.n)
        for k in range(1, 6):
            B.box(w.p(1.25, 0, 0.03), w.d, w.n, 2.5, 0.02, k * 0.35 - 0.02, k * 0.35, B.mi("metal"))
    make("garage_door", garage_door)

    def shopfront(B):
        w = _w(3.8)
        B.face([w.p(0.1, 0.3, 0.02), w.p(3.7, 0.3, 0.02), w.p(3.7, 3.4, 0.02), w.p(0.1, 3.4, 0.02)], B.mi("glass_b"), w.n)
        fr = B.mi("metal")
        for s in (0.05, 1.9, 3.75):
            B.box(w.p(s, 0, 0.05), w.d, w.n, 0.1, 0.1, 0.0, 3.5, fr)
        B.box(w.p(1.9, 0, 0.05), w.d, w.n, 3.8, 0.1, 3.4, 3.5, fr)
        B.box(w.p(1.9, 0, 0.3), w.d, w.n, 3.8, 0.6, 4.2, 5.0, B.mi("retail_band", "#e2504c"))
    make("shopfront", shopfront)
    return objs


# ----------------------------------------------------------------------------
def export(scn, path, objects):
    c3.export(scn, path, objects)


def run(root, part="all"):
    data = bw.osm(root)
    area = play_area(root)
    # earlier prototype scenes own objects with the same names (tree_a, ...)
    for old in ("Corner3D", "Corner3DProps", "StyleTest"):
        sc = bpy.data.scenes.get(old)
        if sc:
            for ob in list(sc.collection.all_objects):
                bpy.data.objects.remove(ob, do_unlink=True)
            bpy.data.scenes.remove(sc)
    out = os.path.join(root, "game", "levels", "micro15")
    os.makedirs(out, exist_ok=True)
    res = {}

    def fresh(name):
        scn = bpy.data.scenes.get(name) or bpy.data.scenes.new(name)
        for ob in list(scn.collection.all_objects):
            bpy.data.objects.remove(ob, do_unlink=True)
        return scn

    if part in ("all", "buildings"):
        scn = fresh("MapBuildings")
        D = Details()
        footprints = {}
        walls = list(c3.WALLS.values())
        n = 0
        for w in data.ways:
            t = w["tags"]
            if "building" not in t:
                continue
            ring = bw.clean_ring(data.coords(w))
            if len(ring) < 3:
                continue
            cx = sum(p[0] for p in ring) / len(ring)
            cy = sum(p[1] for p in ring) / len(ring)
            if not bw.in_extent(cx, cy):
                continue
            footprints["bld_%d" % w["id"]] = [[round(c, 2) for c in to_game(x, y)] for x, y in ring]
            kind, levels = bw.classify(t, ring)
            rng = random.Random(w["id"])
            B = Builder()
            if kind == "apartments":
                build_apartments(B, D, ring, levels, rng, walls[w["id"] % len(walls)], levels > 8)
            else:
                build_generic(B, D, ring, kind, levels, rng, t)
            ob = B.finish("bld_%d" % w["id"], scn.collection)
            ob.location = (-MAP_CENTRE[0], -MAP_CENTRE[1], 0)
            n += 1
        export(scn, os.path.join(out, "buildings.glb"), list(scn.collection.all_objects))
        json.dump(D.items, open(os.path.join(out, "details.json"), "w"), separators=(",", ":"))
        json.dump(footprints, open(os.path.join(out, "footprints.json"), "w"), separators=(",", ":"))
        res["buildings"] = n
        res["details"] = {k: len(v) for k, v in D.items.items()}

    if part in ("all", "ground"):
        scn = fresh("MapGround")
        old_c, old_r = c3.CENTRE, c3.RADIUS
        c3.CENTRE, c3.RADIUS = MAP_CENTRE, 900.0      # ground builder keeps everything in this circle
        try:
            c3.build_ground(data, scn.collection)
        finally:
            c3.CENTRE, c3.RADIUS = old_c, old_r
        if area:
            res["ground_chunks"] = split_ground(list(scn.collection.all_objects), area, scn.collection)
        for ob in scn.collection.all_objects:
            ob.location = (-MAP_CENTRE[0], -MAP_CENTRE[1], 0)
        export(scn, os.path.join(out, "ground.glb"), list(scn.collection.all_objects))
        res["ground"] = True

    if part in ("all", "details"):
        scn = fresh("MapDetails")
        objs = build_prototypes(scn.collection)
        export(scn, os.path.join(out, "details.glb"), objs)
        scn = fresh("MapProps")
        pc = scn.collection
        lib = [c3.make_lamp(pc), c3.make_bench(pc)]
        for far in (False, True):              # detailed, and "_far" for distance (Scatter switches)
            sfx = "_far" if far else ""
            lib += [c3.make_tree("tree_a" + sfx, pc, 1, "leaf_a", 4.4, 3.2, 5, far),
                    c3.make_tree("tree_b" + sfx, pc, 2, "leaf_b", 5.0, 3.7, 6, far),
                    c3.make_tree("tree_c" + sfx, pc, 3, "leaf_c", 3.8, 2.7, 4, far),
                    c3.make_poplar("poplar" + sfx, pc, 4, far),
                    c3.make_bush("bush_a" + sfx, pc, 5, far=far), c3.make_bush("bush_b" + sfx, pc, 6, True, far)]
        export(scn, os.path.join(out, "props.glb"), lib)
        res["details_protos"] = len(objs)

    if part in ("all", "props"):
        kinds = {"tree_round_a": "tree_a", "tree_round_b": "tree_b", "tree_round_c": "tree_c",
                 "tree_poplar": "poplar", "bush": "bush_a", "lamp": "lamp", "bench": "bench"}
        props = {}
        rng = random.Random(15)
        for ob in bpy.data.objects:
            if not ob.name.startswith(("Tree_", "Bush_", "Lamp_", "Bench_")):
                continue
            k = kinds.get(ob.data.name.replace("M15_", "").lower())
            if not k:
                continue
            if k == "bush_a" and rng.random() < 0.4:
                k = "bush_b"
            props.setdefault(k, []).append([round(ob.location.x - MAP_CENTRE[0], 2),
                                            round(-(ob.location.y - MAP_CENTRE[1]), 2),
                                            round(ob.rotation_euler.z, 3), round(ob.scale.x, 2)])
        json.dump(props, open(os.path.join(out, "props.json"), "w"), separators=(",", ":"))
        res["props"] = {k: len(v) for k, v in props.items()}
    return res
