"""Leaf-cluster foliage shared by the map props (build_corner_3d.py) and the
street kit (build_assets.py), following docs/art_direction.md: canopies,
bushes and hedges are balls of overlapping leaf cards, each showing a
painted bunch of leaves (game/style/leaf_*.png, alpha cut out), around a
small dark core. Bent normals (bend_normals) make every crown light as
one soft volume, lighter on top. Spruces are stacked, drooping,
star-shaped tiers with flat facets.

Every function adds faces to a bmesh with a given material index.
"""
import math

import bmesh
from mathutils import Matrix, Vector, noise

UP = Vector((0, 0, 1))


def _sphere_dirs(n, rng, up_bias):
    """n directions spread evenly over a sphere (golden spiral, randomly
    turned and jittered), pushed upwards by up_bias."""
    out = []
    turn = rng.uniform(0, math.tau)
    for i in range(n):
        z = 1.0 - 2.0 * (i + 0.5) / n
        z = max(-1.0, min(1.0, z + rng.uniform(-0.12, 0.12)))
        z = z + up_bias * (1.0 - z * z)
        a = turn + i * 2.399963 + rng.uniform(-0.3, 0.3)
        s = math.sqrt(max(0.0, 1.0 - z * z))
        out.append(Vector((math.cos(a) * s, math.sin(a) * s, z)).normalized())
    return out


def card(bm, uv, centre, normal, width, height, rng, m, roll=0.6):
    """One leaf card: a quad showing the leaf-cluster texture, facing
    normal, its texture's up kept roughly upwards (rolled up to +-roll
    radians) so the lighter leaves stay on top."""
    nrm = normal.normalized()
    side = UP.cross(nrm)
    if side.length < 1e-3:
        side = nrm.orthogonal()
    side = Matrix.Rotation(rng.uniform(-roll, roll), 3, nrm) @ side.normalized()
    up = nrm.cross(side)
    if rng.random() < 0.5:                  # mirror half the cards
        side = -side
    hw, hh = side * width / 2, up * height / 2
    corners = [centre - hw - hh, centre + hw - hh, centre + hw + hh, centre - hw + hh]
    uvs = [(0, 0), (1, 0), (1, 1), (0, 1)]
    vs = [bm.verts.new(c) for c in corners]
    f = bm.faces.new(vs)
    f.material_index = m
    f.smooth = True
    f.normal_update()
    if f.normal.dot(nrm) < 0:
        f.normal_flip()
    for loop in f.loops:
        loop[uv].uv = uvs[vs.index(loop.vert)]
    return f


def clump(bm, centre, radii, rng, m, cards=12, card_size=(0.95, 1.25), core_m=None, core=0.5,
          spread=(0.55, 0.85), up_bias=0.3, lump=0.15, min_z=None, roll=0.6):
    """A ball of leaves: leaf cards around centre (radii of the ellipsoid
    they cover), facing outwards and a little up, overlapping so the
    texture's leaves form a full, scalloped silhouette. card_size is a
    fraction of the mean radius, spread how far out from the middle the
    cards sit. core_m adds a small dark lumpy core (untextured material)
    so the clump is never see-through in the middle. min_z flattens the
    clump on the ground (bushes, hedges)."""
    uv = bm.loops.layers.uv.verify()
    rx, ry, rz = radii
    mean_r = (rx + ry + rz) / 3
    if core_m is not None and core > 0:
        res = bmesh.ops.create_icosphere(bm, subdivisions=2, radius=1.0)
        seed = rng.uniform(0, 100)
        for v in res["verts"]:
            d = v.co.normalized()
            k = core * (1.0 + noise.noise(d * 1.7 + Vector((seed, seed, seed))) * lump)
            v.co = centre + Vector((d.x * rx * k, d.y * ry * k, d.z * rz * k))
            if min_z is not None:
                v.co.z = max(v.co.z, min_z)
        for f in {f for v in res["verts"] for f in v.link_faces}:
            f.material_index = core_m
            f.smooth = True
    for d in _sphere_dirs(cards, rng, up_bias):
        k = rng.uniform(*spread)
        p = centre + Vector((d.x * rx * k, d.y * ry * k, d.z * rz * k))
        size = rng.uniform(*card_size) * mean_r
        if min_z is not None:
            p.z = max(p.z, min_z + size * 0.42)
        out = Vector((d.x / rx, d.y / ry, d.z / rz)).normalized()
        card(bm, uv, p, (out + UP * 0.35).normalized(), size, size * rng.uniform(0.85, 1.0), rng, m, roll)


def spruce_tier(bm, z0, radius, height, rng, m, points=9, droop=0.45):
    """One drooping tier of a spruce: a star of uneven points around a
    peak, with flat facets, and a shallow cone underneath."""
    peak = bm.verts.new((rng.uniform(-0.05, 0.05), rng.uniform(-0.05, 0.05), z0 + height))
    ring = []
    a0 = rng.uniform(0, math.tau)
    for j in range(points * 2):
        a = a0 + math.pi * j / points + rng.uniform(-0.12, 0.12)
        if j % 2 == 0:       # outer point, hanging down
            r = radius * rng.uniform(0.85, 1.12)
            z = z0 - droop * rng.uniform(0.7, 1.2)
        else:                # notch between points, higher up
            r = radius * rng.uniform(0.5, 0.62)
            z = z0 + height * 0.12
        ring.append(bm.verts.new((math.cos(a) * r, math.sin(a) * r, z)))
    under = bm.verts.new((0, 0, z0 + height * 0.25))
    n = len(ring)
    for j in range(n):
        for tri in ((ring[j], ring[(j + 1) % n], peak), (ring[(j + 1) % n], ring[j], under)):
            f = bm.faces.new(tri)
            f.material_index = m
            f.smooth = False


def bend_normals(ob, centre, mat_indices, strength=0.85, axis_scale=1.0):
    """Point foliage normals away from centre (z scaled by axis_scale for
    tall shapes) so a canopy lights as one soft volume."""
    me = ob.data
    leafy = set()
    for p in me.polygons:
        if p.material_index in mat_indices:
            leafy.update(p.vertices)
    normals = []
    for v in me.vertices:
        if v.index in leafy:
            off = v.co - Vector(centre)
            off.z *= axis_scale
            normals.append((off.normalized() * strength + v.normal * (1 - strength)).normalized())
        else:
            normals.append(v.normal.copy())
    me.normals_split_custom_set_from_vertices(normals)
