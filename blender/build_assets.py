"""Street kit for the in-game placement tool: things found around the blocks
of flats in Micro 15 that the map does not scatter on its own (metal fences,
lawn hoop fences, benches, bins, the big green waste containers, the carpet
beating frame, playground swings and slide, concrete chess tables,
bollards, bike racks, planters, hedges, pines and birches).

Every asset is one object standing on the origin, facing -Y (the front in
Godot is +Z), 1 unit = 1 metre. Materials are named like the rest of the
world (C3_*; names containing leaf/bush get the foliage shader in Godot).
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

COLOURS = {
    "fence_green": "#3f7a4a", "metal_dark": "#3a3f47", "metal_grey": "#8e969c", "wood": "#b77a45",
    "concrete": "#c9c4b8", "concrete_dark": "#a8a397", "bin_green": "#3d8a52", "container": "#2f6e45",
    "rubber": "#2a2b2e", "red": "#d0503c", "yellow": "#f0c040", "blue": "#3f78c8", "white": "#f2f0ea",
    "soil": "#6b4b34", "flower_red": "#e0475a", "flower_yellow": "#f6d04d", "trunk": "#7a5a43",
    "birch_bark": "#ece8df", "pine_leaf": "#2f6a46", "birch_leaf": "#8cc65a", "hedge_bush": "#4f8f3e",
    "chess_dark": "#5a5650",
}


def V(*a):
    return Vector(a[0] if len(a) == 1 else a)


def hex_rgba(h):
    h = h.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    c = [x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c]
    return (c[0], c[1], c[2], 1.0)


def material(name):
    m = bpy.data.materials.get("C3_" + name)
    if m is None:
        m = bpy.data.materials.new("C3_" + name)
        c = hex_rgba(COLOURS[name])
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
        for f in piece.faces:
            nf = self.bm.faces.new([vmap[v] for v in f.verts])
            nf.material_index = f.material_index
            nf.smooth = f.smooth
        piece.free()

    def block(self, c, size, mat, rot_z=0.0, bevel=0.0, smooth=False):
        """Box centred on c, optionally with rounded edges."""
        self.begin()
        bmesh.ops.create_cube(self.bm, size=1.0)
        vs = list(self.new_verts())
        bmesh.ops.scale(self.bm, vec=V(size), verts=vs)
        if bevel > 0:
            self.bm.edges.ensure_lookup_table()
            edges = list({e for v in vs for e in v.link_edges})
            bmesh.ops.bevel(self.bm, geom=edges, offset=bevel, segments=2, profile=0.5, affect="EDGES")
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
    """Park bench: cast iron sides, wooden seat and back slats."""
    L = 1.8
    for x in (-L / 2 + 0.12, L / 2 - 0.12):
        k.pipe([(x, -0.22, 0.0), (x, -0.2, 0.43), (x, 0.2, 0.43), (x, 0.22, 0.0)], 0.022, "metal_dark", seg=8)
        k.pipe([(x, 0.18, 0.43), (x, 0.26, 0.85)], 0.02, "metal_dark", seg=8)
        k.pipe([(x, -0.2, 0.43), (x, -0.18, 0.62), (x, 0.05, 0.66), (x, 0.2, 0.62)], 0.016, "metal_dark", seg=8)
    for i in range(4):
        k.block((0, -0.18 + i * 0.12, 0.45), (L, 0.1, 0.035), "wood", bevel=0.008)
    for i in range(3):
        t = 0.5 + i * 0.12
        k.block((0, 0.19 + 0.08 * (t - 0.43) / 0.42 * 2.0 - 0.02, t), (L, 0.03, 0.09), "wood",
                bevel=0.008)


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
    """Small playground slide: ladder, platform and a chute."""
    k.block((0, 0.9, 1.1), (0.6, 0.6, 0.06), "blue", bevel=0.01)
    for x in (-0.28, 0.28):
        for y in (0.62, 1.18):
            k.rod((x, y, 0), (x, y, 1.1), 0.03, "yellow", seg=8)
        k.rod((x, 1.18, 1.1), (x, 1.18, 1.6), 0.025, "yellow", seg=8)
        k.rod((x, 0.62, 1.1), (x, 0.62, 1.6), 0.025, "yellow", seg=8)
        k.rod((x, 0.62, 1.6), (x, 1.18, 1.6), 0.025, "yellow", seg=8)
        k.rod((x, 1.18, 0), (x, 1.6, 0), 0.02, "yellow", seg=6)
    for i in range(1, 5):
        z = i * 0.22
        k.rod((-0.28, 1.18 + 0.0, z), (0.28, 1.18, z), 0.015, "metal_grey", seg=6)
    # chute: a U-channel curving down to the ground
    steps = 12
    prof = [(-0.25, 0.08), (-0.25, 0.0), (0.25, 0.0), (0.25, 0.08)]
    k.begin()
    rings = []
    for i in range(steps + 1):
        t = i / steps
        y = 0.6 - 1.6 * t
        z = 1.12 * (1 - t) ** 1.3 + 0.12 * t
        rings.append([k.bm.verts.new((px, y, z + pz)) for px, pz in prof])
    for a, b in zip(rings, rings[1:]):
        for j in range(len(prof) - 1):
            k.bm.faces.new((a[j], a[j + 1], b[j + 1], b[j]))
    faces = list(k.new_faces())
    bmesh.ops.solidify(k.bm, geom=faces, thickness=0.03)
    k._tag(list(k.new_faces()), "red", True)
    k.end()
    k.rod((-0.2, -0.9, 0), (-0.2, -0.9, 0.14), 0.025, "yellow", seg=6)
    k.rod((0.2, -0.9, 0), (0.2, -0.9, 0.14), 0.025, "yellow", seg=6)


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
        k.blob((x, y, 0.56), (0.07, 0.07, 0.06), "hedge_bush", subdiv=1, noise=0.15, seed=i)
        k.blob((x + 0.02, y - 0.02, 0.64), (0.035, 0.035, 0.025), rnd.choice(["flower_red", "flower_yellow"]),
               subdiv=1)


def hedge(k):
    """2 m of clipped box hedge."""
    for i in range(4):
        k.blob((-0.75 + i * 0.5, 0, 0.42), (0.42, 0.36, 0.46), "hedge_bush", subdiv=2, noise=0.06, seed=i,
               flat_bottom=0.0)


def tree_pine(k):
    """Blue spruce, common in the yards between the blocks."""
    k.rod((0, 0, 0), (0, 0, 1.2), 0.14, "trunk", seg=10, r1=0.1)
    H = 7.5
    tiers = 6
    for i in range(tiers):
        t = i / tiers
        z0 = 0.8 + t * (H - 1.6)
        r = 2.0 * (1 - t) + 0.35
        k.begin()
        ring = [k.bm.verts.new((math.cos(a) * r, math.sin(a) * r, z0 + 0.25 * math.sin(5 * a) * (1 - t) * 0.3))
                for a in (2 * math.pi * j / 14 for j in range(14))]
        tip = k.bm.verts.new((0, 0, z0 + 2.4 - t * 0.6))
        for j in range(14):
            k.bm.faces.new((ring[j], ring[(j + 1) % 14], tip))
        k.bm.faces.new(list(reversed(ring)))
        faces = list(k.new_faces())
        bmesh.ops.recalc_face_normals(k.bm, faces=faces)
        k._tag(faces, "pine_leaf", True)
        k.end()


def tree_birch(k):
    """Birch: thin white trunk and a few loose, light canopy clumps."""
    k.pipe([(0, 0, 0), (0.05, 0.02, 2.5), (0.0, 0.0, 5.0), (-0.1, 0.05, 7.0)], 0.12, "birch_bark", seg=10,
           r1=0.05)
    k.rod((0.03, 0.01, 3.4), (0.9, 0.3, 4.6), 0.04, "birch_bark", seg=6, r1=0.02)
    k.rod((0.0, 0.0, 4.0), (-0.8, -0.4, 5.2), 0.04, "birch_bark", seg=6, r1=0.02)
    rnd = random.Random(7)
    for i, (x, y, z, r) in enumerate(((0, 0, 6.6, 1.3), (0.9, 0.3, 5.2, 1.0), (-0.8, -0.4, 5.6, 1.05),
                                      (0.2, -0.6, 4.6, 0.9), (-0.3, 0.6, 4.9, 0.9))):
        k.blob((x, y, z), (r, r, r * 1.15), "birch_leaf", subdiv=2, noise=0.1, seed=i)


ASSETS = {
    "fence_metal": fence_metal, "fence_low": fence_low, "bench_wood": bench_wood, "trash_bin": trash_bin,
    "dumpster": dumpster, "carpet_beater": carpet_beater, "swing": swing, "slide": slide,
    "chess_table": chess_table, "bollard": bollard, "bike_rack": bike_rack, "planter": planter,
    "hedge": hedge, "tree_pine": tree_pine, "tree_birch": tree_birch,
}


def build(scn):
    col = scn.collection
    objs = []
    for name, fn in ASSETS.items():
        k = Kit()
        fn(k)
        ob = k.to_object(name, col)
        objs.append(ob)
    return objs


def run(root):
    scn = bpy.data.scenes.get("Assets") or bpy.data.scenes.new("Assets")
    prev = bpy.context.window.scene
    bpy.context.window.scene = scn
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
        bpy.ops.export_scene.gltf(filepath=os.path.join(out, "street_kit.glb"), export_format="GLB",
                                  use_selection=True, use_active_scene=True, export_yup=True,
                                  export_animations=False, export_apply=False)
    finally:
        bpy.context.window.scene = prev
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
