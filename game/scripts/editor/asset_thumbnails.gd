## Little pictures of the placeable assets for the editor's asset browser,
## rendered one per frame in a world of their own (soft light, transparent
## background) the first time the browser opens.
class_name AssetThumbnails
extends Node

signal made(path: String, texture: Texture2D)

const SIZE := 112

var _viewport: SubViewport
var _camera: Camera3D
var _queue: Array[String] = []
var _busy := false
var done := {}                            # asset path: Texture2D


func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(SIZE, SIZE)
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.82, 0.86)
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_viewport.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 32, 0)
	sun.light_energy = 1.3
	sun.light_color = Color(1.0, 0.96, 0.9)
	_viewport.add_child(sun)
	_camera = Camera3D.new()
	_camera.fov = 30.0
	_viewport.add_child(_camera)


func request(paths: Array) -> void:
	if DisplayServer.get_name() == "headless":
		return
	for p: String in paths:
		if not done.has(p) and not p in _queue:
			_queue.append(p)
	if not _busy:
		_run()


func _run() -> void:
	_busy = true
	while not _queue.is_empty():
		var path: String = _queue.pop_front()
		var node: Node3D = load(path).instantiate()
		_viewport.add_child(node)
		var box := AABB()
		var first := true
		for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
			var b: AABB = mi.transform * mi.get_aabb()
			box = b if first else box.merge(b)
			first = false
		var radius := maxf(box.size.length() * 0.5, 0.2)
		var dir := Vector3(1.0, 0.65, 1.25).normalized()
		_camera.position = box.get_center() + dir * radius / sin(deg_to_rad(_camera.fov * 0.5)) * 1.02
		_camera.look_at(box.get_center())
		_camera.far = radius * 8.0 + 10.0
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		var img := _viewport.get_texture().get_image()
		node.queue_free()
		if img:
			var tex := ImageTexture.create_from_image(img)
			done[path] = tex
			made.emit(path, tex)
	_busy = false
