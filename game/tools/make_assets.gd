## Turns every prop model into a placeable scene in res://assets/: the mesh
## (saved to assets/meshes/), styled through StyledModel, with collision.
## The building details of the map (windows, balconies, air conditioners...)
## become scenes in res://assets/details/, without collision (like on the
## map) except the entrance stairs. The map editor lists these scenes, and
## they can be dragged into any level in the editor. The "_far" meshes
## (lighter trees and bushes for the distance) are left out.
##
##   godot --headless --path game --script res://tools/make_assets.gd
extends SceneTree

## glTF: the folder under res://assets/ its scenes go to
const SOURCES := {
	"res://levels/micro15/props.glb": "",
	"res://assets/source/street_kit.glb": "",
	"res://levels/micro15/details.glb": "details/",
}
## radius of a 3 m trunk cylinder; everything else gets its exact shape
const TRUNKS := {
	"tree_a": 0.35, "tree_b": 0.4, "tree_c": 0.3, "poplar": 0.3, "lamp": 0.15, "tree_pine": 0.5,
	"tree_birch": 0.25, "bollard": 0.09, "trash_bin": 0.22,
}
const NO_COLLISION := ["bush_a", "bush_b"]
const SOLID_DETAILS := ["entrance"]
## leafy things that are solid as a whole: their bounding box
const BOXES := ["hedge"]


func _init() -> void:
	DirAccess.make_dir_recursive_absolute("res://assets/meshes")
	DirAccess.make_dir_recursive_absolute("res://assets/details")
	var made := []
	for src: String in SOURCES:
		var root: Node = load(src).instantiate()
		for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
			if String(mi.name).ends_with("_far"):
				continue
			made.append(_make(String(mi.name), mi.mesh, SOURCES[src]))
		root.free()
	print("assets: ", made)
	quit()


func _make(asset: String, mesh: Mesh, folder: String) -> String:
	var mesh_path := "res://assets/meshes/%s.res" % asset
	ResourceSaver.save(mesh, mesh_path)
	mesh = load(mesh_path)
	var body := StaticBody3D.new()
	body.name = asset
	body.set_script(load("res://scripts/styled_model.gd"))
	var model := MeshInstance3D.new()
	model.name = "Model"
	model.mesh = mesh
	body.add_child(model)
	model.owner = body
	var detail := folder == "details/"
	if not asset in NO_COLLISION and (not detail or asset in SOLID_DETAILS):
		var shape := CollisionShape3D.new()
		shape.name = "Collision"
		if TRUNKS.has(asset):
			var cyl := CylinderShape3D.new()
			cyl.radius = TRUNKS[asset]
			cyl.height = 3.0
			shape.shape = cyl
			shape.position.y = 1.5
		elif asset in BOXES:
			var aabb := mesh.get_aabb()
			var box := BoxShape3D.new()
			box.size = aabb.size
			shape.shape = box
			shape.position = aabb.get_center()
		else:
			var shape_path := "res://assets/meshes/%s_shape.res" % asset
			ResourceSaver.save(mesh.create_trimesh_shape(), shape_path)
			shape.shape = load(shape_path)
		body.add_child(shape)
		shape.owner = body
	var packed := PackedScene.new()
	packed.pack(body)
	ResourceSaver.save(packed, "res://assets/%s%s.tscn" % [folder, asset])
	body.free()
	return folder + asset
