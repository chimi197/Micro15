## Photo mode (V): the game holds still, the camera comes loose within a few
## metres of the boy, and a picture can be taken (click, Enter or A) into
## the scrapbook: user://photos/, listed in the save and the journal.
##
## While in it: mouse or right stick to aim, WASD / left stick to move the
## camera, Space / Ctrl to rise and sink, wheel or bumpers to zoom, Q / E to
## tilt, 1 to 5 for his expression, F to hide the boy, V or Esc to leave.
class_name PhotoMode
extends Node

const RANGE := 8.0                        # metres the camera may wander from the boy
const EXPRESSIONS := ["", "happy", "grin", "surprised", "focused", "squint"]

var player: Node3D
var hud: Hud
var active := false
var _cam: Camera3D
var _yaw := 0.0
var _pitch := 0.0
var _roll := 0.0
var _fov := 55.0
var _flash: ColorRect
var _hint: Label
var _layer: CanvasLayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_layer = CanvasLayer.new()
	_layer.layer = 6
	add_child(_layer)
	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_flash)
	_hint = Label.new()
	_hint.text = "Click to take a photo  ·  WASD move  ·  Space / Ctrl up / down  ·  wheel zoom  ·  Q / E tilt  ·  1-5 face  ·  F hide him  ·  V to leave"
	_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hint.position.y -= 24
	_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	_hint.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	_hint.add_theme_constant_override("shadow_offset_y", 1)
	_layer.add_child(_hint)
	_layer.visible = false


func enter() -> void:
	if active or player == null:
		return
	active = true
	get_tree().paused = true
	var game_cam: Camera3D = player.camera
	_cam = Camera3D.new()
	_cam.far = game_cam.far
	add_child(_cam)
	_cam.global_transform = game_cam.global_transform
	_fov = game_cam.fov
	_cam.fov = _fov
	var e := _cam.global_basis.get_euler()
	_pitch = e.x
	_yaw = e.y
	_roll = 0.0
	_cam.make_current()
	player.face.process_mode = Node.PROCESS_MODE_ALWAYS
	hud.set_visible_all(false)
	_layer.visible = true
	_hint.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func leave() -> void:
	if not active:
		return
	active = false
	player.body_mesh.visible = true
	player.face.process_mode = Node.PROCESS_MODE_INHERIT
	player.face.express("", 0.0)
	player.camera.make_current()
	_cam.queue_free()
	_layer.visible = false
	hud.set_visible_all(true)
	get_tree().paused = false


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	get_viewport().set_input_as_handled()
	if event is InputEventMouseMotion:
		var s: float = Save.setting("mouse_sensitivity")
		_yaw -= event.relative.x * s
		_pitch = clampf(_pitch - event.relative.y * s, -1.5, 1.5)
	elif event.is_action_pressed("photo") or event.is_action_pressed("pause"):
		leave()
	elif event.is_action_pressed("photo_zoom_in"):
		_fov = clampf(_fov - 3.0, 15.0, 90.0)
	elif event.is_action_pressed("photo_zoom_out"):
		_fov = clampf(_fov + 3.0, 15.0, 90.0)
	elif (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) \
			or event.is_action_pressed("ui_accept") or (event is InputEventJoypadButton and event.pressed
			and event.button_index == JOY_BUTTON_A):
		_take()
	elif event is InputEventKey and event.pressed and not event.echo:
		var k: int = event.physical_keycode
		if k >= KEY_1 and k <= KEY_5:
			var ex: String = EXPRESSIONS[k - KEY_0]
			player.face.express(ex, 9999.0)
		elif k == KEY_0:
			player.face.express("", 0.0)
		elif k == KEY_F:
			player.body_mesh.visible = not player.body_mesh.visible
		elif k == KEY_H:
			_hint.visible = not _hint.visible


func _process(delta: float) -> void:
	if not active:
		return
	var stick := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	_yaw -= stick.x * 2.0 * delta
	_pitch = clampf(_pitch - stick.y * 2.0 * delta, -1.5, 1.5)
	if Input.is_key_pressed(KEY_Q):
		_roll += delta * 0.6
	if Input.is_key_pressed(KEY_E):
		_roll -= delta * 0.6
	if Input.is_joy_button_pressed(0, JOY_BUTTON_LEFT_SHOULDER):
		_fov = clampf(_fov + 25.0 * delta, 15.0, 90.0)
	if Input.is_joy_button_pressed(0, JOY_BUTTON_RIGHT_SHOULDER):
		_fov = clampf(_fov - 25.0 * delta, 15.0, 90.0)
	_cam.global_basis = Basis.from_euler(Vector3(_pitch, _yaw, 0.0)) * Basis(Vector3.BACK, _roll)
	var move := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var up := (1.0 if Input.is_action_pressed("jump") else 0.0) - (1.0 if Input.is_action_pressed("crouch") else 0.0)
	var v := _cam.global_basis * Vector3(move.x, 0, move.y) + Vector3.UP * up
	var p := _cam.global_position + v * 2.5 * delta
	var centre: Vector3 = player.global_position + Vector3.UP * 1.0
	if p.distance_to(centre) > RANGE:
		p = centre + (p - centre).normalized() * RANGE
	p.y = maxf(p.y, player.global_position.y + 0.15)
	_cam.global_position = p
	_cam.fov = lerpf(_cam.fov, _fov, 1.0 - exp(-10.0 * delta))
	_flash.color.a = move_toward(_flash.color.a, 0.0, delta * 3.0)


func _take() -> void:
	_layer.visible = false
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	_layer.visible = true
	DirAccess.make_dir_recursive_absolute("user://photos")
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var file := "user://photos/micro15_%s.png" % stamp
	img.save_png(file)
	Save.add_photo(file, player.global_position)
	_flash.color.a = 0.7
	get_tree().call_group("sound", "play_at", "shutter", _cam.global_position, 1.0)
	hud.toast.call_deferred("Photo saved to the scrapbook")
