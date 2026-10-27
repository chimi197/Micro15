## Style test: one corner of Micro 15 with drawn textures, billboard sprites,
## toon shading and ink outlines.
##
## Run normally to walk around. Run with `-- --shots` to save preview
## screenshots to ../docs/renders/ and quit.
extends Node3D

const SHADOW_TINT := Color(0.70, 0.72, 0.90)
const TEXTURES := {
	"facade_mint": "res://art/textures/facade_mint.png",
	"facade_peach": "res://art/textures/facade_peach.png",
	"facade_lemon": "res://art/textures/facade_lemon.png",
	"facade_sky": "res://art/textures/facade_sky.png",
	"facade_cream": "res://art/textures/facade_cream.png",
	"facade_lilac": "res://art/textures/facade_lilac.png",
	"facade_entrance": "res://art/textures/facade_entrance.png",
	"roof": "res://art/textures/roof.png",
	"grass": "res://art/textures/grass.png",
	"asphalt": "res://art/textures/asphalt.png",
	"pavement": "res://art/textures/pavement.png",
}
const FLAT_COLOURS := {
	"grass_park": Color("#8cc453"),
	"sand": Color("#ebcb7a"),
	"pitch": Color("#5db55a"),
}
# sprite: [texture, height in metres]
const SPRITES := {
	"tree_round_a": ["res://art/sprites/tree_round_a.png", 9.0],
	"tree_round_b": ["res://art/sprites/tree_round_b.png", 8.5],
	"tree_round_c": ["res://art/sprites/tree_round_c.png", 10.0],
	"tree_poplar": ["res://art/sprites/tree_poplar.png", 16.0],
	"bush": ["res://art/sprites/bush_a.png", 1.6],
	"bush_b": ["res://art/sprites/bush_b.png", 1.6],
	"lamp": ["res://art/sprites/lamp.png", 7.5],
	"bench": ["res://art/sprites/bench.png", 1.0],
}
# name: [camera position, look-at target, player position or null]
const SHOTS := {
	"style_test_street": [Vector3(14, 2.6, 13.5), Vector3(100, 3.5, 6), Vector3(18.5, 0.1, 9.5)],
	"style_test_aerial": [Vector3(-95, 60, 95), Vector3(10, 0, -10), null],
	"style_test_alley": [Vector3(-66, 2.4, -12), Vector3(-70, 4, -80), Vector3(-68, 0.1, -17)],
	"style_test_high": [Vector3(60, 18, 50), Vector3(0, 4, -20), null],
}

var player: CharacterBody3D


func _ready() -> void:
	_setup_environment()
	_load_corner()
	_spawn_props()
	_add_ink_outline_pass()
	player = preload("res://scripts/player.gd").new()
	player.position = Vector3(18, 0.2, 9)
	add_child(player)
	if "--shots" in OS.get_cmdline_user_args():
		_take_shots.call_deferred()


func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#bfe6f7")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = SHADOW_TINT
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.fog_enabled = true
	env.fog_light_color = Color("#bfe6f7")
	env.fog_density = 0.0008
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.shadow_blur = 0.0
	sun.directional_shadow_max_distance = 250.0
	add_child(sun)


func _toon(tex_path: String, colour := Color.WHITE) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/toon.gdshader")
	mat.set_shader_parameter("shadow_tint", SHADOW_TINT)
	mat.set_shader_parameter("tint", colour)
	if tex_path != "":
		mat.set_shader_parameter("albedo_tex", load(tex_path))
	return mat


func _load_corner() -> void:
	# grass beyond the edge of the exported corner
	var outer := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(2000, 2000)
	outer.mesh = plane
	var grass := _toon(TEXTURES["grass"])
	grass.set_shader_parameter("uv_scale", Vector2(250, 250))
	outer.material_override = grass
	outer.position.y = -0.03
	add_child(outer)

	var corner: Node3D = load("res://levels/style_test/corner.glb").instantiate()
	add_child(corner)
	var cache := {}
	for mi: MeshInstance3D in corner.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(s)
			var mname := src.resource_name if src else ""
			if not cache.has(mname):
				if TEXTURES.has(mname):
					cache[mname] = _toon(TEXTURES[mname])
				else:
					cache[mname] = _toon("", FLAT_COLOURS.get(mname, Color("#9ccb5b")))
			mi.set_surface_override_material(s, cache[mname])
		mi.create_trimesh_collision()


func _spawn_props() -> void:
	var f := FileAccess.open("res://levels/style_test/props.json", FileAccess.READ)
	var props: Array = JSON.parse_string(f.get_as_text())
	var rng := RandomNumberGenerator.new()
	rng.seed = 15
	var textures := {}
	for p in props:
		var kind: String = p["type"]
		if kind == "bush" and rng.randf() < 0.5:
			kind = "bush_b"
		if not SPRITES.has(kind):
			continue
		var info: Array = SPRITES[kind]
		if not textures.has(kind):
			textures[kind] = load(info[0])
		var tex: Texture2D = textures[kind]
		var spr := Sprite3D.new()
		spr.texture = tex
		spr.pixel_size = info[1] * float(p["scale"]) / tex.get_height()
		spr.offset = Vector2(0, tex.get_height() / 2.0)
		spr.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		spr.shaded = false
		spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		spr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		spr.flip_h = rng.randf() < 0.5 and kind.begins_with("tree")
		var pos: Array = p["pos"]
		spr.position = Vector3(pos[0], 0.0, pos[2])
		add_child(spr)


func _add_ink_outline_pass() -> void:
	var quad := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(2, 2)
	quad.mesh = mesh
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/ink_outline.gdshader")
	quad.material_override = mat
	quad.extra_cull_margin = 16384.0
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(quad)


func _take_shots() -> void:
	player.set_physics_process(false)
	var cam := Camera3D.new()
	cam.fov = 55
	cam.far = 2000
	add_child(cam)
	cam.make_current()
	var out_dir := ProjectSettings.globalize_path("res://").path_join("../docs/renders")
	DirAccess.make_dir_recursive_absolute(out_dir)
	for shot_name in SHOTS:
		var shot: Array = SHOTS[shot_name]
		cam.position = shot[0]
		cam.look_at(shot[1])
		player.visible = shot[2] != null
		if shot[2] != null:
			player.position = shot[2]
		for i in 20:
			await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		img.save_png(out_dir.path_join(shot_name + ".png"))
	get_tree().quit()
