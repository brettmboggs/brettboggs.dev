# Converts printed-part STLs into web-ready GLBs for the /lab/parts viewer.
# Run headless:  blender -b --factory-startup -P tools/parts/convert.py -- <config.json>
#
# Per part: import one or more STLs, stack multi-piece assemblies vertically,
# scale mm to meters (true size in AR), smooth by angle, decimate anything
# heavier than ~150k triangles, give it a matte print material, export GLB.

import bpy
import json
import math
import sys

BONE = (0.545, 0.475, 0.343, 1.0)  # warm bone, linear-ish; reads right on paper
TARGET_TRIS = 150_000


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def import_stl(path):
    before = set(bpy.data.objects)
    bpy.ops.wm.stl_import(filepath=path)
    return [o for o in bpy.data.objects if o not in before]


def bounds_z(obj):
    corners = [obj.matrix_world @ v.co for v in obj.data.vertices]
    zs = [c.z for c in corners]
    return min(zs), max(zs)


def center_xy_floor(obj, floor_z):
    xs, ys, zs = [], [], []
    for v in obj.data.vertices:
        c = obj.matrix_world @ v.co
        xs.append(c.x)
        ys.append(c.y)
        zs.append(c.z)
    cx = (min(xs) + max(xs)) / 2
    cy = (min(ys) + max(ys)) / 2
    obj.location.x -= cx
    obj.location.y -= cy
    obj.location.z += floor_z - min(zs)
    bpy.context.view_layer.update()


def polish(obj, mat):
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    tris = len(obj.data.loop_triangles) or len(obj.data.polygons) * 2
    if tris > TARGET_TRIS:
        mod = obj.modifiers.new("dec", "DECIMATE")
        mod.ratio = TARGET_TRIS / tris
        bpy.ops.object.modifier_apply(modifier=mod.name)
    try:
        bpy.ops.object.shade_smooth_by_angle(angle=math.radians(30))
    except Exception:
        bpy.ops.object.shade_smooth()
    obj.data.materials.clear()
    obj.data.materials.append(mat)


def make_material():
    mat = bpy.data.materials.new("print")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = BONE
    bsdf.inputs["Roughness"].default_value = 0.55
    bsdf.inputs["Metallic"].default_value = 0.0
    return mat


def convert(part):
    reset()
    mat = make_material()
    floor = 0.0
    for src in part["inputs"]:
        objs = import_stl(src)
        for obj in objs:
            polish(obj, mat)
            center_xy_floor(obj, floor)
            lo, hi = bounds_z(obj)
            floor = hi + part.get("gap_mm", 8.0)
    # mm to meters, true scale for AR. locations must shrink with the meshes,
    # or stacked assemblies end up kilometers apart
    for obj in bpy.data.objects:
        obj.select_set(True)
        obj.scale = (0.001, 0.001, 0.001)
        obj.location = obj.location * 0.001
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.ops.export_scene.gltf(filepath=part["out"], export_format="GLB", use_selection=True)
    print(f"WROTE {part['out']}")


config_path = sys.argv[sys.argv.index("--") + 1]
with open(config_path) as f:
    for part in json.load(f):
        convert(part)
print("DONE")
