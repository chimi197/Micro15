"""Street kit for the in-game placement tool: things found around the blocks
of flats in Micro 15 that the map does not scatter on its own (metal fences,
lawn hoop fences, benches, bins, the big green waste containers, the carpet
beating frame, playground swings and slide, concrete chess tables,
bollards, bike racks, planters, hedges, pines and birches), and the shops
and outdoor things of its streets (a kiosk, a mini market, a shop window
for the ground floor of a block, a bus stop, a drinks fridge, an ice cream
freezer, recycling bins, a clothes drying frame, a café table with a
parasol and a fruit stall).

Every asset is one object standing on the origin, facing -Y (the front in
Godot is +Z), 1 unit = 1 metre. Materials are named like the rest of the
world (C3_*; names containing leaf/bush get the foliage shader in Godot).
The hedge, spruce and birch are modelled leaf by leaf with trees.py.
Writes game/assets/source/street_kit.glb; game/tools/make_assets.gd then
turns each object into a placeable scene in game/assets/.

    import sys; sys.path.insert(0, r"<repo>/blender")
    import build_assets; build_assets.run(r"<repo>")
"""
import math
import os
import random

import bmesh
import bpy
from mathutils import Matrix, Vector

import trees

COLOURS = {
    "fence_green": "#3f7a4a", "metal_dark": "#3a3f47", "metal_grey": "#8e969c", "wood": "#b77a45",
    "concrete": "#c9c4b8", "concrete_dark": "#a8a397", "bin_green": "#3d8a52", "container": "#2f6e45",
    "rubber": "#2a2b2e", "red": "#d0503c", "yellow": "#f0c040", "blue": "#3f78c8", "white": "#f2f0ea",
    "soil": "#6b4b34", "flower_red": "#e0475a", "flower_yellow": "#f6d04d", "trunk": "#7a5a43",
    "birch_bark": "#ece8df", "birch_mark": "#3d3a37", "pine_leaf": "#2f6a46", "bark": "#7a5034", "plant": "#4f8f3e", "birch_leaf": "#8cc65a", "hedge_bush": "#4f8f3e",
    "chess_dark": "#5a5650",
    # shops and outdoor things
    "wall_kiosk": "#efe6d2", "wall_shop": "#e7dcc4", "plinth_shop": "#8d8379", "metal_white": "#e9e7e1",
    "frame_shop": "#5b6470", "interior_dark": "#2b2d33", "interior_light": "#d8d2c4", "glass_glare": "#dfeaf0",
    "glass_dark": "#5d7180", "sign_red": "#c8423a", "sign_blue": "#2f5f9e", "sign_green": "#3f8a52",
    "sign_white": "#f4f1ea", "sign_yellow": "#f2c94c", "awning_red": "#c94b3f", "awning_white": "#f1ece2",
    "awning_green": "#3f7f57", "metal_red": "#b8352f", "metal_blue": "#2e69b0", "bin_blue": "#2f62a8",
    "bin_yellow": "#e8bd38", "bin_green_glass": "#3f8a4f", "plastic_white": "#eeebe4", "cloth_a": "#d9665b",
    "cloth_b": "#5b8fd1", "cloth_c": "#f0d26a", "cloth_d": "#f4f1ea", "cloth_e": "#7cbf86",
    "goods_a": "#d64f45", "goods_b": "#f0b23e", "goods_c": "#4f86c6", "goods_d": "#62a85a", "goods_e": "#f2efe6",
    "goods_f": "#8a5a9e", "goods_g": "#e9853a", "bottle_green": "#3f8f5f", "bottle_brown": "#7a4a2a",
    "fruit_red": "#c8322f", "fruit_orange": "#ef8a2c", "fruit_yellow": "#f2cf3d", "fruit_green": "#86b83f",
    "crate_wood": "#c49a63", "lamp_glass_fridge": "#f4f7f2", "roof_box": "#8f8a82",
}


def V(*a):
    return Vector(a[0] if len(a) == 1 else a)


def hex_rgba(h):
    h = h.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    c = [x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c]
    return (c[0], c[1], c[2], 1.0)


def material(name):
    """C3_<name>; a "<leaf>_core" material (the inner leaves of a cluster)
    takes its leaf's colour (the game darkens it)."""
    m = bpy.data.materials.get("C3_" + name)
    if m is None:
        m = bpy.data.materials.new("C3_" + name)
        c = hex_rgba(COLOURS[name.removesuffix("_core")])
        m.diffuse_color = c
        m.use_nodes = True
        bsdf = m.node_tree.nodes.get("Principled BSDF")
        if bsdf:
            bsdf.inputs["Base Color"].default_value = c
            bsdf.inputs["Roughness"].default_value = 1.0
    return m


class Kit:
    """bmesh builder with a material per face."""

    def __init__(self):
        self.bm = bmesh.new()
        self.mats = []

    def mi(self, name):
        m = material(name)
        if m not in self.mats:
            self.mats.append(m)
        return self.mats.index(m)

    def _tag(self, faces, mat, smooth):
        for f in faces:
            f.material_index = self.mi(mat)
            f.smooth = smooth

    # remember where the next piece of geometry starts
    def begin(self):
        """Builds the next piece in its own bmesh (end() merges it), so the
        bmesh operators never touch the pieces made before."""
        self.main = self.bm
        self.bm = bmesh.new()

    def new_verts(self):
        return list(self.bm.verts)

    def new_faces(self):
        return list(self.bm.faces)

    def end(self):
        piece, self.bm = self.bm, self.main
        vmap = {v: self.bm.verts.new(v.co) for v in piece.verts}
        src_uv = piece.loops.layers.uv.active
        dst_uv = self.bm.loops.layers.uv.verify() if src_uv else None
        for f in piece.faces:
            nf = self.bm.faces.new([vmap[v] for v in f.verts])
            nf.material_index = f.material_index
            nf.smooth = f.smooth
            if src_uv:
                for a, b in zip(f.loops, nf.loops):
                    b[dst_uv].uv = a[src_uv].uv
        piece.free()

    def block(self, c, size, mat, rot_z=0.0, bevel=0.0, smooth=False, segments=2):
        """Box centred on c, optionally with rounded (or, with segments=1,
        chamfered) edges."""
        self.begin()
        bmesh.ops.create_cube(self.bm, size=1.0)
        vs = list(self.new_verts())
        bmesh.ops.scale(self.bm, vec=V(size), verts=vs)
        if bevel > 0:
            self.bm.edges.ensure_lookup_table()
            edges = list({e for v in vs for e in v.link_edges})
            bmesh.ops.bevel(self.bm, geom=edges, offset=bevel, segments=segments, profile=0.5, affect="EDGES")
        bmesh.ops.transform(self.bm, matrix=Matrix.Translation(V(c)) @ Matrix.Rotation(rot_z, 4, "Z"),
                            verts=list(self.new_verts()))
        self._tag(self.new_faces(), mat, smooth)
        self.end()

    def rod(self, p0, p1, r, mat, seg=10, caps=True, r1=None):
        """Cylinder (or cone with r1) between two points."""
        self.pipe([V(p0), V(p1)], r, mat, seg, caps, r1)

    def pipe(self, pts, r, mat, seg=10, caps=True, r1=None):
        """Round tube along a polyline, with rings turned to follow the bends."""
        pts = [V(p) for p in pts]
        self.begin()
        n_prev = None
        rings = []
        for i, p in enumerate(pts):
            d = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
            if n_prev is None:
                ref = V(0, 0, 1) if abs(d.z) < 0.9 else V(1, 0, 0)
                n_prev = d.cross(ref).normalized()
            n = (n_prev - d * n_prev.dot(d)).normalized()
            b = d.cross(n)
            rr = r if r1 is None else r + (r1 - r) * i / (len(pts) - 1)
            rings.append([self.bm.verts.new(p + (n * math.cos(a) + b * math.sin(a)) * rr)
                          for a in (2 * math.pi * k / seg for k in range(seg))])
            n_prev = n
        for a, b in zip(rings, rings[1:]):
            for k in range(seg):
                self.bm.faces.new((a[k], a[(k + 1) % seg], b[(k + 1) % seg], b[k]))
        if caps:
            self.bm.faces.new(list(reversed(rings[0])))
            self.bm.faces.new(rings[-1])
        faces = list(self.new_faces())
        bmesh.ops.recalc_face_normals(self.bm, faces=faces)
        for f in faces:
            f.material_index = self.mi(mat)
            f.smooth = len(f.verts) == 4
        self.end()

    def blob(self, c, radii, mat, subdiv=2, noise=0.0, seed=0, flat_bottom=None):
        """Icosphere scaled to radii, optionally lumpy (canopies, hedges, flowers)."""
        self.begin()
        bmesh.ops.create_icosphere(self.bm, subdivisions=subdiv, radius=1.0)
        rnd = random.Random(seed)
        for v in self.new_verts():
            k = 1.0 + (rnd.uniform(-noise, noise) if noise else 0.0)
            v.co = V((v.co.x * radii[0] * k, v.co.y * radii[1] * k, v.co.z * radii[2] * k))
            if flat_bottom is not None:
                v.co.z = max(v.co.z, flat_bottom - c[2])
            v.co += V(c)
        self._tag(self.new_faces(), mat, True)
        self.end()

    def leaf(self, base, axis, normal, length, width, mat):
        """One small modelled leaf (trees.add_leaf), for potted plants."""
        trees.add_leaf(self.bm, None, V(base), V(axis).normalized(), V(normal).normalized(), length, width,
                       self.mi(mat))

    def text(self, body, centre, height, mat, depth=0.02, rot_z=0.0, align="CENTER"):
        """Raised block letters (Blender's built-in font), standing upright and
        reading towards -Y, centred on centre."""
        cu = bpy.data.curves.new("txt", "FONT")
        cu.body = body
        cu.align_x = align
        cu.align_y = "CENTER"
        cu.size = height / 0.72                  # cap height of the built-in font
        cu.extrude = depth / 2
        tmp = bpy.data.objects.new("txt", cu)
        bpy.context.scene.collection.objects.link(tmp)
        bpy.context.view_layer.update()
        me = bpy.data.meshes.new_from_object(tmp.evaluated_get(bpy.context.evaluated_depsgraph_get()))
        bpy.data.objects.remove(tmp, do_unlink=True)
        bpy.data.curves.remove(cu)
        self.begin()
        self.bm.from_mesh(me)
        bpy.data.meshes.remove(me)
        bmesh.ops.transform(self.bm, verts=list(self.bm.verts),
                            matrix=Matrix.Translation(V(centre)) @ Matrix.Rotation(rot_z, 4, "Z")
                            @ Matrix.Rotation(math.pi / 2, 4, "X"))
        self._tag(self.new_faces(), mat, False)
        self.end()

    def awning(self, x0, x1, y_wall, z_top, depth, drop, mats, stripes=8, valance=0.18):
        """Sloping striped awning from a wall (y_wall) out towards -Y, with a
        scalloped valance hanging from the front edge."""
        w = (x1 - x0) / stripes
        for i in range(stripes):
            m = mats[i % len(mats)]
            xa, xb = x0 + w * i, x0 + w * (i + 1)
            self.begin()
            vs = [self.bm.verts.new(c) for c in ((xa, y_wall, z_top), (xb, y_wall, z_top),
                                                  (xb, y_wall - depth, z_top - drop), (xa, y_wall - depth, z_top - drop))]
            f = self.bm.faces.new(vs)
            bmesh.ops.solidify(self.bm, geom=[f], thickness=0.02)
            self._tag(self.new_faces(), m, False)
            self.end()
            self.begin()                         # valance: a flap with a rounded bottom
            pts = [(xa, z_top - drop), (xb, z_top - drop), (xb, z_top - drop - valance * 0.7)] + [
                (xb - w * t / 6, z_top - drop - valance * 0.7 - valance * 0.3 * math.sin(math.pi * t / 6)) for t in range(1, 6)] + [
                (xa, z_top - drop - valance * 0.7)]
            vs = [self.bm.verts.new((x, y_wall - depth, z)) for x, z in pts]
            f = self.bm.faces.new(vs)
            bmesh.ops.solidify(self.bm, geom=[f], thickness=0.015)
            self._tag(self.new_faces(), m, False)
            self.end()
        self.rod((x0, y_wall - depth + 0.01, z_top - drop), (x1, y_wall - depth + 0.01, z_top - drop), 0.015,
                 "metal_dark", seg=6)
        for x in (x0 + 0.05, x1 - 0.05):        # folding arms
            self.rod((x, y_wall, z_top - drop - 0.35), (x, y_wall - depth + 0.03, z_top - drop), 0.012,
                     "metal_dark", seg=6)

    def glare(self, x0, x1, y, z0, z1, n=2, seed=0):
        """A few slanted light streaks standing for the glass of a pane (the
        game's materials are opaque, so shop windows stay open behind them)."""
        rnd = random.Random(seed)
        for i in range(n):
            u = rnd.uniform(0.15, 0.7)
            wdt = rnd.uniform(0.025, 0.06) * (x1 - x0)
            xa = x0 + (x1 - x0) * u
            self.begin()
            vs = [self.bm.verts.new(c) for c in ((xa, y, z0 + 0.02), (xa + wdt, y, z0 + 0.02),
                                                  (min(xa + wdt + (z1 - z0) * 0.45, x1 - 0.01), y, z1 - 0.02),
                                                  (min(xa + (z1 - z0) * 0.45, x1 - 0.02), y, z1 - 0.02))]
            f = self.bm.faces.new(vs)
            bmesh.ops.solidify(self.bm, geom=[f], thickness=0.004)
            self._tag(self.new_faces(), "glass_glare", False)
            self.end()

    def goods(self, x0, x1, y, z, depth, rnd, kinds=("box", "bottle", "jar")):
        """A shelf's worth of packets, bottles and jars in shop colours."""
        x = x0 + 0.03
        while x < x1 - 0.08:
            kind = rnd.choice(kinds)
            if kind == "box":
                w, h = rnd.uniform(0.08, 0.16), rnd.uniform(0.12, 0.28)
                self.block((x + w / 2, y, z + h / 2), (w * 0.92, depth * rnd.uniform(0.5, 0.9), h),
                           rnd.choice(["goods_a", "goods_b", "goods_c", "goods_d", "goods_e", "goods_f", "goods_g"]))
                x += w
            elif kind == "bottle":
                m = rnd.choice(["bottle_green", "bottle_brown", "goods_c", "goods_a", "goods_e"])
                for j in range(rnd.randint(2, 4)):
                    cx = x + 0.035 + j * 0.07
                    if cx > x1 - 0.04:
                        break
                    self.rod((cx, y, z), (cx, y, z + 0.2), 0.03, m, seg=8)
                    self.rod((cx, y, z + 0.2), (cx, y, z + 0.27), 0.03, m, seg=8, r1=0.012)
                    self.rod((cx, y, z + 0.27), (cx, y, z + 0.29), 0.013, "goods_e", seg=6)
                x += 0.07 * rnd.randint(2, 4) + 0.02
            else:
                m = rnd.choice(["goods_b", "goods_d", "goods_a", "goods_g"])
                self.rod((x + 0.05, y, z), (x + 0.05, y, z + 0.11), 0.045, m, seg=10)
                self.rod((x + 0.05, y, z + 0.11), (x + 0.05, y, z + 0.13), 0.047, "goods_e", seg=10)
                x += 0.11
            x += 0.015

    def to_object(self, name, col):
        bmesh.ops.remove_doubles(self.bm, verts=self.bm.verts, dist=1e-5)
        me = bpy.data.meshes.new(name)
        self.bm.to_mesh(me)
        self.bm.free()
        for m in self.mats:
            me.materials.append(m)
        ob = bpy.data.objects.new(name, me)
        col.objects.link(ob)
        return ob


# ----------------------------------------------------------------------------
# Assets
# ----------------------------------------------------------------------------
def fence_metal(k):
    """2 m panel of the painted tube fences around school yards and lawns:
    square posts, two rails, round bars with small spear tips."""
    L, H = 2.0, 1.2
    for x in (-L / 2, L / 2):
        k.block((x, 0, H / 2 + 0.03), (0.06, 0.06, H + 0.06), "fence_green", bevel=0.008)
        k.block((x, 0, H + 0.07), (0.075, 0.075, 0.02), "fence_green", bevel=0.006)
    for z in (0.14, H - 0.12):
        k.block((0, 0, z), (L, 0.04, 0.03), "fence_green", bevel=0.006)
    n = 15
    for i in range(1, n):
        x = -L / 2 + L * i / n
        k.rod((x, 0, 0.06), (x, 0, H - 0.02), 0.009, "fence_green", seg=8, caps=False)
        k.rod((x, 0, H - 0.02), (x, 0, H + 0.06), 0.015, "fence_green", seg=8, r1=0.001)


def fence_low(k):
    """2 m of the knee-high hoop fence that edges the lawns between blocks."""
    L = 2.0
    for x in (-L / 2, L / 2):
        k.rod((x, 0, 0.0), (x, 0, 0.5), 0.018, "fence_green", seg=10)
        k.blob((x, 0, 0.51), (0.024, 0.024, 0.024), "fence_green", subdiv=1)
    k.rod((-L / 2, 0, 0.42), (L / 2, 0, 0.42), 0.012, "fence_green", seg=8)
    hoops = 5
    for i in range(hoops):
        x0 = -L / 2 + L * i / hoops
        w = L / hoops
        pts = [(x0 + w * (0.5 - 0.5 * math.cos(math.pi * t / 10)), 0, 0.42 * math.sin(math.pi * t / 10) ** 0.8)
               for t in range(11)]
        k.pipe(pts, 0.008, "fence_green", seg=6, caps=False)


def bench_wood(k):
    """Park bench: chunky cast iron sides, thick chamfered wooden slats."""
    L = 1.8
    for x in (-L / 2 + 0.12, L / 2 - 0.12):
        k.pipe([(x, -0.22, 0.0), (x, -0.2, 0.43), (x, 0.2, 0.43), (x, 0.22, 0.0)], 0.03, "metal_dark", seg=10)
        k.pipe([(x, 0.18, 0.43), (x, 0.26, 0.85)], 0.028, "metal_dark", seg=10)
        k.pipe([(x, -0.2, 0.43), (x, -0.18, 0.62), (x, 0.05, 0.66), (x, 0.2, 0.62)], 0.024, "metal_dark", seg=10)
        for y in (-0.22, 0.22):
            k.block((x, y, 0.015), (0.09, 0.09, 0.03), "metal_dark", bevel=0.01, segments=1)   # feet
    for i in range(4):
        k.block((0, -0.18 + i * 0.12, 0.46), (L, 0.105, 0.05), "wood", bevel=0.012, segments=1)
    for i in range(3):
        t = 0.5 + i * 0.12
        k.block((0, 0.19 + 0.08 * (t - 0.43) / 0.42 * 2.0 - 0.02, t), (L, 0.045, 0.1), "wood",
                bevel=0.012, segments=1)


def trash_bin(k):
    """Small street bin on a post."""
    k.rod((0, 0.12, 0), (0, 0.12, 0.95), 0.03, "metal_dark", seg=10)
    k.pipe([(0, 0, 0.35), (0, 0, 0.85)], 0.2, "bin_green", seg=20, caps=False)
    k.rod((0, 0, 0.35), (0, 0, 0.37), 0.2, "bin_green", seg=20)
    k.pipe([(0, 0, 0.85), (0, 0, 0.88)], 0.21, "metal_dark", seg=20)


def dumpster(k):
    """The big green 1100 l waste container with a curved lid and wheels."""
    W, D, H = 1.3, 1.05, 1.05
    k.block((0, 0, 0.18 + H / 2), (W, D, H), "container", bevel=0.04)
    lid = [(0, -D / 2 - 0.02 + (D + 0.04) * (0.5 - 0.5 * math.cos(math.pi * t / 8)),
            0.18 + H + 0.1 * math.sin(math.pi * t / 8)) for t in range(9)]
    k.begin()
    rows = []
    for x in (-W / 2 - 0.02, W / 2 + 0.02):
        rows.append([k.bm.verts.new((x, y, z)) for y, z in [(p[1], p[2]) for p in lid]])
    for j in range(len(lid) - 1):
        k.bm.faces.new((rows[0][j], rows[0][j + 1], rows[1][j + 1], rows[1][j]))
    k.bm.faces.new(rows[0])
    k.bm.faces.new(list(reversed(rows[1])))
    faces = list(k.new_faces())
    bmesh.ops.recalc_face_normals(k.bm, faces=faces)
    k._tag(faces, "container", True)
    k.end()
    for x in (-W / 2 + 0.15, W / 2 - 0.15):
        for y in (-D / 2 + 0.15, D / 2 - 0.15):
            k.rod((x, y, 0.18), (x, y, 0.12), 0.03, "metal_grey", seg=8)
            k.rod((x - 0.03, y, 0.08), (x + 0.03, y, 0.08), 0.08, "rubber", seg=14)
    k.rod((-W / 2 - 0.06, D / 2 + 0.03, 0.9), (W / 2 + 0.06, D / 2 + 0.03, 0.9), 0.02, "metal_grey", seg=8)


def carpet_beater(k):
    """The carpet beating frame every courtyard has: a tall pipe goalpost
    with a second rail."""
    L, H = 2.6, 2.1
    for x in (-L / 2, L / 2):
        k.rod((x, 0, 0), (x, 0, H), 0.04, "metal_grey", seg=12)
        k.blob((x, 0, H + 0.01), (0.045, 0.045, 0.045), "metal_grey", subdiv=1)
    k.rod((-L / 2, 0, H - 0.05), (L / 2, 0, H - 0.05), 0.03, "metal_grey", seg=10)
    k.rod((-L / 2, 0, H - 0.45), (L / 2, 0, H - 0.45), 0.025, "metal_grey", seg=10)
    for x in (-L / 2, L / 2):
        k.rod((x, 0, -0.02), (x, 0, 0.06), 0.12, "concrete", seg=12)


def swing(k):
    """Playground swing: A-frame legs, top bar, two seats on chains."""
    L, H = 2.6, 2.2
    for x in (-L / 2, L / 2):
        for y in (-0.6, 0.6):
            k.rod((x, y, 0), (x, 0, H), 0.04, "red", seg=10)
    k.rod((-L / 2 - 0.05, 0, H), (L / 2 + 0.05, 0, H), 0.045, "yellow", seg=12)
    for x in (-0.55, 0.55):
        for dx in (-0.2, 0.2):
            k.rod((x + dx, 0, H - 0.04), (x + dx, 0, 0.45), 0.008, "metal_grey", seg=6)
        k.block((x, 0, 0.43), (0.46, 0.18, 0.04), "rubber", bevel=0.01)


def slide(k):
    """Playground slide as in the courtyards of the blocks: a slanted ladder
    with round rungs and handrails up to a railed platform on four posts, a
    sit-down bar, and a deep chute with rolled rims that curves down to a
    flat run-out on its own legs."""
    H = 1.4                                  # platform deck height
    P = 0.36                                 # half the platform width
    y0, y1 = 0.35, 1.07                      # platform front (chute side) and back (ladder side)
    # posts and deck
    for x in (-P, P):
        for y in (y0, y1):
            k.rod((x, y, 0), (x, y, H + 0.85), 0.032, "yellow", seg=10)
            k.blob((x, y, H + 0.86), (0.036, 0.036, 0.03), "yellow", subdiv=1)
            k.rod((x, y, -0.02), (x, y, 0.04), 0.07, "concrete", seg=10)     # footings
    k.block((0, (y0 + y1) / 2, H), (2 * P + 0.02, y1 - y0 + 0.02, 0.05), "blue", bevel=0.012)
    for x in (-P, P):                        # deck frame under the plate
        k.rod((x, y0, H - 0.04), (x, y1, H - 0.04), 0.022, "yellow", seg=8)
    for y in (y0, y1):
        k.rod((-P, y, H - 0.04), (P, y, H - 0.04), 0.022, "yellow", seg=8)
    # guard rails on the two open sides, top and middle
    for x in (-P, P):
        for z in (H + 0.4, H + 0.8):
            k.rod((x, y0, z), (x, y1, z), 0.02, "yellow", seg=8)
        for i in range(1, 4):
            y = y0 + (y1 - y0) * i / 4
            k.rod((x, y, H + 0.03), (x, y, H + 0.8), 0.011, "yellow", seg=6)
    k.rod((-P, y0, H + 0.62), (P, y0, H + 0.62), 0.022, "blue", seg=10)          # sit-down bar
    # ladder: two slanted stringers from the ground behind to the deck, rungs
    # all the way up, handrails that carry on above the deck
    foot = y1 + 0.55
    for x in (-0.24, 0.24):
        k.rod((x, foot, 0), (x, y1, H), 0.028, "yellow", seg=10)
        yb, zb = foot + (y1 - foot) * 0.2, H * 0.2          # rises from the stringer near the foot
        k.pipe([(x, yb, zb), (x, yb - 0.02, zb + 0.75), (x, y1 + 0.02, H + 0.85), (x, y1 - 0.04, H + 0.85)],
               0.02, "yellow", seg=8)
    n = 6
    for i in range(1, n + 1):
        t = i / (n + 1)
        y, z = foot + (y1 - foot) * t, H * t
        k.rod((-0.24, y, z), (0.24, y, z), 0.016, "metal_grey", seg=8)
    # chute: a deep U channel, from the deck edge down a curve to a flat end
    W, wall = 0.25, 0.2
    prof = [(-W - 0.02, wall), (-W, 0.03), (-W + 0.05, 0.0), (W - 0.05, 0.0), (W, 0.03), (W + 0.02, wall)]
    path = []
    steps = 18
    run = 1.9                                # horizontal length of the slope
    for i in range(steps + 1):
        t = i / steps
        s_ = t * t * (3 - 2 * t)             # eases in at the top, flattens at the bottom
        path.append((y0 + 0.02 - run * t, H + 0.02 - (H - 0.32) * s_))
    path.append((path[-1][0] - 0.45, 0.32))   # flat run-out
    k.begin()
    rings = []
    for y, z in path:
        rings.append([k.bm.verts.new((px, y, z + pz)) for px, pz in prof])
    for a, b in zip(rings, rings[1:]):
        for j in range(len(prof) - 1):
            k.bm.faces.new((a[j], a[j + 1], b[j + 1], b[j]))
    faces = list(k.new_faces())
    bmesh.ops.solidify(k.bm, geom=faces, thickness=0.025)
    k._tag(list(k.new_faces()), "red", True)
    k.end()
    for side in (-1, 1):                     # rolled rims along the top of the walls
        k.pipe([(side * (W + 0.025), y, z + wall) for y, z in path], 0.022, "red", seg=8)
    # legs under the run-out and under the middle of the slope
    yl = path[-1][0] + 0.2
    ym, zm = path[steps // 2]
    for x in (-W + 0.04, W - 0.04):
        k.rod((x, yl, 0), (x, yl, 0.31), 0.026, "yellow", seg=8)
        k.rod((x, ym, 0), (x, ym, zm - 0.01), 0.026, "yellow", seg=8)
    k.rod((-W + 0.04, yl, 0.12), (W - 0.04, yl, 0.12), 0.018, "yellow", seg=6)
    k.rod((-W + 0.04, ym, 0.3), (W - 0.04, ym, 0.3), 0.018, "yellow", seg=6)


def chess_table(k):
    """Round concrete chess table with two stools, as in the parks of Satu Mare."""
    k.rod((0, 0, 0), (0, 0, 0.7), 0.12, "concrete_dark", seg=16)
    k.rod((0, 0, 0.68), (0, 0, 0.76), 0.42, "concrete", seg=28)
    for i in range(8):
        for j in range(8):
            if (i + j) % 2 == 0:
                k.block((-0.14 + 0.04 * i, -0.14 + 0.04 * j, 0.762), (0.04, 0.04, 0.004), "chess_dark")
    for y in (-0.75, 0.75):
        k.rod((0, y, 0), (0, y, 0.42), 0.09, "concrete_dark", seg=14)
        k.rod((0, y, 0.4), (0, y, 0.46), 0.2, "concrete", seg=20)


def bollard(k):
    k.rod((0, 0, 0), (0, 0, 0.75), 0.08, "metal_dark", seg=14)
    k.blob((0, 0, 0.75), (0.08, 0.08, 0.05), "metal_dark", subdiv=2)
    k.rod((0, 0, 0.6), (0, 0, 0.64), 0.082, "white", seg=14)


def bike_rack(k):
    for x in (-0.6, -0.2, 0.2, 0.6):
        k.pipe([(x, -0.3, 0)] + [(x, -0.3 + 0.6 * (0.5 - 0.5 * math.cos(math.pi * t / 8)),
                                   0.8 * math.sin(math.pi * t / 8) ** 0.6) for t in range(1, 8)] + [(x, 0.3, 0)],
               0.022, "metal_grey", seg=8)
    k.rod((-0.65, 0, 0.35), (0.65, 0, 0.35), 0.018, "metal_grey", seg=8)


def planter(k):
    """Concrete flower box with flowers."""
    k.block((0, 0, 0.25), (1.2, 0.6, 0.5), "concrete", bevel=0.02)
    k.block((0, 0, 0.49), (1.1, 0.5, 0.02), "soil")
    rnd = random.Random(4)
    for i in range(14):
        x, y = rnd.uniform(-0.48, 0.48), rnd.uniform(-0.18, 0.18)
        top = V(x, y, rnd.uniform(0.6, 0.7))
        k.rod((x, y, 0.5), top, 0.006, "plant", seg=4, caps=False)
        for j in range(6):                                   # leaves around the stem
            a = rnd.uniform(0, math.tau)
            z = rnd.uniform(0.52, top.z - 0.03)
            d = V(math.cos(a), math.sin(a), rnd.uniform(0.1, 0.5))
            k.leaf((x, y, z), d, V(0, 0, 1) - d * d.z, rnd.uniform(0.07, 0.1), 0.045, "plant")
        k.blob(top, (0.035, 0.035, 0.025), rnd.choice(["flower_red", "flower_yellow"]), subdiv=1)


def kiosk(k):
    """Corner kiosk ("chioșc") selling papers, snacks and drinks: a little
    cream booth on a plinth with shelves of goods behind its front windows,
    a serving hatch under a striped awning and a lit NON STOP sign."""
    W, D, H, z0 = 2.6, 2.0, 2.45, 0.12
    rnd = random.Random(21)
    k.block((0, 0, z0 / 2), (W + 0.12, D + 0.12, z0), "concrete", bevel=0.01)
    k.block((0, D / 2 - 0.04, z0 + H / 2), (W, 0.08, H), "wall_kiosk", bevel=0.01)
    for sx in (-1, 1):
        k.block((sx * (W / 2 - 0.04), 0, z0 + H / 2), (0.08, D, H), "wall_kiosk", bevel=0.01)
        k.block((sx * (W / 2 - 0.09), 0.05, z0 + H / 2), (0.02, D - 0.2, H - 0.05), "interior_dark")
    k.block((0, -D / 2 + 0.04, z0 + 0.45), (W, 0.08, 0.9), "wall_kiosk", bevel=0.01)
    k.block((0, -D / 2 + 0.04, z0 + H - 0.12), (W, 0.08, 0.24), "wall_kiosk", bevel=0.01)
    k.block((0, D / 2 - 0.1, z0 + H / 2), (W - 0.16, 0.02, H - 0.05), "interior_dark")
    k.block((0, 0, z0 + H - 0.26), (W - 0.16, D - 0.16, 0.02), "interior_dark")
    k.block((0, 0, z0 + 0.02), (W - 0.16, D - 0.16, 0.04), "interior_dark")
    # window frame: three panes, the middle one the open serving hatch
    zA, zB = z0 + 0.9, z0 + H - 0.24
    xs = (-W / 2 + 0.06, -0.42, 0.42, W / 2 - 0.06)
    for x in xs:
        k.block((x, -D / 2 + 0.03, (zA + zB) / 2), (0.05, 0.07, zB - zA), "metal_white")
    for z in (zA, zB):
        k.block((0, -D / 2 + 0.03, z), (W - 0.06, 0.07, 0.05), "metal_white")
    k.block((0, -D / 2 - 0.12, zA + 0.02), (0.9, 0.3, 0.04), "metal_white", bevel=0.008)     # hatch ledge
    k.glare(xs[0], xs[1], -D / 2 + 0.02, zA, zB, n=2, seed=1)
    k.glare(xs[2], xs[3], -D / 2 + 0.02, zA, zB, n=2, seed=2)
    # shelves of goods behind the windows, and the back rack
    for z in (zA + 0.08, zA + 0.5, zA + 0.92):
        k.block((0, -D / 2 + 0.32, z), (W - 0.3, 0.36, 0.025), "metal_white")
        k.goods(-W / 2 + 0.2, W / 2 - 0.2, -D / 2 + 0.3, z + 0.013, 0.2, rnd)
    k.block((0, D / 2 - 0.3, z0 + 1.2), (W - 0.4, 0.36, 1.9), "interior_light")
    for z in (z0 + 0.9, z0 + 1.3, z0 + 1.7):
        k.goods(-W / 2 + 0.3, W / 2 - 0.3, D / 2 - 0.5, z, 0.12, rnd, ("box",))
    # roof, sign, awning, side poster
    k.block((0, 0, z0 + H + 0.06), (W + 0.3, D + 0.3, 0.12), "metal_white", bevel=0.02)
    k.block((0, -D / 2 - 0.1, z0 + H + 0.38), (W + 0.3, 0.2, 0.52), "sign_red", bevel=0.015)
    k.text("NON STOP", (0, -D / 2 - 0.21, z0 + H + 0.38), 0.27, "sign_white", depth=0.02)
    k.awning(-W / 2, W / 2, -D / 2, z0 + H - 0.04, 0.5, 0.16, ["awning_red", "awning_white"], stripes=8,
             valance=0.12)
    k.block((W / 2 + 0.006, 0, z0 + 1.45), (0.012, 1.3, 1.1), "sign_yellow", bevel=0.004)
    k.text("ZIARE", (W / 2 + 0.02, 0, z0 + 1.7), 0.22, "sign_blue", rot_z=math.pi / 2)
    k.text("CAFEA", (W / 2 + 0.02, 0, z0 + 1.25), 0.22, "sign_red", rot_z=math.pi / 2)


def mini_market(k):
    """Neighbourhood mini market: a one-storey shop with big windows full of
    shelves, a glass double door up two steps, a MINI MARKET sign band, a
    flat roof with a parapet and an air conditioner on the side."""
    W, D, H, z0, t = 6.0, 4.4, 3.3, 0.3, 0.2
    rnd = random.Random(31)
    k.block((0, 0, z0 / 2), (W + 0.2, D + 0.2, z0), "plinth_shop", bevel=0.01)
    k.block((0, -D / 2 - 0.35, z0 / 4), (1.9, 0.7, z0 / 2), "concrete", bevel=0.01)          # steps
    k.block((0, -D / 2 - 0.17, z0 * 0.75), (1.9, 0.34, z0 / 2), "concrete", bevel=0.01)
    k.block((0, D / 2 - t / 2, z0 + H / 2), (W, t, H), "wall_shop")
    for sx in (-1, 1):
        k.block((sx * (W / 2 - t / 2), 0, z0 + H / 2), (t, D, H), "wall_shop")
    # front: piers, window plinths, lintel band
    zs, zh = z0 + 0.5, z0 + 2.5                         # window sill and head
    win = [(-2.7, -0.65), (0.65, 2.7)]
    for x0, x1 in [(-W / 2, -2.7), (-0.65, -0.6), (0.6, 0.65), (2.7, W / 2)]:
        k.block(((x0 + x1) / 2, -D / 2 + t / 2, z0 + H / 2), (x1 - x0, t, H), "wall_shop")
    for x0, x1 in win:
        k.block(((x0 + x1) / 2, -D / 2 + t / 2, z0 + 0.25), (x1 - x0, t + 0.04, 0.5), "plinth_shop")
    k.block((0, -D / 2 + t / 2, (zh + z0 + H) / 2), (W, t, z0 + H - zh), "wall_shop")
    # interior: light walls, ceiling, floor
    k.block((0, D / 2 - t - 0.01, z0 + H / 2), (W - 2 * t, 0.02, H), "interior_light")
    for sx in (-1, 1):
        k.block((sx * (W / 2 - t - 0.01), 0, z0 + H / 2), (0.02, D - 2 * t, H), "interior_light")
    k.block((0, 0, z0 + 2.75), (W - 2 * t, D - 2 * t, 0.02), "sign_white")
    k.block((0, 0, z0 + 0.01), (W - 2 * t, D - 2 * t, 0.02), "plinth_shop")
    # window frames, glass and the shelves behind them
    for x0, x1 in win:
        for x in (x0 + 0.03, (x0 + x1) / 2, x1 - 0.03):
            k.block((x, -D / 2 + 0.05, (zs + zh) / 2), (0.06, 0.08, zh - zs), "frame_shop")
        for z in (zs, zh):
            k.block(((x0 + x1) / 2, -D / 2 + 0.05, z), (x1 - x0, 0.08, 0.06), "frame_shop")
        k.glare(x0 + 0.06, (x0 + x1) / 2 - 0.03, -D / 2 + 0.03, zs, zh, n=2, seed=int(x0 * 10))
        k.glare((x0 + x1) / 2 + 0.03, x1 - 0.06, -D / 2 + 0.03, zs, zh, n=1, seed=int(x1 * 10))
        for z in (z0 + 0.35, z0 + 0.85, z0 + 1.35, z0 + 1.85):
            k.block(((x0 + x1) / 2, -D / 2 + 0.75, z), (x1 - x0 - 0.1, 0.45, 0.025), "metal_white")
            k.goods(x0 + 0.05, x1 - 0.05, -D / 2 + 0.72, z + 0.013, 0.3, rnd)
        k.block(((x0 + x1) / 2, -D / 2 + 0.98, z0 + 1.1), (x1 - x0 - 0.1, 0.02, 2.0), "metal_white")
    for z in (z0 + 0.5, z0 + 1.0, z0 + 1.5, z0 + 2.0):                                       # back wall
        k.block((0, D / 2 - t - 0.25, z), (W - 0.8, 0.45, 0.025), "metal_white")
        k.goods(-W / 2 + 0.5, W / 2 - 0.5, D / 2 - t - 0.28, z + 0.013, 0.3, rnd)
    # glass double door
    zd = z0 + 2.25
    for x in (-0.6, 0.0, 0.6):
        k.block((x, -D / 2 + 0.05, (z0 + zd) / 2), (0.07, 0.08, zd - z0), "frame_shop")
    for z in (z0 + 0.04, z0 + 0.95, zd):
        k.block((0, -D / 2 + 0.05, z), (1.2, 0.08, 0.08 if z != z0 + 0.95 else 0.05), "frame_shop")
    k.block((0, -D / 2 + 0.05, (zd + zh) / 2 + 0.02), (1.2, 0.08, zh - zd), "frame_shop")
    for x in (-0.3, 0.3):
        k.glare(x - 0.26, x + 0.26, -D / 2 + 0.02, z0 + 0.1, zd - 0.05, n=1, seed=int(x * 100) + 5)
        k.rod((x - 0.12 * (1 if x > 0 else -1), -D / 2 - 0.02, z0 + 0.85),
              (x - 0.12 * (1 if x > 0 else -1), -D / 2 - 0.02, z0 + 1.35), 0.015, "metal_grey", seg=6)
    k.block((0.3, -D / 2 + 0.0, z0 + 1.55), (0.36, 0.01, 0.16), "sign_green")
    k.text("DESCHIS", (0.3, -D / 2 - 0.007, z0 + 1.55), 0.07, "sign_white", depth=0.006)
    # sign band, roof, parapet, AC unit
    k.block((0, -D / 2 - 0.08, z0 + 2.9), (W - 0.3, 0.16, 0.62), "sign_blue", bevel=0.02)
    k.text("MINI MARKET", (0, -D / 2 - 0.17, z0 + 2.9), 0.36, "sign_white", depth=0.025)
    k.block((0, 0, z0 + H + 0.08), (W + 0.06, D + 0.06, 0.16), "roof_box")
    for sx in (-1, 1):
        k.block((sx * (W / 2 - 0.07), 0, z0 + H + 0.3), (0.14, D + 0.06, 0.32), "wall_shop")
    for sy in (-1, 1):
        k.block((0, sy * (D / 2 - 0.07), z0 + H + 0.3), (W + 0.06, 0.14, 0.32), "wall_shop")
    k.block((W / 2 + 0.18, 0.9, z0 + 2.2), (0.32, 0.8, 0.55), "metal_white", bevel=0.02)
    k.rod((W / 2 + 0.34, 0.75, z0 + 2.2), (W / 2 + 0.35, 0.75, z0 + 2.2), 0.2, "metal_grey", seg=16)
    k.rod((W / 2 + 0.1, 1.2, z0 + 1.9), (W / 2 + 0.1, 1.2, 0.0), 0.012, "metal_white", seg=6)    # drain line


def shop_window(k):
    """Shop window ("vitrină") for the ground floor of a block: stands with
    its back on the wall (origin), a granite sill, a display of goods on
    stands and two dress forms, a MAGAZIN sign band and a striped awning."""
    W, Dp, H = 2.6, 0.5, 2.6
    rnd = random.Random(41)
    zs, zh = 0.5, 2.35
    k.block((0, -0.25, zs / 2), (W, 0.5, zs), "plinth_shop", bevel=0.01)
    for sx in (-1, 1):
        k.block((sx * (W / 2 - 0.08), -Dp / 2, H / 2), (0.16, Dp, H), "frame_shop", bevel=0.01)
    k.block((0, -Dp / 2, (zh + H) / 2), (W, Dp, H - zh), "frame_shop", bevel=0.01)
    k.block((0, -0.02, (zs + zh) / 2), (W - 0.3, 0.04, zh - zs), "interior_light")
    k.block((0, -Dp / 2, zs + 0.01), (W - 0.3, Dp - 0.04, 0.02), "wood")
    k.block((0, -Dp / 2, zh - 0.02), (W - 0.3, Dp - 0.04, 0.04), "interior_dark")
    k.block((0, -Dp + 0.03, zs + 0.02), (W - 0.3, 0.05, 0.05), "frame_shop")             # glass frame
    k.block((0, -Dp + 0.03, zh - 0.02), (W - 0.3, 0.05, 0.05), "frame_shop")
    k.glare(-W / 2 + 0.16, W / 2 - 0.16, -Dp + 0.01, zs, zh, n=3, seed=7)
    for x, h in ((-0.75, 0.22), (0.1, 0.12), (0.8, 0.3)):                                # stands with goods
        k.block((x, -0.28, zs + h / 2), (0.42, 0.3, h), "sign_white", bevel=0.01)
        k.goods(x - 0.2, x + 0.2, -0.28, zs + h, 0.18, rnd, ("box", "jar"))
    for x, m in ((-0.3, "cloth_a"), (0.45, "cloth_b")):                                  # dress forms
        k.rod((x, -0.2, zs), (x, -0.2, zs + 0.5), 0.012, "metal_dark", seg=6)
        k.rod((x, -0.2, zs), (x, -0.2, zs + 0.02), 0.12, "metal_dark", seg=12)
        k.rod((x, -0.2, zs + 0.5), (x, -0.2, zs + 1.05), 0.2, m, seg=14, r1=0.13)
        k.blob((x, -0.2, zs + 1.12), (0.14, 0.1, 0.1), m, subdiv=2)
        k.rod((x, -0.2, zs + 1.2), (x, -0.2, zs + 1.3), 0.03, "metal_dark", seg=6)
    k.block((0, -Dp - 0.04, (zh + H) / 2), (W - 0.1, 0.06, H - zh - 0.04), "sign_white")
    k.text("MAGAZIN", (0, -Dp - 0.075, (zh + H) / 2), 0.15, "sign_blue", depth=0.012)
    k.awning(-W / 2, W / 2, 0.0, H + 0.45, 1.0, 0.45, ["awning_green", "awning_white"], stripes=9)


def bus_stop(k):
    """Bus shelter: steel frame, a back wall and one side of glass, a bench,
    a sloping roof with a STAȚIE fascia, and the stop's sign on a pole."""
    L, D, H = 3.8, 1.4, 2.45
    for x in (-L / 2 + 0.05, L / 2 - 0.05):
        for y in (-D / 2 + 0.1, D / 2 - 0.05):
            k.block((x, y, H / 2), (0.08, 0.08, H), "metal_dark", bevel=0.01)
            k.block((x, y, 0.02), (0.18, 0.18, 0.04), "metal_dark", bevel=0.01)
    k.begin()                                    # roof slab, falling to the back
    vs = [k.bm.verts.new(c) for c in ((-L / 2 - 0.15, -D / 2 - 0.25, H + 0.12), (L / 2 + 0.15, -D / 2 - 0.25, H + 0.12),
                                      (L / 2 + 0.15, D / 2 + 0.15, H + 0.02), (-L / 2 - 0.15, D / 2 + 0.15, H + 0.02))]
    f = k.bm.faces.new(vs)
    bmesh.ops.solidify(k.bm, geom=[f], thickness=0.06)
    k._tag(k.new_faces(), "metal_dark", False)
    k.end()
    k.block((0, -D / 2 - 0.27, H + 0.12), (L + 0.32, 0.05, 0.3), "metal_blue", bevel=0.008)
    k.text("STAȚIE", (0, -D / 2 - 0.3, H + 0.12), 0.17, "sign_white", depth=0.012)
    k.block((0, D / 2 - 0.05, H / 2 + 0.1), (L - 0.12, 0.03, H - 0.4), "glass_dark")       # back glass
    k.block((L / 2 - 0.05, 0, H / 2 + 0.1), (0.03, D - 0.2, H - 0.4), "glass_dark")       # side glass
    k.glare(-L / 2 + 0.1, L / 2 - 0.1, D / 2 - 0.07, 0.3, H - 0.1, n=3, seed=3)
    for z in (0.25, H - 0.08):
        k.block((0, D / 2 - 0.05, z), (L - 0.12, 0.05, 0.05), "metal_dark")
    k.block((L / 2 - 0.05, 0.0, 0.25), (0.05, D - 0.2, 0.05), "metal_dark")
    k.block((-L / 2 + 0.6, D / 2 - 0.08, 1.45), (0.9, 0.02, 1.3), "sign_white")            # timetable poster
    k.block((-L / 2 + 0.6, D / 2 - 0.095, 1.7), (0.7, 0.01, 0.06), "sign_blue")
    for i in range(6):
        k.block((-L / 2 + 0.6, D / 2 - 0.095, 1.5 - i * 0.12), (0.6, 0.01, 0.025), "goods_c")
    for x in (-0.9, 0.9):                                                                   # bench
        k.block((x, D / 2 - 0.35, 0.22), (0.06, 0.06, 0.44), "metal_grey")
    for i in range(3):
        k.block((0, D / 2 - 0.5 + i * 0.13, 0.46), (2.2, 0.1, 0.035), "wood", bevel=0.01, segments=1)
    k.rod((-L / 2 - 0.35, -D / 2 - 0.1, 0), (-L / 2 - 0.35, -D / 2 - 0.1, 2.75), 0.035, "metal_grey", seg=10)
    k.block((-L / 2 - 0.35, -D / 2 - 0.13, 2.45), (0.5, 0.03, 0.5), "sign_yellow", bevel=0.01)
    k.text("STAȚIE", (-L / 2 - 0.35, -D / 2 - 0.15, 2.58), 0.08, "sign_blue", depth=0.008)
    k.block((-L / 2 - 0.35, -D / 2 - 0.146, 2.36), (0.32, 0.005, 0.16), "sign_blue")     # bus pictogram
    for x in (-0.11, 0.11):
        k.rod((-L / 2 - 0.35 + x, -D / 2 - 0.15, 2.28), (-L / 2 - 0.35 + x, -D / 2 - 0.155, 2.28), 0.03,
              "sign_blue", seg=10)


def drinks_fridge(k):
    """Outdoor drinks fridge in front of a shop: red cabinet, a glass door
    onto lit shelves of bottles, and a BĂUTURI RECI header."""
    W, D, H = 0.7, 0.65, 1.95
    rnd = random.Random(51)
    k.block((0, 0.02, H / 2 + 0.05), (W, D - 0.04, H - 0.1), "metal_red", bevel=0.02)
    for x in (-W / 2 + 0.08, W / 2 - 0.08):
        for y in (-D / 2 + 0.08, D / 2 - 0.08):
            k.rod((x, y, 0), (x, y, 0.06), 0.025, "rubber", seg=8)
    k.block((0, -D / 2 + 0.02, 1.0), (W - 0.12, 0.04, 1.45), "lamp_glass_fridge")         # lit inside
    for z in (0.38, 0.72, 1.06, 1.4):
        k.block((0, -D / 2 - 0.02, z), (W - 0.14, 0.12, 0.015), "metal_white")
        k.goods(-W / 2 + 0.08, W / 2 - 0.08, -D / 2 - 0.03, z + 0.008, 0.1, rnd, ("bottle",))
    for x in (-W / 2 + 0.04, W / 2 - 0.04):                                                 # door frame
        k.block((x, -D / 2 - 0.08, 1.0), (0.06, 0.04, 1.55), "metal_red")
    for z in (0.24, 1.76):
        k.block((0, -D / 2 - 0.08, z), (W, 0.04, 0.06), "metal_red")
    k.glare(-W / 2 + 0.07, W / 2 - 0.07, -D / 2 - 0.1, 0.27, 1.73, n=2, seed=11)
    k.rod((W / 2 - 0.1, -D / 2 - 0.13, 0.85), (W / 2 - 0.1, -D / 2 - 0.13, 1.25), 0.012, "metal_grey", seg=6)
    k.block((0, -D / 2 - 0.02, H - 0.1), (W, 0.06, 0.2), "sign_white", bevel=0.01)
    k.text("BĂUTURI RECI", (0, -D / 2 - 0.055, H - 0.1), 0.055, "metal_red", depth=0.006)


def ice_cream_freezer(k):
    """Ice cream chest freezer: white and blue, sliding glass lids over tubs
    of ice cream, ÎNGHEȚATĂ on the front, on castors."""
    W, D, H = 1.3, 0.66, 0.86
    k.block((0, 0, 0.08 + (H - 0.08) / 2), (W, D, H - 0.08), "plastic_white", bevel=0.03)
    k.block((0, -D / 2 - 0.005, 0.45), (W - 0.06, 0.01, 0.3), "metal_blue")
    k.text("ÎNGHEȚATĂ", (0, -D / 2 - 0.012, 0.45), 0.13, "sign_white", depth=0.006)
    k.block((0, 0, H - 0.02), (W - 0.1, D - 0.1, 0.02), "interior_light")                   # tubs inside
    for i in range(4):
        for j in range(2):
            x, y = -W / 2 + 0.2 + i * 0.3, -0.12 + j * 0.24
            m = ["goods_a", "goods_e", "goods_b", "goods_g", "goods_f", "goods_d", "goods_e", "goods_a"][i * 2 + j]
            k.block((x, y, H + 0.0), (0.26, 0.2, 0.04), m)
    for sy in (-1, 1):                                                                      # rim
        k.block((0, sy * (D / 2 - 0.03), H + 0.04), (W, 0.06, 0.04), "plastic_white")
    for sx in (-1, 1):
        k.block((sx * (W / 2 - 0.03), 0, H + 0.04), (0.06, D, 0.04), "plastic_white")
    for x in (-W / 4, W / 4):                                                               # lid frames
        for sy in (-1, 1):
            k.block((x, sy * (D / 2 - 0.05), H + 0.07), (W / 2 - 0.06, 0.03, 0.015), "frame_shop")
        for sx in (-1, 1):
            k.block((x + sx * (W / 4 - 0.045), 0, H + 0.07), (0.03, D - 0.08, 0.015), "frame_shop")
    for i, x in enumerate((-W / 4, W / 4)):
        rnd = random.Random(60 + i)
        for _ in range(2):
            u = rnd.uniform(-0.18, 0.12)
            k.block((x + u, 0, H + 0.085), (0.05, D - 0.14, 0.004), "glass_glare", rot_z=0.4)
    for x in (-W / 2 + 0.1, W / 2 - 0.1):
        for y in (-D / 2 + 0.1, D / 2 - 0.1):
            k.rod((x, y, 0.08), (x, y, 0.05), 0.012, "metal_grey", seg=6)
            k.rod((x - 0.02, y, 0.03), (x + 0.02, y, 0.03), 0.03, "rubber", seg=10)


def recycling_bins(k):
    """Three wheelie bins for sorted rubbish, side by side: paper (blue),
    plastic and metal (yellow), glass (green), each with its label."""
    for i, (m, label) in enumerate((("bin_blue", "HÂRTIE"), ("bin_yellow", "PLASTIC"), ("bin_green_glass", "STICLĂ"))):
        x = (i - 1) * 0.72
        W, D, H = 0.6, 0.72, 1.0
        k.begin()                                 # body: wider at the top
        bmesh.ops.create_cube(k.bm, size=1.0)
        for v in k.bm.verts:
            sc = 0.9 if v.co.z < 0 else 1.0
            v.co = V(x + v.co.x * W * sc, v.co.y * D * sc, 0.07 + (v.co.z + 0.5) * (H - 0.07))
        bmesh.ops.bevel(k.bm, geom=list(k.bm.edges), offset=0.03, segments=2, profile=0.5, affect="EDGES")
        k._tag(k.new_faces(), m, False)
        k.end()
        k.block((x, -0.02, H + 0.03), (W + 0.06, D + 0.08, 0.05), m, bevel=0.015)            # lid
        k.block((x, D / 2 + 0.06, H - 0.05), (W - 0.04, 0.05, 0.05), "metal_dark", bevel=0.01)  # handle
        for sx in (-1, 1):
            k.rod((x + sx * (W / 2 - 0.08), D / 2 - 0.06, 0.09), (x + sx * (W / 2 - 0.02), D / 2 - 0.06, 0.09),
                  0.09, "rubber", seg=14)
        k.block((x, -D / 2 - 0.004, 0.68), (0.4, 0.008, 0.2), "sign_white")
        k.text(label, (x, -D / 2 - 0.01, 0.68), 0.065, m, depth=0.006)


def clothes_dryer(k):
    """Courtyard clothes drying frame: two T posts with washing lines and
    some laundry pegged on them."""
    L = 4.0
    rnd = random.Random(71)
    for x in (-L / 2, L / 2):
        k.rod((x, 0, 0), (x, 0, 1.95), 0.035, "metal_grey", seg=10)
        k.rod((x, -0.65, 1.9), (x, 0.65, 1.9), 0.025, "metal_grey", seg=8)
        k.rod((x, 0, -0.02), (x, 0, 0.06), 0.12, "concrete", seg=12)
    lines = (-0.55, -0.2, 0.2, 0.55)
    for y in lines:
        k.pipe([(-L / 2, y, 1.9)] + [(-L / 2 + L * t / 8, y, 1.9 - 0.08 * math.sin(math.pi * t / 8)) for t in range(1, 8)]
               + [(L / 2, y, 1.9)], 0.005, "plastic_white", seg=5, caps=False)
    def sag(x):
        return 1.9 - 0.08 * math.sin(math.pi * (x + L / 2) / L)
    for y in (-0.55, 0.2):                      # shirts and towels on two lines
        x = -L / 2 + 0.35
        while x < L / 2 - 0.5:
            m = rnd.choice(["cloth_a", "cloth_b", "cloth_c", "cloth_d", "cloth_e"])
            if rnd.random() < 0.5:              # towel
                w, h = rnd.uniform(0.45, 0.6), rnd.uniform(0.5, 0.7)
                k.block((x + w / 2, y, sag(x + w / 2) - h / 2), (w, 0.012, h), m)
            else:                               # T-shirt: one flat T-shaped piece
                w, h = 0.5, 0.55
                cx, top = x + w / 2, sag(x + w / 2) - 0.02
                outline = [(-0.2, 0), (0.2, 0), (0.32, -0.06), (0.3, -0.2), (0.2, -0.16), (0.2, -h),
                           (-0.2, -h), (-0.2, -0.16), (-0.3, -0.2), (-0.32, -0.06)]
                k.begin()
                f = k.bm.faces.new([k.bm.verts.new((cx + px, y, top + pz)) for px, pz in outline])
                bmesh.ops.solidify(k.bm, geom=[f], thickness=0.012)
                k._tag(k.new_faces(), m, False)
                k.end()
            for px in (x + 0.04, x + w - 0.04):
                k.block((px, y, sag(px) - 0.01), (0.015, 0.025, 0.06), "wood")
            x += w + rnd.uniform(0.12, 0.3)
    x = -1.2
    for i in range(5):                          # socks on a third line
        k.block((x, -0.2, sag(x) - 0.12), (0.07, 0.01, 0.22), rnd.choice(["cloth_d", "cloth_b", "metal_dark"]))
        x += rnd.uniform(0.15, 0.3)


def terrace_table(k):
    """Café terrace set: a round table, four plastic chairs and a striped
    parasol on a weighted base."""
    k.rod((0, 0, 0), (0, 0, 0.04), 0.25, "plastic_white", seg=20)
    k.rod((0, 0, 0.04), (0, 0, 0.72), 0.03, "metal_grey", seg=10)
    k.rod((0, 0, 0.72), (0, 0, 0.75), 0.42, "plastic_white", seg=28)
    for a in range(4):
        ang = a * math.pi / 2 + math.pi / 4
        cx, cy = math.cos(ang) * 0.72, math.sin(ang) * 0.72
        c, s_ = math.cos(ang), math.sin(ang)
        k.block((cx, cy, 0.44), (0.44, 0.44, 0.04), "plastic_white", rot_z=ang, bevel=0.015)
        bx, by = cx + c * 0.21, cy + s_ * 0.21
        k.block((bx, by, 0.68), (0.04, 0.42, 0.42), "plastic_white", rot_z=ang, bevel=0.015)
        for dx in (-0.19, 0.19):
            for dy in (-0.19, 0.19):
                px = cx + c * dx - s_ * dy
                py = cy + s_ * dx + c * dy
                k.rod((px, py, 0), (px, py, 0.43), 0.016, "plastic_white", seg=6)
    k.rod((0, 0, 0.75), (0, 0, 2.35), 0.022, "metal_grey", seg=8)
    R, n = 1.35, 8
    for i in range(n):                          # canopy panels
        a0, a1 = 2 * math.pi * i / n, 2 * math.pi * (i + 1) / n
        k.begin()
        vs = [k.bm.verts.new(c) for c in ((0, 0, 2.38), (math.cos(a0) * R, math.sin(a0) * R, 2.0),
                                           (math.cos(a1) * R, math.sin(a1) * R, 2.0))]
        f = k.bm.faces.new(vs)
        bmesh.ops.solidify(k.bm, geom=[f], thickness=0.015)
        k._tag(k.new_faces(), "awning_red" if i % 2 else "awning_white", False)
        k.end()
        k.rod((0, 0, 2.3), (math.cos(a0) * R * 0.98, math.sin(a0) * R * 0.98, 1.99), 0.008, "metal_grey", seg=5)
    k.blob((0, 0, 2.4), (0.04, 0.04, 0.04), "metal_grey", subdiv=1)


def fruit_stand(k):
    """Market stall ("tarabă") with crates of apples, oranges, lemons and
    pears on a wooden table under a striped canvas roof, with price cards."""
    W, Dt = 2.2, 0.9
    rnd = random.Random(81)
    k.block((0, 0, 0.78), (W, Dt, 0.05), "wood", bevel=0.01)
    for x in (-W / 2 + 0.08, W / 2 - 0.08):
        for y in (-Dt / 2 + 0.08, Dt / 2 - 0.08):
            k.block((x, y, 0.38), (0.06, 0.06, 0.76), "wood")
    k.block((0, -Dt / 2 + 0.02, 0.5), (W - 0.1, 0.02, 0.5), "awning_green")                 # front skirt
    fruits = ["fruit_red", "fruit_orange", "fruit_yellow", "fruit_green", "fruit_red", "fruit_orange"]
    for i in range(6):
        cx = -W / 2 + 0.2 + (i % 3) * 0.7 + 0.15
        cy = -0.2 if i < 3 else 0.22
        z0 = 0.81 + (0.0 if i < 3 else 0.12)
        if i >= 3:
            k.block((cx, cy, 0.87), (0.6, 0.4, 0.12), "crate_wood")                         # riser
        for dz in (0.02, 0.1):                                                              # slatted crate
            for sy in (-1, 1):
                k.block((cx, cy + sy * 0.19, z0 + dz + 0.03), (0.6, 0.02, 0.06), "crate_wood")
            for sx in (-1, 1):
                k.block((cx + sx * 0.29, cy, z0 + dz + 0.03), (0.02, 0.4, 0.06), "crate_wood")
        k.block((cx, cy, z0 + 0.01), (0.58, 0.38, 0.02), "crate_wood")
        m = fruits[i]
        r = 0.045 if m != "fruit_yellow" else 0.04
        for layer in range(2):
            for a in range(6):
                for b in range(4):
                    fx = cx - 0.24 + a * 0.095 + rnd.uniform(-0.01, 0.01) + layer * 0.045
                    fy = cy - 0.14 + b * 0.093 + rnd.uniform(-0.01, 0.01) + layer * 0.045
                    if layer and (a == 5 or b == 3):
                        continue
                    k.blob((fx, fy, z0 + 0.06 + r + layer * 0.07), (r, r, r * (1.15 if m == "fruit_yellow" else 0.95)),
                           m, subdiv=1, noise=0.06, seed=a * 7 + b + layer * 50 + i * 100)
        k.rod((cx + 0.2, cy - 0.17, z0 + 0.05), (cx + 0.2, cy - 0.17, z0 + 0.3), 0.004, "wood", seg=4)
        k.block((cx + 0.2, cy - 0.175, z0 + 0.33), (0.14, 0.01, 0.09), "sign_white")
        k.text("%d LEI" % rnd.choice([3, 4, 5, 6, 7, 8]), (cx + 0.2, cy - 0.183, z0 + 0.33), 0.035,
               "sign_red", depth=0.004)
    for x in (-W / 2 - 0.05, W / 2 + 0.05):                                                 # canvas roof
        k.rod((x, -Dt / 2 - 0.25, 0), (x, -Dt / 2 - 0.25, 2.05), 0.02, "metal_grey", seg=8)
        k.rod((x, Dt / 2 + 0.05, 0), (x, Dt / 2 + 0.05, 2.25), 0.02, "metal_grey", seg=8)
    k.awning(-W / 2 - 0.1, W / 2 + 0.1, Dt / 2 + 0.1, 2.28, Dt + 0.4, 0.26, ["awning_green", "awning_white"],
             stripes=8, valance=0.15)


def hedge(P):
    """2 m of clipped hedge, leaf by leaf (trees.hedge)."""
    trees.hedge(P, 7)


def tree_pine(P):
    """Blue spruce, common in the yards between the blocks (trees.spruce)."""
    trees.spruce(P, 11)


def tree_birch(P):
    """Birch: white trunk with dark marks, small hanging leaves (trees.birch)."""
    trees.birch(P, 3)


ASSETS = {
    "fence_metal": fence_metal, "fence_low": fence_low, "bench_wood": bench_wood, "trash_bin": trash_bin,
    "dumpster": dumpster, "carpet_beater": carpet_beater, "swing": swing, "slide": slide,
    "chess_table": chess_table, "bollard": bollard, "bike_rack": bike_rack, "planter": planter,
    "kiosk": kiosk, "mini_market": mini_market, "shop_window": shop_window, "bus_stop": bus_stop,
    "drinks_fridge": drinks_fridge, "ice_cream_freezer": ice_cream_freezer, "recycling_bins": recycling_bins,
    "clothes_dryer": clothes_dryer, "terrace_table": terrace_table, "fruit_stand": fruit_stand,
}
PLANTS = {"hedge": hedge, "tree_pine": tree_pine, "tree_birch": tree_birch}    # built with trees.Plant


def build(scn):
    col = scn.collection
    objs = []
    for name, fn in ASSETS.items():
        k = Kit()
        fn(k)
        ob = k.to_object(name, col)
        objs.append(ob)
    for name, fn in PLANTS.items():
        P = trees.Plant(material)
        fn(P)
        objs.append(P.finish(name, col))
    return objs


def run(root):
    scn = bpy.data.scenes.get("Assets") or bpy.data.scenes.new("Assets")
    win = bpy.context.window                    # None in background Blender / the bpy module
    prev = win.scene if win else None
    if win:
        win.scene = scn
    try:
        for ob in list(scn.collection.all_objects):
            bpy.data.objects.remove(ob, do_unlink=True)
        for d in [d for d in bpy.data.meshes if d.users == 0]:
            bpy.data.meshes.remove(d)
        objs = build(scn)
        out = os.path.join(root, "game", "assets", "source")
        os.makedirs(out, exist_ok=True)
        vl = scn.view_layers[0]
        for ob in scn.objects:
            ob.select_set(ob in objs, view_layer=vl)
        kw = dict(filepath=os.path.join(out, "street_kit.glb"), export_format="GLB", use_selection=True,
                  use_active_scene=True, export_yup=True, export_animations=False, export_apply=False)
        if win:
            bpy.ops.export_scene.gltf(**kw)
        else:
            with bpy.context.temp_override(scene=scn, view_layer=vl):
                bpy.ops.export_scene.gltf(**kw)
    finally:
        if win:
            win.scene = prev
    return {o.name: [sum(len(p.vertices) - 2 for p in o.data.polygons), [round(x, 2) for x in o.dimensions]]
            for o in objs}


def preview(root):
    """Lines the assets up and renders them to renders/assets.png."""
    scn = bpy.data.scenes["Assets"]
    objs = sorted(scn.objects, key=lambda o: o.name)
    x = 0.0
    for ob in objs:
        w = ob.dimensions.x
        ob.location = (x + w / 2, 0, 0)
        x += w + 0.6
    cam_data = bpy.data.cameras.get("assets_cam") or bpy.data.cameras.new("assets_cam")
    cam = scn.objects.get("assets_cam") or bpy.data.objects.new("assets_cam", cam_data)
    if cam.name not in scn.collection.objects:
        scn.collection.objects.link(cam)
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = x + 1
    cam.location = (x / 2, -30, 12)
    cam.rotation_euler = (math.radians(72), 0, 0)
    scn.camera = cam
    sun = scn.objects.get("assets_sun")
    if sun is None:
        sun = bpy.data.objects.new("assets_sun", bpy.data.lights.new("assets_sun", "SUN"))
        scn.collection.objects.link(sun)
    sun.rotation_euler = (math.radians(50), 0, math.radians(30))
    scn.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items] else "BLENDER_EEVEE"
    scn.render.resolution_x, scn.render.resolution_y = 2400, 700
    scn.render.filepath = os.path.join(root, "renders", "assets.png")
    if scn.world is None:
        scn.world = bpy.data.worlds.new("assets_world")
    scn.world.use_nodes = True
    bg = scn.world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs[0].default_value = (0.75, 0.82, 0.9, 1)
    prev = bpy.context.window.scene
    bpy.context.window.scene = scn
    try:
        bpy.ops.render.render(write_still=True)
    finally:
        bpy.context.window.scene = prev
        for ob in objs:
            ob.location = (0, 0, 0)
    return scn.render.filepath
