"""Playable character: the boy from reference/character_sheet.png.

Built in layers, like a game character with an outfit system:

* Base body: one smooth, watertight mesh grown from a stick figure with
  Blender's Skin modifier and subdivided, skinned to a 26-bone humanoid rig
  with automatic (bone heat) weights. It is exported in pieces (upper and
  lower torso, pelvis, upper arms, thighs, ankles, feet and the rest) that
  share their seams, so the game can hide whatever a garment covers.
* Head, face, hair and hands: separate smooth meshes with hand-set weights.
  Three hair bones are left for a spring simulation in the game.
* Garments (T-shirt, shorts, socks, sneakers): separate meshes, each modelled
  from its own stick figure, cut open at the hems, given thickness and rolled
  edges, and fitted so they stay clear of the body (and of the garments
  under them). They take their weights from the body surface underneath, so
  they move with it. kid.json lists the garments and the body pieces each one
  hides; anything built the same way (another outfit, an accessory) can be
  added later without touching the body.

Animations are retargeted (retarget_ual.py) from Quaternius' Universal
Animation Library 1 and 2, CC0 clips animated for game characters: idle,
walk, sprint, jump start / loop / land, a mid-air flip for the double jump,
crouch idle and walk, jab and cross punches and a hit reaction (CLIPS).
They are sampled at 30 fps, scaled to the boy's leg length and set on the
ground; the cycles' ground speeds go to kid.json so the game can match them.

The rest pose holds the arms a little away from the body (ARM_SPREAD) so the
weights and garments are clean under the armpits.

The boy faces -Y in Blender (+Z in Godot), 1 unit = 1 m, about 1.5 m tall.
Writes game/characters/kid/kid.glb and kid.json.

    import sys; sys.path.insert(0, r"<repo>/blender")
    import build_character; build_character.run(r"<repo>")
    build_character.preview(r"<repo>")      # optional turnaround renders
"""
import bmesh
import bpy
import json
import math
import os
import random
from mathutils import Euler, Matrix, Vector
from mathutils.bvhtree import BVHTree
from mathutils.interpolate import poly_3d_calc

import retarget_ual

FPS = 30
COLOURS = {
    "skin": "#eda872", "shirt": "#3c5fb3", "shorts": "#2b3250", "hair": "#2a1d17",
    "shoe": "#29314f", "sole": "#f1f1ec", "sock": "#f4f4f0", "sclera": "#f7f2ea", "iris": "#4a2c1c",
    "pupil": "#140d0a", "lid": "#1e1511", "brow": "#33241c", "mouth": "#94503d", "stripe": "#f1f1ec",
}
SIDES = (("L", 1), ("R", -1))
ARM_SPREAD = 0.16                    # radians the rest-pose arms sit further out than the animations assume
SHOULDER = (0.155, 0.012, 1.075)     # shoulder joint (left side)
# head and hair are modelled at this scale about a point near the top of the
# skull: a slightly bigger head, sitting lower on the neck
HEAD_XF = Matrix.Translation((0, 0.01, 1.40)) @ Matrix.Scale(1.06, 4) @ Matrix.Translation((0, -0.01, -1.40))


def V(*a):
    return Vector(a[0] if len(a) == 1 else a)


def arm_pt(k, x, y, z):
    """A point of the arm given for arms hanging close to the body (left side,
    x > 0), moved into the spread rest pose for side k."""
    px, _, pz = SHOULDER
    t = -k * ARM_SPREAD
    dx, dz = k * (x - px), z - pz
    return (k * px + dx * math.cos(t) + dz * math.sin(t), y, pz - dx * math.sin(t) + dz * math.cos(t))


# bone: (head, tail, parent, deforms the skin-modifier body)
BONES = {
    "root": ((0, 0, 0), (0, 0, 0.12), None, False),
    "hips": ((0, 0.005, 0.70), (0, 0.005, 0.80), "root", True),
    "spine": ((0, 0.005, 0.80), (0, 0.003, 0.90), "hips", True),
    "spine1": ((0, 0.003, 0.90), (0, 0.004, 1.00), "spine", True),
    "chest": ((0, 0.004, 1.00), (0, 0.008, 1.11), "spine1", True),
    "neck": ((0, 0.01, 1.11), (0, 0.008, 1.21), "chest", True),
    "head": ((0, 0.008, 1.21), (0, 0.008, 1.45), "neck", True),
}
for _n, _h, _t in (("hair_front", (0, -0.045, 1.43), (0, -0.095, 1.37)), ("hair_top", (0, 0.015, 1.46), (0, 0.03, 1.53)),
                   ("hair_back", (0, 0.075, 1.40), (0, 0.105, 1.32))):
    BONES[_n] = (tuple(HEAD_XF @ V(_h)), tuple(HEAD_XF @ V(_t)), "head", False)
for _s, _k in SIDES:
    BONES.update({
        "shoulder." + _s: ((_k * 0.02, 0.008, 1.085), (_k * 0.15, 0.012, 1.08), "chest", True),
        "upper_arm." + _s: (arm_pt(_k, *SHOULDER), arm_pt(_k, 0.2, 0.012, 0.855), "shoulder." + _s, True),
        "forearm." + _s: (arm_pt(_k, 0.2, 0.012, 0.855), arm_pt(_k, 0.228, 0.0, 0.66), "upper_arm." + _s, True),
        "hand." + _s: (arm_pt(_k, 0.228, 0.0, 0.66), arm_pt(_k, 0.236, -0.004, 0.598), "forearm." + _s, True),
        "fingers." + _s: (arm_pt(_k, 0.236, -0.004, 0.598), arm_pt(_k, 0.24, -0.006, 0.545), "hand." + _s, False),
        "thigh." + _s: ((_k * 0.085, 0.005, 0.69), (_k * 0.09, 0.0, 0.40), "hips", True),
        "shin." + _s: ((_k * 0.09, 0.0, 0.40), (_k * 0.092, 0.012, 0.085), "thigh." + _s, True),
        "foot." + _s: ((_k * 0.092, 0.012, 0.085), (_k * 0.092, -0.058, 0.025), "shin." + _s, True),
        "toe." + _s: ((_k * 0.092, -0.058, 0.025), (_k * 0.092, -0.12, 0.02), "foot." + _s, False),
    })


def head_of(b):
    return V(BONES[b][0])


def tail_of(b):
    return V(BONES[b][1])


def bone_dir(b):
    return (tail_of(b) - head_of(b)).normalized()


# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------
def hex_rgba(h):
    h = h.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    c = [x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c]
    return (c[0], c[1], c[2], 1.0)


def material(name):
    m = bpy.data.materials.get("CH_" + name)
    if m is None:
        m = bpy.data.materials.new("CH_" + name)
        c = hex_rgba(COLOURS[name])
        m.diffuse_color = c
        m.use_nodes = True
        bsdf = m.node_tree.nodes.get("Principled BSDF")
        if bsdf:
            bsdf.inputs["Base Color"].default_value = c
            bsdf.inputs["Roughness"].default_value = 1.0
    return m


def smoothstep(e0, e1, x):
    t = min(max((x - e0) / (e1 - e0), 0.0), 1.0)
    return t * t * (3 - 2 * t)


def lerp(a, b, t):
    return a + (b - a) * t


def frame(axis):
    a = axis.normalized()
    ref = V(0, -1, 0) if abs(a.z) > 0.7 else V(0, 0, 1)
    u = a.cross(ref).normalized()
    return u, a.cross(u).normalized()


def ring(c, axis, ru, rv, n=12, power=2.0, u=None):
    if u is None:
        u, v = frame(axis)
    else:
        v = axis.normalized().cross(u).normalized()
    e = 2.0 / power
    pts = []
    for i in range(n):
        t = 2 * math.pi * i / n
        cu, sv = math.cos(t), math.sin(t)
        pts.append(c + u * (ru * math.copysign(abs(cu) ** e, cu)) + v * (rv * math.copysign(abs(sv) ** e, sv)))
    return pts


def catmull(points, w):
    """Catmull-Rom through [(w_i, value)] (values are floats or Vectors)."""
    if w <= points[0][0]:
        return points[0][1]
    if w >= points[-1][0]:
        return points[-1][1]
    for i in range(len(points) - 1):
        if points[i][0] <= w <= points[i + 1][0]:
            break
    p0 = points[max(i - 1, 0)][1]
    p1, p2 = points[i][1], points[i + 1][1]
    p3 = points[min(i + 2, len(points) - 1)][1]
    t = (w - points[i][0]) / (points[i + 1][0] - points[i][0])
    return 0.5 * ((2 * p1) + (p2 - p0) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t +
                  (3 * p1 - p0 - 3 * p2 + p3) * t * t * t)


def line_dist(p, a, b):
    ab = b - a
    t = (p - a).dot(ab) / ab.length_squared
    return (p - (a + ab * t)).length


class Mesh:
    """bmesh with per-vertex skin weights ({bone: weight}) and materials."""

    def __init__(self, bm=None):
        self.bm = bm or bmesh.new()
        self.weights = []
        self.mats = []

    def mi(self, name):
        m = material(name)
        if m not in self.mats:
            self.mats.append(m)
        return self.mats.index(m)

    def v(self, p, w):
        self.weights.append(w)
        return self.bm.verts.new(p)

    def pad(self, w):
        self.weights.extend([w] * (len(self.bm.verts) - len(self.weights)))

    def face(self, verts, mat, outward, smooth=True):
        f = self.bm.faces.new(verts)
        f.material_index = mat
        f.smooth = smooth
        f.normal_update()
        if f.normal.dot(outward) < 0:
            f.normal_flip()
        return f

    def loft(self, rings, mat, w, cap0=False, cap1=False, outward=None, tip=None):
        """Quad strips between rings; w is a weight dict or a function of position."""
        wf = w if callable(w) else (lambda p: w)
        vs = [[self.v(p, wf(p)) for p in r] for r in rings]
        cs = [sum(r, Vector()) / len(r) for r in rings]
        n = len(vs[0])
        for i in range(len(vs) - 1):
            mid = (cs[i] + cs[i + 1]) / 2
            for j in range(n):
                q = (vs[i][j], vs[i][(j + 1) % n], vs[i + 1][(j + 1) % n], vs[i + 1][j])
                self.face(q, mat, outward if outward is not None else sum((x.co for x in q), Vector()) / 4 - mid)
        if cap0:
            self.face(vs[0], mat, cs[0] - cs[1])
        if tip is not None:
            tv = self.v(tip, wf(tip))
            for j in range(n):
                self.face((vs[-1][j], vs[-1][(j + 1) % n], tv), mat, tip - cs[-1])
        elif cap1:
            self.face(vs[-1], mat, cs[-1] - cs[-2])
        return vs

    def to_object(self, name, col, arm, xf=None):
        if xf is not None:
            bmesh.ops.transform(self.bm, matrix=xf, verts=self.bm.verts)
        me = bpy.data.meshes.new(name)
        self.bm.to_mesh(me)
        self.bm.free()
        for m in self.mats:
            me.materials.append(m)
        ob = bpy.data.objects.new(name, me)
        col.objects.link(ob)
        groups = {b: ob.vertex_groups.new(name=b) for b in BONES}
        for v, w in zip(me.vertices, self.weights):
            total = sum(w.values()) or 1.0
            for b, x in w.items():
                if x > 1e-4:
                    groups[b].add([v.index], x / total, "REPLACE")
        attach(ob, arm)
        return ob


def attach(ob, arm):
    ob.parent = arm
    if not any(m.type == "ARMATURE" for m in ob.modifiers):
        ob.modifiers.new("Armature", "ARMATURE").object = arm


def skin_surface(scn, name, nodes, edges, roots=None):
    """Smooth closed surface grown from a stick figure: nodes are
    (name, position, (radius across, radius deep)), edges join node names."""
    names = [n for n, _, _ in nodes]
    me = bpy.data.meshes.new(name + "_graph")
    me.from_pydata([p for _, p, _ in nodes], [(names.index(a), names.index(b)) for a, b in edges], [])
    src = bpy.data.objects.new(name + "_graph", me)
    scn.collection.objects.link(src)
    sk = src.modifiers.new("Skin", "SKIN")
    sk.branch_smoothing = 0.6
    sk.use_smooth_shade = True
    data = me.skin_vertices[0].data
    for d, (_, _, r) in zip(data, nodes):
        d.radius = r
        d.use_root = False
    for r in roots or names[:1]:
        data[names.index(r)].use_root = True
    sub = src.modifiers.new("Subdivision", "SUBSURF")
    sub.levels = sub.render_levels = 2
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    out = bpy.data.meshes.new_from_object(src.evaluated_get(dg))
    bpy.data.objects.remove(src, do_unlink=True)
    bpy.data.meshes.remove(me)
    out.name = name
    for p in out.polygons:
        p.use_smooth = True
    return out


# ----------------------------------------------------------------------------
# Base body
# ----------------------------------------------------------------------------
SKIN = [("pelvis", (0, 0.006, 0.715), (0.128, 0.088)), ("waist", (0, 0.004, 0.83), (0.118, 0.08)),
        ("ribs", (0, 0.002, 0.95), (0.13, 0.085)), ("chest", (0, 0.006, 1.04), (0.135, 0.085)),
        ("neck0", (0, 0.012, 1.115), (0.057, 0.054)), ("neck1", (0, 0.012, 1.215), (0.053, 0.05))]
SKIN_EDGES = [("pelvis", "waist"), ("waist", "ribs"), ("ribs", "chest"), ("chest", "neck0"), ("neck0", "neck1")]
for _s, _k in SIDES:
    SKIN += [("clav" + _s, (_k * 0.085, 0.01, 1.08), (0.06, 0.055))]
    SKIN += [(n + _s, arm_pt(_k, x, y, z), r) for n, (x, y, z), r in (
        ("shoulder", (0.16, 0.012, 1.065), (0.054, 0.052)), ("bicep", (0.18, 0.012, 0.96), (0.045, 0.046)),
        ("elbow", (0.2, 0.012, 0.855), (0.037, 0.039)), ("forearm", (0.214, 0.007, 0.76), (0.033, 0.038)),
        ("wrist", (0.228, 0.0, 0.665), (0.021, 0.027)), ("wrist_end", (0.231, -0.001, 0.645), (0.02, 0.026)))]
    SKIN += [(n + _s, (_k * x, y, z), r) for n, (x, y, z), r in (
        ("hip", (0.08, 0.005, 0.655), (0.078, 0.08)), ("thigh", (0.087, 0.004, 0.54), (0.064, 0.066)),
        ("knee", (0.09, 0.0, 0.40), (0.047, 0.05)), ("calf", (0.091, 0.012, 0.29), (0.048, 0.053)),
        ("shin_low", (0.092, 0.012, 0.17), (0.036, 0.038)), ("ankle", (0.092, 0.012, 0.09), (0.031, 0.033)),
        ("heel", (0.092, 0.01, 0.05), (0.03, 0.04)))]
    SKIN_EDGES += [(a + _s if a not in ("chest", "pelvis") else a, b + _s) for a, b in (
        ("chest", "clav"), ("clav", "shoulder"), ("shoulder", "bicep"), ("bicep", "elbow"), ("elbow", "forearm"),
        ("forearm", "wrist"), ("wrist", "wrist_end"), ("pelvis", "hip"), ("hip", "thigh"), ("thigh", "knee"),
        ("knee", "calf"), ("calf", "shin_low"), ("shin_low", "ankle"), ("ankle", "heel"))]

HEM, COLLAR, WAIST = 0.70, 1.145, 0.80        # shirt bottom, neckline at the sides, shorts top (z)
SLEEVE, SHORTS = 0.11, 0.265                  # sleeve / shorts leg length along the bone
SOCK_TOP = 0.14

SEGMENTS = {"torso": (V(0, 0.005, 0.66), V(0, 0.008, 1.11)), "neck": (V(0, 0.01, 1.11), V(0, 0.01, 1.25))}
for _s, _k in SIDES:
    SEGMENTS.update({
        "shoulder." + _s: (head_of("shoulder." + _s), head_of("upper_arm." + _s)),
        "upper_arm." + _s: (head_of("upper_arm." + _s), tail_of("upper_arm." + _s)),
        "forearm." + _s: (head_of("forearm." + _s), tail_of("hand." + _s)),
        "thigh." + _s: (head_of("thigh." + _s), tail_of("thigh." + _s)),
        "shin." + _s: (head_of("shin." + _s), V(_k * 0.092, 0.012, 0.0)),
    })


def classify(p):
    """Nearest body part and the distance along it."""
    best = None
    for name, (a, b) in SEGMENTS.items():
        ab = b - a
        t = min(max((p - a).dot(ab) / ab.length_squared, 0.0), 1.0)
        d = (p - (a + ab * t)).length
        if best is None or d < best[0]:
            best = (d, name, t * ab.length)
    return best[1].split(".")[0], best[2], (1 if best[1].endswith(".L") else -1)


def collar_z(y):
    """Height of the T-shirt's crew neck: lower at the front."""
    return COLLAR + 0.3 * (y - 0.01)


# Body pieces, and the garments that cover them completely. Each piece stops
# a little inside the garment's openings, so the skin still shows when you
# look into a sleeve or a trouser leg.
BODY_PARTS = ("base", "torso_upper", "torso_lower", "pelvis", "upper_arms", "thighs", "ankles", "feet")


def body_region(c):
    part, along, _ = classify(c)
    if c.z < 0.085:
        return "feet"
    if part == "shin" and c.z < SOCK_TOP - 0.012:
        return "ankles"
    if part == "upper_arm":
        return "upper_arms" if along <= SLEEVE - 0.035 else "base"
    if part == "thigh":
        if along <= 0.04:
            return "pelvis"
        return "thighs" if along <= SHORTS - 0.05 else "base"
    if part in ("torso", "shoulder", "neck"):
        if c.z >= collar_z(c.y) - 0.015:
            return "base"
        if c.z >= 0.785:
            return "torso_upper"
        return "torso_lower" if c.z >= 0.725 else "pelvis"
    return "base"


def build_body(scn, arm):
    body_me = skin_surface(scn, "kid_body", SKIN, SKIN_EDGES)
    body = bpy.data.objects.new("kid_body", body_me)
    scn.collection.objects.link(body)

    # automatic weights from the bones that deform the body
    vl = scn.view_layers[0]
    for ob in scn.objects:
        ob.select_set(False, view_layer=vl)
    body.select_set(True, view_layer=vl)
    arm.select_set(True, view_layer=vl)
    vl.objects.active = arm
    with bpy.context.temp_override(active_object=arm, object=arm, selected_objects=[body, arm],
                                   selected_editable_objects=[body, arm]):
        bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    for b in arm.data.bones:
        b.use_deform = b.name != "root"
    for name in BONES:
        if name not in body.vertex_groups:
            body.vertex_groups.new(name=name)
    return body


def split_body(body, col, arm):
    """Cuts the body into BODY_PARTS objects. Seam vertices are shared, with
    the same weights and normals on both sides, so the pieces join invisibly."""
    me = body.data
    normals = [v.normal.copy() for v in me.vertices]
    group_names = [g.name for g in body.vertex_groups]
    region = [body_region(V(p.center)) for p in me.polygons]
    pieces = {}
    for part in BODY_PARTS:
        keep = {i for i, r in enumerate(region) if r == part}
        if not keep:
            continue
        bm = bmesh.new()
        bm.from_mesh(me)
        orig = bm.verts.layers.int.new("orig")
        for v in bm.verts:
            v[orig] = v.index
        bm.faces.ensure_lookup_table()
        bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.index not in keep], context="FACES")
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
        pm = bpy.data.meshes.new("body_" + part)
        bm.to_mesh(pm)
        bm.free()
        ids = [d.value for d in pm.attributes["orig"].data]
        pm.attributes.remove(pm.attributes["orig"])
        pm.normals_split_custom_set_from_vertices([normals[i] for i in ids])
        pm.materials.append(material("skin"))
        ob = bpy.data.objects.new("body_" + part, pm)
        col.objects.link(ob)
        for g in group_names:
            ob.vertex_groups.new(name=g)
        attach(ob, arm)
        pieces[part] = ob
    bpy.data.objects.remove(body, do_unlink=True)
    bpy.data.meshes.remove(me)
    return pieces


class BodySampler:
    """Nearest point on the (rest pose) body: its BVH for fitting garments,
    and its interpolated skin weights for skinning them."""

    def __init__(self, body):
        names = {g.index: g.name for g in body.vertex_groups if g.name in BONES}
        me = body.data
        self.weights = [{names[g.group]: g.weight for g in v.groups if g.group in names and g.weight > 1e-4}
                        for v in me.vertices]
        bm = bmesh.new()
        bm.from_mesh(me)
        bmesh.ops.triangulate(bm, faces=bm.faces[:])
        bm.verts.index_update()
        bm.faces.index_update()
        self.tris = [[v.index for v in f.verts] for f in bm.faces]
        self.cos = [v.co.copy() for v in bm.verts]
        self.bvh = BVHTree.FromBMesh(bm)
        bm.free()

    def __call__(self, p):
        loc, _, i, _ = self.bvh.find_nearest(p)
        ids = self.tris[i]
        out = {}
        for j, b in zip(ids, poly_3d_calc([self.cos[j] for j in ids], loc)):
            for g, x in self.weights[j].items():
                out[g] = out.get(g, 0.0) + x * b
        return out


# ----------------------------------------------------------------------------
# Garments
# ----------------------------------------------------------------------------
def fit(bm, bvh, clearance, where=None):
    """Pushes the surface out wherever it is closer than clearance to what
    the BVH holds, relaxing the pushed area so it stays smooth."""
    def push():
        moved = set()
        for v in bm.verts:
            if where and not where(v.co):
                continue
            loc, nrm, _, dist = bvh.find_nearest(v.co)
            if loc is None or dist > 0.08:
                continue
            d = (v.co - loc).dot(nrm)
            if d < clearance:
                v.co += nrm * (clearance - d)
                moved.add(v)
        return moved

    for _ in range(3):
        moved = push()
        if not moved:
            return
        area = moved | {e.other_vert(v) for v in moved for e in v.link_edges}
        new = {v: v.co * 0.5 + sum((e.other_vert(v).co for e in v.link_edges), Vector()) * (0.5 / len(v.link_edges))
               for v in area if v.link_edges}
        for v, co in new.items():
            v.co = co
    push()


def cut_open(bm, co, no, tip, eligible):
    """Opens a hem: slices the faces near the cut with a plane and removes the
    part beyond it that holds the point tip (the end cap of the tube)."""
    faces = [f for f in bm.faces if eligible(f.calc_center_median())]
    edges = {e for f in faces for e in f.edges}
    verts = {v for f in faces for v in f.verts}
    res = bmesh.ops.bisect_plane(bm, geom=list(verts) + list(edges) + faces, dist=1e-6, plane_co=co, plane_no=no)
    cut = {e for e in res["geom_cut"] if isinstance(e, bmesh.types.BMEdge)}
    start = min(bm.faces, key=lambda f: (f.calc_center_median() - tip).length)
    region, stack = {start}, [start]
    while stack:
        f = stack.pop()
        for e in f.edges:
            if e in cut:
                continue
            for g in e.link_faces:
                if g not in region:
                    region.add(g)
                    stack.append(g)
    if any((f.calc_center_median() - co).dot(no) < -0.002 for f in region):
        raise RuntimeError("cut at %s does not close round the tube" % tuple(round(x, 3) for x in co))
    bmesh.ops.delete(bm, geom=list(region), context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")


def boundary_loops(bm):
    """Open edges as ordered loops of (position, normal)."""
    bm.normal_update()
    nxt = {}
    for e in bm.edges:
        if e.is_boundary:
            a, b = e.verts
            nxt.setdefault(a, []).append(b)
            nxt.setdefault(b, []).append(a)
    seen, loops = set(), []
    for v0 in nxt:
        if v0 in seen:
            continue
        loop, prev, cur = [v0], None, v0
        seen.add(v0)
        while True:
            cand = [w for w in nxt[cur] if w is not prev and w not in seen]
            if not cand:
                break
            prev, cur = cur, cand[0]
            loop.append(cur)
            seen.add(cur)
        loops.append([(v.co.copy(), v.normal.copy()) for v in loop])
    return loops


def solidify(bm, thickness):
    """Inner shell plus rim, so the inside of a sleeve or a leg is drawn too."""
    bm.normal_update()
    faces = list(bm.faces)
    rim = [(e, e.link_faces[0]) for e in bm.edges if e.is_boundary]
    inner = {v: bm.verts.new(v.co - v.normal * thickness) for v in list(bm.verts)}
    for f in faces:
        nf = bm.faces.new([inner[v] for v in reversed(f.verts)])
        nf.smooth = True
    for e, f0 in rim:
        a, b = e.verts
        f = bm.faces.new((a, b, inner[b], inner[a]))
        f.smooth = True
        f.normal_update()
        if f.normal.dot((a.co + b.co) / 2 - f0.calc_center_median()) < 0:
            f.normal_flip()


def add_rib(bm, loop, r, sides=8):
    """Rolled hem: a soft tube following an opening."""
    n = len(loop)
    rings, axis = [], []
    for i, (p, nrm) in enumerate(loop):
        t = (loop[(i + 1) % n][0] - loop[i - 1][0]).normalized()
        u = (nrm - t * nrm.dot(t)).normalized()
        c = p + u * r * 0.3
        axis.append(c)
        rings.append([bm.verts.new(q) for q in ring(c, t, r, r * 0.85, sides, u=u)])
    for i in range(n):
        a, b = rings[i], rings[(i + 1) % n]
        mid_axis = (axis[i] + axis[(i + 1) % n]) / 2
        for j in range(sides):
            f = bm.faces.new((a[j], a[(j + 1) % sides], b[(j + 1) % sides], b[j]))
            f.smooth = True
            f.normal_update()
            if f.normal.dot(f.calc_center_median() - mid_axis) < 0:
                f.normal_flip()


def transfer_weights(bm, sample, smooth=2):
    """Weights from the body surface under each vertex, smoothed over the
    garment and limited to the four strongest bones."""
    bm.verts.index_update()
    W = [sample(v.co) for v in bm.verts]
    nb = [[e.other_vert(v).index for e in v.link_edges] for v in bm.verts]
    for _ in range(smooth):
        new = []
        for i, w in enumerate(W):
            if not nb[i]:
                new.append(w)
                continue
            acc = {g: x * 0.5 for g, x in w.items()}
            s = 0.5 / len(nb[i])
            for j in nb[i]:
                for g, x in W[j].items():
                    acc[g] = acc.get(g, 0.0) + x * s
            new.append(acc)
        W = new
    out = []
    for w in W:
        top = sorted(w.items(), key=lambda kv: -kv[1])[:4]
        total = sum(x for _, x in top) or 1.0
        out.append({g: x / total for g, x in top if x / total > 0.01})
    return out


def build_garment(scn, col, arm, sample, name, mat, nodes, edges, cuts, clearance, thickness, rib,
                  roots=None, over=()):
    """A garment mesh of its own: grown from a stick figure, fitted, opened
    at the hems, given thickness and rolled edges, weighted from the body.
    over: [(bvh, clearance, where)] of garments it must stay outside of.
    Returns the object and a BVH of it for the garments that go on top."""
    me = skin_surface(scn, name, nodes, edges, roots)
    bm = bmesh.new()
    bm.from_mesh(me)
    bpy.data.meshes.remove(me)
    fit(bm, sample.bvh, clearance)
    for bvh, c, where in over:
        fit(bm, bvh, c, where)
    for co, no, tip, eligible in cuts:
        cut_open(bm, V(co), V(no).normalized(), V(tip), eligible)
    loops = boundary_loops(bm)
    solidify(bm, thickness)
    for loop in loops:
        add_rib(bm, loop, rib(loop) if callable(rib) else rib)
    for f in bm.faces:
        f.material_index = 0
        f.smooth = True
    bm.normal_update()
    bvh = BVHTree.FromBMesh(bm)
    gm = Mesh(bm)
    gm.weights = transfer_weights(bm, sample)
    gm.mi(mat)
    return gm.to_object(name, col, arm), bvh


def build_shorts(scn, col, arm, sample):
    nodes = [("pelvis", (0, 0.006, 0.715), (0.139, 0.099)), ("waist", (0, 0.004, 0.80), (0.125, 0.089)),
             ("top", (0, 0.004, 0.87), (0.123, 0.087))]
    edges = [("pelvis", "waist"), ("waist", "top")]
    cuts = [((0, 0.004, WAIST), (0, 0, 1), (0, 0.004, 0.97), lambda c: c.z > 0.74)]
    for s, k in SIDES:
        nodes += [("hip" + s, (k * 0.085, 0.005, 0.655), (0.085, 0.092)),
                  ("thigh" + s, (k * 0.095, 0.003, 0.54), (0.074, 0.083)),
                  ("leg" + s, (k * 0.1, 0.0, 0.44), (0.07, 0.078)),
                  ("leg_end" + s, (k * 0.102, -0.002, 0.36), (0.07, 0.078))]
        edges += [("pelvis", "hip" + s), ("hip" + s, "thigh" + s), ("thigh" + s, "leg" + s),
                  ("leg" + s, "leg_end" + s)]
        a, b, d = head_of("thigh." + s), tail_of("thigh." + s), bone_dir("thigh." + s)
        co = a + d * SHORTS
        cuts.append((co, d, V(k * 0.102, -0.002, 0.36) + d * 0.08,
                     lambda c, a=a, b=b, co=co, k=k: c.x * k > 0 and line_dist(c, a, b) < 0.1 and (c - co).length < 0.13))
    return build_garment(scn, col, arm, sample, "garment_shorts", "shorts", nodes, edges, cuts,
                         clearance=0.006, thickness=0.003, rib=0.0045)


def build_shirt(scn, col, arm, sample, shorts_bvh):
    nodes = [("hem0", (0, 0.006, 0.54), (0.156, 0.114)), ("hem1", (0, 0.006, 0.63), (0.155, 0.113)),
             ("hem", (0, 0.006, 0.72), (0.153, 0.111)),
             ("waist", (0, 0.004, 0.83), (0.14, 0.099)), ("ribs", (0, 0.002, 0.95), (0.142, 0.099)),
             ("chest", (0, 0.006, 1.04), (0.146, 0.097)), ("neck0", (0, 0.012, 1.115), (0.069, 0.065)),
             ("neck1", (0, 0.012, 1.20), (0.065, 0.062))]
    edges = [("hem0", "hem1"), ("hem1", "hem"), ("hem", "waist"), ("waist", "ribs"), ("ribs", "chest"), ("chest", "neck0"),
             ("neck0", "neck1")]
    cuts = [((0, 0.006, HEM), (0, 0, -1), (0, 0.006, 0.4), lambda c: c.z < 0.78),
            ((0, 0.01, COLLAR), (0, -0.3, 1), (0, 0.012, 1.28),
             lambda c: c.z > 1.06 and math.hypot(c.x, c.y - 0.01) < 0.085)]
    for s, k in SIDES:
        nodes += [("clav" + s, (k * 0.085, 0.01, 1.08), (0.071, 0.066)),
                  ("shoulder" + s, arm_pt(k, 0.16, 0.012, 1.065), (0.066, 0.064)),
                  ("sleeve" + s, arm_pt(k, 0.18, 0.012, 0.96), (0.062, 0.062)),
                  ("sleeve_end" + s, arm_pt(k, 0.19, 0.012, 0.90), (0.062, 0.062))]
        edges += [("chest", "clav" + s), ("clav" + s, "shoulder" + s), ("shoulder" + s, "sleeve" + s),
                  ("sleeve" + s, "sleeve_end" + s)]
        a, b, d = head_of("upper_arm." + s), tail_of("upper_arm." + s), bone_dir("upper_arm." + s)
        co = a + d * SLEEVE
        cuts.append((co, d, V(arm_pt(k, 0.19, 0.012, 0.90)) + d * 0.08,
                     lambda c, a=a, b=b, co=co: line_dist(c, a, b) < 0.085 and (c - co).length < 0.11))

    def rib(loop):
        c = sum((p for p, _ in loop), Vector()) / len(loop)
        return 0.0055 if c.z > 1.05 and abs(c.x) < 0.05 else 0.0038

    return build_garment(scn, col, arm, sample, "garment_shirt", "shirt", nodes, edges, cuts,
                         clearance=0.008, thickness=0.0025, rib=rib,
                         over=[(shorts_bvh, 0.008, lambda p: p.z < 0.84)])


def build_socks(scn, col, arm, sample):
    nodes, edges, cuts, roots = [], [], [], []
    for s, k in SIDES:
        nodes += [("heel" + s, (k * 0.092, 0.01, 0.045), (0.034, 0.045)),
                  ("ankle" + s, (k * 0.092, 0.012, 0.09), (0.035, 0.037)),
                  ("shin" + s, (k * 0.092, 0.012, 0.17), (0.04, 0.042)),
                  ("top" + s, (k * 0.092, 0.012, 0.22), (0.041, 0.043))]
        edges += [("heel" + s, "ankle" + s), ("ankle" + s, "shin" + s), ("shin" + s, "top" + s)]
        roots.append("heel" + s)
        co = V(k * 0.092, 0.012, SOCK_TOP)
        cuts.append((co, (0, 0, 1), (k * 0.092, 0.012, 0.28),
                     lambda c, co=co, k=k: c.x * k > 0 and (c - co).length < 0.08))
    return build_garment(scn, col, arm, sample, "garment_socks", "sock", nodes, edges, cuts,
                         clearance=0.003, thickness=0.002, rib=0.0045, roots=roots)


# garment: body pieces it covers completely
OUTFIT = {
    "garment_shirt": ["torso_upper", "torso_lower", "upper_arms"],
    "garment_shorts": ["torso_lower", "pelvis", "thighs"],
    "garment_socks": ["ankles", "feet"],
    "garment_shoes": ["feet"],
}


# ----------------------------------------------------------------------------
# Head, face, hair
# ----------------------------------------------------------------------------
# (z, half width, half depth, centre y), chin to crown
HEAD = [(1.192, 0.0, 0.0, -0.05), (1.195, 0.026, 0.020, -0.052), (1.204, 0.043, 0.033, -0.05),
        (1.218, 0.061, 0.052, -0.038), (1.236, 0.075, 0.068, -0.025), (1.260, 0.085, 0.082, -0.013),
        (1.290, 0.092, 0.094, -0.004), (1.325, 0.096, 0.102, 0.002), (1.360, 0.098, 0.106, 0.006),
        (1.395, 0.095, 0.105, 0.010), (1.425, 0.085, 0.097, 0.012), (1.450, 0.066, 0.079, 0.013),
        (1.466, 0.042, 0.052, 0.013), (1.474, 0.020, 0.025, 0.013), (1.477, 0.0, 0.0, 0.013)]
HEAD_W = {"head": 1.0}
# (x, z, sigma x, sigma z, height): nose, cheeks, brow, eye sockets, lips, chin
FACE_BUMPS = [(0, 1.322, 0.007, 0.016, 0.005), (0, 1.297, 0.009, 0.013, 0.010), (0, 1.29, 0.007, 0.007, 0.006),
              (0.011, 1.289, 0.005, 0.005, 0.004), (-0.011, 1.289, 0.005, 0.005, 0.004),
              (0.055, 1.28, 0.025, 0.025, 0.005), (-0.055, 1.28, 0.025, 0.025, 0.005),
              (0.036, 1.347, 0.022, 0.008, 0.004), (-0.036, 1.347, 0.022, 0.008, 0.004),
              (0.036, 1.325, 0.016, 0.011, -0.005), (-0.036, 1.325, 0.016, 0.011, -0.005),
              (0, 1.258, 0.016, 0.006, 0.003), (0, 1.212, 0.022, 0.012, 0.004)]
# hairline height by angle from the front (0) to the back (pi)
HAIRLINE = [(0.0, 1.374), (0.35, 1.371), (0.7, 1.358), (1.0, 1.334), (1.2, 1.300), (1.35, 1.318),
            (1.55, 1.338), (1.8, 1.31), (2.3, 1.262), (math.pi, 1.245)]


def head_profile(z):
    rows = [(r[0], V(r[1], r[2], r[3])) for r in HEAD]
    return catmull(rows, z)


def hairline(a):
    return catmull([(x, y) for x, y in HAIRLINE], a)


def build_head(col, arm):
    H = Mesh()
    bm = H.bm
    skin = H.mi("skin")
    bmesh.ops.create_uvsphere(bm, u_segments=64, v_segments=40, radius=1.0)
    n_sphere = len(bm.verts)
    z0, z1 = HEAD[0][0], HEAD[-1][0]
    for v in bm.verts:
        s = v.co.copy()
        theta = math.atan2(s.y, s.x)
        z = (z0 + z1) / 2 + (z1 - z0) / 2 * s.z
        rx, ry, cy = head_profile(z)
        ry *= 0.95 if math.sin(theta) < 0 else 1.0
        v.co = V(rx * math.cos(theta), cy + ry * math.sin(theta), z)
    bm.normal_update()
    for v in bm.verts:
        if v.co.y > 0.0:
            continue
        h = sum(a * math.exp(-((v.co.x - x) ** 2 / (2 * sx * sx) + (v.co.z - z) ** 2 / (2 * sz * sz)))
                for x, z, sx, sz, a in FACE_BUMPS)
        v.co += v.normal * h
    for f in bm.faces:
        f.material_index = skin
        f.smooth = True
    H.pad(HEAD_W)
    for k in (1, -1):
        res = bmesh.ops.create_icosphere(bm, subdivisions=3, radius=1.0,
                                         matrix=Matrix.Translation(V(k * 0.094, 0.016, 1.31)) @
                                         Matrix.Rotation(k * 0.25, 4, "Z") @ Matrix.Diagonal((0.015, 0.024, 0.032, 1)))
        for f in {f for v in res["verts"] for f in v.link_faces}:
            f.material_index = skin
            f.smooth = True
    H.pad(HEAD_W)
    bm.normal_update()
    bvh = BVHTree.FromBMesh(bm)

    def hit(x, z, off):
        loc, nrm, _, _ = bvh.ray_cast(V(x, -0.4, z), V(0, 1, 0))
        return loc + nrm * off, nrm

    def fan(outline, centre, off, mat):
        c, n = hit(centre[0], centre[1], off)
        cv = H.v(c, HEAD_W)
        ring_v = [H.v(hit(x, z, off)[0], HEAD_W) for x, z in outline]
        for i in range(len(ring_v)):
            H.face((cv, ring_v[i], ring_v[(i + 1) % len(ring_v)]), mat, n)

    def ribbon(path, widths, off, mat):
        left, right, norms = [], [], []
        for i, (x, z) in enumerate(path):
            a = path[max(i - 1, 0)]
            b = path[min(i + 1, len(path) - 1)]
            tx, tz = b[0] - a[0], b[1] - a[1]
            ln = math.hypot(tx, tz) or 1.0
            px, pz = -tz / ln, tx / ln
            w = widths[i] / 2
            pl, n = hit(x + px * w, z + pz * w, off)
            pr, _ = hit(x - px * w, z - pz * w, off)
            left.append(H.v(pl, HEAD_W))
            right.append(H.v(pr, HEAD_W))
            norms.append(n)
        for i in range(len(path) - 1):
            H.face((left[i], right[i], right[i + 1], left[i + 1]), mat, norms[i])

    sclera, iris, pupil, lid, brow, mouth = (H.mi(n) for n in ("sclera", "iris", "pupil", "lid", "brow", "mouth"))
    W, Hh = 0.034, 0.019
    for k in (1, -1):
        cx, cz = k * 0.037, 1.322

        def almond(t, scale=1.0):
            x = cx + 0.5 * W * scale * math.cos(t)
            s = math.sin(t)
            z = cz + 0.5 * Hh * scale * s * (1.0 if s > 0 else 0.8) + 0.002 * k * (x - cx) / (W / 2) * scale
            return x, z

        def lower_z(x):
            u = min(1.0, abs(x - cx) / (W / 2))
            return cz - 0.4 * Hh * math.sqrt(1 - u * u) + 0.002 * k * (x - cx) / (W / 2)

        fan([almond(2 * math.pi * i / 28) for i in range(28)], (cx, cz), 0.0010, sclera)
        ix, iz = cx - k * 0.0015, cz + 0.0005
        circ = []
        for i in range(24):
            t = 2 * math.pi * i / 24
            x, z = ix + 0.0096 * math.cos(t), iz + 0.0093 * math.sin(t)
            circ.append((x, max(z, lower_z(x) + 0.0004)))
        fan(circ, (ix, iz), 0.0015, iris)
        fan([(ix + 0.005 * math.cos(2 * math.pi * i / 16), iz + 0.005 * math.sin(2 * math.pi * i / 16))
             for i in range(16)], (ix, iz), 0.0019, pupil)
        hx, hz = ix + 0.003, iz + 0.0035
        fan([(hx + 0.0022 * math.cos(2 * math.pi * i / 10), hz + 0.0022 * math.sin(2 * math.pi * i / 10))
             for i in range(10)], (hx, hz), 0.0023, sclera)
        # upper lid: thick dark line along the top of the almond, flicking out at the outer corner
        ts = [math.pi - math.pi * i / 14 for i in range(15)] if k > 0 else [math.pi * i / 14 for i in range(15)]
        path = [almond(t) for t in ts]
        ox, oz = path[-1]
        path.append((ox + k * 0.004, oz + 0.002))
        widths = [0.0012 + 0.0022 * math.sin(math.pi * i / 14) ** 0.6 for i in range(15)] + [0.0006]
        path = [(x, z + 0.0006) for x, z in path]
        ribbon(path, widths, 0.0024, lid)
        # eyebrow: thick at the inner end, slightly arched, thin at the outer end
        bp = [(k * lerp(0.016, 0.058, i / 10),
               1.3445 + 0.0065 * math.sin(0.5 * math.pi * min(1.0, i / 7)) - 0.003 * max(0.0, (i - 7) / 3))
              for i in range(11)]                    # low at the inner end: a calm, determined look
        ribbon(bp, [0.0064 * (1 - 0.5 * (i / 10) ** 1.5) for i in range(11)], 0.0012, brow)
    mp = [(lerp(-0.014, 0.014, i / 10), 1.2562 - 0.0012 * (2 * i / 10 - 1) ** 2) for i in range(11)]
    ribbon(mp, [0.0022 * (1 - 0.55 * abs(2 * i / 10 - 1) ** 1.5) for i in range(11)], 0.0009, mouth)
    head = H.to_object("kid_head", col, arm, HEAD_XF)
    head["sphere_verts"] = n_sphere                   # the skull, before the ears and face
    return head


def build_hair(col, arm, head_obj):
    """Hair: a cap that gives the head its volume, with a smooth hairline,
    and ~120 pointed locks layered on it whose tips flick outwards."""
    me = head_obj.data
    sphere_verts = head_obj["sphere_verts"]
    skull = BVHTree.FromPolygons([v.co for v in me.vertices[:sphere_verts]],
                                 [p.vertices for p in me.polygons if all(i < sphere_verts for i in p.vertices)])
    hm = Mesh()
    hair = hm.mi("hair")
    centre = V(0, 0.008, 1.33)

    def azimuth(p):
        return abs(math.atan2(p.x, -(p.y - 0.004)))      # 0 at the front, pi at the back

    # cap: a grid from the hairline up to the crown, lifted off the skull
    cols, rows, crown = 72, 12, V(0, 0.013, 1.477)
    grid = []
    for j in range(cols):
        th = 2 * math.pi * j / cols
        a = azimuth(V(math.cos(th), math.sin(th), 0))
        z0 = hairline(a) - 0.004
        col_v = []
        for i in range(rows):
            t = i / rows
            z = lerp(z0, 1.474, 1 - (1 - t) ** 1.3)
            rx, ry, cy = head_profile(z)
            ry *= 0.95 if math.sin(th) < 0 else 1.0
            p = V(rx * math.cos(th), cy + ry * math.sin(th), z)
            loc, nrm, _, _ = skull.ray_cast(centre, (p - centre).normalized())
            if loc is None:                                # grazed an edge exactly
                loc, nrm, _, _ = skull.find_nearest(p)
            off = 0.003 + smoothstep(0.0, 0.3, t) * (0.012 + 0.012 * smoothstep(1.38, 1.47, z)
                                                      + 0.008 * smoothstep(0.9, 2.2, a))
            col_v.append(hm.v(loc + nrm * off, HEAD_W))
        grid.append(col_v)
    top = hm.v(crown + V(0, 0, 0.026), HEAD_W)
    for j in range(cols):
        a_col, b_col = grid[j], grid[(j + 1) % cols]
        for i in range(rows - 1):
            q = (a_col[i], b_col[i], b_col[i + 1], a_col[i + 1])
            hm.face(q, hair, sum((v.co for v in q), Vector()) / 4 - centre)
        hm.face((a_col[-1], b_col[-1], top), hair, top.co - centre)
    hm.bm.normal_update()
    bvh = BVHTree.FromBMesh(hm.bm)

    rng = random.Random(15)
    n_dirs = 420
    whorl = V(0, 0.03, 1.475)
    golden = math.pi * (3 - math.sqrt(5))
    for i in range(n_dirs):
        zz = 1 - (i + 0.5) / n_dirs * 1.4               # upper part of a sphere
        if zz < -0.6:
            continue
        r = math.sqrt(max(0.0, 1 - zz * zz))
        d = V(r * math.cos(golden * i), r * math.sin(golden * i), zz)
        loc, nrm, _, _ = bvh.ray_cast(centre, d)
        if loc is None:
            continue
        a = azimuth(loc)
        if loc.z < hairline(a) + 0.01 or rng.random() < 0.66:
            continue
        n = (loc - centre).normalized().lerp(nrm, 0.5).normalized()

        def along(vec):
            t = vec - n * vec.dot(n)
            return t.normalized() if t.length > 1e-4 else V(0, 1, 0)

        jitter = V(rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1)) * 0.3
        if loc.z > 1.44:
            g = along(loc - whorl + jitter * 0.03)
            lift, length, width, bone = rng.uniform(0.22, 0.45), rng.uniform(0.055, 0.085), \
                rng.uniform(0.036, 0.048), "hair_top"
        elif a < 0.8:
            g = along(V(0, -0.25, -1) + jitter)
            lift, length, width, bone = rng.uniform(0.04, 0.14), rng.uniform(0.06, 0.08), \
                rng.uniform(0.032, 0.042), "hair_front"
        elif a < 2.3:
            g = along(V(0, 0.3, -1) + jitter)
            lift, length, width, bone = rng.uniform(0.05, 0.14), rng.uniform(0.05, 0.068), \
                rng.uniform(0.034, 0.046), "hair_back"
        else:
            g = along(V(0, 0.15, -1) + jitter)
            lift, length, width, bone = rng.uniform(0.08, 0.22), rng.uniform(0.05, 0.07), \
                rng.uniform(0.036, 0.048), "hair_back"
        tuft(hm, loc, n, g, length, width, lift, bone, hair, front=a < 0.8)
    return hm.to_object("kid_hair", col, arm, HEAD_XF)


def tuft(hm, root, n, g, length, width, lift, bone, mat, front=False):
    """One lock: wide at the root, lying on the cap, tip flicking outwards."""
    p0 = root - n * 0.008
    p1 = root + (g * 0.55 + n * lift * 0.12) * length
    p2 = root + (g + n * lift * 0.55) * length
    if front and p2.z < 1.352:                       # keep the fringe above the eyebrows
        s = max(0.3, (root.z - 1.352) / max(root.z - p2.z, 1e-4))
        p1 = root + (p1 - root) * s
        p2 = root + (p2 - root) * s
    rings, steps = [], 6

    def bez(t):
        return p0 * (1 - t) ** 2 + p1 * 2 * t * (1 - t) + p2 * t * t

    def weight(p):
        t = min(1.0, (p - p0).length / max((p2 - p0).length, 1e-4))
        s = smoothstep(0.1, 0.9, t) * 0.9
        return {"head": 1 - s, bone: s}

    for i in range(steps):
        t = i / steps
        p = bez(t)
        tan = (bez(t + 0.01) - p).normalized()
        side = n.cross(tan).normalized()
        w = width * (1 - t) * (1 + 0.15 * math.sin(math.pi * t))
        rings.append(ring(p, tan, w / 2, w * 0.3, 6, u=side))
    hm.loft(rings, mat, weight, cap0=True, tip=bez(1.0))


# ----------------------------------------------------------------------------
# Hands and sneakers
# ----------------------------------------------------------------------------
def build_hands(col, arm):
    hm = Mesh()
    skin = hm.mi("skin")
    for s, k in SIDES:
        W = head_of("hand." + s)
        h = bone_dir("hand." + s)
        pn = V(-k, 0, 0)
        pn = (pn - h * pn.dot(h)).normalized()
        a = h.cross(pn).normalized()
        if a.y > 0:
            a = -a                                      # a points to the front, where the thumb is
        hand_w = {"hand." + s: 1.0}
        hm.loft([ring(W + h * t, h, rw, rt, 12, power=2.4, u=a) for t, rw, rt in
                 ((-0.006, 0.024, 0.011), (0.012, 0.028, 0.0125), (0.04, 0.031, 0.013), (0.062, 0.03, 0.011))],
                skin, hand_w, cap0=True, cap1=True)
        knuckle = W + h * 0.062

        for off, scale in ((0.0195, 1.0), (0.0065, 1.08), (-0.0065, 1.0), (-0.0195, 0.82)):
            base = W + h * 0.056 + a * off + pn * 0.001
            d = h.copy()
            pts, radius = [base], 0.0068
            for seg, bend in ((0.022, 0.2), (0.016, 0.35), (0.014, 0.3)):
                d = (d * math.cos(bend) + pn * math.sin(bend)).normalized()
                pts.append(pts[-1] + d * seg * scale)
            rs = [ring(p, (pts[min(i + 1, 3)] - pts[max(i - 1, 0)]), radius * (1 - 0.18 * i / 3),
                       radius * (1 - 0.18 * i / 3), 8, u=a) for i, p in enumerate(pts)]

            def fw(p, s=s):
                t = smoothstep(0.0, 0.012, (p - knuckle).dot(h))
                return {"hand." + s: 1 - t, "fingers." + s: t}

            hm.loft(rs, skin, fw, cap0=True, tip=pts[-1] + d * 0.004)
        tb = W + h * 0.018 + a * 0.026 + pn * 0.004
        td = (h * 0.75 + a * 0.35 + pn * 0.45).normalized()
        t1 = tb + td * 0.021
        td2 = (td + pn * 0.3).normalized()
        t2 = t1 + td2 * 0.018
        hm.loft([ring(tb, td, 0.0085, 0.0085, 8, u=a), ring(t1, td + td2, 0.0078, 0.0078, 8, u=a),
                 ring(t2, td2, 0.0068, 0.0068, 8, u=a)], skin, hand_w, cap0=True, tip=t2 + td2 * 0.004)
    return hm.to_object("kid_hands", col, arm)


SHOE = [(0.078, 0.030, 0.030, 0.085), (0.07, 0.040, 0.028, 0.098), (0.05, 0.047, 0.026, 0.104),
        (0.02, 0.050, 0.026, 0.100), (-0.01, 0.052, 0.026, 0.092), (-0.04, 0.053, 0.026, 0.082),
        (-0.07, 0.053, 0.026, 0.070), (-0.10, 0.052, 0.026, 0.060), (-0.125, 0.049, 0.027, 0.053),
        (-0.145, 0.043, 0.029, 0.048), (-0.16, 0.033, 0.031, 0.043), (-0.168, 0.020, 0.033, 0.040)]


def build_shoes(col, arm):
    sm = Mesh()
    shoe, sole, stripe = sm.mi("shoe"), sm.mi("sole"), sm.mi("stripe")
    fwd = V(0, -1, 0)
    for s, k in SIDES:
        A = head_of("foot." + s)
        A0 = V(A.x, A.y, 0)

        def w(p, s=s):
            t = smoothstep(-0.05, -0.08, p.y - A.y)
            return {"foot." + s: 1 - t, "toe." + s: t}

        sm.loft([ring(A0 + V(0, dy, (zb + zt) / 2), fwd, hw, (zt - zb) / 2, 16, power=2.6)
                 for dy, hw, zb, zt in SHOE], shoe, w, cap0=True, cap1=True)
        # padded collar round the ankle opening
        c = A0 + V(0, 0.022, 0.1)
        sm.loft([[c + V(math.cos(t) * (0.036 + 0.009 * math.cos(u)), math.sin(t) * (0.042 + 0.009 * math.cos(u)),
                        0.009 * math.sin(u)) for t in [2 * math.pi * i / 16 for i in range(16)]]
                 for u in [2 * math.pi * j / 8 for j in range(9)]], shoe, w)
        sole_st = [(0.083, 0.034, 0.0, 0.03)] + [(dy, hw + 0.006, 0.0 + 0.04 * max(0.0, -dy - 0.1), 0.03)
                                                 for dy, hw, _, _ in SHOE[1:-1]] + [(-0.176, 0.026, 0.008, 0.036)]
        sm.loft([ring(A0 + V(0, dy, (zb + zt) / 2), fwd, hw, (zt - zb) / 2, 16, power=4.0)
                 for dy, hw, zb, zt in sole_st], sole, w, cap0=True, cap1=True)
        bvh = BVHTree.FromBMesh(sm.bm)

        def on_side(side, dy, z, off=0.0012):
            z = min(z, catmull([(-st[0], st[3]) for st in SHOE], -dy) - 0.008)   # stay below the top edge
            loc, nrm, _, _ = bvh.ray_cast(V(A.x + side * 0.2, A.y + dy, z), V(-side, 0, 0))
            return loc + nrm * off, nrm

        def on_top(x, dy, off=0.0012):
            loc, nrm, _, _ = bvh.ray_cast(V(x, A.y + dy, 0.3), V(0, 0, -1))
            return loc + nrm * off, nrm

        for side in (1, -1):
            for y0 in (-0.002, -0.028):
                path = [(y0 - 0.034 * i / 6, 0.034 + 0.048 * i / 6) for i in range(7)]
                L, R, N = [], [], []
                for dy, z in path:
                    pl, n = on_side(side, dy - 0.0035, z)
                    pr, _ = on_side(side, dy + 0.0035, z)
                    L.append(sm.v(pl, w(pl)))
                    R.append(sm.v(pr, w(pr)))
                    N.append(n)
                for i in range(6):
                    sm.face((L[i], R[i], R[i + 1], L[i + 1]), stripe, N[i])
        for dy in (-0.012, -0.032, -0.052, -0.072):
            L, R, N = [], [], []
            for i in range(5):
                x = A.x + lerp(-0.019, 0.019, i / 4)
                pl, n = on_top(x, dy - 0.003)
                pr, _ = on_top(x, dy + 0.003)
                L.append(sm.v(pl, w(pl)))
                R.append(sm.v(pr, w(pr)))
                N.append(n)
            for i in range(4):
                sm.face((L[i], R[i], R[i + 1], L[i + 1]), stripe, N[i])
    return sm.to_object("garment_shoes", col, arm)


# ----------------------------------------------------------------------------
# Rig and animation
# ----------------------------------------------------------------------------
def build_armature(scn):
    arm_data = bpy.data.armatures.new("kid_rig")
    arm = bpy.data.objects.new("kid_rig", arm_data)
    scn.collection.objects.link(arm)
    vl = scn.view_layers[0]
    vl.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    for name, (h, t, parent, deform) in BONES.items():
        eb = arm_data.edit_bones.new(name)
        eb.head, eb.tail = h, t
        d = V(t) - V(h)
        eb.align_roll(V(0, -1, 0) if abs(d.z) > abs(d.y) else V(0, 0, 1))
        eb.use_deform = deform
        if parent:
            eb.parent = arm_data.edit_bones[parent]
    bpy.ops.object.mode_set(mode="OBJECT")
    return arm


# ----------------------------------------------------------------------------
# Animations: retargeted from the Universal Animation Library (CC0)
# ----------------------------------------------------------------------------
# name: (library file, clip, loops, lands on the ground)
CLIPS = {
    "idle": ("UAL1.glb", "Idle_Loop", True, True),
    "walk": ("UAL1.glb", "Walk_Loop", True, True),
    "run": ("UAL1.glb", "Sprint_Loop", True, True),
    "jump": ("UAL1.glb", "Jump_Start", False, True),
    "fall": ("UAL1.glb", "Jump_Loop", True, False),
    "land": ("UAL1.glb", "Jump_Land", False, True),
    "double_jump": ("UAL2.glb", "NinjaJump_Start", False, False),
    "crouch_idle": ("UAL1.glb", "Crouch_Idle_Loop", True, True),
    "crouch_walk": ("UAL1.glb", "Crouch_Fwd_Loop", True, True),
    "punch_jab": ("UAL1.glb", "Punch_Jab", False, True),
    "punch_cross": ("UAL1.glb", "Punch_Cross", False, True),
    "hit": ("UAL1.glb", "Hit_Chest", False, True),
}
GAITS = ("walk", "run", "crouch_walk")
ARM_OUT = 0.04                       # radians the arms are held further out than the source (wider torso)
HEAD_UP = 0.16                       # radians the head is tilted up from the source
HEEL_REL = V(0, 0.058, -0.085)       # heel contact point, from the ankle
BALL_REL = V(0, -0.07, -0.085)       # ball of the foot, from the ankle


def _contacts(arm, mats):
    """Heel and ball positions of both feet for one pose."""
    pts = []
    for s, _ in SIDES:
        rest = arm.data.bones["foot." + s].matrix_local
        for rel in (HEEL_REL, BALL_REL):
            local = rest.inverted() @ (rest.translation + rel)
            pts.append(mats["foot." + s] @ local)
    return pts


def animate(arm, root):
    """Retargets every clip in CLIPS onto the rig as actions (one NLA track
    each, so the glTF export keeps them all); returns the gait speeds."""
    lib_scene, rigs = retarget_ual.load_library(root)
    leg = (head_of("thigh.L") - head_of("foot.L")).length
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
    ad = arm.animation_data_create()
    for t in list(ad.nla_tracks):
        ad.nla_tracks.remove(t)
    speeds, stats = {}, {}
    for name, (src, clip, loops, grounded) in CLIPS.items():
        rig = rigs[src]
        thigh = retarget_ual.BONE_MAPS[src]["thigh.L"]
        foot = retarget_ual.BONE_MAPS[src]["foot.L"]
        src_leg = (rig.data.bones[thigh].head_local - rig.data.bones[foot].head_local).length
        frames, src_rest, src_hips = retarget_ual.sample(lib_scene, rig, clip)
        poses = retarget_ual.retarget(arm, frames, src_rest, src_hips, src, leg / src_leg, ARM_OUT, HEAD_UP)
        fks = [retarget_ual.forward_kinematics(arm, local, delta) for local, delta in poses]
        lift = 0.0
        if grounded:
            lift = -min(min(p.z for p in _contacts(arm, m)) for m in fks)
        if name in GAITS:
            speeds[name] = round(_stance_speed(arm, fks), 3)
        old = bpy.data.actions.get(name)
        if old:
            bpy.data.actions.remove(old)
        action = bpy.data.actions.new(name)
        action.use_fake_user = True
        ad.action = action
        rest_hips = arm.data.bones["hips"].matrix_local.to_3x3().inverted()
        for f, (local, delta) in enumerate(poses):
            for pb in arm.pose.bones:
                pb.rotation_quaternion = local[pb.name]
                pb.keyframe_insert("rotation_quaternion", frame=f + 1)
            hp = arm.pose.bones["hips"]
            hp.location = rest_hips @ (delta + V(0, 0, lift))
            hp.keyframe_insert("location", frame=f + 1)
        track = ad.nla_tracks.new()
        track.name = name
        track.strips.new(name, 1, action)
        ad.action = None
        stats[name] = {"frames": len(poses), "lift": round(lift, 3)}
    for pb in arm.pose.bones:
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.location = (0, 0, 0)
    return speeds, stats


def _stance_speed(arm, fks):
    """Ground speed (m/s) at which the planted foot of a cycle does not
    slide: how fast the lowest contact point moves backwards."""
    total, n = 0.0, 0
    for a, b in zip(fks, fks[1:]):
        ca, cb = _contacts(arm, a), _contacts(arm, b)
        i = min(range(len(ca)), key=lambda j: ca[j].z)
        if ca[i].z - min(p.z for p in ca) < 0.01:
            total += (cb[i].y - ca[i].y) * FPS
            n += 1
    return abs(total / max(n, 1))


# ----------------------------------------------------------------------------
def min_gap(ob, bvh, where):
    """Smallest signed distance from ob's vertices (where(p)) to a surface."""
    gap = 1.0
    for v in ob.data.vertices:
        if where(v.co):
            loc, nrm, _, _ = bvh.find_nearest(v.co)
            if loc is not None:
                gap = min(gap, (v.co - loc).dot(nrm))
    return round(gap, 4)


def run(root):
    scn = bpy.data.scenes.get("Character") or bpy.data.scenes.new("Character")
    scn.render.fps = FPS
    prev = bpy.context.window.scene
    bpy.context.window.scene = scn
    try:
        for ob in list(scn.collection.all_objects):
            bpy.data.objects.remove(ob, do_unlink=True)
        for coll in (bpy.data.meshes, bpy.data.armatures):
            for d in [d for d in coll if d.users == 0]:
                coll.remove(d)
        col = scn.collection
        arm = build_armature(scn)
        body = build_body(scn, arm)
        sample = BodySampler(body)
        shorts, shorts_bvh = build_shorts(scn, col, arm, sample)
        shirt, _ = build_shirt(scn, col, arm, sample, shorts_bvh)
        socks, _ = build_socks(scn, col, arm, sample)
        gaps = {"shirt_over_shorts": min_gap(shirt, shorts_bvh, lambda p: p.z < 0.80),
                "shirt_over_body": min_gap(shirt, sample.bvh, lambda p: True),
                "shorts_over_body": min_gap(shorts, sample.bvh, lambda p: True),
                "socks_over_body": min_gap(socks, sample.bvh, lambda p: True)}
        pieces = split_body(body, col, arm)
        head = build_head(col, arm)
        hair = build_hair(col, arm, head)
        hands = build_hands(col, arm)
        shoes = build_shoes(col, arm)
        speeds, clips = animate(arm, root)
        parts = list(pieces.values()) + [head, hair, hands, shirt, shorts, socks, shoes]

        out = os.path.join(root, "game", "characters", "kid")
        os.makedirs(out, exist_ok=True)
        info = {
            "gait_speed": speeds,
            "body_parts": {p: "body_" + p for p in pieces},
            "garments": {g: {"hides": h} for g, h in OUTFIT.items()},
            "outfit": list(OUTFIT),
            "spring_bones": ["hair_front", "hair_top", "hair_back"],
        }
        with open(os.path.join(out, "kid.json"), "w") as f:
            json.dump(info, f, indent=1)
        vl = scn.view_layers[0]
        for ob in scn.objects:
            ob.select_set(ob is arm or ob in parts, view_layer=vl)
        bpy.ops.export_scene.gltf(filepath=os.path.join(out, "kid.glb"), export_format="GLB", use_selection=True,
                                  use_active_scene=True, export_yup=True, export_skins=True,
                                  export_animations=True, export_animation_mode="NLA_TRACKS", export_morph=False,
                                  export_apply=False)
    finally:
        bpy.context.window.scene = prev
    return {"tris": {o.name: sum(len(p.vertices) - 2 for p in o.data.polygons) for o in parts},
            "gaps": gaps, "clips": clips, "gait_speed": info["gait_speed"]}


def preview(root, frames=None):
    """Workbench renders for checking against the sheet: renders/kid/*.png.
    Body pieces under the outfit are left out, as in the game."""
    scn = bpy.data.scenes["Character"]
    scn.render.engine = "BLENDER_WORKBENCH"
    sh = scn.display.shading
    sh.light, sh.color_type, sh.show_object_outline, sh.show_cavity = "STUDIO", "MATERIAL", True, False
    cam = bpy.data.objects.get("CharCam") or bpy.data.objects.new("CharCam", bpy.data.cameras.new("CharCam"))
    if cam.name not in scn.collection.objects:
        scn.collection.objects.link(cam)
    cam.data.type = "ORTHO"
    scn.camera = cam
    arm = bpy.data.objects["kid_rig"]
    arm.animation_data.use_nla = False
    covered = {"body_" + p for g in OUTFIT for p in OUTFIT[g]}
    for ob in scn.objects:
        ob.hide_render = ob.name in covered
    out = os.path.join(root, "renders", "kid")
    os.makedirs(out, exist_ok=True)
    prev = bpy.context.window.scene
    bpy.context.window.scene = scn

    def shot(name, deg, z, scale, w, h, action=None, fr=1):
        arm.animation_data.action = bpy.data.actions[action] if action else None
        if not action:
            for pb in arm.pose.bones:
                pb.rotation_quaternion = (1, 0, 0, 0)
                pb.location = (0, 0, 0)
        scn.frame_set(fr)
        a = math.radians(deg)
        cam.location = V(0, 0, z) + V(math.sin(a), -math.cos(a), 0) * 5
        cam.rotation_euler = (math.pi / 2, 0, a)
        cam.data.ortho_scale = scale
        scn.render.resolution_x, scn.render.resolution_y = w, h
        scn.render.filepath = os.path.join(out, name + ".png")
        bpy.ops.render.render(write_still=True)

    try:
        for name, deg in (("front", 0), ("q34", 35), ("side", 90), ("back", 180)):
            shot(name, deg, 0.76, 1.75, 500, 760, "idle", 1)
        shot("rest", 0, 0.76, 1.75, 500, 760)
        shot("face", 0, 1.33, 0.42, 600, 600, "idle", 1)
        shot("face34", 35, 1.33, 0.42, 600, 600, "idle", 1)
        shot("chest", 20, 1.0, 0.6, 600, 600, "idle", 1)
        for act, fr in frames or (("walk", 1), ("walk", 10), ("run", 1), ("run", 8), ("jump", 8),
                                  ("double_jump", 10), ("crouch_idle", 1), ("crouch_walk", 10), ("punch_jab", 8),
                                  ("punch_cross", 10), ("hit", 6), ("land", 3)):
            shot("pose_%s_%02d" % (act, fr), 70, 0.8, 1.9, 500, 760, act, fr)
    finally:
        arm.animation_data.action = None
        arm.animation_data.use_nla = True
        scn.frame_set(1)
        for ob in scn.objects:
            ob.hide_render = False
        bpy.context.window.scene = prev
    return {"renders": sorted(os.listdir(out))}
