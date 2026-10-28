"""Leaf-cluster foliage shared by the map props (build_corner_3d.py) and the
street kit (build_assets.py), following docs/art_direction.md: canopies,
bushes and hedges are clumps of double-sided leaf cards around a small
lumpy core, so they have a ragged outline and light like soft volumes
once their normals are bent outwards (bend_normals). Spruces are stacked,
drooping, star-shaped tiers with flat facets.

Every function adds faces to a bmesh with a given material index.
"""
import math

import bmesh
from mathutils import Matrix, Vector, noise

UP = Vector((0, 0, 1))


def _random_dir(rng, up_bias):
    """A random unit vector, more often pointing up when up_bias > 0."""
    z = rng.uniform(-1.0, 1.0)
    z = z + up_bias * (1.0 - z * z)
    a = rng.uniform(0, math.tau)
    s = math.sqrt(max(0.0, 1.0 - z * z))
    return Vector((math.cos(a) * s, math.sin(a) * s, z)).normalized()


def leaf(bm, p, outward, length, width, rng, m, droop=0.3, fold=0.12):
    """One double-sided leaf card at p: a folded diamond facing mostly
    outward and up, its tip pointing away from the clump and drooping."""
    nrm = (outward + UP * 0.6).normalized()
    t = outward - nrm * outward.dot(nrm)
    if t.length < 1e-3:
        t = nrm.orthogonal()
    t = Matrix.Rotation(rng.uniform(-1.0, 1.0), 3, nrm) @ t.normalized()
    b = nrm.cross(t)
    base = p - t * length * 0.35
    tip = p + t * length * 0.65 - UP * droop * length
    l = p + b * width * 0.5 - nrm * fold * width
    r = p - b * width * 0.5 - nrm * fold * width
    vs = [bm.verts.new(v) for v in (base, r, tip, l)]
    for tri in ((vs[0], vs[1], vs[2]), (vs[0], vs[2], vs[3])):
        f = bm.faces.new(tri)
        f.material_index = m
        f.smooth = True
        f.normal_update()
        if f.normal.dot(nrm) < 0:
            f.normal_flip()


def clump(bm, centre, radii, rng, m, leaves=44, leaf_size=(0.38, 0.58), core=0.72, up_bias=0.35,
          droop=0.3, lump=0.18, min_z=None):
    """A clump of leaves: a lumpy core (radii scaled by core) and leaf cards
    scattered over the surface of the ellipsoid radii. min_z flattens the
    clump on the ground (bushes, hedges)."""
    rx, ry, rz = radii
    res = bmesh.ops.create_icosphere(bm, subdivisions=1, radius=1.0)
    seed = rng.uniform(0, 100)
    for v in res["verts"]:
        d = v.co.normalized()
        k = core * (1.0 + noise.noise(d * 1.7 + Vector((seed, seed, seed))) * lump)
        v.co = centre + Vector((d.x * rx * k, d.y * ry * k, d.z * rz * k))
        if min_z is not None:
            v.co.z = max(v.co.z, min_z)
    for f in {f for v in res["verts"] for f in v.link_faces}:
        f.material_index = m
        f.smooth = True
    for _ in range(leaves):
        d = _random_dir(rng, up_bias)
        k = rng.uniform(0.8, 1.05)
        p = centre + Vector((d.x * rx * k, d.y * ry * k, d.z * rz * k))
        if min_z is not None:
            p.z = max(p.z, min_z + 0.08)
        out = Vector((d.x / rx, d.y / ry, d.z / rz)).normalized()
        L = rng.uniform(*leaf_size)
        leaf(bm, p, out, L, L * rng.uniform(0.55, 0.75), rng, m, droop=droop)


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
