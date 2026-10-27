## Turns every prop model into a placeable scene in res://assets/: the mesh
## (saved to assets/meshes/), cel-shaded through StyledModel, with collision.
## The admin placement tool lists these scenes, and they can be dragged
## into any level in the editor.
##
##   godot --headless --path game --script res://tools/make_assets.gd
extends SceneTree

const SOURCES := ["res://levels/micro15/props.glb", "res://assets/source/street_kit.glb"]
## radius of a 3 m trunk cylinder; everything else gets its exact shape
const TRUNKS := {
	"tree_a": 0.35, "tree_b": 0.4, "tree_c": 0.3, "poplar": 0.3, "lamp": 0.15, "tree_pine": 0.5,
	"tree_birch": 0.25, "bollard": 0.09, "trash_bin": 0.22,
}
const NO_COLLISION := ["bush_a", "bush_b"]


func _init() -> void:
	DirAccess.make_dir_recursive_absolute("res://assets/meshes")
	var made := []
	for src: String in SOURCES:
		var root: Node = load(src).instantiate()
		for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
			made.append(_make(String(mi.name), mi.mesh))
		root.free()
	print("assets: ", made)
	quit()


func _make(asset: String, mesh: Mesh) -> String:
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
	if not asset in NO_COLLISION:
		var shape := CollisionShape3D.new()
		shape.name = "Collision"
		if TRUNKS.has(asset):
			var cyl := CylinderShape3D.new()
			cyl.radius = TRUNKS[asset]
			cyl.height = 3.0
			shape.shape = cyl
			shape.position.y = 1.5
		else:
			var shape_path := "res://assets/meshes/%s_shape.res" % asset
			ResourceSaver.save(mesh.create_trimesh_shape(), shape_path)
			shape.shape = load(shape_path)
		body.add_child(shape)
		shape.owner = body
	var packed := PackedScene.new()
	packed.pack(body)
	ResourceSaver.save(packed, "res://assets/%s.tscn" % asset)
	body.free()
	return asset
