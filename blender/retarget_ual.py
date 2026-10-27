"""Retargets motion-captured style animations from Quaternius' Universal
Animation Library 1 and 2 (CC0, tools/downloads/ual, see
tools/get_animations.py) onto the boy's rig.

Each target bone follows the world-space rotation of its source bone,
measured from a rest pose in which the boy's bone is first turned to point
the same way as the source bone (so the source's T-pose and the boy's
relaxed rest pose line up). The hips move by the source's hips motion
scaled to the boy's leg length, and each clip is lifted or lowered so its
lowest foot contact touches the ground.
"""
import json
import math
import os
import struct

import bpy
from mathutils import Matrix, Vector

UAL_FILES = ("UAL1.glb", "UAL2.glb")
SIDES = (("L", "l"), ("R", "r"))


def _map_ual1():
    m = {"hips": "DEF-hips", "spine": "DEF-spine.001", "spine1": "DEF-spine.002", "chest": "DEF-spine.003",
         "neck": "DEF-neck", "head": "DEF-head"}
    for s, _ in SIDES:
        for kid, src in (("shoulder", "shoulder"), ("upper_arm", "upper_arm"), ("forearm", "forearm"),
                         ("hand", "hand"), ("thigh", "thigh"), ("shin", "shin"), ("foot", "foot"), ("toe", "toe")):
            m[kid + "." + s] = "DEF-%s.%s" % (src, s)
        m["fingers." + s] = "DEF-f_middle.01." + s
    return m


def _map_ual2():
    m = {"hips": "pelvis", "spine": "spine_01", "spine1": "spine_02", "chest": "spine_03", "neck": "neck_01",
         "head": "Head"}
    for s, t in SIDES:
        for kid, src in (("shoulder", "clavicle"), ("upper_arm", "upperarm"), ("forearm", "lowerarm"),
                         ("hand", "hand"), ("thigh", "thigh"), ("shin", "calf"), ("foot", "foot"), ("toe", "ball"),
                         ("fingers", "middle_01")):
            m[kid + "." + s] = "%s_%s" % (src, t)
    return m


BONE_MAPS = {"UAL1.glb": _map_ual1(), "UAL2.glb": _map_ual2()}
HIPS = {"UAL1.glb": "DEF-hips", "UAL2.glb": "pelvis"}
ARM_CHAIN = ("upper_arm", "forearm", "hand", "fingers")


def load_library(root):
    """Imports both libraries once into a scene of their own; returns
    {file: armature object}."""
    scn = bpy.data.scenes.get("UAL") or bpy.data.scenes.new("UAL")
    scn.render.fps = 30
    rigs = {o["ual_src"]: o for o in scn.objects if o.type == "ARMATURE" and "ual_src" in o}
    missing = [f for f in UAL_FILES if f not in rigs]
    if missing:
        prev = bpy.context.window.scene
        bpy.context.window.scene = scn
        try:
            for f in missing:
                before = set(bpy.data.objects)
                bpy.ops.import_scene.gltf(filepath=os.path.join(root, "tools", "downloads", "ual", f))
                for o in set(bpy.data.objects) - before:
                    if o.type == "ARMATURE":
                        o["ual_src"] = f
                        rigs[f] = o
                    else:
                        bpy.data.objects.remove(o)      # the mannequin meshes only slow sampling down
        finally:
            bpy.context.window.scene = prev
    for f, rig in rigs.items():
        durations = _durations(os.path.join(root, "tools", "downloads", "ual", f))
        for a in bpy.data.actions:
            name = a.name.split(".")[0]
            if name in durations and a.slots and a.slots[0].identifier == "OB" + rig.name and durations[name] > 0:
                a["ual_fps"] = (a.frame_range[1] - a.frame_range[0]) / durations[name]
    return scn, rigs


def _durations(path):
    """Length in seconds of every animation in a .glb."""
    with open(path, "rb") as fh:
        head = fh.read(20)
        js = json.loads(fh.read(struct.unpack("<I", head[12:16])[0]))
    return {a["name"]: max(js["accessors"][s["input"]]["max"][0] for s in a["samplers"])
            for a in js.get("animations", [])}


def _action_for(rig, name):
    """The library action called name that animates this rig."""
    for a in bpy.data.actions:
        if a.name.split(".")[0] == name and a.slots and a.slots[0].identifier == "OB" + rig.name:
            return a
    raise KeyError("no action %s for %s" % (name, rig.name))


def sample(scn, rig, action_name, fps=30, speed=1.0, start=0.0, end=None):
    """Armature-space rotations of the source bones and the hips position,
    sampled at fps from the action (keyed at the scene rate it was
    imported with)."""
    act = _action_for(rig, action_name)
    src_fps = act.get("ual_fps", 24.0)
    ad = rig.animation_data_create()
    ad.use_nla = False
    ad.action = act
    ad.action_slot = act.slots[0]
    f0, f1 = act.frame_range
    t_end = (f1 - f0) / src_fps if end is None else end
    n = max(1, round((t_end - start) / speed * fps))
    frames = []
    hips = HIPS[rig["ual_src"]]
    for k in range(n + 1):
        t = start + k / n * (t_end - start)
        f = f0 + t * src_fps
        scn.frame_set(int(math.floor(f)), subframe=f - math.floor(f))
        frames.append({"rot": {pb.name: (rig.matrix_world @ pb.matrix).to_quaternion() for pb in rig.pose.bones},
                       "hips": rig.matrix_world @ rig.pose.bones[hips].head})
    rest = {b.name: (rig.matrix_world.to_quaternion() @ b.matrix_local.to_quaternion()) for b in rig.data.bones}
    rest_hips = rig.matrix_world @ rig.data.bones[hips].head_local
    ad.action = None
    return frames, rest, rest_hips


def retarget(kid_arm, frames, src_rest, src_rest_hips, src_file, leg_ratio, arm_out=0.0, head_up=0.0):
    """Per frame: {kid bone: local quaternion} and the hips location (bone
    space), for the kid armature's rest pose. arm_out holds the arms that
    much further from the body, head_up tilts the head up (the boy's head is
    much bigger than the adult source's, so the same tilt looks droopy)."""
    bmap = BONE_MAPS[src_file]
    bones = kid_arm.data.bones
    rest = {b.name: b.matrix_local.to_quaternion() for b in bones}
    # rest of each kid bone turned to point along its source bone
    aligned = {}
    for kb, sb in bmap.items():
        t_dir = bones[kb].matrix_local.to_3x3() @ Vector((0, 1, 0))
        s_dir = src_rest[sb] @ Vector((0, 1, 0))
        aligned[kb] = t_dir.rotation_difference(s_dir) @ rest[kb]
    out = []
    order = [b.name for b in bones]          # parents come before children
    for fr in frames:
        world = {}
        for name in order:
            b = bones[name]
            if name in bmap:
                sb = bmap[name]
                world[name] = fr["rot"][sb] @ src_rest[sb].inverted() @ aligned[name]
            elif b.parent:
                world[name] = world[b.parent.name] @ rest[b.parent.name].inverted() @ rest[name]
            else:
                world[name] = rest[name]
        if arm_out:
            for s, k in (("L", -1), ("R", 1)):
                q = Matrix.Rotation(k * arm_out, 3, "Y").to_quaternion()
                for part in ARM_CHAIN:
                    world[part + "." + s] = q @ world[part + "." + s]
        if head_up:
            world["head"] = Matrix.Rotation(-head_up, 3, "X").to_quaternion() @ world["head"]
        local = {}
        for name in order:
            b = bones[name]
            if b.parent:
                p = b.parent.name
                local[name] = (rest[name].inverted() @ rest[p] @ world[p].inverted() @ world[name]).normalized()
            else:
                local[name] = (rest[name].inverted() @ world[name]).normalized()
        delta = (fr["hips"] - src_rest_hips) * leg_ratio
        out.append((local, delta))
    return out


def forward_kinematics(kid_arm, local, delta):
    """Armature-space 4x4 matrices of every kid bone for one pose."""
    mats = {}
    for b in kid_arm.data.bones:
        basis = local[b.name].to_matrix().to_4x4()
        if b.name == "hips":
            basis = Matrix.Translation(b.matrix_local.to_3x3().inverted() @ delta) @ basis
        if b.parent:
            mats[b.name] = mats[b.parent.name] @ b.parent.matrix_local.inverted() @ b.matrix_local @ basis
        else:
            mats[b.name] = b.matrix_local @ basis
    return mats
