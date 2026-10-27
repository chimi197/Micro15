"""Export one corner of Micro 15 for the Godot style test.

Builds a fresh, UV-mapped low-detail version of the buildings, roads and
ground around CENTRE (windows and balconies come from the drawn facade
textures instead of geometry), exports it to game/levels/style_test/corner.glb
and writes the tree / lamp / bench positions to props.json.

    import sys; sys.path.insert(0, r"<repo>/blender")
    import export_style_test; export_style_test.run(r"<repo>")
"""
import bmesh
import bpy
import json
import math
import os
import random
from mathutils import Vector

import build_world as bw

CENTRE = (250.0, 560.0)
RADIUS = 115.0
BAY_TILE = 4 * 3.2        # facade texture width in metres (4 bays)
FLOOR_TILE = 3 * 2.8      # facade texture height in metres (3 floors)
WALLS = ["mint", "peach", "lemon", "sky", "cream", "lilac"]


def near(x, y, r=RADIUS):
    return math.hypot(x - CENTRE[0], y - CENTRE[1]) <= r


def plain_material(name):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    return m


def planar_uv(bm, scale):
    uv = bm.loops.layers.uv.verify()
    for f in bm.faces:
        for lp in f.loops:
            lp[uv].uv = ((lp.vert.co.x - CENTRE[0]) / scale, (lp.vert.co.y - CENTRE[1]) / scale)


def make_obj(name, bm, col, mats):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(m)
    ob = bpy.data.objects.new(name, me)
    col.objects.link(ob)
    return ob


def building(bm, ring, height, wall_idx, roof_idx, entrance_idx, uv, rng):
    bot = [bm.verts.new((x, y, 0.0)) for x, y in ring]
    top = [bm.verts.new((x, y, height)) for x, y in ring]
    u = rng.uniform(0, 1)
    for i in range(len(ring)):
        j = (i + 1) % len(ring)
        L = (Vector(ring[j]) - Vector(ring[i])).length
        f = bm.faces.new((bot[i], bot[j], top[j], top[i]))
        f.material_index = wall_idx
        u0, u1 = u, u + L / BAY_TILE
        for lp, (uu, vv) in zip(f.loops, ((u0, 0), (u1, 0), (u1, height / FLOOR_TILE), (u0, height / FLOOR_TILE))):
            lp[uv].uv = (uu, vv)
        u = u1
        # stairwell entrance decal on long walls
        if L > 18 and i % 2 == 0:
            a, b = Vector(ring[i]), Vector(ring[j])
            d = (b - a) / L
            n = Vector((d.y, -d.x))
            c = a + d * (L / 2) + n * 0.03
            h = d * 1.6
            vs = [bm.verts.new((p.x, p.y, z)) for p, z in ((c - h, 0.0), (c + h, 0.0), (c + h, 2.8), (c - h, 2.8))]
            ef = bm.faces.new(vs)
            ef.material_index = entrance_idx
            for lp, co in zip(ef.loops, ((0, 0), (1, 0), (1, 1), (0, 1))):
                lp[uv].uv = co
    rf = bm.faces.new(top)
    rf.material_index = roof_idx
    for lp in rf.loops:
        lp[uv].uv = (lp.vert.co.x / 6.0, lp.vert.co.y / 6.0)
    # parapet lip
    r = bmesh.ops.inset_region(bm, faces=[rf], thickness=0.45, depth=0.0)
    for f in r["faces"]:
        f.material_index = roof_idx
    bmesh.ops.translate(bm, verts=list(rf.verts), vec=(0, 0, -0.4))


def run(root):
    data = bw.osm(root)
    out_dir = os.path.join(root, "game", "levels", "style_test")
    os.makedirs(out_dir, exist_ok=True)

    # build in a separate scene so the main world stays untouched
    scn = bpy.data.scenes.get("StyleTest") or bpy.data.scenes.new("StyleTest")
    for ob in list(scn.collection.all_objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    col = scn.collection

    # ground disc
    bm = bmesh.new()
    seg = 64
    vs = [bm.verts.new((CENTRE[0] + math.cos(a) * (RADIUS + 25), CENTRE[1] + math.sin(a) * (RADIUS + 25), 0.0))
          for a in [math.tau * k / seg for k in range(seg)]]
    bm.faces.new(vs)
    planar_uv(bm, 8.0)
    make_obj("ground", bm, col, [plain_material("grass")])

    # land use patches
    area_mat = {"parking": "asphalt", "playground": "sand", "pitch": "pitch", "school": "sand",
                "kindergarten": "sand", "park": "grass_park", "grass": "grass_park"}
    bm = bmesh.new()
    mats = []
    for w in data.ways:
        t = w["tags"]
        kind = t.get("amenity") or t.get("leisure") or t.get("landuse")
        if kind not in area_mat:
            continue
        ring = bw.clean_ring(data.coords(w))
        if len(ring) < 3 or not any(near(x, y) for x, y in ring):
            continue
        name = area_mat[kind]
        if name not in mats:
            mats.append(name)
        z = 0.03 if name != "asphalt" else 0.04
        try:
            f = bm.faces.new([bm.verts.new((x, y, z)) for x, y in ring])
            f.material_index = mats.index(name)
        except ValueError:
            pass
    planar_uv(bm, 6.0)
    make_obj("areas", bm, col, [plain_material(m) for m in mats])

    # roads + sidewalks
    road = bmesh.new()
    walk = bmesh.new()
    path = bmesh.new()
    for w in data.ways:
        hw = w["tags"].get("highway")
        if hw not in bw.ROAD_STYLES:
            continue
        width, key, z, sw, _ = bw.ROAD_STYLES[hw]
        pts = [p for p in data.coords(w)]
        if not any(near(x, y, RADIUS + 20) for x, y in pts):
            continue
        if key == "asphalt":
            bw.ribbon(road, pts, width, z)
            if sw:
                bw.ribbon(walk, pts, width + 2 * sw, 0.045)
        else:
            bw.ribbon(path, pts, max(width, 2.0), 0.06)
    for bm_, scale in ((road, 6.0), (walk, 4.0), (path, 4.0)):
        planar_uv(bm_, scale)
    make_obj("roads", road, col, [plain_material("asphalt")])
    make_obj("sidewalks", walk, col, [plain_material("pavement")])
    make_obj("paths", path, col, [plain_material("pavement")])

    # buildings
    bm = bmesh.new()
    uv = bm.loops.layers.uv.verify()
    mat_names = ["facade_" + n for n in WALLS] + ["roof", "facade_entrance"]
    nb = 0
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
        h = levels * 2.8 + 0.4 if kind == "apartments" else max(levels, 1) * 3.0
        rng = random.Random(w["id"])
        building(bm, ring, h, w["id"] % len(WALLS), len(WALLS), len(WALLS) + 1, uv, rng)
        nb += 1
    make_obj("buildings", bm, col, [plain_material(m) for m in mat_names])

    # props from the main world scene
    props = []
    for ob in bpy.data.objects:
        if ob.name.startswith(("Tree_", "Bush_", "Lamp_", "Bench_")) and near(ob.location.x, ob.location.y):
            kind = ob.data.name.replace("M15_", "").lower()
            props.append({"type": kind, "pos": [round(ob.location.x - CENTRE[0], 2), 0.0,
                                                round(-(ob.location.y - CENTRE[1]), 2)],
                          "rot": round(ob.rotation_euler.z, 3), "scale": round(ob.scale.x, 2)})
    json.dump(props, open(os.path.join(out_dir, "props.json"), "w"), indent=0)

    # centre the corner on the origin for the game
    for ob in scn.collection.all_objects:
        ob.location.x -= CENTRE[0]
        ob.location.y -= CENTRE[1]

    prev = bpy.context.window.scene
    bpy.context.window.scene = scn
    bpy.ops.object.select_all(action="DESELECT")
    bpy.ops.export_scene.gltf(filepath=os.path.join(out_dir, "corner.glb"), export_format="GLB",
                              use_active_scene=True, export_apply=True)
    bpy.context.window.scene = prev
    return {"buildings": nb, "props": len(props)}
