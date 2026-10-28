## Admin and modding tool (autoload "Admin"). It only exists when the game
## runs from the Godot editor (the "editor" feature), never in exported
## builds for players.
##
## F1 shows the admin bar. Then:
##   B           build mode: pick an asset from the list (res://assets/),
##               left click places it on whatever is under the mouse,
##               wheel or Q/E turns it, Shift+wheel or Z/X scales it,
##               G snaps to a 0.5 m grid, Delete removes the thing under
##               the mouse (placed or part of the map: trees, bushes,
##               lamps, benches), middle click copies it, Ctrl+Z undoes.
##               Hold the right mouse button to look around.
##               Two tools sit at the top of the list:
##                 remove tool  left click removes what is under the mouse
##                 grass brush  hold left to grow grass, Shift+left to
##                              clear it, wheel or Z/X for the brush size
##   N           noclip: fly through everything (Space up, Ctrl down,
##               Shift fast)
##   T           teleport to the point under the mouse / screen centre
##   [ ]         movement speed down / up
##   , .         time of day back / on by half an hour (moves the sun)
##   /           day cycle running / stopped; Shift+, . slower / faster
##   F2 / F3     ink lines / 3D grass on or off
##   F12         screenshot to screenshots/
##
## Placed things go into the level's "Placed" scene (for Micro 15,
## levels/micro15/placed.tscn), saved after every change, so they are part
## of the level and can be moved or deleted in the editor as well. Map
## props that were removed are listed in levels/micro15/removed_props.json
## and painted grass in levels/micro15/grass_paint.json.
extends Node

const ASSETS_DIR := "res://assets/"
const ROTATE_STEP := PI / 12.0
const GRID := 0.5
const TOOLS := ["erase", "grass"]
const TOOL_NAMES := ["[ remove tool ]", "[ grass brush ]"]
const ERASE_RADIUS := 1.5
const HELP := "F1 hide   B build   N noclip   T teleport   [ ] speed   , . time   / day cycle   F2 ink   F3 grass   F12 screenshot"
const BUILD_HELP := "click place   wheel/Q E turn   shift+wheel/Z X scale   G grid   Del remove   middle copy   ctrl+Z undo   hold right mouse to look"
const ERASE_HELP := "click remove (placed things, trees, bushes, lamps, benches)   ctrl+Z undo   hold right mouse to look"
const GRASS_HELP := "hold left grow grass   shift+left clear grass   wheel/Z X brush size   ctrl+Z undo   hold right mouse to look"

var enabled := OS.has_feature("editor")
var active := false
var building := false

var _layer: CanvasLayer
var _label: Label
var _palette: ItemList
var _assets: PackedStringArray = []
var _ghost: Node3D
var _ghost_asset := ""
var _yaw := 0.0
var _scale := 1.0
var _snap := false
var _tool := ""                          # "" places _ghost_asset, else one of TOOLS
var _brush := 3.0                        # grass brush radius, metres
var _ring: MeshInstance3D                # shows the tool's reach on the ground
var _painting := 0                       # 1 growing grass, -1 clearing it
var _last_dab := Vector3.INF
var _stroke_start := 0
var _undo: Array = []                    # ["add", node], ["remove", scene path, transform, name],
                                         # ["prop", scatter, prototype, position], ["grass", field, strokes before]
var _message := ""
var _message_time := 0.0


func _ready() -> void:
	if not enabled:
		set_process(false)
		set_process_input(false)
		return
	_layer = CanvasLayer.new()
	_layer.layer = 50
	_layer.visible = false
	add_child(_layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(12, 12)
	_layer.add_child(panel)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 15)
	panel.add_child(_label)
	_palette = ItemList.new()
	_palette.position = Vector2(12, 140)
	_palette.size = Vector2(220, 520)
	_palette.visible = false
	_palette.focus_mode = Control.FOCUS_NONE
	_palette.item_selected.connect(_on_palette)
	_layer.add_child(_palette)
	for f in DirAccess.get_files_at(ASSETS_DIR):
		if f.ends_with(".tscn"):
			_assets.append(f.get_basename())
	_assets.sort()
	for t in TOOL_NAMES:
		_palette.add_item(t)
	for a in _assets:
		_palette.add_item(a.replace("_", " "))


func _process(delta: float) -> void:
	if not active:
		return
	_message_time -= delta
	var player := _player()
	var lines := ["ADMIN   " + HELP]
	if building and _tool == "erase":
		lines.append("REMOVE   " + ERASE_HELP)
	elif building and _tool == "grass":
		lines.append("GRASS   " + GRASS_HELP)
		lines.append("brush %.1f m" % _brush)
	elif building:
		lines.append("BUILD   " + BUILD_HELP)
		lines.append("asset: %s   turn %d°   scale %.2f   grid %s" % [_ghost_asset.get_file().get_basename(),
				roundi(rad_to_deg(_yaw)), _scale, "on" if _snap else "off"])
	var cycle := _sun_cycle()
	if cycle:
		lines.append("time %s   day cycle %s (a day takes %s min)" % [cycle.clock(),
				"running" if cycle.running else "stopped", str(snappedf(cycle.day_minutes, 0.1))])
	if player:
		lines.append("pos %s   speed x%.1f   noclip %s   %d fps" % [player.global_position.snapped(Vector3.ONE * 0.1),
				player.speed_multiplier, "on" if player.noclip else "off", Engine.get_frames_per_second()])
	if _message_time > 0.0:
		lines.append(_message)
	_label.text = "\n".join(lines)
	if building:
		_update_ghost()
		if _painting != 0:
			_paint_grass()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F1:
			_set_active(not active)
			get_viewport().set_input_as_handled()
			return
		if active and _key(event):
			get_viewport().set_input_as_handled()
			return
	if building:
		_build_input(event)


func _set_active(on: bool) -> void:
	active = on
	_layer.visible = on
	if not on and building:
		_set_building(false)


func _key(event: InputEventKey) -> bool:
	var player := _player()
	match event.keycode:
		KEY_B:
			_set_building(not building)
		KEY_N:
			if player:
				player.set_noclip(not player.noclip)
				player.spring_arm.collision_mask = 0 if player.noclip else 1
				_say("noclip " + ("on" if player.noclip else "off"))
		KEY_T:
			var hit := _ray()
			if player and hit:
				player.global_position = hit.position + Vector3.UP * 0.2
				player.velocity = Vector3.ZERO
				_say("teleported to %s" % hit.position.snapped(Vector3.ONE * 0.1))
		KEY_BRACKETLEFT, KEY_BRACKETRIGHT:
			if player:
				var f := 0.5 if event.keycode == KEY_BRACKETLEFT else 2.0
				player.speed_multiplier = clampf(player.speed_multiplier * f, 0.25, 16.0)
		KEY_COMMA, KEY_PERIOD:
			var later := event.keycode == KEY_PERIOD
			var cycle := _sun_cycle()
			if cycle and event.shift_pressed:
				cycle.day_minutes = clampf(cycle.day_minutes * (0.5 if later else 2.0), 0.5, 24.0 * 60.0)
				_say("a day takes %s min" % str(snappedf(cycle.day_minutes, 0.1)))
				return true
			if cycle:
				cycle.shift(0.5 if later else -0.5)
				return true
			var sun := get_tree().current_scene.find_child("Sun", true, false) as DirectionalLight3D
			if sun == null:
				sun = get_tree().current_scene.find_children("*", "DirectionalLight3D", true, false).front()
			if sun:
				var step := deg_to_rad(5.0 if event.keycode == KEY_COMMA else -5.0)
				sun.rotation.x = clampf(sun.rotation.x + step, deg_to_rad(-85.0), deg_to_rad(-8.0))
		KEY_SLASH:
			var cycle := _sun_cycle()
			if cycle:
				cycle.running = not cycle.running
				_say("day cycle " + ("running" if cycle.running else "stopped"))
		KEY_F2:
			_toggle("InkOutline")
		KEY_F3:
			_toggle("Grass")
		KEY_F12:
			var dir := ProjectSettings.globalize_path("res://").path_join("../screenshots")
			DirAccess.make_dir_recursive_absolute(dir)
			var path := dir.path_join(Time.get_datetime_string_from_system().replace(":", "-") + ".png")
			get_viewport().get_texture().get_image().save_png(path)
			_say("saved " + path)
		_:
			return building and _build_key(event)
	return true


func _toggle(node_name: String) -> void:
	var n := get_tree().current_scene.find_child(node_name, true, false) as Node3D
	if n:
		n.visible = not n.visible
		_say("%s %s" % [node_name, "on" if n.visible else "off"])


func _say(text: String) -> void:
	_message = text
	_message_time = 3.0


func _sun_cycle() -> SunCycle:
	var scene := get_tree().current_scene
	return scene.get_node_or_null("SunCycle") as SunCycle if scene else null


# ----------------------------------------------------------------------------
# Build mode
# ----------------------------------------------------------------------------
func _set_building(on: bool) -> void:
	building = on
	_palette.visible = on
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if on else Input.MOUSE_MODE_CAPTURED
	if on and _tool.is_empty():
		if _ghost_asset.is_empty() and not _assets.is_empty():
			_pick(ASSETS_DIR + _assets[0] + ".tscn")
		elif not _ghost_asset.is_empty():
			_pick(_ghost_asset)
	if not on:
		_end_painting()
		if _ghost:
			_ghost.queue_free()
			_ghost = null
		if _ring:
			_ring.queue_free()
			_ring = null


func _on_palette(i: int) -> void:
	if i < TOOLS.size():
		_pick_tool(TOOLS[i])
	else:
		_pick(ASSETS_DIR + _assets[i - TOOLS.size()] + ".tscn")


func _pick_tool(tool: String) -> void:
	_tool = tool
	if _ghost:
		_ghost.queue_free()
		_ghost = null
	_palette.select(TOOLS.find(tool))


func _pick(path: String) -> void:
	_tool = ""
	_ghost_asset = path
	if _ghost:
		_ghost.queue_free()
	_ghost = load(path).instantiate()
	for shape: CollisionShape3D in _ghost.find_children("*", "CollisionShape3D", true, false):
		shape.disabled = true
	if _ghost is CollisionObject3D:
		(_ghost as CollisionObject3D).collision_layer = 0
	get_tree().current_scene.add_child(_ghost)
	var i := _assets.find(path.get_file().get_basename())
	if i >= 0:
		_palette.select(i + TOOLS.size())


func _update_ghost() -> void:
	_update_ring()
	if _ghost == null:
		return
	var hit := _ray()
	_ghost.visible = not hit.is_empty()
	if hit:
		_ghost.global_transform = _placement(hit.position)


func _placement(p: Vector3) -> Transform3D:
	if _snap:
		p.x = snappedf(p.x, GRID)
		p.z = snappedf(p.z, GRID)
	return Transform3D(Basis(Vector3.UP, _yaw).scaled(Vector3.ONE * _scale), p)


func _build_key(event: InputEventKey) -> bool:
	if event.ctrl_pressed and event.keycode == KEY_Z:
		_undo_last()
		return true
	if _tool == "grass" and event.keycode in [KEY_Z, KEY_X]:
		_brush = clampf(_brush * (0.8 if event.keycode == KEY_Z else 1.25), 0.5, 20.0)
		return true
	match event.keycode:
		KEY_Q, KEY_E:
			_yaw = wrapf(_yaw + (ROTATE_STEP if event.keycode == KEY_Q else -ROTATE_STEP), -PI, PI)
		KEY_Z, KEY_X:
			_scale = clampf(_scale * (0.9 if event.keycode == KEY_Z else 1.1), 0.2, 5.0)
		KEY_G:
			_snap = not _snap
		KEY_DELETE, KEY_BACKSPACE:
			_remove_under_mouse()
		KEY_ESCAPE:
			_set_building(false)
		_:
			return false
	return true


func _build_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_end_painting()
		if _palette.get_global_rect().has_point(event.position):
			return
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_RIGHT:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if mb.pressed else Input.MOUSE_MODE_VISIBLE
			MOUSE_BUTTON_LEFT:
				if mb.pressed and _tool == "grass":
					_start_painting(-1 if mb.shift_pressed else 1)
				elif mb.pressed and _tool == "erase":
					_remove_under_mouse()
				elif mb.pressed:
					_place()
			MOUSE_BUTTON_MIDDLE:
				if mb.pressed:
					_copy_under_mouse()
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					var up := mb.button_index == MOUSE_BUTTON_WHEEL_UP
					if _tool == "grass":
						_brush = clampf(_brush * (1.1 if up else 0.9), 0.5, 20.0)
					elif mb.shift_pressed:
						_scale = clampf(_scale * (1.05 if up else 0.95), 0.2, 5.0)
					else:
						_yaw = wrapf(_yaw + (ROTATE_STEP if up else -ROTATE_STEP), -PI, PI)
		get_viewport().set_input_as_handled()


func _place() -> void:
	var hit := _ray()
	if hit.is_empty() or _ghost_asset.is_empty():
		return
	var root := _placed_root()
	var node: Node3D = load(_ghost_asset).instantiate()
	node.name = _ghost_asset.get_file().get_basename()
	root.add_child(node, true)
	node.owner = root
	node.global_transform = _placement(hit.position)
	_undo.append(["add", node])
	_save()


func _placed_under_mouse() -> Node3D:
	var hit := _ray()
	if hit.is_empty() or not hit.collider is Node:
		return null
	var root := _placed_root()
	var n: Node = hit.collider
	while n and n.get_parent() != root:
		n = n.get_parent()
	return n as Node3D


## Removes the placed thing under the mouse, or else the nearest map prop
## (tree, bush, lamp, bench) within ERASE_RADIUS of the point.
func _remove_under_mouse() -> void:
	var n := _placed_under_mouse()
	if n:
		_undo.append(["remove", n.scene_file_path, n.transform, n.name])
		n.get_parent().remove_child(n)
		n.queue_free()
		_save()
		return
	var hit := _ray()
	if hit:
		for scatter in _prop_scatters():
			var removed: Array = scatter.remove_near(hit.position, ERASE_RADIUS)
			if not removed.is_empty():
				_undo.append(["prop", scatter, removed[0], removed[1]])
				_say("removed %s (saved to %s)" % [removed[0], scatter.removed_file])
				return
	_say("nothing to remove under the mouse")


func _prop_scatters() -> Array[Scatter]:
	var out: Array[Scatter] = []
	for n in get_tree().current_scene.find_children("*", "Node3D", true, false):
		if n is Scatter and n.format == "props":
			out.append(n)
	return out


func _grass_field() -> GrassField:
	for n in get_tree().current_scene.find_children("*", "Node3D", true, false):
		if n is GrassField:
			return n
	return null


# Grass brush: one undo step per press of the mouse button.
func _start_painting(mode: int) -> void:
	var field := _grass_field()
	if field == null:
		_say("this level has no grass")
		return
	_painting = mode
	_stroke_start = field.stroke_count()
	_last_dab = Vector3.INF
	_paint_grass()


func _paint_grass() -> void:
	var field := _grass_field()
	var hit := _ray()
	if field == null or hit.is_empty():
		return
	var p: Vector3 = hit.position
	if _last_dab != Vector3.INF and p.distance_to(_last_dab) < _brush * 0.35:
		return
	_last_dab = p
	field.paint(p.x, p.z, _brush, _painting > 0)


func _end_painting() -> void:
	if _painting == 0:
		return
	_painting = 0
	var field := _grass_field()
	if field and field.stroke_count() > _stroke_start:
		_undo.append(["grass", field, _stroke_start])


## A ring on the ground under the mouse: the remove tool's reach or the
## grass brush (green grows, orange with Shift clears).
func _update_ring() -> void:
	if _tool.is_empty():
		if _ring:
			_ring.visible = false
		return
	if _ring == null:
		_ring = MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.92
		torus.outer_radius = 1.0
		torus.rings = 48
		_ring.mesh = torus
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.no_depth_test = true
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ring.material_override = m
		_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		get_tree().current_scene.add_child(_ring)
	var hit := _ray()
	_ring.visible = not hit.is_empty()
	if hit:
		var r := _brush if _tool == "grass" else ERASE_RADIUS
		_ring.global_transform = Transform3D(Basis.from_scale(Vector3(r, 0.3, r)), hit.position + Vector3.UP * 0.05)
		var colour := Color(1.0, 0.3, 0.25, 0.8)
		if _tool == "grass":
			colour = Color(0.95, 0.55, 0.2, 0.8) if Input.is_key_pressed(KEY_SHIFT) else Color(0.4, 1.0, 0.35, 0.8)
		(_ring.material_override as StandardMaterial3D).albedo_color = colour


func _copy_under_mouse() -> void:
	var n := _placed_under_mouse()
	if n and not n.scene_file_path.is_empty():
		_pick(n.scene_file_path)
		_yaw = n.transform.basis.get_euler().y
		_scale = n.transform.basis.get_scale().x


func _undo_last() -> void:
	if _undo.is_empty():
		return
	var step: Array = _undo.pop_back()
	if step[0] == "prop":
		if is_instance_valid(step[1]):
			step[1].restore(step[2], step[3])
		_say("undone")
		return
	if step[0] == "grass":
		if is_instance_valid(step[1]):
			step[1].truncate_strokes(step[2])
		_say("undone")
		return
	if step[0] == "add":
		if is_instance_valid(step[1]):
			step[1].queue_free()
			step[1].get_parent().remove_child(step[1])
	else:
		var root := _placed_root()
		var node: Node3D = load(step[1]).instantiate()
		node.name = step[3]
		root.add_child(node, true)
		node.owner = root
		node.transform = step[2]
	_save()
	_say("undone")


## The level's Placed node (made if the level has none).
func _placed_root() -> Node3D:
	var scene := get_tree().current_scene
	var root := scene.get_node_or_null("Placed") as Node3D
	if root == null:
		root = Node3D.new()
		root.name = "Placed"
		scene.add_child(root)
	return root


## Writes the placed things to the level's placed.tscn, as instances of the
## asset scenes, so the editor shows them as normal nodes.
func _save() -> void:
	var root := _placed_root()
	var path := root.scene_file_path
	if path.is_empty():
		path = get_tree().current_scene.scene_file_path.get_base_dir().path_join("placed.tscn")
	var out := Node3D.new()
	out.name = "Placed"
	for child: Node in root.get_children():
		if child is Node3D and not child.scene_file_path.is_empty():
			var copy: Node3D = load(child.scene_file_path).instantiate()
			copy.name = child.name
			copy.transform = child.transform
			out.add_child(copy)
			copy.owner = out
	var packed := PackedScene.new()
	packed.pack(out)
	var err := ResourceSaver.save(packed, path)
	out.free()
	_say("saved %d placed things to %s" % [root.get_child_count(), path] if err == OK else "could not save " + path)


func _player() -> CharacterBody3D:
	var scene := get_tree().current_scene
	return scene.get_node_or_null("Player") as CharacterBody3D if scene else null


## What is under the mouse (or the screen centre while looking around),
## ignoring the player and the ghost.
func _ray() -> Dictionary:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return {}
	var mp := get_viewport().get_mouse_position()
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		mp = get_viewport().get_visible_rect().size / 2.0
	var from := cam.project_ray_origin(mp)
	var query := PhysicsRayQueryParameters3D.create(from, from + cam.project_ray_normal(mp) * 500.0)
	var player := _player()
	if player:
		query.exclude = [player.get_rid()]
	return cam.get_world_3d().direct_space_state.intersect_ray(query)
