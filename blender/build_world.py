"""Build the Micro 15 (Satu Mare, Romania) world in Blender from OpenStreetMap data.

Run inside Blender:

    import sys; sys.path.insert(0, r"<repo>/blender")
    import build_world; build_world.build_all(r"<repo>")

Every stage can also be run on its own (see STAGES) so a remote call never
runs for too long. 1 Blender unit = 1 metre, +Y = north.
"""
import bpy
import bmesh
import json
import math
import os
import random
from mathutils import Vector

LAT0, LON0 = 47.7816296, 22.8595870          # OSM "Micro 15" suburb node
KX = math.cos(math.radians(LAT0)) * 111320.0
KY = 110540.0
# Map extent in metres around the suburb node (covers every block of flats).
XMIN, XMAX, YMIN, YMAX = -480.0, 760.0, -380.0, 790.0

FLOOR_H = 2.8

# --------------------------------------------------------------------------
# Palette (flat, saturated cartoon colours)
# --------------------------------------------------------------------------
PALETTE = {
    "grass": "#9CCB5B", "grass_dark": "#7DB547", "park": "#86C24F",
    "meadow": "#B9D46A", "wood": "#5E9E43", "sand": "#EBCB7A",
    "pitch": "#5DB55A", "pool": "#4FB6E8", "dirt": "#C49A6C",
    "asphalt": "#5F6673", "asphalt_light": "#8A919C", "sidewalk": "#D9D2C3",
    "path": "#E6D6AE", "line": "#F4F1E6", "industrial": "#B4B0A8",
    "roof_flat": "#8E8B87", "roof_tile": "#D2603F", "roof_dark": "#6E4A3C",
    "window": "#35527A", "window_lit": "#FFE08A", "frame": "#F7F4EC",
    "balcony": "#EFEAE0", "door": "#7A4B2F", "garage": "#A9B4C2",
    "trunk": "#8A5A3B", "leaf_a": "#4FA843", "leaf_b": "#6CBF48",
    "leaf_c": "#3E8E3E", "poplar": "#3F9447", "bush": "#5AAE45",
    "metal": "#4A4E57", "lamp": "#FFF2B3", "bench": "#B07A4A",
    "outline": "#1B1B24", "church": "#F3EBD9", "church_roof": "#3F6E8C",
    "gold": "#E8B93A", "school": "#F2C14E", "hospital": "#F5F5F0",
    "retail": "#E9EEF2", "retail_band": "#E2504C",
}
BLOCK_COLOURS = ["#F2E3B3", "#F4B183", "#F7D774", "#A8D8B9", "#9EC9E2",
                 "#E98B6D", "#F3D1C4", "#D9E4A6", "#E7E2D6", "#C9B6E4"]
HOUSE_COLOURS = ["#F6E7C1", "#F2C59A", "#E8F0D0", "#F5D5D5", "#D6E8F2", "#FBE9A0"]


def hex_rgba(h):
    h = h.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    # sRGB -> linear
    c = [x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c]
    return (c[0], c[1], c[2], 1.0)


# --------------------------------------------------------------------------
# Materials
# --------------------------------------------------------------------------
def toon_material(name, colour, emissive=False):
    """Cel shaded material: 3 hard light bands multiplied with a flat colour.

    The node tree is EEVEE only (Shader to RGB); the base colour is also set
    as the viewport/diffuse colour so game engine exporters pick it up.
    """
    mat = bpy.data.materials.get("M15_" + name)
    if mat:
        return mat
    mat = bpy.data.materials.new("M15_" + name)
    mat.diffuse_color = hex_rgba(colour)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    out.location = (800, 0)
    emit = nt.nodes.new("ShaderNodeEmission")
    emit.location = (600, 0)
    if emissive:
        emit.inputs["Color"].default_value = hex_rgba(colour)
        emit.inputs["Strength"].default_value = 1.6
    else:
        diff = nt.nodes.new("ShaderNodeBsdfDiffuse")
        diff.location = (-400, 0)
        s2r = nt.nodes.new("ShaderNodeShaderToRGB")
        s2r.location = (-200, 0)
        ramp = nt.nodes.new("ShaderNodeValToRGB")
        ramp.location = (0, 0)
        ramp.color_ramp.interpolation = "CONSTANT"
        els = ramp.color_ramp.elements
        els[0].position, els[0].color = 0.0, (0.55, 0.58, 0.72, 1)   # shadow (cool tint)
        els[1].position, els[1].color = 0.12, (0.80, 0.82, 0.88, 1)  # mid
        e = els.new(0.38)
        e.color = (1.0, 1.0, 1.0, 1)                                  # lit
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.blend_type = "MULTIPLY"
        mix.location = (300, 0)
        mix.inputs["Factor"].default_value = 1.0
        mix.inputs[6].default_value = hex_rgba(colour)
        nt.links.new(diff.outputs["BSDF"], s2r.inputs["Shader"])
        nt.links.new(s2r.outputs["Color"], ramp.inputs["Fac"])
        nt.links.new(ramp.outputs["Color"], mix.inputs[7])
        nt.links.new(mix.outputs[2], emit.inputs["Color"])
    nt.links.new(emit.outputs["Emission"], out.inputs["Surface"])
    return mat


def outline_material():
    mat = bpy.data.materials.get("M15_outline")
    if mat:
        return mat
    mat = bpy.data.materials.new("M15_outline")
    mat.diffuse_color = hex_rgba(PALETTE["outline"])
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    emit = nt.nodes.new("ShaderNodeEmission")
    emit.inputs["Color"].default_value = hex_rgba(PALETTE["outline"])
    nt.links.new(emit.outputs["Emission"], out.inputs["Surface"])
    mat.use_backface_culling = True
    return mat


def add_outline(obj, thickness):
    """Inverted hull outline (works in any engine: flipped, culled shell)."""
    mats = obj.data.materials
    if "M15_outline" not in [m.name for m in mats if m]:
        mats.append(outline_material())
    mod = obj.modifiers.new("Outline", "SOLIDIFY")
    mod.thickness = -thickness
    mod.offset = -1.0
    mod.use_flip_normals = True
    mod.use_rim = False
    mod.use_even_offset = False      # even offset spikes on sharp footprint corners
    mod.use_quality_normals = True
    mod.material_offset = len(mats) - 1
    mod.material_offset_rim = len(mats) - 1
    return mod


# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------
def collection(name, parent=None):
    col = bpy.data.collections.get(name)
    if not col:
        col = bpy.data.collections.new(name)
        (parent or bpy.context.scene.collection).children.link(col)
    return col


def clear_collection(col):
    for ob in list(col.objects):
        bpy.data.objects.remove(ob, do_unlink=True)


def new_object(name, bm, col, mats):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(m)
    ob = bpy.data.objects.new(name, me)
    col.objects.link(ob)
    return ob


def polygon_area(pts):
    a = 0.0
    for i in range(len(pts)):
        x1, y1 = pts[i]
        x2, y2 = pts[(i + 1) % len(pts)]
        a += x1 * y2 - x2 * y1
    return a / 2.0


def clean_ring(pts, tol=0.3):
    if len(pts) > 1 and pts[0] == pts[-1]:
        pts = pts[:-1]
    out = []
    for p in pts:
        if not out or (abs(p[0] - out[-1][0]) + abs(p[1] - out[-1][1])) > tol:
            out.append(p)
    if len(out) > 2 and (abs(out[0][0] - out[-1][0]) + abs(out[0][1] - out[-1][1])) <= tol:
        out.pop()
    if len(out) >= 3 and polygon_area(out) < 0:
        out.reverse()          # counter clockwise -> outward normal is (dy, -dx)
    return out


def point_in_poly(x, y, pts):
    inside = False
    j = len(pts) - 1
    for i in range(len(pts)):
        xi, yi = pts[i]
        xj, yj = pts[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi + 1e-12) + xi:
            inside = not inside
        j = i
    return inside


def min_rect_dims(pts):
    """Width/length of the minimum-area bounding rectangle (edge aligned)."""
    best = None
    for i in range(len(pts)):
        x1, y1 = pts[i]
        x2, y2 = pts[(i + 1) % len(pts)]
        ang = math.atan2(y2 - y1, x2 - x1)
        c, s = math.cos(-ang), math.sin(-ang)
        xs = [x * c - y * s for x, y in pts]
        ys = [x * s + y * c for x, y in pts]
        w, h = max(xs) - min(xs), max(ys) - min(ys)
        if best is None or w * h < best[0] * best[1]:
            best = (w, h)
    return min(best), max(best)


def in_extent(x, y, margin=0.0):
    return XMIN - margin <= x <= XMAX + margin and YMIN - margin <= y <= YMAX + margin


# --------------------------------------------------------------------------
# OSM loading
# --------------------------------------------------------------------------
class OSM:
    def __init__(self, path):
        d = json.load(open(path, encoding="utf-8"))
        self.nodes = {}
        for e in d["elements"]:
            if e["type"] == "node" and "lat" in e:
                self.nodes[e["id"]] = ((e["lon"] - LON0) * KX, (e["lat"] - LAT0) * KY)
        self.ways = [e for e in d["elements"] if e["type"] == "way" and e.get("tags")]
        self.points = [e for e in d["elements"] if e["type"] == "node" and e.get("tags")]

    def coords(self, way):
        return [self.nodes[n] for n in way["nodes"] if n in self.nodes]


_OSM = None


def osm(root):
    global _OSM
    if _OSM is None:
        _OSM = OSM(os.path.join(root, "reference", "micro15_osm.json"))
    return _OSM


# --------------------------------------------------------------------------
# Stage: scene setup
# --------------------------------------------------------------------------
def stage_scene(root):
    scn = bpy.context.scene
    for name in ("Cube", "Light", "Camera"):          # Blender's startup scene
        if bpy.data.objects.get(name):
            bpy.data.objects.remove(bpy.data.objects[name], do_unlink=True)
    scn.unit_settings.system = "METRIC"
    scn.render.engine = "BLENDER_EEVEE"
    scn.view_settings.view_transform = "Standard"
    scn.view_settings.look = "None"
    scn.render.resolution_x, scn.render.resolution_y = 1920, 1080
    world = scn.world or bpy.data.worlds.new("M15_Sky")
    scn.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    if bg is None:
        bg = world.node_tree.nodes.new("ShaderNodeBackground")
        out = world.node_tree.nodes.get("World Output") or world.node_tree.nodes.new("ShaderNodeOutputWorld")
        world.node_tree.links.new(bg.outputs[0], out.inputs[0])
    bg.inputs["Color"].default_value = hex_rgba("#BFE6F7")
    bg.inputs["Strength"].default_value = 0.9

    col = collection("M15_Lighting")
    clear_collection(col)
    sun = bpy.data.lights.new("M15_Sun", "SUN")
    sun.energy = 3.0
    sun.angle = math.radians(1.0)
    sun.color = (1.0, 0.97, 0.9)
    so = bpy.data.objects.new("M15_Sun", sun)
    so.rotation_euler = (math.radians(50), math.radians(10), math.radians(35))
    col.objects.link(so)
    return {"ok": True}


# --------------------------------------------------------------------------
# Stage: ground + land use areas
# --------------------------------------------------------------------------
AREA_STYLES = [
    # (tag, value, palette key, z)
    ("landuse", "grass", "grass_dark", 0.02),
    ("landuse", "meadow", "meadow", 0.02),
    ("natural", "grassland", "meadow", 0.02),
    ("natural", "heath", "meadow", 0.02),
    ("landuse", "industrial", "industrial", 0.015),
    ("landuse", "construction", "dirt", 0.015),
    ("landuse", "religious", "grass_dark", 0.018),
    ("landuse", "retail", "asphalt_light", 0.015),
    ("leisure", "park", "park", 0.025),
    ("natural", "wood", "wood", 0.03),
    ("amenity", "school", "sand", 0.022),
    ("amenity", "kindergarten", "sand", 0.022),
    ("amenity", "parking", "asphalt_light", 0.045),
    ("amenity", "marketplace", "sidewalk", 0.045),
    ("amenity", "fuel", "asphalt_light", 0.045),
    ("leisure", "playground", "sand", 0.05),
    ("leisure", "pitch", "pitch", 0.055),
    ("leisure", "swimming_pool", "pool", 0.06),
]


def stage_ground(root):
    data = osm(root)
    col = collection("M15_Ground")
    clear_collection(col)

    bm = bmesh.new()
    m = 40.0
    vs = [bm.verts.new((x, y, 0.0)) for x, y in
          ((XMIN - m, YMIN - m), (XMAX + m, YMIN - m), (XMAX + m, YMAX + m), (XMIN - m, YMAX + m))]
    bm.faces.new(vs)
    new_object("M15_Ground", bm, col, [toon_material("grass", PALETTE["grass"])])

    groups = {}
    for w in data.ways:
        t = w["tags"]
        for i, (k, v, key, z) in enumerate(AREA_STYLES):
            if t.get(k) == v:
                pts = clean_ring(data.coords(w))
                if len(pts) < 3:
                    break
                cx = sum(p[0] for p in pts) / len(pts)
                cy = sum(p[1] for p in pts) / len(pts)
                if not in_extent(cx, cy):
                    break
                groups.setdefault((key, z, v), []).append(pts)
                break
    n = 0
    for (key, z, v), polys in groups.items():
        bm = bmesh.new()
        for pts in polys:
            try:
                bm.faces.new([bm.verts.new((x, y, z)) for x, y in pts])
                n += 1
            except ValueError:
                pass
        new_object("M15_Area_" + v, bm, col, [toon_material(key, PALETTE[key])])

    # pitch markings: white outline strip inside each pitch
    return {"areas": n, "groups": len(groups)}


# --------------------------------------------------------------------------
# Stage: roads
# --------------------------------------------------------------------------
ROAD_STYLES = {
    # highway: (width, palette key, z, sidewalk width, centre line)
    "primary": (13.0, "asphalt", 0.08, 3.0, True),
    "primary_link": (7.0, "asphalt", 0.08, 2.0, False),
    "secondary": (11.0, "asphalt", 0.075, 3.0, True),
    "tertiary": (9.0, "asphalt", 0.07, 2.5, True),
    "residential": (7.0, "asphalt", 0.065, 2.0, False),
    "living_street": (5.5, "asphalt", 0.06, 1.5, False),
    "unclassified": (6.0, "asphalt", 0.06, 1.5, False),
    "service": (4.5, "asphalt", 0.05, 0.0, False),
    "footway": (2.2, "path", 0.07, 0.0, False),
    "pedestrian": (4.0, "sidewalk", 0.07, 0.0, False),
    "path": (1.6, "path", 0.07, 0.0, False),
    "cycleway": (2.0, "pool", 0.072, 0.0, False),
    "steps": (2.0, "sidewalk", 0.07, 0.0, False),
}


def ribbon(bm, pts, width, z):
    """Add a flat strip along a polyline with mitred joints."""
    if len(pts) < 2:
        return
    hw = width / 2.0
    left, right = [], []
    for i, p in enumerate(pts):
        p = Vector((p[0], p[1]))
        if i == 0:
            d = (Vector(pts[1]) - p).normalized()
            nrm = Vector((-d.y, d.x))
            scale = 1.0
        elif i == len(pts) - 1:
            d = (p - Vector(pts[i - 1])).normalized()
            nrm = Vector((-d.y, d.x))
            scale = 1.0
        else:
            d1 = (p - Vector(pts[i - 1])).normalized()
            d2 = (Vector(pts[i + 1]) - p).normalized()
            n1, n2 = Vector((-d1.y, d1.x)), Vector((-d2.y, d2.x))
            nrm = (n1 + n2)
            if nrm.length < 1e-4:
                nrm = n1
            nrm.normalize()
            scale = min(1.0 / max(nrm.dot(n1), 0.35), 2.5)
        off = nrm * hw * scale
        left.append(bm.verts.new((p.x + off.x, p.y + off.y, z)))
        right.append(bm.verts.new((p.x - off.x, p.y - off.y, z)))
    for i in range(len(pts) - 1):
        try:
            bm.faces.new((right[i], right[i + 1], left[i + 1], left[i]))
        except ValueError:
            pass
    # round-ish caps so joints between separate ways do not show gaps
    for p, z_ in ((pts[0], z), (pts[-1], z)):
        seg = 8
        vs = [bm.verts.new((p[0] + math.cos(a) * hw, p[1] + math.sin(a) * hw, z_ - 0.002))
              for a in [2 * math.pi * k / seg for k in range(seg)]]
        bm.faces.new(vs)


def clip_polyline(pts):
    """Keep only the runs of a polyline inside the map extent."""
    runs, cur = [], []
    for p in pts:
        if in_extent(p[0], p[1], 30):
            cur.append(p)
        else:
            if len(cur) > 1:
                runs.append(cur)
            cur = []
    if len(cur) > 1:
        runs.append(cur)
    return runs


def dashes(bm, pts, z, dash=3.0, gap=4.0, width=0.25):
    acc = 0.0
    for i in range(len(pts) - 1):
        a, b = Vector(pts[i]), Vector(pts[i + 1])
        seg = (b - a)
        L = seg.length
        if L < 0.01:
            continue
        d = seg / L
        n = Vector((-d.y, d.x)) * width / 2
        t = -acc
        while t < L:
            s0, s1 = max(t, 0.0), min(t + dash, L)
            if s1 > s0:
                p0, p1 = a + d * s0, a + d * s1
                bm.faces.new([bm.verts.new((v.x, v.y, z)) for v in
                              (p0 - n, p1 - n, p1 + n, p0 + n)])
            t += dash + gap
        acc = (acc + L) % (dash + gap)


def stage_roads(root):
    data = osm(root)
    col = collection("M15_Roads")
    clear_collection(col)
    by_key, walks, lines = {}, bmesh.new(), bmesh.new()
    n = 0
    for w in data.ways:
        hw = w["tags"].get("highway")
        if hw not in ROAD_STYLES or w["tags"].get("area") == "yes":
            continue
        width, key, z, sw, centre = ROAD_STYLES[hw]
        if w["tags"].get("lanes"):
            try:
                width = max(width, 3.4 * int(w["tags"]["lanes"]))
            except ValueError:
                pass
        for run in clip_polyline(data.coords(w)):
            if key not in by_key:
                by_key[key] = bmesh.new()
            ribbon(by_key[key], run, width, z)
            if sw:
                ribbon(walks, run, width + 2 * sw, 0.04)
            if centre:
                dashes(lines, run, z + 0.01)
            n += 1
    for key, bm in by_key.items():
        new_object("M15_Road_" + key, bm, col, [toon_material(key, PALETTE[key])])
    new_object("M15_Sidewalks", walks, col, [toon_material("sidewalk", PALETTE["sidewalk"])])
    new_object("M15_RoadLines", lines, col, [toon_material("line", PALETTE["line"])])
    return {"roads": n}


# --------------------------------------------------------------------------
# Stage: buildings
# --------------------------------------------------------------------------
def classify(t, pts):
    """Return (kind, levels) for a building way."""
    b = t.get("building")
    area = abs(polygon_area(pts))
    try:
        lv = int(float(t.get("building:levels", "0")))
    except ValueError:
        lv = 0
    w, l = min_rect_dims(pts)
    if b in ("apartments", "residential") or (b == "yes" and area > 350):
        if not lv:
            # Micro 15 mixes P+4 slabs and P+10 point towers. Compact
            # footprints are the towers, long slabs are 4 storeys.
            lv = 11 if (l / max(w, 1) < 1.7 and 220 < area < 650) else 5
        return "apartments", lv
    if b == "house":
        return "house", lv or 1
    if b in ("garages", "garage", "roof", "shed"):
        return "garage", 1
    if b == "church":
        return "church", lv or 3
    if b in ("school", "kindergarten"):
        return "school", lv or (1 if b == "kindergarten" else 3)
    if b == "hospital":
        return "hospital", lv or 4
    if b in ("retail", "commercial", "supermarket", "warehouse", "industrial"):
        return "retail", lv or 2
    return "small", lv or (1 if area < 150 else 2)


def window_grid(bm, ring, base_z, floors, mat_win, mat_balc, mat_frame, rng,
                spacing=3.2, win_w=1.4, win_h=1.3, balconies=False, door_mat=None):
    """Window quads (and optional balconies) floating just off each wall."""
    for i in range(len(ring)):
        a = Vector(ring[i])
        b = Vector(ring[(i + 1) % len(ring)])
        seg = b - a
        L = seg.length
        if L < 2.5:
            continue
        d = seg / L
        nrm = Vector((d.y, -d.x))
        cols = max(1, int(L // spacing))
        pad = (L - cols * spacing) / 2 + spacing / 2
        long_wall = L > 18
        door_col = cols // 2 if (door_mat and long_wall and i % 2 == 0) else -1
        for f in range(floors):
            z0 = base_z + f * FLOOR_H + 0.9
            for c in range(cols):
                cx = a + d * (pad + c * spacing)
                if f == 0 and c == door_col:
                    o = cx + nrm * 0.04
                    _quad(bm, o, d, 1.6, base_z, base_z + 2.3, door_mat)
                    # entrance canopy
                    _box(bm, cx + nrm * 0.8, d, nrm, 2.4, 1.6, base_z + 2.5, base_z + 2.7, mat_frame)
                    continue
                if balconies and long_wall and f > 0 and c % 2 == 1:
                    _box(bm, cx + nrm * 0.6, d, nrm, spacing * 0.85, 1.2, z0 - 0.9, z0 + 0.15, mat_balc)
                    _quad(bm, cx + nrm * 0.04, d, win_w * 0.8, z0 + 0.15 - 0.9, z0 + win_h, mat_win)
                    continue
                o = cx + nrm * 0.06
                _quad(bm, o + nrm * 0.0, d, win_w + 0.3, z0 - 0.15, z0 + win_h + 0.15, mat_frame)
                _quad(bm, o + nrm * 0.02, d, win_w, z0, z0 + win_h,
                      mat_win if rng.random() > 0.08 else mat_win + 1)


# Faces of single-sided decals (windows, doors, fascia bands). They keep
# the normal they are built with and get no outline shell.
_FLAT = set()


def _quad(bm, centre, d, w, z0, z1, mat):
    h = d * (w / 2)
    vs = [bm.verts.new((v.x, v.y, z)) for v, z in
          ((centre - h, z0), (centre + h, z0), (centre + h, z1), (centre - h, z1))]
    f = bm.faces.new(vs)
    f.material_index = mat
    _FLAT.add(f)


def _box(bm, centre, d, nrm, w, depth, z0, z1, mat):
    h = d * (w / 2)
    n = nrm * (depth / 2)
    corners = [centre - h - n, centre + h - n, centre + h + n, centre - h + n]
    if d.x * nrm.y - d.y * nrm.x < 0:
        corners.reverse()        # keep the ring counter clockwise -> outward normals
    bot = [bm.verts.new((c.x, c.y, z0)) for c in corners]
    top = [bm.verts.new((c.x, c.y, z1)) for c in corners]
    faces = [bm.faces.new(top)]
    for i in range(4):
        j = (i + 1) % 4
        faces.append(bm.faces.new((bot[i], bot[j], top[j], top[i])))
    faces.append(bm.faces.new(list(reversed(bot))))
    for f in faces:
        f.material_index = mat


def prism(bm, ring, z0, z1, wall_mat, roof_mat, roof="flat", roof_h=2.5):
    bot = [bm.verts.new((x, y, z0)) for x, y in ring]
    top = [bm.verts.new((x, y, z1)) for x, y in ring]
    for i in range(len(ring)):
        j = (i + 1) % len(ring)
        f = bm.faces.new((bot[i], bot[j], top[j], top[i]))
        f.material_index = wall_mat
    roof_f = bm.faces.new(top)
    roof_f.material_index = roof_mat
    if roof == "parapet":
        r = bmesh.ops.inset_region(bm, faces=[roof_f], thickness=0.5, depth=0.0)
        for f in r["faces"]:
            f.material_index = wall_mat
        bmesh.ops.translate(bm, verts=list(roof_f.verts), vec=(0, 0, -0.5))
    elif roof == "hip":
        w, l = min_rect_dims(ring)
        r = bmesh.ops.inset_region(bm, faces=[roof_f], thickness=w * 0.42, depth=0.0)
        for f in r["faces"]:
            f.material_index = roof_mat
        bmesh.ops.translate(bm, verts=list(roof_f.verts), vec=(0, 0, roof_h))
    return roof_f


def stage_buildings(root, kinds=None):
    data = osm(root)
    parent = collection("M15_Buildings")
    cols = {k: collection("M15_" + k.capitalize(), parent)
            for k in ("apartments", "house", "garage", "church", "school", "hospital", "retail", "small")}
    for k, c in cols.items():
        if kinds is None or k in kinds:
            clear_collection(c)
    counts = {}
    for w in data.ways:
        t = w["tags"]
        if "building" not in t:
            continue
        ring = clean_ring(data.coords(w))
        if len(ring) < 3:
            continue
        cx = sum(p[0] for p in ring) / len(ring)
        cy = sum(p[1] for p in ring) / len(ring)
        if not in_extent(cx, cy):
            continue
        kind, levels = classify(t, ring)
        if kinds is not None and kind not in kinds:
            continue
        rng = random.Random(w["id"])
        build_one(w, t, ring, kind, levels, rng, cols[kind])
        counts[kind] = counts.get(kind, 0) + 1
    return counts


def build_one(w, t, ring, kind, levels, rng, col):
    _FLAT.clear()
    bm = bmesh.new()
    name = t.get("name") or t.get("addr:street", "") + " " + t.get("addr:housenumber", "")
    name = ("M15_%s_%d %s" % (kind, w["id"], name.strip()))[:60]
    h = levels * FLOOR_H + 0.4
    base = 0.0
    # material slots: 0 wall, 1 roof, 2 window, 3 window lit, 4 balcony, 5 frame, 6 door, 7 accent
    if kind == "apartments":
        wall = toon_material("block_%d" % (w["id"] % len(BLOCK_COLOURS)), BLOCK_COLOURS[w["id"] % len(BLOCK_COLOURS)])
        mats = [wall, toon_material("roof_flat", PALETTE["roof_flat"])]
        prism(bm, ring, base, h, 0, 1, roof="parapet")
        # plinth (darker band at ground level)
    elif kind == "house":
        col_hex = HOUSE_COLOURS[w["id"] % len(HOUSE_COLOURS)]
        mats = [toon_material("house_%s" % col_hex[1:], col_hex), toon_material("roof_tile", PALETTE["roof_tile"])]
        h = levels * 3.0
        prism(bm, ring, base, h, 0, 1, roof="hip", roof_h=2.2 + rng.random())
    elif kind == "garage":
        mats = [toon_material("garage", PALETTE["garage"]), toon_material("roof_dark", PALETTE["roof_dark"])]
        h = 2.6
        prism(bm, ring, base, h, 0, 1)
    elif kind == "church":
        mats = [toon_material("church", PALETTE["church"]), toon_material("church_roof", PALETTE["church_roof"])]
        h = 9.0
        prism(bm, ring, base, h, 0, 1, roof="hip", roof_h=5.0)
    elif kind == "school":
        mats = [toon_material("school", PALETTE["school"]), toon_material("roof_flat", PALETTE["roof_flat"])]
        h = levels * 3.4
        prism(bm, ring, base, h, 0, 1, roof="parapet")
    elif kind == "hospital":
        mats = [toon_material("hospital", PALETTE["hospital"]), toon_material("roof_flat", PALETTE["roof_flat"])]
        h = levels * 3.4
        prism(bm, ring, base, h, 0, 1, roof="parapet")
    elif kind == "retail":
        mats = [toon_material("retail", PALETTE["retail"]), toon_material("roof_flat", PALETTE["roof_flat"])]
        h = 7.0
        prism(bm, ring, base, h, 0, 1, roof="parapet")
    else:
        col_hex = HOUSE_COLOURS[(w["id"] // 3) % len(HOUSE_COLOURS)]
        mats = [toon_material("house_%s" % col_hex[1:], col_hex), toon_material("roof_flat", PALETTE["roof_flat"])]
        h = levels * 3.0
        prism(bm, ring, base, h, 0, 1)
    mats += [toon_material("window", PALETTE["window"]),
             toon_material("window_lit", PALETTE["window_lit"], emissive=False),
             toon_material("balcony", PALETTE["balcony"]),
             toon_material("frame", PALETTE["frame"]),
             toon_material("door", PALETTE["door"]),
             toon_material("retail_band", PALETTE["retail_band"])]

    if kind == "apartments":
        window_grid(bm, ring, base, levels, 2, 4, 5, rng, balconies=True, door_mat=6)
    elif kind in ("school", "hospital"):
        window_grid(bm, ring, base, levels, 2, 4, 5, rng, spacing=3.6, win_w=2.2, win_h=1.6, door_mat=6)
    elif kind in ("house", "small"):
        window_grid(bm, ring, base, levels, 2, 4, 5, rng, spacing=4.0, win_w=1.1, win_h=1.1)
    elif kind == "retail":
        # coloured fascia band + shop windows on the ground floor
        for i in range(len(ring)):
            a, b = Vector(ring[i]), Vector(ring[(i + 1) % len(ring)])
            L = (b - a).length
            if L < 3:
                continue
            d = (b - a) / L
            nrm = Vector((d.y, -d.x))
            _quad(bm, (a + b) / 2 + nrm * 0.05, d, L - 0.4, 5.0, 6.4, 7)
            _quad(bm, (a + b) / 2 + nrm * 0.05, d, L * 0.8, 0.4, 3.6, 2)
    elif kind == "church":
        window_grid(bm, ring, base, 1, 2, 4, 5, rng, spacing=4.0, win_w=1.0, win_h=3.5)
        # bell tower with an onion-ish spire on the west end
        xs = [p[0] for p in ring]
        ys = [p[1] for p in ring]
        tx, ty = min(xs) + 4.5, (min(ys) + max(ys)) / 2
        sq = [(tx - 3, ty - 3), (tx + 3, ty - 3), (tx + 3, ty + 3), (tx - 3, ty + 3)]
        prism(bm, sq, 0, 22, 0, 1, roof="hip", roof_h=9.0)

    # Everything is built with outward normals already; recalculating them
    # flips the roofs of concave footprints.
    solid = [f for f in bm.faces if f not in _FLAT]
    hull = bm.verts.layers.deform.verify()
    for f in solid:
        for v in f.verts:
            v[hull][0] = 1.0
    _FLAT.clear()
    ob = new_object(name, bm, col, mats)
    ob.vertex_groups.new(name="hull")
    ob["osm_id"] = w["id"]
    ob["kind"] = kind
    ob["levels"] = levels
    mod = add_outline(ob, 0.12)
    mod.vertex_group = "hull"
    mod.thickness_vertex_group = 0.0
    return ob


# --------------------------------------------------------------------------
# Stage: trees, bushes and street props
# --------------------------------------------------------------------------
def _tree_protos():
    col = collection("M15_Prototypes")
    col.hide_render = True
    col.hide_viewport = True
    protos = {}

    def finish(name, bm, mats, outline=0.08):
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        ob = new_object(name, bm, col, mats)
        for p in ob.data.polygons:
            p.use_smooth = False
        add_outline(ob, outline)
        protos[name] = ob

    trunk = toon_material("trunk", PALETTE["trunk"])
    for key, leaf in (("round_a", "leaf_a"), ("round_b", "leaf_b"), ("round_c", "leaf_c")):
        if bpy.data.objects.get("M15_Tree_" + key):
            protos["M15_Tree_" + key] = bpy.data.objects["M15_Tree_" + key]
            continue
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=6, radius1=0.3, radius2=0.22, depth=3.0,
                              matrix=__import__("mathutils").Matrix.Translation((0, 0, 1.5)))
        for f in bm.faces:
            f.material_index = 0
        r = bmesh.ops.create_icosphere(bm, subdivisions=1, radius=2.6,
                                       matrix=__import__("mathutils").Matrix.Translation((0, 0, 4.6)))
        for v in r["verts"]:
            v.co.z = 4.6 + (v.co.z - 4.6) * 0.85
        for f in bm.faces:
            if f.verts[0] in r["verts"]:
                f.material_index = 1
        finish("M15_Tree_" + key, bm, [trunk, toon_material(leaf, PALETTE[leaf])])

    if not bpy.data.objects.get("M15_Tree_poplar"):
        bm = bmesh.new()
        M = __import__("mathutils").Matrix
        bmesh.ops.create_cone(bm, cap_ends=True, segments=6, radius1=0.25, radius2=0.2, depth=2.0,
                              matrix=M.Translation((0, 0, 1.0)))
        r = bmesh.ops.create_uvsphere(bm, u_segments=7, v_segments=6, radius=1.0,
                                      matrix=M.Translation((0, 0, 7.5)) @ M.Diagonal((1.6, 1.6, 6.0, 1.0)))
        for f in bm.faces:
            f.material_index = 1 if f.verts[0] in r["verts"] else 0
        finish("M15_Tree_poplar", bm, [trunk, toon_material("poplar", PALETTE["poplar"])])
    else:
        protos["M15_Tree_poplar"] = bpy.data.objects["M15_Tree_poplar"]

    if not bpy.data.objects.get("M15_Bush"):
        bm = bmesh.new()
        M = __import__("mathutils").Matrix
        r = bmesh.ops.create_icosphere(bm, subdivisions=1, radius=1.0,
                                       matrix=M.Translation((0, 0, 0.6)) @ M.Diagonal((1.4, 1.0, 0.75, 1.0)))
        finish("M15_Bush", bm, [toon_material("bush", PALETTE["bush"])], 0.05)
    else:
        protos["M15_Bush"] = bpy.data.objects["M15_Bush"]

    if not bpy.data.objects.get("M15_Lamp"):
        bm = bmesh.new()
        M = __import__("mathutils").Matrix
        bmesh.ops.create_cone(bm, cap_ends=True, segments=6, radius1=0.12, radius2=0.08, depth=7.0,
                              matrix=M.Translation((0, 0, 3.5)))
        _box(bm, Vector((0.7, 0)), Vector((1, 0)), Vector((0, 1)), 1.6, 0.25, 6.85, 7.05, 0)
        _box(bm, Vector((1.3, 0)), Vector((1, 0)), Vector((0, 1)), 0.6, 0.35, 6.7, 6.85, 1)
        finish("M15_Lamp", bm, [toon_material("metal", PALETTE["metal"]),
                                toon_material("lamp", PALETTE["lamp"], emissive=True)], 0.04)
    else:
        protos["M15_Lamp"] = bpy.data.objects["M15_Lamp"]

    if not bpy.data.objects.get("M15_Bench"):
        bm = bmesh.new()
        X, Y = Vector((1, 0)), Vector((0, 1))
        _box(bm, Vector((0, 0)), X, Y, 1.8, 0.5, 0.42, 0.5, 0)
        _box(bm, Vector((0, -0.22)), X, Y, 1.8, 0.08, 0.5, 0.95, 0)
        for sx in (-0.75, 0.75):
            _box(bm, Vector((sx, 0)), X, Y, 0.08, 0.45, 0.0, 0.42, 1)
        finish("M15_Bench", bm, [toon_material("bench", PALETTE["bench"]),
                                 toon_material("metal", PALETTE["metal"])], 0.03)
    else:
        protos["M15_Bench"] = bpy.data.objects["M15_Bench"]
    return protos


class Grid:
    """Coarse occupancy grid used to keep trees off roads and buildings."""

    def __init__(self, cell=2.0):
        self.cell = cell
        self.cells = set()

    def key(self, x, y):
        return (int(math.floor(x / self.cell)), int(math.floor(y / self.cell)))

    def mark_poly(self, pts, pad=0.0):
        """Rasterise a polygon at cell resolution, then grow it by *pad*."""
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        c = self.cell
        r = int(math.ceil(pad / c))
        i0, j0 = self.key(min(xs), min(ys))
        i1, j1 = self.key(max(xs), max(ys))
        hit = []
        for i in range(i0, i1 + 1):
            for j in range(j0, j1 + 1):
                if point_in_poly((i + 0.5) * c, (j + 0.5) * c, pts):
                    hit.append((i, j))
        if not hit:
            hit.append(self.key(sum(xs) / len(xs), sum(ys) / len(ys)))
        for i, j in hit:
            for di in range(-r, r + 1):
                for dj in range(-r, r + 1):
                    self.cells.add((i + di, j + dj))

    def mark_line(self, pts, half):
        c = self.cell
        for i in range(len(pts) - 1):
            a, b = Vector(pts[i]), Vector(pts[i + 1])
            L = (b - a).length
            steps = max(1, int(L / (c / 2)))
            for s in range(steps + 1):
                p = a.lerp(b, s / steps)
                r = -half
                while r <= half:
                    for q in (Vector((p.x + r, p.y)), Vector((p.x, p.y + r))):
                        self.cells.add(self.key(q.x, q.y))
                    r += c / 2

    def free(self, x, y):
        return self.key(x, y) not in self.cells


def stage_vegetation(root, density=1.0, seed=15):
    data = osm(root)
    protos = _tree_protos()
    col = collection("M15_Vegetation")
    clear_collection(col)
    props = collection("M15_Props")
    clear_collection(props)

    grid = Grid(2.0)
    green = Grid(4.0)
    for w in data.ways:
        t = w["tags"]
        pts = data.coords(w)
        if "building" in t:
            ring = clean_ring(pts)
            if len(ring) >= 3:
                grid.mark_poly(ring, pad=3.0)
        elif t.get("highway") in ROAD_STYLES:
            width, _, _, sw, _ = ROAD_STYLES[t["highway"]]
            grid.mark_line(pts, width / 2 + sw + 1.0)
        elif t.get("amenity") in ("parking", "fuel", "marketplace") or t.get("leisure") in (
                "pitch", "swimming_pool", "playground") or t.get("landuse") in ("industrial", "retail", "construction"):
            ring = clean_ring(pts)
            if len(ring) >= 3:
                grid.mark_poly(ring, pad=1.0)
        if t.get("leisure") == "park" or t.get("landuse") == "grass" or t.get("natural") == "wood":
            ring = clean_ring(pts)
            if len(ring) >= 3:
                green.mark_poly(ring)

    rng = random.Random(seed)
    placed = Grid(5.0)
    names = ["M15_Tree_round_a", "M15_Tree_round_b", "M15_Tree_round_c", "M15_Tree_poplar", "M15_Bush"]
    weights = [0.28, 0.24, 0.16, 0.14, 0.18]
    n_try = int(16000 * density)
    count = 0
    for _ in range(n_try):
        x = rng.uniform(XMIN, XMAX)
        y = rng.uniform(YMIN, YMAX)
        if not grid.free(x, y) or not placed.free(x, y):
            continue
        in_green = not green.free(x, y)
        if not in_green and rng.random() > 0.45:
            continue
        name = rng.choices(names, weights)[0]
        ob = bpy.data.objects.new(name.replace("M15_", "") + "_%d" % count, protos[name].data)
        _copy_outline(protos[name], ob)
        ob.location = (x, y, 0.0)
        ob.rotation_euler.z = rng.uniform(0, math.tau)
        s = rng.uniform(0.8, 1.25)
        ob.scale = (s, s, s * rng.uniform(0.9, 1.15))
        col.objects.link(ob)
        placed.cells.add(placed.key(x, y))
        count += 1

    # street lamps along main roads, benches along footways
    lamps = benches = 0
    for w in data.ways:
        hw = w["tags"].get("highway")
        if hw not in ("primary", "secondary", "tertiary", "residential", "footway"):
            continue
        width, _, _, sw, _ = ROAD_STYLES[hw]
        every = 32.0 if hw != "footway" else 45.0
        for run in clip_polyline(data.coords(w)):
            acc = every / 2
            for i in range(len(run) - 1):
                a, b = Vector(run[i]), Vector(run[i + 1])
                L = (b - a).length
                if L < 0.01:
                    continue
                d = (b - a) / L
                nrm = Vector((d.y, -d.x))
                while acc < L:
                    p = a + d * acc
                    if hw == "footway":
                        q = p + nrm * (width / 2 + 0.6)
                        ob = bpy.data.objects.new("Bench_%d" % benches, protos["M15_Bench"].data)
                        ob.rotation_euler.z = math.atan2(d.y, d.x) + math.pi
                        benches += 1
                    else:
                        q = p + nrm * (width / 2 + max(sw, 1.0) * 0.7)
                        ob = bpy.data.objects.new("Lamp_%d" % lamps, protos["M15_Lamp"].data)
                        ob.rotation_euler.z = math.atan2(-nrm.y, -nrm.x)
                        lamps += 1
                    _copy_outline(protos["M15_Bench" if hw == "footway" else "M15_Lamp"], ob)
                    ob.location = (q.x, q.y, 0.05)
                    props.objects.link(ob)
                    acc += every
                acc -= L
    return {"trees": count, "lamps": lamps, "benches": benches}


def _copy_outline(src, dst):
    for m in list(dst.modifiers):
        dst.modifiers.remove(m)
    sm = src.modifiers.get("Outline")
    if not sm:
        return
    m = dst.modifiers.new("Outline", "SOLIDIFY")
    for attr in ("thickness", "offset", "use_flip_normals", "use_rim", "use_even_offset", "use_quality_normals",
                 "material_offset", "material_offset_rim"):
        setattr(m, attr, getattr(sm, attr))


# --------------------------------------------------------------------------
# Stage: cameras (preview shots)
# --------------------------------------------------------------------------
def look_at(ob, target):
    d = Vector(target) - ob.location
    ob.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()


def stage_cameras(root):
    col = collection("M15_Cameras")
    clear_collection(col)
    shots = {
        "M15_Cam_Overview": ((-260, -520, 420), (150, 230, 0), 35),
        "M15_Cam_Birdseye": ((40, -60, 120), (170, 160, 0), 28),
        # behind-the-shoulder height, looking north up Strada Astronautilor
        "M15_Cam_ThirdPerson": ((172, 262, 3.2), (172, 345, 4.0), 22),
        "M15_Cam_Street": ((172, 262, 9.0), (172, 345, 2.0), 22),
    }
    for name, (loc, tgt, lens) in shots.items():
        cam = bpy.data.cameras.new(name)
        cam.lens = lens
        cam.clip_end = 3000
        ob = bpy.data.objects.new(name, cam)
        ob.location = loc
        look_at(ob, tgt)
        col.objects.link(ob)
    bpy.context.scene.camera = bpy.data.objects["M15_Cam_Overview"]
    return {"cameras": list(shots)}


def render_shot(cam_name, path, res=(1600, 900)):
    scn = bpy.context.scene
    scn.camera = bpy.data.objects[cam_name]
    scn.render.resolution_x, scn.render.resolution_y = res
    scn.render.resolution_percentage = 100
    scn.render.filepath = path
    bpy.ops.render.render(write_still=True)
    return path


STAGES = ["scene", "ground", "roads", "buildings", "vegetation", "cameras"]


def build_all(root):
    out = {}
    out["scene"] = stage_scene(root)
    out["ground"] = stage_ground(root)
    out["roads"] = stage_roads(root)
    out["buildings"] = stage_buildings(root)
    out["vegetation"] = stage_vegetation(root)
    out["cameras"] = stage_cameras(root)
    return out
