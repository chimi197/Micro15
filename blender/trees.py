"""Trees, bushes and hedges modelled leaf by leaf (docs/art_direction.md).

A plant is a skeleton of tapered branches (trunk, limbs forking into
twigs) with clusters of leaves at the twig ends. Every leaf is its own
small mesh: an almond outline folded along the midrib, its tip drooping.
Leaves hang outwards and a little down from each cluster's middle; the
ones deep inside a cluster use the darker "<leaf>_core" material so the
crown reads dark inside and between the clusters.

Leaf normals are bent: each leaf's own normal is blended with the
direction out of the crown, so the crown lights as one soft volume
(lighter on top, darker underneath) while neighbouring leaves still catch
the light a little differently. UV.x is a random shade per leaf and UV.y
runs from the leaf's base (0) to its tip (1); the foliage shader uses both.

Every plant can be made in two versions: the detailed one, and a "far"
one for distance with fewer, bigger leaves on the same skeleton.

    P = Plant(material_fn)          # material_fn(name) -> bpy Material
    broadleaf(P, seed=1, leaf="leaf_a", bark="bark")
    ob = P.finish("tree_a", collection)
"""
import math
import random

import bmesh
import bpy
from mathutils import Matrix, Vector

UP = Vector((0, 0, 1))


def _unit(rng):
    while True:
        v = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1)))
        if 0.05 < v.length <= 1.0:
            return v.normalized()


def _perp(d):
    p = d.cross(UP if abs(d.z) < 0.95 else Vector((1, 0, 0)))
    return p.normalized()


def add_leaf(bm, uv, base, axis, normal, length, width, m, shade=0.5, coarse=False):
    """Adds one leaf to bm: from base along axis, facing normal, an almond
    outline (8 points, or 6 when coarse) folded up along the midrib, the
    tip drooping. UV is (shade, 0 at the base .. 1 at the tip). Returns
    [(face, [normal per loop])] with the leaf's own, folded normals."""
    s = axis.cross(normal).normalized()
    n = normal
    fold = width * 0.14
    if coarse:
        outline = [(0.0, 0.0), (0.3, 0.46), (0.7, 0.4), (1.0, 0.0), (0.7, -0.4), (0.3, -0.46)]
    else:
        outline = [(0.0, 0.0), (0.18, 0.36), (0.48, 0.5), (0.78, 0.36), (1.0, 0.0),
                   (0.78, -0.36), (0.48, -0.5), (0.18, -0.36)]
    verts, vnorm, vv = [], [], []
    for t, w in outline:
        lift = fold * abs(w) * 2.0 - length * 0.12 * t * t
        verts.append(bm.verts.new(base + axis * (t * length) + s * (w * width) + n * lift))
        vnorm.append((n - s * (0.5 * math.copysign(1.0, w))).normalized() if w else n.copy())
        vv.append(t)
    tip = len(outline) // 2
    out = []
    for k in list(range(1, tip)) + list(range(tip, len(outline) - 1)):
        f = bm.faces.new((verts[0], verts[k], verts[k + 1]))
        f.material_index = m
        f.smooth = True
        f.normal_update()
        if f.normal.dot(n) < 0:
            f.normal_flip()
        normals = []
        for loop in f.loops:
            i = verts.index(loop.vert)
            if uv is not None:
                loop[uv].uv = (shade, vv[i])
            normals.append(vnorm[i])
        out.append((f, normals))
    return out


class Plant:
    """One plant's mesh: branches, leaves and their bent normals."""

    def __init__(self, material_fn, far=False):
        self.material_fn = material_fn
        self.far = far                  # fewer, bigger leaves (distance version)
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.verify()
        self.mats = []
        self.normals = {}               # face index -> per-loop normals (leaves)
        self.leaf_count = 0

    def mi(self, name):
        m = self.material_fn(name)
        if m not in self.mats:
            self.mats.append(m)
        return self.mats.index(m)

    # -- branches ----------------------------------------------------------
    def tube(self, pts, radii, m, seg=8):
        """Smooth round tube along pts with a radius per point, capped at
        the thin end."""
        rings = []
        n_prev = None
        for i, p in enumerate(pts):
            d = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
            if n_prev is None:
                n_prev = _perp(d)
            n = (n_prev - d * n_prev.dot(d)).normalized()
            b = d.cross(n)
            rings.append([self.bm.verts.new(p + (n * math.cos(a) + b * math.sin(a)) * radii[i])
                          for a in (math.tau * k / seg for k in range(seg))])
            n_prev = n
        faces = []
        for a, b in zip(rings, rings[1:]):
            for k in range(seg):
                faces.append(self.bm.faces.new((a[k], a[(k + 1) % seg], b[(k + 1) % seg], b[k])))
        faces.append(self.bm.faces.new(rings[-1]))
        for f in faces:
            f.material_index = m
            f.smooth = True
        return faces

    def limb(self, p0, p1, r0, r1, m, rng, bend=0.08, seg=7):
        """A slightly curved branch from p0 to p1."""
        d = p1 - p0
        side = _perp(d.normalized()) * rng.uniform(-1, 1) + UP * 0.5
        pts = [p0 + d * t + side * (math.sin(math.pi * t) * bend * d.length) for t in (0.0, 0.35, 0.7, 1.0)]
        self.tube(pts, [r0 + (r1 - r0) * t for t in (0.0, 0.35, 0.7, 1.0)], m, seg)

    # -- leaves ------------------------------------------------------------
    def leaf(self, base, axis, normal, length, width, m, shade, out, bend=0.6):
        """One leaf (see add_leaf); its normals lean towards out, the
        direction out of the crown here, by bend."""
        for f, normals in add_leaf(self.bm, self.uv, base, axis, normal, length, width, m, shade, self.far):
            self.normals[f] = [(out * bend + n * (1.0 - bend)).normalized() for n in normals]
        self.leaf_count += 1

    def cluster(self, c, radii, rng, m_out, m_in, leaf_len, coverage=1.3, hang=0.3, crown=None,
                min_z=None, normal_up=0.5):
        """A ball of leaves around c (radii of the ellipsoid it fills),
        dense at the surface. hang pulls the leaves' tips down (negative:
        up, for poplars). crown = (centre, radii) of the whole crown, for
        the bent normals (default: this cluster). min_z keeps leaves above
        the ground (bushes)."""
        if self.far:
            leaf_len *= 2.1
            coverage *= 0.85
        width = leaf_len * 0.62
        rx, ry, rz = radii
        area = 4.0 * math.pi * ((rx * ry) ** 1.6 + (rx * rz) ** 1.6 + (ry * rz) ** 1.6) ** (1 / 1.6) / 3 ** (1 / 1.6)
        n = max(6, int(area * coverage / (leaf_len * width * 0.6)))
        cc, cr = crown or (c, radii)
        for _ in range(n):
            d = _unit(rng)
            r = 0.3 + 0.7 * rng.random() ** 0.35                      # mostly near the surface
            p = c + Vector((d.x * rx * r, d.y * ry * r, d.z * rz * r))
            if min_z is not None and p.z < min_z + leaf_len * 0.3:
                p.z = min_z + leaf_len * 0.3 + rng.uniform(0, leaf_len * 0.3)
            out_local = Vector((d.x / rx, d.y / ry, d.z / rz)).normalized()
            q = p - cc
            out_crown = Vector((q.x / cr[0], q.y / cr[1], q.z / cr[2]))
            out_crown = out_crown.normalized() if out_crown.length > 1e-4 else UP.copy()
            out = (out_crown * 0.7 + out_local * 0.3).normalized()
            axis = (out_local * 0.75 + _unit(rng) * 0.55 - UP * hang).normalized()
            nrm = out_local * 0.6 + UP * normal_up + _unit(rng) * 0.35
            nrm = nrm - axis * nrm.dot(axis)
            nrm = nrm.normalized() if nrm.length > 1e-3 else _perp(axis)
            L = leaf_len * rng.uniform(0.8, 1.2)
            inner = r < 0.62
            self.leaf(p - axis * L * 0.35, axis, nrm, L, width * rng.uniform(0.85, 1.15), m_in if inner else m_out,
                      rng.random(), out)

    # -- result ------------------------------------------------------------
    def finish(self, name, col):
        faces = list(self.bm.faces)
        custom = [self.normals.get(f) for f in faces]
        me = bpy.data.meshes.new(name)
        self.bm.to_mesh(me)
        self.bm.free()
        for m in self.mats:
            me.materials.append(m)
        loop_normals = [None] * len(me.loops)
        auto = me.corner_normals
        for poly, cn in zip(me.polygons, custom):
            for k, li in enumerate(poly.loop_indices):
                loop_normals[li] = tuple(cn[k]) if cn else tuple(auto[li].vector)
        me.normals_split_custom_set(loop_normals)
        ob = bpy.data.objects.new(name, me)
        col.objects.link(ob)
        return ob


# ----------------------------------------------------------------------------
# Skeletons
# ----------------------------------------------------------------------------
def _fork(P, m, p0, d, length, r0, rng, depth, tips, spread=(0.35, 0.65), up=0.25, children=2):
    """A limb from p0 along d that forks into thinner limbs (depth times).
    Collects (tip, direction, depth) for every limb end in tips."""
    r1 = r0 * 0.62
    p1 = p0 + d * length
    P.limb(p0, p1, r0, r1, m, rng)
    tips.append((p1, d, depth))
    if depth <= 0:
        return
    base_side = _perp(d)
    a0 = rng.uniform(0, math.tau)
    for k in range(children):
        axis = Matrix.Rotation(a0 + math.tau * k / children + rng.uniform(-0.5, 0.5), 3, d) @ base_side
        cd = (Matrix.Rotation(rng.uniform(*spread), 3, axis) @ d + UP * up).normalized()
        _fork(P, m, p1 - d * r1, cd, length * rng.uniform(0.6, 0.75), r1, rng, depth - 1, tips, spread, up,
              children)


def _trunk(P, m, height, r0, rng, lean=0.12, flare=True):
    lean_v = Vector((rng.uniform(-lean, lean), rng.uniform(-lean, lean), 0))
    top = Vector((0, 0, height)) + lean_v
    pts = [Vector((0, 0, 0)), lean_v * 0.15 + Vector((0, 0, height * 0.4)), lean_v * 0.5 + Vector((0, 0, height * 0.75)),
           top]
    P.tube(pts, [r0, r0 * 0.88, r0 * 0.78, r0 * 0.66], m, 10)
    if flare:
        P.tube([Vector((0, 0, -0.05)), Vector((0, 0, 0.18)), Vector((0, 0, 0.45))], [r0 * 1.45, r0 * 1.12, r0 * 0.98],
               m, 10)
    return top


def _crown_of(clusters):
    lo = Vector((min(c.x - r[0] for c, r in clusters), min(c.y - r[1] for c, r in clusters),
                 min(c.z - r[2] for c, r in clusters)))
    hi = Vector((max(c.x + r[0] for c, r in clusters), max(c.y + r[1] for c, r in clusters),
                 max(c.z + r[2] for c, r in clusters)))
    return (lo + hi) / 2, (hi - lo) / 2


# ----------------------------------------------------------------------------
# Plants
# ----------------------------------------------------------------------------
def broadleaf(P, seed, leaf, bark="bark", trunk_h=4.4, crown_r=3.2, limbs=5, leaf_len=0.4, coverage=1.25):
    """Street tree (lime, maple, ash): a tall clear trunk, limbs forking
    twice up into an oval crown, and a leaf cluster on every twig end and
    fork, so the crown is a heap of leafy lumps with gaps between them."""
    rng = random.Random(seed)
    m_bark = P.mi(bark)
    m_out, m_in = P.mi(leaf), P.mi(leaf + "_core")
    top = _trunk(P, m_bark, trunk_h, 0.16 + crown_r * 0.035, rng)
    tips = []
    a0 = rng.uniform(0, math.tau)
    r_limb = 0.08 + crown_r * 0.02
    for k in range(limbs):
        a = a0 + math.tau * k / limbs + rng.uniform(-0.35, 0.35)
        tilt = math.radians(rng.uniform(32, 55))
        d = Vector((math.cos(a) * math.sin(tilt), math.sin(a) * math.sin(tilt), math.cos(tilt)))
        z = rng.uniform(0.82, 1.0)
        _fork(P, m_bark, Vector((top.x * z, top.y * z, trunk_h * z)), d, crown_r * rng.uniform(0.45, 0.6), r_limb,
              rng, 2, tips)
    _fork(P, m_bark, top, (UP + _unit(rng) * 0.15).normalized(), crown_r * 0.6, r_limb, rng, 1, tips)
    clusters = []
    for p, d, depth in tips:
        if depth == 0:
            r = crown_r * rng.uniform(0.3, 0.38)
            clusters.append((p + d * r * 0.4, Vector((r, r, r * 0.8))))
        elif depth == 1 and rng.random() < 0.6:
            r = crown_r * rng.uniform(0.26, 0.32)
            clusters.append((p + d * r * 0.3, Vector((r, r, r * 0.8))))
    crown = _crown_of(clusters)
    for c, r in clusters:
        P.cluster(c, r, rng, m_out, m_in, leaf_len, coverage, crown=crown)
    return crown


def poplar(P, seed, leaf="poplar", bark="bark", height=13.0, leaf_len=0.32):
    """Lombardy poplar: a tall column of short, steep branches and leaf
    clusters hugging the trunk, the leaves pointing up."""
    rng = random.Random(seed)
    m_bark = P.mi(bark)
    m_out, m_in = P.mi(leaf), P.mi(leaf + "_core")
    _trunk(P, m_bark, height * 0.92, 0.26, rng, lean=0.06)
    clusters = []
    z = 2.4
    while z < height - 0.6:
        t = (z - 2.4) / (height - 2.4)
        width = 0.55 + 0.75 * math.sin(math.pi * min(1.0, t * 1.1 + 0.08)) ** 0.8
        a = rng.uniform(0, math.tau)
        d = Vector((math.cos(a) * 0.35, math.sin(a) * 0.35, 1.0)).normalized()
        base = Vector((0, 0, z))
        P.limb(base, base + d * width * 1.2, 0.07, 0.03, m_bark, rng, seg=5)
        c = base + d * width * 0.9
        clusters.append((c, Vector((width * 0.8, width * 0.8, width * 1.1))))
        z += rng.uniform(0.7, 1.0)
    crown = _crown_of(clusters)
    for c, r in clusters:
        P.cluster(c, r, rng, m_out, m_in, leaf_len, 1.25, hang=-0.35, crown=crown, normal_up=0.3)
    return crown


def birch(P, seed, leaf="birch_leaf", bark="birch_bark", mark="birch_mark", height=7.2, leaf_len=0.24):
    """Birch: a slim white trunk with dark marks, thin limbs arching out
    and small leaves hanging from them in loose clusters."""
    rng = random.Random(seed)
    m_bark, m_mark = P.mi(bark), P.mi(mark)
    m_out, m_in = P.mi(leaf), P.mi(leaf + "_core")
    top = _trunk(P, m_bark, height, 0.14, rng, lean=0.15, flare=False)
    for z in (0.5, 1.1, 1.7, 2.4, 3.0, 3.7, 4.5):                  # the dark bands
        P.tube([Vector((top.x * z / height, top.y * z / height, z)),
                Vector((top.x * z / height, top.y * z / height, z + rng.uniform(0.05, 0.12)))],
               [0.14 * (1 - 0.34 * z / height) + 0.006] * 2, m_mark, 10)
    tips = []
    a0 = rng.uniform(0, math.tau)
    for k in range(6):
        a = a0 + math.tau * k / 6 + rng.uniform(-0.3, 0.3)
        z = height * rng.uniform(0.42, 0.85)
        tilt = math.radians(rng.uniform(40, 62))
        d = Vector((math.cos(a) * math.sin(tilt), math.sin(a) * math.sin(tilt), math.cos(tilt)))
        _fork(P, m_bark, Vector((top.x * z / height, top.y * z / height, z)), d, rng.uniform(1.2, 1.7), 0.05, rng,
              1, tips, spread=(0.4, 0.8), up=-0.15)
    clusters = []
    for p, d, depth in tips:
        r = rng.uniform(0.6, 0.8)
        clusters.append((p + Vector((0, 0, -r * 0.35)), Vector((r, r, r * 1.2))))
    clusters.append((top + Vector((0, 0, 0.2)), Vector((0.8, 0.8, 1.0))))
    crown = _crown_of(clusters)
    for c, r in clusters:
        P.cluster(c, r, rng, m_out, m_in, leaf_len, 1.0, hang=0.75, crown=crown)
    return crown


def spruce(P, seed, needle="pine_leaf", bark="trunk", height=7.5, base_r=2.1):
    """Blue spruce: whorls of branches that droop and shorten towards the
    top, each covered in tufts of needles pointing out along it."""
    rng = random.Random(seed)
    m_bark = P.mi(bark)
    m_out, m_in = P.mi(needle), P.mi(needle + "_core")
    P.tube([Vector((0, 0, 0)), Vector((0, 0, height))], [0.16, 0.03], m_bark, 8)
    z = 0.9
    needle_len = 0.3 if not P.far else 0.55
    while z < height - 0.3:
        t = (z - 0.9) / (height - 0.9)
        length = base_r * (1 - t) ** 1.05 + 0.25
        nb = max(4, int(7 - t * 3))
        a0 = rng.uniform(0, math.tau)
        for k in range(nb):
            a = a0 + math.tau * k / nb + rng.uniform(-0.2, 0.2)
            out = Vector((math.cos(a), math.sin(a), 0))
            p0 = Vector((0, 0, z))
            p1 = p0 + out * length + Vector((0, 0, -0.25 * length))
            pm = p0 + out * length * 0.5 + Vector((0, 0, 0.05))
            P.tube([p0, pm, p1], [0.04, 0.025, 0.01], m_bark, 5)
            steps = max(3, int(length / (0.14 if not P.far else 0.32)))
            for i in range(steps):
                u = (i + 0.5) / steps
                q = (p0 * (1 - u) ** 2 + pm * 2 * u * (1 - u) + p1 * u * u)
                fwd = ((pm - p0) * 2 * (1 - u) + (p1 - pm) * 2 * u).normalized()
                for _ in range(5 if not P.far else 3):
                    side = _unit(rng)
                    axis = (fwd * 0.8 + side * 0.6 + Vector((0, 0, -0.15))).normalized()
                    nrm = (UP + side * 0.4)
                    nrm = (nrm - axis * nrm.dot(axis)).normalized()
                    o = (out * 0.7 + UP * (0.6 - t * 0.3)).normalized()
                    inner = u < 0.35 and rng.random() < 0.7
                    L = needle_len * rng.uniform(0.75, 1.15) * (0.75 + 0.25 * (1 - t))
                    P.leaf(q, axis, nrm, L, L * 0.22, m_in if inner else m_out, rng.random(), o, bend=0.5)
        z += rng.uniform(0.45, 0.6)
    # the leading shoot
    P.tube([Vector((0, 0, height - 0.2)), Vector((0, 0, height + 0.5))], [0.04, 0.004], P.mi(needle), 5)
    return Vector((0, 0, height / 2)), Vector((base_r, base_r, height / 2))


def bush(P, seed, leaf="bush", flowers=None, size=1.0, leaf_len=0.24):
    """A low shrub of three to five leaf clusters sitting on the ground,
    optionally with small flowers among the outer leaves."""
    rng = random.Random(seed)
    m_out, m_in = P.mi(leaf), P.mi(leaf + "_core")
    m_twig = P.mi("bark")
    clusters = []
    for _ in range(rng.randint(3, 5)):
        c = Vector((rng.uniform(-0.75, 0.75) * size, rng.uniform(-0.4, 0.4) * size, rng.uniform(0.38, 0.6) * size))
        r = rng.uniform(0.5, 0.72) * size
        clusters.append((c, Vector((r, r, r * 0.85))))
        P.limb(Vector((c.x * 0.3, c.y * 0.3, 0)), c, 0.035, 0.015, m_twig, rng, seg=5)
    crown = _crown_of(clusters)
    for c, r in clusters:
        P.cluster(c, r, rng, m_out, m_in, leaf_len, 1.35, hang=0.1, crown=crown, min_z=0.0)
    if flowers:
        fm = P.mi(flowers)
        for _ in range(16):
            c, r = rng.choice(clusters)
            d = _unit(rng)
            d.z = abs(d.z) * 0.8 + 0.2
            p = c + Vector((d.x * r.x, d.y * r.y, d.z * r.z)) * 0.95
            res = bmesh.ops.create_icosphere(P.bm, subdivisions=1, radius=0.07, matrix=Matrix.Translation(p))
            for f in {f for v in res["verts"] for f in v.link_faces}:
                f.material_index = fm
                f.smooth = True
    return crown


def hedge(P, seed, leaf="hedge_bush", length=1.9, depth=0.6, height=0.8, leaf_len=0.16):
    """2 m of clipped hedge: small leaves covering a box shape, pointing
    out of its faces, so the top and sides read as clipped but every leaf
    is its own; a dark box of inner leaves fills it."""
    rng = random.Random(seed)
    m_out, m_in = P.mi(leaf), P.mi(leaf + "_core")
    if P.far:
        leaf_len *= 2.0
    width = leaf_len * 0.62
    hx, hy = length / 2, depth / 2
    faces = [  # (centre, normal, u axis, u half, v axis, v half)
        (Vector((0, 0, height)), UP, Vector((1, 0, 0)), hx, Vector((0, 1, 0)), hy),
        (Vector((0, -hy, height / 2)), Vector((0, -1, 0)), Vector((1, 0, 0)), hx, UP, height / 2),
        (Vector((0, hy, height / 2)), Vector((0, 1, 0)), Vector((1, 0, 0)), hx, UP, height / 2),
        (Vector((-hx, 0, height / 2)), Vector((-1, 0, 0)), Vector((0, 1, 0)), hy, UP, height / 2),
        (Vector((hx, 0, height / 2)), Vector((1, 0, 0)), Vector((0, 1, 0)), hy, UP, height / 2),
    ]
    centre = Vector((0, 0, height * 0.5))
    radii = Vector((hx, hy, height * 0.5))
    for c, nrm, u, uh, v, vh in faces:
        n = int(4 * uh * vh * 1.7 / (leaf_len * width * 0.6))
        for _ in range(n):
            p = c + u * rng.uniform(-uh, uh) + v * rng.uniform(-vh, vh) + nrm * rng.uniform(-0.06, 0.03)
            p.z = max(p.z, 0.03)
            q = p - centre
            out = (Vector((q.x / radii.x, q.y / radii.y, q.z / radii.z)).normalized() * 0.5 + nrm * 0.5).normalized()
            axis = (nrm * 0.55 + _unit(rng) * 0.8).normalized()
            ln = nrm + UP * 0.3 + _unit(rng) * 0.3
            ln = ln - axis * ln.dot(axis)
            ln = ln.normalized() if ln.length > 1e-3 else _perp(axis)
            L = leaf_len * rng.uniform(0.8, 1.2)
            P.leaf(p - axis * L * 0.4, axis, ln, L, width, m_out, rng.random(), out)
    # inner leaves so the hedge is never see-through
    inner = Vector((hx - 0.12, hy - 0.1, height * 0.5 - 0.08))
    P.cluster(centre, inner, rng, m_in, m_in, leaf_len * 1.4, 1.0, crown=(centre, radii))
    return centre, radii
