## Put on the root of an imported glTF scene (or any node with meshes under
## it) to draw it with the game's cel-shaded materials, in the editor too.
## With solid, its meshes also get trimesh collision when the game runs.
@tool
class_name StyledModel
extends Node3D

@export var solid := false


func _ready() -> void:
	# a scene opened on its own in the editor keeps its plain glTF colours,
	# so the cel-shaded copies are never saved into it
	if Engine.is_editor_hint() and get_tree().edited_scene_root == self:
		return
	WorldStyle.shared().apply(self)
	if solid and not Engine.is_editor_hint():
		for mi: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
			mi.create_trimesh_collision()
