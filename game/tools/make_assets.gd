## Turns every prop model into a placeable scene in res://assets/: the mesh
## (saved to assets/meshes/), styled through StyledModel, with collision.
## The building details of the map (windows, balconies, air conditioners...)
## become scenes in res://assets/details/, without collision (like on the
## map) except the entrance stairs. The map editor lists these scenes, and
## they can be dragged into any level in the editor. A tree or bush with a
## "_far" mesh (a lighter one for the distance) switches to it past FAR_FROM,
## like the map's own, and small things stop drawing sooner than big ones.
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
	"tree_birch": 0.25, "bollard": 0.09, "trash_bin": 0.22, "utility_pole": 0.17, "crossing_sign": 0.04,
	"hydrant": 0.12,
}
const NO_COLLISION := ["bush_a", "bush_b", "manhole", "wall_sign", "block_number", "wall_lamp", "gas_pipe"]
const SOLID_DETAILS := ["entrance"]
## things that are solid as a whole: their bounding box
const BOXES := ["hedge", "kiosk", "mini_market", "drinks_fridge", "ice_cream_freezer", "recycling_bins",
	"electric_box", "advert_column"]
## where the "_far" mesh takes over, as on the map (Props.far_from)
const FAR_FROM := 70.0


func _init() -> void:
	DirAccess.make_dir_recursive_absolute("res://assets/meshes")
	DirAccess.make_dir_recursive_absolute("res://assets/details")
	var made := []
	for src: String in SOURCES:
		var root: Node = load(src).instantiate()
		var meshes := {}
		for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
			meshes[String(mi.name)] = mi.mesh
		for asset: String in meshes:
			if not asset.ends_with("_far"):
				made.append(_make(asset, meshes[asset], meshes.get(asset + "_far"), SOURCES[src]))
		root.free()
	print("assets: ", made)
	quit()


func _make(asset: String, mesh: Mesh, far_mesh: Mesh, folder: String) -> String:
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
	# How far it draws: building details as far as on the map, other things
	# by size, from 120 m for a bollard to 500 m for a tree or a shop.
	var aabb := mesh.get_aabb()
	var view_range := 450.0 if detail else clampf(80.0 * maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z)), 120.0, 500.0)
	model.visibility_range_end = view_range
	model.visibility_range_end_margin = 4.0
	if far_mesh:
		var far_path := "res://assets/meshes/%s_far.res" % asset
		ResourceSaver.save(far_mesh, far_path)
		var far := MeshInstance3D.new()
		far.name = "Far"
		far.mesh = load(far_path)
		far.visibility_range_begin = FAR_FROM
		far.visibility_range_begin_margin = 4.0
		far.visibility_range_end = view_range
		far.visibility_range_end_margin = 4.0
		model.visibility_range_end = FAR_FROM
		body.add_child(far)
		far.owner = body
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
