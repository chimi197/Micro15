"""Full 3D corner of Micro 15 for the Godot prototype.

Models every block of flats around CENTRE with real geometry: recessed
windows with frames and sills, open and enclosed balconies, stairwell
windows, entrances with canopies and steps, plinths, drainpipes, roof
parapets, roof stair houses, antennas, AC units and satellite dishes. Roads
get raised sidewalks with kerbs. Trees, bushes, lamps and benches are
modelled as stylised 3D props.

Writes:
    game/levels/corner/corner.glb   buildings, roads, ground
    game/levels/corner/props.glb    tree / bush / lamp / bench models
    game/levels/corner/props.json   where to place the props
    game/levels/corner/grass_mask.png is made by tools/make_grass_mask.py

    import sys; sys.path.insert(0, r"<repo>/blender")
    import build_corner_3d; build_corner_3d.run(r"<repo>")
"""
import bmesh
import bpy
import json
import math
import os
import random
from mathutils import Matrix, Vector, noise

import build_world as bw
import foliage as fol

CENTRE = (250.0, 560.0)
RADIUS = 115.0
FLOOR = 2.8
PLINTH = 1.0          # raised ground floor
UP = Vector((0, 0, 1))

COLOURS = {
    "plinth": "#8d8a86", "frame_white": "#f7f5ef", "frame_brown": "#7a4f35",
    "glass": "#3e6596", "glass_b": "#4f7aa8", "glass_dark": "#2f4b73",
    "slab": "#d9d4c8", "parapet_white": "#f1ede4", "parapet_grey": "#b9b6b0",
    "roof": "#7f7c78", "roof_box": "#a7a39c", "metal": "#4a4e57", "door": "#6d4630",
    "door_metal": "#5b6b7a", "canopy": "#c9c4b8", "step": "#b5b0a6",
    "curtain_a": "#f28b82", "curtain_b": "#f6c26b", "curtain_c": "#fbfbf6", "curtain_d": "#9fd3e8",
    "plant": "#4fa843", "flower": "#f25c54", "ac": "#ecebe6", "dish": "#e9e9e4",
    "asphalt": "#5f6673", "pavement": "#d6cfbf", "kerb": "#b9b3a6", "path": "#e2d3ad",
    "lawn": "#8cc456", "sand": "#ebcb7a", "pitch": "#5db55a", "parking": "#7d838e",
    "bark": "#7a5034", "leaf_a": "#4fa843", "leaf_b": "#6cbf48", "leaf_c": "#3e8e3e",
    "poplar": "#3f9447", "bush": "#5aae45", "lamp_glass": "#fff2b3", "wood": "#b07a4a",
    "line": "#f4f1e6",
}
WALLS = {"mint": "#a8d8b9", "peach": "#f4b183", "lemon": "#f7d774", "sky": "#9ec9e2",
         "cream": "#f2e3b3", "lilac": "#c9b6e4", "salmon": "#e98b6d", "white": "#ebe7dc"}


def mat(name, colour=None):
    m = bpy.data.materials.get("C3_" + name)
    if m is None:
        m = bpy.data.materials.new("C3_" + name)
        c = bw.hex_rgba(colour or COLOURS[name])
        m.diffuse_color = c
        m.use_nodes = True
        bsdf = m.node_tree.nodes.get("Principled BSDF")
        if bsdf:
            bsdf.inputs["Base Color"].default_value = c
            bsdf.inputs["Roughness"].default_value = 1.0
    return m


class Builder:
    """Accumulates faces in one bmesh with a material palette."""

    def __init__(self):
        self.bm = bmesh.new()
        self.mats = []

    def mi(self, name, colour=None):
        m = mat(name, colour)
        if m not in self.mats:
            self.mats.append(m)
        return self.mats.index(m)

    def face(self, pts, m, normal=None):
        vs = [self.bm.verts.new(p) for p in pts]
        f = self.bm.faces.new(vs)
        f.material_index = m
        if normal is not None:
            f.normal_update()
            if f.normal.dot(normal) < 0:
                f.normal_flip()
        return f

    def box(self, c, d, n, w, depth, z0, z1, m):
        """Box centred on c (xy) spanning w along d, depth along n, z0..z1."""
        d = Vector((d.x, d.y, 0)).normalized()
        n = Vector((n.x, n.y, 0)).normalized()
        c = Vector((c.x, c.y, 0))
        hw, hd = d * (w / 2), n * (depth / 2)
        ring = [c - hw - hd, c + hw - hd, c + hw + hd, c - hw + hd]
        b = [Vector((p.x, p.y, z0)) for p in ring]
        t = [Vector((p.x, p.y, z1)) for p in ring]
        self.face(t, m, UP)
        self.face(list(reversed(b)), m, -UP)
        for i in range(4):
            j = (i + 1) % 4
            mid = (ring[i] + ring[j]) / 2 - c
            self.face([b[i], b[j], t[j], t[i]], m, mid)

    def cylinder(self, base, radius, height, m, segs=8, r_top=None, smooth=False):
        r = bmesh.ops.create_cone(self.bm, cap_ends=True, segments=segs, radius1=radius,
                                  radius2=radius if r_top is None else r_top, depth=height,
                                  matrix=Matrix.Translation(base + Vector((0, 0, height / 2))))
        for f in {f for v in r["verts"] for f in v.link_faces}:
            f.material_index = m
            f.smooth = smooth and len(f.verts) == 4      # round sides, flat caps

    def cbox(self, c, d, n, w, depth, z0, z1, m, chamfer=0.015):
        """Like box, with chamfered edges that catch the light (built in its
        own bmesh so the bevel never touches the rest)."""
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        bmesh.ops.scale(bm, vec=Vector((w, depth, z1 - z0)), verts=bm.verts)
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=chamfer, segments=1, profile=0.5, affect="EDGES")
        d = Vector((d.x, d.y, 0)).normalized()
        rot = Matrix.Rotation(math.atan2(d.y, d.x), 4, "Z")
        bmesh.ops.transform(bm, matrix=Matrix.Translation(Vector((c.x, c.y, (z0 + z1) / 2))) @ rot, verts=bm.verts)
        vmap = {v: self.bm.verts.new(v.co) for v in bm.verts}
        for f in bm.faces:
            nf = self.bm.faces.new([vmap[v] for v in f.verts])
            nf.material_index = m
        bm.free()

    def finish(self, name, col):
        bmesh.ops.remove_doubles(self.bm, verts=self.bm.verts, dist=0.001)
        me = bpy.data.meshes.new(name)
        self.bm.to_mesh(me)
        self.bm.free()
        for m in self.mats:
            me.materials.append(m)
        ob = bpy.data.objects.new(name, me)
        col.objects.link(ob)
        return ob


# ----------------------------------------------------------------------------
# Block of flats
# ----------------------------------------------------------------------------
class Wall:
    def __init__(self, a, b):
        self.a = Vector((a[0], a[1], 0))
        self.b = Vector((b[0], b[1], 0))
        self.L = (self.b - self.a).length
        self.d = (self.b - self.a) / self.L
        self.n = Vector((self.d.y, -self.d.x, 0))      # outward for CCW rings

    def p(self, u, z, out=0.0):
        q = self.a + self.d * u + self.n * out
        return Vector((q.x, q.y, z))


def wall_cell(B, w, u0, u1, z0, z1, m_wall, holes=()):
    """Wall rectangle with rectangular holes (list of (hu0, hu1, hz0, hz1))."""
    if not holes:
        B.face([w.p(u0, z0), w.p(u1, z0), w.p(u1, z1), w.p(u0, z1)], m_wall, w.n)
        return
    holes = sorted(holes)
    zb = min(h[2] for h in holes)
    zt = max(h[3] for h in holes)
    if zb > z0:
        B.face([w.p(u0, z0), w.p(u1, z0), w.p(u1, zb), w.p(u0, zb)], m_wall, w.n)
    if zt < z1:
        B.face([w.p(u0, zt), w.p(u1, zt), w.p(u1, z1), w.p(u0, z1)], m_wall, w.n)
    cur = u0
    for hu0, hu1, hz0, hz1 in holes:
        if hu0 > cur:
            B.face([w.p(cur, zb), w.p(hu0, zb), w.p(hu0, zt), w.p(cur, zt)], m_wall, w.n)
        if hz0 > zb:
            B.face([w.p(hu0, zb), w.p(hu1, zb), w.p(hu1, hz0), w.p(hu0, hz0)], m_wall, w.n)
        if hz1 < zt:
            B.face([w.p(hu0, hz1), w.p(hu1, hz1), w.p(hu1, zt), w.p(hu0, zt)], m_wall, w.n)
        cur = hu1
    if cur < u1:
        B.face([w.p(cur, zb), w.p(u1, zb), w.p(u1, zt), w.p(cur, zt)], m_wall, w.n)


def opening(B, w, hu0, hu1, hz0, hz1, rng, M, depth=0.18, kind="window", m_reveal=None):
    """Reveal, glass/door, frame, sill and maybe a curtain for one hole."""
    m_rev = m_reveal if m_reveal is not None else M["wall"]
    dn = -depth
    # reveals
    B.face([w.p(hu0, hz0), w.p(hu1, hz0), w.p(hu1, hz0, dn), w.p(hu0, hz0, dn)], m_rev, UP)
    B.face([w.p(hu0, hz1), w.p(hu1, hz1), w.p(hu1, hz1, dn), w.p(hu0, hz1, dn)], m_rev, -UP)
    B.face([w.p(hu0, hz0), w.p(hu0, hz1), w.p(hu0, hz1, dn), w.p(hu0, hz0, dn)], m_rev, w.d)
    B.face([w.p(hu1, hz0), w.p(hu1, hz1), w.p(hu1, hz1, dn), w.p(hu1, hz0, dn)], m_rev, -w.d)
    frame = M["frame_white"] if rng.random() < 0.8 else M["frame_brown"]
    if kind == "door":
        B.face([w.p(hu0, hz0, dn), w.p(hu1, hz0, dn), w.p(hu1, hz1, dn), w.p(hu0, hz1, dn)], M["door"], w.n)
        return
    glass = rng.choice([M["glass"], M["glass"], M["glass_b"], M["glass_dark"]])
    B.face([w.p(hu0, hz0, dn), w.p(hu1, hz0, dn), w.p(hu1, hz1, dn), w.p(hu0, hz1, dn)], glass, w.n)
    t = 0.06
    fd = dn + 0.03
    c = lambda u: w.p(u, 0, fd)
    # outer frame
    B.box(c((hu0 + hu1) / 2), w.d, w.n, hu1 - hu0, 0.06, hz0, hz0 + t, frame)
    B.box(c((hu0 + hu1) / 2), w.d, w.n, hu1 - hu0, 0.06, hz1 - t, hz1, frame)
    B.box(c(hu0 + t / 2), w.d, w.n, t, 0.06, hz0, hz1, frame)
    B.box(c(hu1 - t / 2), w.d, w.n, t, 0.06, hz0, hz1, frame)
    # mullion and transom
    if hu1 - hu0 > 1.0:
        B.box(c((hu0 + hu1) / 2), w.d, w.n, t, 0.06, hz0, hz1, frame)
    if kind == "window" and hz1 - hz0 > 1.0:
        zt = hz0 + (hz1 - hz0) * 0.68
        B.box(c((hu0 + hu1) / 2), w.d, w.n, hu1 - hu0, 0.06, zt - t / 2, zt + t / 2, frame)
    # curtain on one side
    if rng.random() < 0.45:
        cm = rng.choice([M["curtain_a"], M["curtain_b"], M["curtain_c"], M["curtain_d"]])
        cw = (hu1 - hu0) * rng.uniform(0.2, 0.35)
        cu0, cu1 = (hu0 + t, hu0 + t + cw) if rng.random() < 0.5 else (hu1 - t - cw, hu1 - t)
        B.face([w.p(cu0, hz0 + t, dn + 0.01), w.p(cu1, hz0 + t, dn + 0.01), w.p(cu1, hz1 - t, dn + 0.01),
                w.p(cu0, hz1 - t, dn + 0.01)], cm, w.n)
    # sill
    if kind == "window":
        B.box(w.p((hu0 + hu1) / 2, 0, 0.04), w.d, w.n, hu1 - hu0 + 0.12, 0.2, hz0 - 0.05, hz0, M["slab"])


def balcony(B, w, uc, width, zf, rng, M, enclosed):
    """Balcony hanging off the wall: slab, parapet panels, maybe glazing."""
    depth = 1.15
    slab_t = 0.16
    c0 = w.p(uc, 0, depth / 2)
    B.box(c0, w.d, w.n, width, depth, zf - slab_t, zf, M["slab"])
    par = M["parapet"]
    ph = 1.05
    pt = 0.08
    B.box(w.p(uc, 0, depth - pt / 2), w.d, w.n, width, pt, zf, zf + ph, par)
    for s in (-1, 1):
        B.box(w.p(uc + s * (width / 2 - pt / 2), 0, depth / 2), w.d, w.n, pt, depth - pt, zf, zf + ph, par)
    # parapet top rail
    B.box(w.p(uc, 0, depth - pt / 2), w.d, w.n, width + 0.04, pt + 0.06, zf + ph, zf + ph + 0.05, M["slab"])
    if enclosed:
        frame = M["frame_white"] if rng.random() < 0.75 else M["frame_brown"]
        top = zf + FLOOR - 0.25
        g = M["glass_b"]
        # front glazing and side glazing
        B.face([w.p(uc - width / 2, zf + ph, depth - 0.05), w.p(uc + width / 2, zf + ph, depth - 0.05),
                w.p(uc + width / 2, top, depth - 0.05), w.p(uc - width / 2, top, depth - 0.05)], g, w.n)
        for s in (-1, 1):
            u = uc + s * width / 2
            B.face([w.p(u, zf + ph, 0), w.p(u, zf + ph, depth - 0.05), w.p(u, top, depth - 0.05), w.p(u, top, 0)],
                   g, w.d * s)
        nseg = max(2, int(width / 0.9))
        for k in range(nseg + 1):
            u = uc - width / 2 + width * k / nseg
            B.box(w.p(u, 0, depth - 0.04), w.d, w.n, 0.06, 0.08, zf + ph, top, frame)
        B.box(w.p(uc, 0, depth - 0.04), w.d, w.n, width, 0.08, top - 0.06, top, frame)
        # roof of the enclosure (slab of the balcony above covers most of it)
        B.box(w.p(uc, 0, depth / 2), w.d, w.n, width, depth, top, top + 0.05, M["slab"])
    else:
        extra = rng.random()
        if extra < 0.3:      # flower pots on the rail
            for k in range(3):
                u = uc - width / 3 + k * width / 3
                B.box(w.p(u, 0, depth - 0.05), w.d, w.n, 0.35, 0.18, zf + ph + 0.05, zf + ph + 0.25, M["door"])
                B.box(w.p(u, 0, depth - 0.05), w.d, w.n, 0.38, 0.22, zf + ph + 0.25, zf + ph + 0.45,
                      M["plant"] if k != 1 else M["flower"])
        elif extra < 0.42:   # satellite dish
            B.box(w.p(uc + width / 2 - 0.4, 0, depth + 0.05), w.d, w.n, 0.08, 0.08, zf + ph - 0.3, zf + ph + 0.4,
                  M["metal"])
            dish = w.p(uc + width / 2 - 0.4, zf + ph + 0.55, depth + 0.25)
            r = bmesh.ops.create_cone(B.bm, cap_ends=True, segments=10, radius1=0.38, radius2=0.04, depth=0.18,
                                      matrix=Matrix.Translation(dish) @ w.n.to_track_quat("-Z", "Z").to_matrix().to_4x4())
            for f in {f for v in r["verts"] for f in v.link_faces}:
                f.material_index = M["dish"]


def build_block(B, ring, floors, rng, M, kind="apartments"):
    walls = [Wall(ring[i], ring[(i + 1) % len(ring)]) for i in range(len(ring))]
    top = PLINTH + floors * FLOOR
    H = top + 0.5
    long_walls = sorted([i for i, w in enumerate(walls) if w.L > 14], key=lambda i: -walls[i].L)
    balcony_side = set(long_walls[0::2]) if kind == "apartments" else set()
    entrance_side = set(long_walls[1::2]) or set(long_walls[:1])
    if kind == "tower":
        balcony_side = {i for i, w in enumerate(walls) if w.L > 9}
        entrance_side = set(long_walls[:1]) or {max(range(len(walls)), key=lambda i: walls[i].L)}
    stair_houses = []
    for wi, w in enumerate(walls):
        if w.L < 2.0:
            wall_cell(B, w, 0, w.L, 0, H, M["wall"])
            continue
        margin = 0.7 if w.L > 4 else w.L / 2
        n = max(0, round((w.L - 2 * margin) / 3.2))
        bay = (w.L - 2 * margin) / n if n else 0
        # stairwell bays (entrances)
        stairs = set()
        if wi in entrance_side and n >= 3:
            ne = max(1, round(w.L / 26))
            for k in range(ne):
                stairs.add(min(n - 1, int((k + 0.5) * n / ne)))
        # plinth + margins
        wall_cell(B, w, 0, w.L, 0, PLINTH, M["plinth"]) if not stairs else None
        if n == 0:
            wall_cell(B, w, 0, w.L, PLINTH, H, M["wall"])
            continue
        wall_cell(B, w, 0, margin, PLINTH if not stairs else 0, H, M["wall"])
        wall_cell(B, w, w.L - margin, w.L, PLINTH if not stairs else 0, H, M["wall"])
        if stairs:
            for c in range(n):
                u0 = margin + c * bay
                if c in stairs:
                    continue
                wall_cell(B, w, u0, u0 + bay, 0, PLINTH, M["plinth"])
        wall_cell(B, w, margin, w.L - margin, top, H, M["wall"])
        has_balc = wi in balcony_side
        # the entrance side gets a sparser column of balconies too
        balc_every = 2 if has_balc else (3 if wi in entrance_side and kind != "other" else 0)
        for c in range(n):
            u0 = margin + c * bay
            u1 = u0 + bay
            uc = (u0 + u1) / 2
            if c in stairs:
                # entrance: door down at ground, small landing windows above
                du0, du1 = uc - 0.75, uc + 0.75
                wall_cell(B, w, u0, u1, 0, PLINTH + FLOOR, M["wall"], [(du0, du1, 0.45, 2.75)])
                opening(B, w, du0, du1, 0.45, 2.75, rng, M, kind="door")
                B.box(w.p(uc, 0, 0.9), w.d, w.n, 2.6, 1.8, 2.95, 3.15, M["canopy"])          # canopy
                B.box(w.p(uc, 0, 0.6), w.d, w.n, 2.0, 1.2, 0.0, 0.15, M["step"])
                B.box(w.p(uc, 0, 0.45), w.d, w.n, 2.0, 0.9, 0.15, 0.3, M["step"])
                B.box(w.p(uc, 0, 0.3), w.d, w.n, 2.0, 0.6, 0.3, 0.45, M["step"])
                for f in range(1, floors):
                    zb = PLINTH + f * FLOOR            # landing window sits between floors
                    hole = (uc - 0.5, uc + 0.5, zb + 0.4, zb + 1.5)
                    wall_cell(B, w, u0, u1, zb, zb + FLOOR, M["wall"], [hole])
                    opening(B, w, *hole, rng, M, kind="small")
                stair_houses.append((w, uc))
                continue
            for f in range(floors):
                zf = PLINTH + f * FLOOR
                if balc_every and c % balc_every == 1 and not (stairs and min(abs(c - k) for k in stairs) < 1):
                    holes = [(u0 + 0.25, u0 + 1.15, zf, zf + 2.2), (u0 + 1.45, u1 - 0.25, zf + 0.9, zf + 2.3)]
                    wall_cell(B, w, u0, u1, zf, zf + FLOOR, M["wall"], holes)
                    opening(B, w, *holes[0], rng, M, kind="balcony_door")
                    opening(B, w, *holes[1], rng, M)
                    balcony(B, w, uc, bay - 0.15, zf, rng, M, enclosed=rng.random() < 0.4)
                else:
                    hw = 0.8 if bay > 2.6 else bay * 0.3
                    hole = (uc - hw, uc + hw, zf + 0.9, zf + 2.3)
                    wall_cell(B, w, u0, u1, zf, zf + FLOOR, M["wall"], [hole])
                    opening(B, w, *hole, rng, M)
                    if rng.random() < 0.12:       # AC unit next to the window
                        B.box(w.p(u1 - 0.45, 0, 0.18), w.d, w.n, 0.75, 0.3, zf + 1.0, zf + 1.55, M["ac"])
                        B.box(w.p(u1 - 0.45, 0, 0.34), w.d, w.n, 0.5, 0.03, zf + 1.1, zf + 1.45, M["metal"])
        # basement vents in the plinth
        for c in range(n):
            if c in stairs:
                continue
            uc = margin + (c + 0.5) * bay
            B.box(w.p(uc, 0, 0.01), w.d, w.n, 0.6, 0.04, 0.35, 0.65, M["metal"])

    # roof with a parapet: inset the roof, then push the inner part down
    tops = [B.bm.verts.new((x, y, H)) for x, y in ring]
    roof = B.bm.faces.new(tops)
    roof.material_index = M["parapet_cap"]
    roof.normal_update()
    if roof.normal.z < 0:
        roof.normal_flip()
    inner = bmesh.ops.inset_region(B.bm, faces=[roof], thickness=0.3, depth=0.0)
    r = bmesh.ops.extrude_face_region(B.bm, geom=[roof])
    new_verts = [v for v in r["geom"] if isinstance(v, bmesh.types.BMVert)]
    bmesh.ops.translate(B.bm, verts=new_verts, vec=(0, 0, -0.45))
    cx = sum(p[0] for p in ring) / len(ring)
    cy = sum(p[1] for p in ring) / len(ring)
    for f in {f for v in new_verts for f in v.link_faces}:
        f.normal_update()
        if abs(f.normal.z) > 0.5:
            f.material_index = M["roof"]
            if f.normal.z < 0:
                f.normal_flip()
        else:
            f.material_index = M["wall"]
            if f.normal.dot(Vector((cx, cy, 0)) - f.calc_center_median()) < 0:
                f.normal_flip()
    for w, uc in stair_houses:
        c = w.p(uc, 0, -4.0)
        B.box(c, w.d, w.n, 3.0, 3.2, H - 0.45, H + 2.2, M["roof_box"])
        B.box(c, w.d, w.n, 3.3, 3.5, H + 2.2, H + 2.35, M["parapet_cap"])
        if rng.random() < 0.6:
            B.cylinder(Vector((c.x + 1.0, c.y, H + 2.35)), 0.04, 2.5, M["metal"], 6)
            B.box(Vector((c.x + 1.0, c.y, 0)), w.d, w.n, 1.2, 0.05, H + 4.3, H + 4.36, M["metal"])
    # drainpipes on the corners
    for i, p in enumerate(ring):
        w0, w1 = walls[i - 1], walls[i]
        if w0.L < 2 or w1.L < 2:
            continue
        out = (w0.n + w1.n)
        if out.length < 0.1:
            continue
        out.normalize()
        base = Vector((p[0], p[1], 0)) + out * 0.2
        B.cylinder(Vector((base.x, base.y, 0)), 0.06, H - 0.1, M["metal"], 6)
    return H


def block_materials(B, wall_key, rng):
    M = {"wall": B.mi("wall_" + wall_key, WALLS[wall_key])}
    for k in ("plinth", "frame_white", "frame_brown", "glass", "glass_b", "glass_dark", "slab", "roof", "roof_box",
              "metal", "door", "canopy", "step", "curtain_a", "curtain_b", "curtain_c", "curtain_d", "plant",
              "flower", "ac", "dish"):
        M[k] = B.mi(k)
    M["parapet"] = B.mi("parapet_white") if rng.random() < 0.6 else B.mi("parapet_grey")
    M["parapet_cap"] = B.mi("slab")
    return M


# ----------------------------------------------------------------------------
# Ground: lawn, land use, roads with raised sidewalks and kerbs
# ----------------------------------------------------------------------------
def near(x, y, r=RADIUS):
    return math.hypot(x - CENTRE[0], y - CENTRE[1]) <= r


def extrude_up(bm, faces, h, m_side):
    r = bmesh.ops.extrude_face_region(bm, geom=faces)
    verts = [v for v in r["geom"] if isinstance(v, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, verts=verts, vec=(0, 0, h))
    for f in {f for v in verts for f in v.link_faces}:
        f.normal_update()
        if abs(f.normal.z) < 0.5:
            f.material_index = m_side


def build_ground(data, col):
    B = Builder()
    lawn = B.mi("lawn")
    seg = 72
    R = RADIUS + 60
    B.face([Vector((CENTRE[0] + math.cos(a) * R, CENTRE[1] + math.sin(a) * R, 0)) for a in
            [math.tau * k / seg for k in range(seg)]], lawn, UP)
    styles = {"parking": ("parking", 0.02), "playground": ("sand", 0.03), "pitch": ("pitch", 0.03),
              "school": (None, 0), "kindergarten": ("sand", 0.025)}
    for w in data.ways:
        t = w["tags"]
        k = t.get("amenity") or t.get("leisure")
        if k not in styles or not styles[k][0]:
            continue
        ring = bw.clean_ring(data.coords(w))
        if len(ring) < 3 or not any(near(x, y, RADIUS + 40) for x, y in ring):
            continue
        try:
            B.face([Vector((x, y, styles[k][1])) for x, y in ring], B.mi(styles[k][0]), UP)
        except ValueError:
            pass
    B.finish("ground", col)

    road, walk = Builder(), Builder()
    m_asph = road.mi("asphalt")
    m_line = road.mi("line")
    m_pave, m_kerb, m_path = walk.mi("pavement"), walk.mi("kerb"), walk.mi("path")
    for w in data.ways:
        hw = w["tags"].get("highway")
        if hw not in bw.ROAD_STYLES:
            continue
        pts = data.coords(w)
        if not any(near(x, y, RADIUS + 50) for x, y in pts):
            continue
        width, key, z, sw, centre = bw.ROAD_STYLES[hw]
        if key == "asphalt":
            n0 = len(road.bm.faces)
            bw.ribbon(road.bm, pts, width, 0.03)
            for f in list(road.bm.faces)[n0:]:
                f.material_index = m_asph
            if centre:
                n0 = len(road.bm.faces)
                bw.dashes(road.bm, pts, 0.045)
                for f in list(road.bm.faces)[n0:]:
                    f.material_index = m_line
            if sw:
                n0 = len(walk.bm.faces)
                bw.ribbon(walk.bm, pts, width + 2 * sw, 0.0)
                new = list(walk.bm.faces)[n0:]
                for f in new:
                    f.material_index = m_pave
                walk.bm.normal_update()
                extrude_up(walk.bm, new, 0.12, m_kerb)
        else:
            n0 = len(walk.bm.faces)
            bw.ribbon(walk.bm, pts, max(width, 1.8), 0.0)
            new = list(walk.bm.faces)[n0:]
            for f in new:
                f.material_index = m_path
            walk.bm.normal_update()
            extrude_up(walk.bm, new, 0.06, m_path)
    # Sidewalks are one slab under the whole road corridor; the road sits just
    # on top, so the kerb shows between the pavement and the lawn.
    bmesh.ops.translate(road.bm, verts=road.bm.verts, vec=(0, 0, 0.1))
    road.finish("roads", col)
    walk.finish("sidewalks", col)


# ----------------------------------------------------------------------------
# Props: stylised 3D trees, bushes, lamps, benches
# ----------------------------------------------------------------------------
def bent_normals(ob, centre, leaf_index, strength=0.85, axis_scale=1.0):
    """Point foliage normals away from the canopy centre (see foliage.py)."""
    fol.bend_normals(ob, centre, {leaf_index}, strength, axis_scale)


def trunk(B, m, height, rng, branches=3, r0=0.28):
    """Tapered, slightly leaning trunk with forking branches. Returns the
    branch tips (and the top of the trunk) for the leaf clumps."""
    lean = Vector((rng.uniform(-0.15, 0.15), rng.uniform(-0.15, 0.15), 0))
    top = Vector((0, 0, height)) + lean
    _limb(B, Vector((0, 0, 0)), top, r0, r0 * 0.55, m, 9)
    B.cylinder(Vector((0, 0, 0)), r0 * 1.35, 0.25, m, 9, r_top=r0, smooth=True)   # root flare
    tips = [top]
    a0 = rng.uniform(0, math.tau)
    for k in range(branches):
        a = a0 + math.tau * k / max(branches, 1) + rng.uniform(-0.4, 0.4)
        tilt = rng.uniform(0.6, 0.95)
        L = rng.uniform(1.3, 2.0)
        z = height * rng.uniform(0.6, 0.85)
        dirv = Vector((math.cos(a) * math.sin(tilt), math.sin(a) * math.sin(tilt), math.cos(tilt)))
        base = Vector((0, 0, z)) + lean * (z / height)
        _limb(B, base, base + dirv * L, r0 * 0.45, r0 * 0.2, m, 7)
        tips.append(base + dirv * L)
    return tips


def _limb(B, p0, p1, r0, r1, m, segs):
    d = p1 - p0
    mtx = Matrix.Translation((p0 + p1) / 2) @ d.to_track_quat("Z", "Y").to_matrix().to_4x4()
    r = bmesh.ops.create_cone(B.bm, cap_ends=True, segments=segs, radius1=r0, radius2=r1, depth=d.length,
                              matrix=mtx)
    for f in {f for v in r["verts"] for f in v.link_faces}:
        f.material_index = m
        f.smooth = len(f.verts) == 4


def make_tree(name, col, seed, leaf, height=3.2, spread=2.4, nblobs=7):
    """Broadleaf tree: a forked trunk carrying a ragged crown of leaf
    clumps, lighter on top and darker underneath (foliage shader)."""
    rng = random.Random(seed)
    B = Builder()
    tips = trunk(B, B.mi("bark"), height + 0.6, rng, branches=min(nblobs // 2, 4))
    li = B.mi(leaf)
    centre = Vector((0, 0, height + spread * 0.9))
    clumps = [(centre + Vector((0, 0, spread * 0.25)), spread * 0.8)]
    for t in tips[1:]:
        clumps.append((t + Vector((0, 0, spread * 0.15)), spread * rng.uniform(0.5, 0.62)))
    for k in range(nblobs - len(tips) + 1):
        a = math.tau * k / max(nblobs - len(tips) + 1, 1) + rng.uniform(-0.5, 0.5)
        rr = spread * rng.uniform(0.55, 0.8)
        clumps.append((centre + Vector((math.cos(a) * rr, math.sin(a) * rr, rng.uniform(-0.5, 0.8))),
                       spread * rng.uniform(0.45, 0.6)))
    clumps.append((centre + Vector((rng.uniform(-0.3, 0.3), rng.uniform(-0.3, 0.3), spread * 0.8)), spread * 0.5))
    for c, r in clumps:
        fol.clump(B.bm, c, (r, r, r * 0.9), rng, li, leaves=int(30 + 10 * r), leaf_size=(0.4, 0.62))
    ob = B.finish(name, col)
    bent_normals(ob, centre, li)
    return ob


def make_poplar(name, col, seed):
    """Lombardy poplar: a tall, narrow column of upward-pointing clumps."""
    rng = random.Random(seed)
    B = Builder()
    trunk(B, B.mi("bark"), 2.8, rng, branches=0, r0=0.25)
    li = B.mi("poplar")
    for k in range(8):
        z = 2.4 + k * 1.45
        r = 1.35 * math.sin(math.pi * (k + 0.9) / 8.8) + 0.3
        c = Vector((rng.uniform(-0.25, 0.25), rng.uniform(-0.25, 0.25), z))
        fol.clump(B.bm, c, (r, r, r * 1.25), rng, li, leaves=int(26 + 12 * r), leaf_size=(0.32, 0.48),
                  up_bias=0.6, droop=0.1)
    ob = B.finish(name, col)
    bent_normals(ob, Vector((0, 0, 7.5)), li, axis_scale=0.25)
    return ob


def make_bush(name, col, seed, flowers=False):
    rng = random.Random(seed)
    B = Builder()
    li = B.mi("bush")
    centre = Vector((0, 0, 0.45))
    for _ in range(4):
        c = Vector((rng.uniform(-0.8, 0.8), rng.uniform(-0.45, 0.45), rng.uniform(0.4, 0.65)))
        r = rng.uniform(0.55, 0.8)
        fol.clump(B.bm, c, (r, r, r * 0.85), rng, li, leaves=int(22 + 14 * r), leaf_size=(0.26, 0.4),
                  min_z=0.0)
    if flowers:
        fm = B.mi("flower")
        for _ in range(12):
            a = rng.uniform(0, math.tau)
            p = centre + Vector((math.cos(a) * 1.0, math.sin(a) * 0.62, rng.uniform(0.2, 0.65)))
            r = bmesh.ops.create_icosphere(B.bm, subdivisions=1, radius=0.09, matrix=Matrix.Translation(p))
            for f in {f for v in r["verts"] for f in v.link_faces}:
                f.material_index = fm
    ob = B.finish(name, col)
    bent_normals(ob, centre, li)
    return ob


def make_lamp(col):
    """Street lamp: chamfered concrete-grey base, smooth tapered pole, a
    chunky arm and a box head with a glowing diffuser underneath."""
    B = Builder()
    m, g = B.mi("metal"), B.mi("lamp_glass")
    X, Y = Vector((1, 0, 0)), Vector((0, 1, 0))
    B.cbox(Vector((0, 0, 0)), X, Y, 0.34, 0.34, 0.0, 0.55, m, 0.03)
    B.cylinder(Vector((0, 0, 0.55)), 0.1, 6.3, m, 12, r_top=0.065, smooth=True)
    B.cbox(Vector((0.62, 0, 0)), X, Y, 1.3, 0.1, 6.8, 6.92, m, 0.02)
    B.cbox(Vector((1.35, 0, 0)), X, Y, 0.78, 0.36, 6.74, 7.0, m, 0.035)
    B.cbox(Vector((1.35, 0, 0)), X, Y, 0.64, 0.26, 6.68, 6.75, g, 0.015)
    return B.finish("lamp", col)


def make_bench(col):
    """Park bench with chunky painted metal sides and thick, chamfered
    wooden slats (one degree of exaggeration, see docs/art_direction.md)."""
    B = Builder()
    m, wd = B.mi("fence_green", "#3f6e4a"), B.mi("wood")
    X, Y = Vector((1, 0, 0)), Vector((0, 1, 0))
    for k in range(3):
        B.cbox(Vector((0, -0.2 + k * 0.165, 0)), X, Y, 1.85, 0.14, 0.42, 0.48, wd, 0.012)
    for k in range(2):
        B.cbox(Vector((0, 0.29, 0)), X, Y, 1.85, 0.055, 0.6 + k * 0.18, 0.73 + k * 0.18, wd, 0.012)
    for sx in (-0.74, 0.74):
        B.cbox(Vector((sx, -0.2, 0)), X, Y, 0.08, 0.08, 0.0, 0.42, m, 0.012)       # front leg
        B.cbox(Vector((sx, 0.22, 0)), X, Y, 0.08, 0.08, 0.0, 0.42, m, 0.012)       # back leg
        B.cbox(Vector((sx, 0.01, 0)), X, Y, 0.08, 0.56, 0.36, 0.42, m, 0.012)      # seat rail
        B.cbox(Vector((sx, 0.29, 0)), X, Y, 0.08, 0.08, 0.42, 0.98, m, 0.012)      # back post
    return B.finish("bench", col)


# ----------------------------------------------------------------------------
def export(scn, path, objects):
    prev = bpy.context.window.scene
    bpy.context.window.scene = scn
    vl = scn.view_layers[0]
    for ob in scn.objects:
        ob.select_set(False, view_layer=vl)
    for ob in objects:
        ob.select_set(True, view_layer=vl)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, use_active_scene=True,
                              export_apply=True, export_yup=True)
    bpy.context.window.scene = prev


def run(root, stage="all"):
    data = bw.osm(root)
    out = os.path.join(root, "game", "levels", "corner")
    os.makedirs(out, exist_ok=True)
    scn = bpy.data.scenes.get("Corner3D") or bpy.data.scenes.new("Corner3D")
    col = scn.collection
    for ob in list(col.all_objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    for me in [m for m in bpy.data.meshes if m.users == 0]:
        bpy.data.meshes.remove(me)

    build_ground(data, col)
    nb = 0
    keys = list(WALLS)
    for w in data.ways:
        t = w["tags"]
        if "building" not in t:
            continue
        ring = bw.clean_ring(data.coords(w))
        if len(ring) < 3:
            continue
        cx = sum(p[0] for p in ring) / len(ring)
        cy = sum(p[1] for p in ring) / len(ring)
        if not near(cx, cy):
            continue
        kind, levels = bw.classify(t, ring)
        rng = random.Random(w["id"])
        B = Builder()
        M = block_materials(B, keys[w["id"] % len(keys)], rng)
        bkind = "tower" if levels > 8 else ("apartments" if kind == "apartments" else "other")
        build_block(B, ring, levels if kind == "apartments" else max(1, levels), rng, M, bkind)
        ob = B.finish("block_%d" % w["id"], col)
        ob["osm_id"] = w["id"]
        nb += 1
    for ob in col.all_objects:
        ob.location.x -= CENTRE[0]
        ob.location.y -= CENTRE[1]
    export(scn, os.path.join(out, "corner.glb"), list(col.all_objects))

    # props library
    pscn = bpy.data.scenes.get("Corner3DProps") or bpy.data.scenes.new("Corner3DProps")
    pcol = pscn.collection
    for ob in list(pcol.all_objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    lib = [make_tree("tree_a", pcol, 1, "leaf_a"), make_tree("tree_b", pcol, 2, "leaf_b", 3.6, 2.8, 8),
           make_tree("tree_c", pcol, 3, "leaf_c", 2.8, 2.1, 6), make_poplar("poplar", pcol, 4),
           make_bush("bush_a", pcol, 5), make_bush("bush_b", pcol, 6, flowers=True),
           make_lamp(pcol), make_bench(pcol)]
    for i, ob in enumerate(lib):
        ob.location.x = i * 8.0            # spread out for viewing; Godot resets positions
    export(pscn, os.path.join(out, "props.glb"), lib)

    # placements, reusing the scattered vegetation of the main world
    kinds = {"tree_round_a": "tree_a", "tree_round_b": "tree_b", "tree_round_c": "tree_c",
             "tree_poplar": "poplar", "bush": "bush_a", "lamp": "lamp", "bench": "bench"}
    props = []
    rng = random.Random(15)
    for ob in bpy.data.objects:
        if not ob.name.startswith(("Tree_", "Bush_", "Lamp_", "Bench_")):
            continue
        if not near(ob.location.x, ob.location.y, RADIUS + 30):
            continue
        k = kinds.get(ob.data.name.replace("M15_", "").lower())
        if not k:
            continue
        if k == "bush_a" and rng.random() < 0.4:
            k = "bush_b"
        props.append({"type": k, "pos": [round(ob.location.x - CENTRE[0], 2), round(-(ob.location.y - CENTRE[1]), 2)],
                      "rot": round(ob.rotation_euler.z, 3), "scale": round(ob.scale.x, 2)})
    json.dump(props, open(os.path.join(out, "props.json"), "w"))
    return {"buildings": nb, "props": len(props),
            "faces": sum(len(o.data.polygons) for o in col.all_objects if o.type == "MESH")}
