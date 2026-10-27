"""Playable character: the boy from docs/character_sheet.png.

A low-poly, flat-shaded mesh (spiky dark hair, blue T-shirt, navy shorts,
white socks, navy sneakers with white soles, stripes and laces) skinned to a
humanoid armature, with idle, walk, run, jump, fall and land animations.

The boy faces -Y in Blender (+Z in Godot), 1 unit = 1 m, about 1.5 m tall.
Animations are posed procedurally: every frame is keyed from a function of
the cycle phase, so loops are seamless.

Writes game/characters/kid/kid.glb.

    import sys; sys.path.insert(0, r"<repo>/blender")
    import build_character; build_character.run(r"<repo>")
"""
import bmesh
import bpy
import math
import os
import random
from mathutils import Euler, Matrix, Vector

FPS = 30
COLOURS = {
    "skin": "#eaa46d", "shirt": "#3d5fb2", "shorts": "#2c3352", "hair": "#3a2920",
    "shoe": "#2a3253", "white": "#f3f3ef", "eye": "#2b1d16", "brow": "#3a2920", "mouth": "#a35f45",
}

# bone: (head, tail, parent)
BONES = {
    "root": ((0, 0, 0), (0, 0, 0.15), None),
    "hips": ((0, 0, 0.70), (0, 0, 0.82), "root"),
    "spine": ((0, 0, 0.82), (0, 0, 0.97), "hips"),
    "chest": ((0, 0, 0.97), (0, 0, 1.13), "spine"),
    "neck": ((0, 0, 1.13), (0, -0.005, 1.215), "chest"),
    "head": ((0, -0.005, 1.215), (0, -0.005, 1.45), "neck"),
}
for _s, _k in (("L", 1), ("R", -1)):
    BONES.update({
        "upper_arm." + _s: ((_k * 0.17, 0, 1.10), (_k * 0.205, 0.005, 0.86), "chest"),
        "forearm." + _s: ((_k * 0.205, 0.005, 0.86), (_k * 0.235, -0.005, 0.655), "upper_arm." + _s),
        "hand." + _s: ((_k * 0.235, -0.005, 0.655), (_k * 0.25, -0.012, 0.555), "forearm." + _s),
        "thigh." + _s: ((_k * 0.09, 0, 0.70), (_k * 0.095, 0, 0.40), "hips"),
        "shin." + _s: ((_k * 0.095, 0, 0.40), (_k * 0.095, 0.01, 0.09), "thigh." + _s),
        "foot." + _s: ((_k * 0.095, 0.01, 0.09), (_k * 0.095, -0.11, 0.03), "shin." + _s),
    })
SIDES = (("L", 1), ("R", -1))

# head cross-sections: (z, half width, half depth, centre y)
HEAD = [(1.198, 0.03, 0.026, -0.058), (1.222, 0.062, 0.058, -0.032), (1.258, 0.084, 0.084, -0.012),
        (1.30, 0.093, 0.097, 0.0), (1.35, 0.097, 0.104, 0.005), (1.40, 0.092, 0.10, 0.01),
        (1.44, 0.07, 0.08, 0.012), (1.468, 0.034, 0.04, 0.012)]
HEAD_CENTRE = Vector((0, 0.008, 1.33))


def V(*a):
    return Vector(a[0] if len(a) == 1 else a)


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


def frame(axis):
    a = axis.normalized()
    ref = V(0, -1, 0) if abs(a.z) > 0.7 else V(0, 0, 1)
    u = a.cross(ref).normalized()
    return u, a.cross(u).normalized()


def ring(c, axis, ru, rv, n=10, power=2.0, phase=0.0):
    """Superellipse cross-section around axis (power 2 = ellipse, higher = boxier)."""
    u, v = frame(axis)
    e = 2.0 / power
    pts = []
    for k in range(n):
        t = 2 * math.pi * k / n + phase
        cu, sv = math.cos(t), math.sin(t)
        pts.append(c + u * (ru * math.copysign(abs(cu) ** e, cu)) + v * (rv * math.copysign(abs(sv) ** e, sv)))
    return pts


def head_at(z):
    if z <= HEAD[0][0]:
        return HEAD[0][1:]
    for a, b in zip(HEAD, HEAD[1:]):
        if z <= b[0]:
            t = (z - a[0]) / (b[0] - a[0])
            return tuple(a[i] + (b[i] - a[i]) * t for i in (1, 2, 3))
    return HEAD[-1][1:]


def head_surface(t, z):
    """Point and outward normal on the head at ring angle t (front = -pi/2)."""
    rx, ry, cy = head_at(z)
    p = V(rx * math.cos(t), cy + ry * math.sin(t), z)
    return p, V(math.cos(t) / rx, math.sin(t) / ry, 0).normalized()


def face_point(x, z, off=0.0):
    rx = head_at(z)[0]
    p, n = head_surface(-math.acos(max(-1.0, min(1.0, x / rx))), z)
    return p + n * off, n


class Body:
    """bmesh with, per vertex, the bone chain it is skinned to."""

    def __init__(self):
        self.bm = bmesh.new()
        self.tags = []
        self.mats = []

    def mi(self, name):
        m = material(name)
        if m not in self.mats:
            self.mats.append(m)
        return self.mats.index(m)

    def v(self, p, chain):
        self.tags.append(chain)
        return self.bm.verts.new(p)

    def face(self, verts, mat, outward):
        f = self.bm.faces.new(verts)
        f.material_index = mat
        f.normal_update()
        if f.normal.dot(outward) < 0:
            f.normal_flip()
        return f

    def poly(self, pts, mat, chain, outward):
        return self.face([self.v(p, chain) for p in pts], mat, outward)

    def loft(self, rings, mat, chain, cap0=False, cap1=False, outward=None):
        vs = [[self.v(p, chain) for p in r] for r in rings]
        cs = [sum(r, Vector()) / len(r) for r in rings]
        n = len(vs[0])
        for i in range(len(vs) - 1):
            mid = (cs[i] + cs[i + 1]) / 2
            for j in range(n):
                q = (vs[i][j], vs[i][(j + 1) % n], vs[i + 1][(j + 1) % n], vs[i + 1][j])
                if outward is not None:
                    self.face(q, mat, outward)
                else:
                    self.face(q, mat, sum((x.co for x in q), Vector()) / 4 - mid)
        if cap0:
            self.face(vs[0], mat, cs[0] - cs[1])
        if cap1:
            self.face(vs[-1], mat, cs[-1] - cs[-2])

    def pyramid(self, base_c, d, width, length, mat, chain, sink=0.01):
        u, v = frame(d)
        b = base_c - d * sink
        base = [self.v(b + (u * x + v * y) * width / 2, chain) for x, y in ((1, 1), (-1, 1), (-1, -1), (1, -1))]
        tip = self.v(base_c + d * length, chain)
        for i in range(4):
            a, c = base[i], base[(i + 1) % 4]
            self.face((a, c, tip), mat, (a.co + c.co) / 2 - b)

    def ellipsoid(self, c, r, mat, chain):
        res = bmesh.ops.create_icosphere(self.bm, subdivisions=1, radius=1.0,
                                         matrix=Matrix.Translation(c) @ Matrix.Diagonal((r[0], r[1], r[2], 1.0)))
        for f in {f for v in res["verts"] for f in v.link_faces}:
            f.material_index = mat
        self.tags.extend([chain] * (len(self.bm.verts) - len(self.tags)))


# ----------------------------------------------------------------------------
# Modelling
# ----------------------------------------------------------------------------
def bone_vec(name, end):
    return V(BONES[name][0 if end == "head" else 1])


def build_torso(B):
    shirt = B.mi("shirt")
    rows = [(0.685, 0.168, 0.108, 0.0), (0.80, 0.158, 0.10, 0.0), (0.93, 0.162, 0.104, 0.0),
            (1.04, 0.172, 0.105, 0.0), (1.10, 0.172, 0.10, 0.005), (1.135, 0.152, 0.088, 0.008),
            (1.16, 0.105, 0.07, 0.008), (1.172, 0.072, 0.058, 0.008)]
    up = V(0, 0, 1)
    rings = [ring(V(0, cy, z), up, rx, ry, 16, phase=-math.pi / 2) for z, rx, ry, cy in rows]
    chain = ("hips", "spine", "chest")
    B.loft(rings, shirt, chain, cap1=True)
    # hem turned inwards so the shirt never looks hollow from below
    B.loft([rings[0], ring(V(0, 0, 0.70), up, 0.148, 0.092, 16, phase=-math.pi / 2)], shirt, chain,
           outward=V(0, 0, -1))
    # crew-neck collar band
    B.loft([ring(V(0, 0.008, 1.158), up, 0.08, 0.064, 16, phase=-math.pi / 2),
            ring(V(0, 0.008, 1.172), up, 0.062, 0.052, 16, phase=-math.pi / 2)], shirt, chain)

    # shorts: pelvis and two wide legs
    sh = B.mi("shorts")
    B.loft([ring(V(0, 0, z), up, rx, ry, 16, phase=-math.pi / 2)
            for z, rx, ry in ((0.785, 0.146, 0.094), (0.72, 0.158, 0.10), (0.66, 0.15, 0.095), (0.63, 0.12, 0.08))],
           sh, ("hips",), cap0=True, cap1=True)
    for s, k in SIDES:
        h, kn = bone_vec("thigh." + s, "head"), bone_vec("thigh." + s, "tail")
        a = (kn - h).normalized()
        legs = [ring(h + a * t, a, ru, rv, 12) for t, ru, rv in ((-0.02, 0.085, 0.092), (0.15, 0.087, 0.094),
                                                                  (0.29, 0.083, 0.09))]
        B.loft(legs, sh, ("hips", "thigh." + s))
        B.loft([legs[-1], ring(h + a * 0.285, a, 0.05, 0.05, 12)], sh, ("hips", "thigh." + s), outward=a)


def build_arms(B):
    shirt, skin = B.mi("shirt"), B.mi("skin")
    for s, k in SIDES:
        S, E = bone_vec("upper_arm." + s, "head"), bone_vec("upper_arm." + s, "tail")
        W, H = bone_vec("hand." + s, "head"), bone_vec("hand." + s, "tail")
        a = (E - S).normalized()
        f = (W - E).normalized()
        # short sleeve
        sleeve = [ring(S + a * t + V(0, 0, -0.012), a, r, r * 0.97, 10)
                  for t, r in ((-0.03, 0.045), (0.04, 0.058), (0.125, 0.062))]
        B.loft(sleeve, shirt, ("chest", "upper_arm." + s))
        B.loft([sleeve[-1], ring(S + a * 0.12 + V(0, 0, -0.012), a, 0.043, 0.043, 10)], shirt, ("chest", "upper_arm." + s), outward=a)
        # bare arm
        elbow_axis = (a + f).normalized()
        arm = [ring(S + a * 0.08, a, 0.045, 0.045, 8), ring(S + a * 0.17, a, 0.044, 0.043, 8),
               ring(E, elbow_axis, 0.039, 0.038, 8), ring(E.lerp(W, 0.45), f, 0.04, 0.037, 8),
               ring(W, f, 0.031, 0.028, 8)]
        B.loft(arm, skin, ("upper_arm." + s, "forearm." + s, "hand." + s), cap0=True, cap1=True)
        # mitten hand, palm facing the leg, and a thumb in front
        h = (H - W).normalized()
        hand = [ring(W + h * t, h, ru, rv, 8) for t, ru, rv in ((0.0, 0.016, 0.028), (0.035, 0.019, 0.034),
                                                               (0.07, 0.017, 0.032), (0.095, 0.01, 0.022))]
        B.loft(hand, skin, ("hand." + s,), cap0=True, cap1=True)
        ta = V(-k * 0.15, -0.35, -1).normalized()
        t0 = W + h * 0.025 + V(-k * 0.004, -0.026, 0)
        B.loft([ring(t0, ta, 0.011, 0.011, 6), ring(t0 + ta * 0.04, ta, 0.009, 0.009, 6)], skin, ("hand." + s,),
               cap0=True, cap1=True)


def build_legs(B):
    skin, white, shoe = B.mi("skin"), B.mi("white"), B.mi("shoe")
    up = V(0, 0, 1)
    for s, k in SIDES:
        hip, knee = bone_vec("thigh." + s, "head"), bone_vec("thigh." + s, "tail")
        ankle = bone_vec("shin." + s, "tail")

        def on_leg(z):
            if z >= knee.z:
                return hip.lerp(knee, (hip.z - z) / (hip.z - knee.z))
            return knee.lerp(ankle, (knee.z - z) / (knee.z - ankle.z))

        chain = ("thigh." + s, "shin." + s, "foot." + s)
        rows = ((0.64, 0.052), (0.50, 0.05), (0.43, 0.045), (0.40, 0.043), (0.32, 0.047), (0.22, 0.04),
                (0.14, 0.032), (0.10, 0.031))
        B.loft([ring(on_leg(z) + V(0, 0.006 if 0.2 < z < 0.38 else 0, 0), up, r, r, 8) for z, r in rows], skin,
               chain, cap0=True, cap1=True)
        # sock
        B.loft([ring(on_leg(z), up, r, r, 8) for z, r in ((0.075, 0.035), (0.135, 0.036))], white,
               ("shin." + s, "foot." + s), cap1=True)

        # sneaker: upper, sole, side stripes, laces
        fwd = V(0, -1, 0)
        A = V(ankle.x, ankle.y, 0)
        upper = [(0.07, 0.042, 0.03, 0.095), (0.045, 0.05, 0.025, 0.105), (0.0, 0.052, 0.025, 0.1),
                 (-0.05, 0.053, 0.025, 0.085), (-0.10, 0.052, 0.025, 0.066), (-0.14, 0.046, 0.025, 0.052),
                 (-0.165, 0.032, 0.03, 0.042)]
        B.loft([ring(A + V(0, dy, (zb + zt) / 2), fwd, hw, (zt - zb) / 2, 12, power=3.0)
                for dy, hw, zb, zt in upper], shoe, ("foot." + s,), cap0=True, cap1=True)
        sole = [(0.075, 0.045, 0.0, 0.032)] + [(dy, hw + 0.005, 0.0, 0.032) for dy, hw, _, _ in upper[1:-1]] + \
               [(-0.172, 0.036, 0.0, 0.03)]
        B.loft([ring(A + V(0, dy, (zb + zt) / 2), fwd, hw, (zt - zb) / 2, 12, power=4.0) for dy, hw, zb, zt in sole],
               white, ("foot." + s,), cap0=True, cap1=True)

        def width(dy):
            for a, b in zip(upper, upper[1:]):
                if a[0] >= dy >= b[0]:
                    t = (a[0] - dy) / (a[0] - b[0])
                    return a[1] + (b[1] - a[1]) * t, a[3] + (b[3] - a[3]) * t
            return upper[-1][1], upper[-1][3]

        for side in (1, -1):
            for y0 in (-0.005, -0.04):
                pts = []
                for dy, z in ((y0, 0.036), (y0 - 0.018, 0.036), (y0 - 0.048, 0.078), (y0 - 0.03, 0.078)):
                    w = width(dy)[0]
                    # superellipse side bulge: slightly inside the half width at these heights
                    pts.append(A + V(side * (w + 0.0015), dy, z))
                B.poly(pts, white, ("foot." + s,), V(side, 0, 0))
        for dy in (-0.03, -0.055, -0.08):
            ztop = width(dy)[1] + 0.003
            B.poly([A + V(x, dy + e, ztop) for x, e in ((-0.026, 0.004), (0.026, 0.004), (0.026, -0.004),
                                                         (-0.026, -0.004))], white, ("foot." + s,), V(0, 0, 1))


def build_head(B):
    skin, hair, eye, white, brow, mouth = (B.mi(n) for n in ("skin", "hair", "eye", "white", "brow", "mouth"))
    chain = ("head",)
    up = V(0, 0, 1)
    # neck
    B.loft([ring(V(0, 0.004, z), up, 0.052, 0.048, 10) for z in (1.10, 1.16, 1.23)], skin,
           ("chest", "neck", "head"), cap0=True, cap1=True)
    first = len(B.bm.verts)
    # skull and face
    B.loft([ring(V(0, cy, z), up, rx, ry, 14, phase=-math.pi / 2) for z, rx, ry, cy in HEAD], skin, chain,
           cap0=True, cap1=True)
    for k in (1, -1):
        B.ellipsoid(V(k * 0.094, 0.014, 1.312), (0.014, 0.022, 0.03), skin, chain)

    def disc(x, z, w, h, off, mat, n=10, dz=0.0):
        c, nrm = face_point(x, z, off)
        tx = up.cross(nrm).normalized()
        ty = nrm.cross(tx).normalized()
        pts = [c + tx * (w / 2 * math.cos(2 * math.pi * i / n)) + ty * (h / 2 * math.sin(2 * math.pi * i / n) + dz)
               for i in range(n)]
        B.poly(pts, mat, chain, nrm)

    for k in (1, -1):
        x = k * 0.036
        disc(x, 1.322, 0.03, 0.018, 0.0015, white)
        disc(x - k * 0.002, 1.322, 0.018, 0.0195, 0.003, eye)
        disc(x - k * 0.002 + 0.004, 1.3265, 0.005, 0.005, 0.0042, white, n=6)
        disc(x, 1.3315, 0.034, 0.004, 0.0035, eye, n=6)                       # upper lid line
        # eyebrow: inner end a little lower (a determined look)
        pts = []
        for xi, zi in ((0.018, 1.350), (0.056, 1.356), (0.056, 1.3645), (0.018, 1.359)):
            p, n = face_point(k * xi, zi, 0.003)
            pts.append(p)
        B.poly(pts, brow, chain, V(0, -1, 0))
    disc(0.0, 1.252, 0.027, 0.0045, 0.0015, mouth, n=8)
    # nose
    l, _ = face_point(0.011, 1.29)
    r, _ = face_point(-0.011, 1.29)
    top, n = face_point(0.0, 1.318)
    tip = face_point(0.0, 1.291, 0.016)[0]
    for tri, out in (((l, top, tip), V(1, -0.5, 0)), ((r, top, tip), V(-1, -0.5, 0)), ((l, r, tip), V(0, -0.3, -1))):
        B.poly(tri, skin, chain, out)

    # hair cap: the skull pushed outwards, down to an uneven hairline
    def hair_point(t, s):
        f = max(0.0, -math.sin(t))
        b = max(0.0, math.sin(t))
        zl = 1.272 + 0.1 * f ** 1.3 - 0.022 * b
        z = zl + (1.468 - zl) * (1 - (1 - s) ** 1.5)
        p, _ = head_surface(t, z)
        d = (p - HEAD_CENTRE).normalized()
        return p + d * (0.015 + 0.008 * s), d

    n = 14
    rows = [[hair_point(2 * math.pi * j / n - math.pi / 2, i / 6)[0] for j in range(n)] for i in range(7)]
    B.loft(rows, hair, chain, cap1=True)
    # tufts: short, mostly lying along the head, pointing down over the ears
    # and nape, falling over the forehead at the front, a few up on the crown
    rng = random.Random(15)
    back = V(0, 1, 0)
    for i in range(5):
        for j in range(14):
            s = min(0.95, 0.03 + i / 5 + rng.uniform(-0.03, 0.08))
            t = 2 * math.pi * (j + rng.uniform(-0.3, 0.3) + (0.5 if i % 2 else 0)) / 14 - math.pi / 2
            p, nrm = hair_point(t, s)
            front = -math.sin(t)
            down = V(0, 0, -1) - nrm * nrm.z
            down = down.normalized() if down.length > 0.2 else back
            if front > 0.5 and s < 0.45:
                d = (V(0, -0.25, -1) + nrm * 0.3).normalized()
                length = rng.uniform(0.035, 0.05)
                if (p + d * length).z < 1.36:
                    length = max(0.012, (p.z - 1.36) / -d.z)
            elif s > 0.6:
                d = (nrm * 0.55 + back * 0.8 + V(rng.uniform(-0.3, 0.3), 0, 0)).normalized()
                length = rng.uniform(0.022, 0.036)
            else:
                d = (down + nrm * 0.3 + back * 0.15).normalized()
                length = rng.uniform(0.028, 0.042)
            B.pyramid(p, d, rng.uniform(0.04, 0.055), length, hair, chain, sink=0.012)
    # sit the head a little lower: a short neck, as on the sheet
    B.bm.verts.ensure_lookup_table()
    bmesh.ops.translate(B.bm, verts=B.bm.verts[first:], vec=(0, 0, -0.03))


# ----------------------------------------------------------------------------
# Rig, skin weights, animations
# ----------------------------------------------------------------------------
def build_armature(scn):
    arm_data = bpy.data.armatures.new("kid_rig")
    arm = bpy.data.objects.new("kid_rig", arm_data)
    scn.collection.objects.link(arm)
    prev = bpy.context.window.scene
    bpy.context.window.scene = scn
    vl = scn.view_layers[0]
    vl.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    for name, (h, t, parent) in BONES.items():
        eb = arm_data.edit_bones.new(name)
        eb.head, eb.tail = h, t
        eb.align_roll(V(0, -1, 0) if abs(V(t).z - V(h).z) > abs(V(t).y - V(h).y) else V(0, 0, 1))
        if parent:
            eb.parent = arm_data.edit_bones[parent]
    bpy.ops.object.mode_set(mode="OBJECT")
    bpy.context.window.scene = prev
    return arm


def chain_weights(p, chain, blend=0.035):
    """Skin weights along a bone chain: each joint blends over +-blend metres."""
    if len(chain) == 1:
        return {chain[0]: 1.0}
    s = [1.0]
    for name in chain[1:]:
        h, t = bone_vec(name, "head"), bone_vec(name, "tail")
        along = (p - h).dot((t - h).normalized())
        s.append(smoothstep(-blend, blend, along))
    s.append(0.0)
    w = {name: max(0.0, s[i] - s[i + 1]) for i, name in enumerate(chain)}
    total = sum(w.values()) or 1.0
    return {k: v / total for k, v in w.items() if v > 1e-4}


def skin(B, name, col, arm):
    me = bpy.data.meshes.new(name)
    B.bm.to_mesh(me)
    for m in B.mats:
        me.materials.append(m)
    ob = bpy.data.objects.new(name, me)
    col.objects.link(ob)
    groups = {b: ob.vertex_groups.new(name=b) for b in BONES}
    for v, chain in zip(me.vertices, B.tags):
        for bone, w in chain_weights(v.co, chain).items():
            groups[bone].add([v.index], w, "REPLACE")
    ob.parent = arm
    mod = ob.modifiers.new("Armature", "ARMATURE")
    mod.object = arm
    B.bm.free()
    return ob


def blend(a, b, w):
    out = {}
    for k in set(a) | set(b):
        va, vb = a.get(k, (0, 0, 0)), b.get(k, (0, 0, 0))
        out[k] = tuple(x + (y - x) * w for x, y in zip(va, vb))
    return out


def add(p, bone, x=0.0, y=0.0, z=0.0):
    o = p.get(bone, (0.0, 0.0, 0.0))
    p[bone] = (o[0] + x, o[1] + y, o[2] + z)


# Poses: bone -> (X, Y, Z) rotation in radians about the armature axes
# (X: positive tips the limb backwards / the torso forwards, knee bend is
# positive, elbow bend negative; Y and Z mirror between sides), plus "loc"
# for the hips offset in metres.
def stand():
    p = {}
    for s, k in SIDES:
        add(p, "upper_arm." + s, y=k * 0.05)
        add(p, "forearm." + s, x=-0.15)
    return p


def idle(ph):
    p = stand()
    b = math.sin(2 * math.pi * ph)
    add(p, "chest", x=0.02 * b)
    add(p, "neck", x=-0.01 * b)
    add(p, "head", z=0.06 * math.sin(2 * math.pi * ph + 1.0), x=0.01 * b)
    add(p, "loc", z=-0.004 * (1 - math.cos(2 * math.pi * ph)))
    for s, k in SIDES:
        add(p, "upper_arm." + s, y=k * 0.02 * b)
        add(p, "thigh." + s, x=-0.01)
        add(p, "shin." + s, x=0.02)
        add(p, "foot." + s, x=-0.01)
    return p


def cycle(ph, run):
    s, c = math.sin(2 * math.pi * ph), math.cos(2 * math.pi * ph)
    p = stand()
    if run:
        add(p, "loc", z=0.035 * math.cos(4 * math.pi * ph) - 0.035)
        add(p, "hips", z=-0.12 * s)
        add(p, "spine", x=0.12)
        add(p, "chest", x=0.06, z=0.16 * s)
        add(p, "head", x=-0.14, z=-0.04 * s)
    else:
        add(p, "loc", z=0.014 * math.cos(4 * math.pi * ph) - 0.008)
        add(p, "hips", z=-0.08 * s)
        add(p, "spine", x=0.03)
        add(p, "chest", z=0.1 * s)
        add(p, "head", x=-0.03, z=-0.05 * s)
    for side, k in SIDES:
        ls, lc = k * s, k * c                 # left leg forward when s > 0
        swing = max(0.0, lc)                  # this foot is in the air moving forward
        if run:
            thigh = -0.8 * ls - 0.12
            knee = 0.3 + 1.45 * swing ** 1.2
            foot = -(thigh + knee) * 0.7 + 0.15
            add(p, "upper_arm." + side, x=0.7 * ls, y=-k * 0.08)
            add(p, "forearm." + side, x=-1.25 - 0.2 * max(0.0, -ls))
        else:
            thigh = -0.5 * ls
            knee = 0.1 + 0.8 * swing ** 1.5
            foot = -(thigh + knee) * 0.9
            add(p, "upper_arm." + side, x=0.4 * ls)
            add(p, "forearm." + side, x=-0.15 - 0.3 * max(0.0, -ls))
        add(p, "thigh." + side, x=thigh)
        add(p, "shin." + side, x=knee)
        add(p, "foot." + side, x=foot)
    return p


def air(wave=0.0):
    p = {}
    add(p, "spine", x=0.08)
    add(p, "head", x=-0.06)
    add(p, "thigh.L", x=-1.0 + 0.08 * wave)
    add(p, "shin.L", x=1.55)
    add(p, "foot.L", x=-0.2)
    add(p, "thigh.R", x=-0.3 - 0.08 * wave)
    add(p, "shin.R", x=0.85)
    add(p, "foot.R", x=0.1)
    for s, k in SIDES:
        add(p, "upper_arm." + s, x=-0.7 + 0.12 * wave * k, y=-k * 0.85)
        add(p, "forearm." + s, x=-0.7)
    return p


def takeoff():
    p = {}
    add(p, "spine", x=-0.06)
    add(p, "head", x=-0.1)
    for s, k in SIDES:
        add(p, "thigh." + s, x=0.08)
        add(p, "shin." + s, x=0.05)
        add(p, "foot." + s, x=0.55)
        add(p, "upper_arm." + s, x=-2.3, y=-k * 0.1)
        add(p, "forearm." + s, x=-0.3)
    return p


def crouch():
    p = {"loc": (0.0, 0.0, -0.14)}
    add(p, "spine", x=0.35)
    add(p, "head", x=-0.25)
    for s, k in SIDES:
        add(p, "thigh." + s, x=-0.8, y=k * 0.05)
        add(p, "shin." + s, x=1.4)
        add(p, "foot." + s, x=-0.6)
        add(p, "upper_arm." + s, x=-0.6, y=-k * 0.15)
        add(p, "forearm." + s, x=-0.6)
    return p


def jump(t):
    return blend(takeoff(), air(), smoothstep(0.0, 1.0, t))


def land(t):
    a = t / 0.25 if t < 0.25 else 1.0 - smoothstep(0.25, 1.0, t)
    return blend(stand(), crouch(), a)


# name: (frames, loops, pose function of phase/progress in [0, 1])
ANIMATIONS = {
    "idle": (60, True, idle),
    "walk": (24, True, lambda ph: cycle(ph, False)),
    "run": (16, True, lambda ph: cycle(ph, True)),
    "jump": (10, False, jump),
    "fall": (30, True, lambda ph: air(math.sin(2 * math.pi * ph))),
    "land": (10, False, land),
}


def animate(arm):
    rest = {b.name: b.matrix_local.to_3x3() for b in arm.data.bones}
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
    ad = arm.animation_data_create()
    for name, (frames, loops, fn) in ANIMATIONS.items():
        old = bpy.data.actions.get(name)
        if old:
            bpy.data.actions.remove(old)
        action = bpy.data.actions.new(name)
        action.use_fake_user = True
        ad.action = action
        for f in range(frames + 1):
            pose = fn(f / frames)
            for pb in arm.pose.bones:
                e = pose.get(pb.name, (0.0, 0.0, 0.0))
                m = rest[pb.name]
                pb.rotation_quaternion = (m.inverted() @ Euler(e, "XYZ").to_matrix() @ m).to_quaternion()
                pb.keyframe_insert("rotation_quaternion", frame=f + 1)
            hips = arm.pose.bones["hips"]
            hips.location = rest["hips"].inverted() @ V(pose.get("loc", (0.0, 0.0, 0.0)))
            hips.keyframe_insert("location", frame=f + 1)
        track = ad.nla_tracks.new()
        track.name = name
        track.strips.new(name, 1, action)
        ad.action = None
    for pb in arm.pose.bones:
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.location = (0, 0, 0)


def run(root):
    scn = bpy.data.scenes.get("Character") or bpy.data.scenes.new("Character")
    scn.render.fps = FPS
    for ob in list(scn.collection.all_objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    for a in [a for a in bpy.data.armatures if a.users == 0]:
        bpy.data.armatures.remove(a)
    for m in [m for m in bpy.data.meshes if m.users == 0]:
        bpy.data.meshes.remove(m)

    arm = build_armature(scn)
    B = Body()
    build_torso(B)
    build_arms(B)
    build_legs(B)
    build_head(B)
    body = skin(B, "kid", scn.collection, arm)
    animate(arm)

    out = os.path.join(root, "game", "characters", "kid")
    os.makedirs(out, exist_ok=True)
    prev = bpy.context.window.scene
    bpy.context.window.scene = scn
    vl = scn.view_layers[0]
    for ob in scn.objects:
        ob.select_set(ob in (arm, body), view_layer=vl)
    bpy.ops.export_scene.gltf(filepath=os.path.join(out, "kid.glb"), export_format="GLB", use_selection=True,
                              use_active_scene=True, export_yup=True, export_skins=True, export_animations=True,
                              export_animation_mode="ACTIONS", export_morph=False)
    bpy.context.window.scene = prev
    return {"verts": len(body.data.vertices), "faces": len(body.data.polygons),
            "actions": list(ANIMATIONS)}


def preview(root):
    """Workbench renders for checking against the sheet: renders/kid/*.png."""
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
    out = os.path.join(root, "renders", "kid")
    os.makedirs(out, exist_ok=True)
    prev = bpy.context.window.scene
    bpy.context.window.scene = scn

    def shot(name, deg, z, scale, w, h, action=None, fr=1):
        arm.animation_data.action = bpy.data.actions[action] if action else None
        scn.frame_set(fr)
        if not action:
            for pb in arm.pose.bones:
                pb.rotation_quaternion = (1, 0, 0, 0)
                pb.location = (0, 0, 0)
        a = math.radians(deg)
        cam.location = V(0, 0, z) + V(math.sin(a), -math.cos(a), 0) * 5
        cam.rotation_euler = (math.pi / 2, 0, a)
        cam.data.ortho_scale = scale
        scn.render.resolution_x, scn.render.resolution_y = w, h
        scn.render.filepath = os.path.join(out, name + ".png")
        bpy.ops.render.render(write_still=True)

    for name, deg in (("front", 0), ("q34", 35), ("side", 90), ("back", 180)):
        shot(name, deg, 0.76, 1.75, 500, 760)
    shot("face", 0, 1.33, 0.42, 600, 600)
    for act, fr in (("walk", 7), ("run", 5), ("jump", 11), ("land", 4)):
        shot("pose_" + act, 70, 0.8, 1.9, 500, 760, act, fr)
    arm.animation_data.action = None
    scn.frame_set(1)
    bpy.context.window.scene = prev
    return {"renders": sorted(os.listdir(out))}
