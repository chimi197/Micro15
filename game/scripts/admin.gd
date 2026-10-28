## Map editor (autoload "Admin"). It only exists when the game runs from the
## Godot editor (the "editor" feature), never in exported builds for players.
##
## F1 opens the editor: a free camera, a tool bar and panels (the screen is
## built by scripts/editor/editor_ui.gd; the Keys button lists every
## shortcut). The tools:
##   Select       click (Shift+click) to select anything on the map: placed
##                things, the map's trees, bushes, lamps and benches,
##                windows, balconies and other building details, whole
##                buildings. Drag or G to move, R to turn, arrows to nudge,
##                Delete, Ctrl+D to copy, exact numbers in the inspector.
##                Map things become placed things the first time they move.
##   Place        asset browser with pictures, search and categories.
##   Remove       click removes what the red box shows; Shift+drag removes
##                everything ticked inside the ring; one button removes the
##                trees and bushes standing on roads.
##   Grass        grows or clears 3D grass.
##   Pins         numbered notes on the map (levels/micro15/pins.json), to
##                point at places when asking for changes.
##   Sky & light  presets and sliders for the sun, sky, clouds, fog and
##                camera; can be saved as the level's look.
## Everywhere: the coordinate grid (H), the map (M), the coordinates under
## the mouse in the status bar (Ctrl+C copies them), Go to x, z, undo and
## redo (Ctrl+Z / Ctrl+Y). In the game, F4 shows the player's coordinates.
## F2 / F3 turn the old ink lines / the 3D grass on and off, F12 saves a
## screenshot.
##
## Everything is saved as it changes: placed things in the level's "Placed"
## scene (levels/micro15/placed.tscn), so they can be edited in the Godot
## editor as well; taken-out map things in removed_props.json,
## removed_details.json and removed_buildings.json; grass in
## grass_paint.json; pins in pins.json; the look in lighting.json.
extends Node

const ASSETS_DIR := "res://assets/"
const ROTATE_STEP := PI / 12.0
const GRID := 0.5
const PLANTS := ["tree_a", "tree_b", "tree_c", "poplar", "bush_a", "bush_b", "hedge", "tree_pine",
	"tree_birch", "planter"]
const HINTS := {
	"select": "Click: select   Shift+click: add   drag / G: move   R: turn   arrows: nudge   Del: remove   Ctrl+D: copy   F: fly to",
	"place": "Click: place   wheel / R: turn   Shift+wheel / Z X: size   middle click: same asset as the one under the mouse",
	"remove": "Click: remove what the red box shows   Shift+drag: remove inside the ring (Shift+wheel: size)",
	"grass": "Hold left: grow grass   Shift or Clear: clear it   wheel / Z X: brush size",
	"pins": "Click: drop a pin with a note",
	"light": "Pick a preset or move the sliders; Save keeps it as the level's look",
}

var enabled := OS.has_feature("editor")
var active := false                        # the editor is open
var building: bool:                        # (player.gd: no punching while editing)
	get: return active
var save_enabled := true                   # the self-test turns saving off
var tool := "select"
var place_asset := ""
var brush := 3.0
var grass_brush := 3.0
var thumbnails: AssetThumbnails
var ui: EditorUI

var _layer: CanvasLayer
var _overlay: EditorOverlay
var _camera: EditorCamera
var _coords: Label                          # F4 in the game
var _ghost: Node3D
var _yaw := 0.0
var _scale := 1.0
var _selection: Array = []                  # refs (see _ref_*)
var _hover := {}
var _cursor := Vector3.INF                  # the point under the mouse
var _pick_wait := 0.0
var _undo: Array = []                       # [label, do, undo]
var _redo: Array = []
var _grab := {}
var _press := {}
var _brush_refs: Array = []
var _brushing := false
var _painting := 0
var _last_dab := Vector3.INF
var _stroke_start := 0
var _pins: Array = []
var _pin_at := Vector3.INF
var _map_taken := false
var _slow := 0.0


func _ready() -> void:
	if not enabled:
		set_process(false)
		set_process_input(false)
		set_process_unhandled_input(false)
		return
	thumbnails = AssetThumbnails.new()
	add_child(thumbnails)
	_layer = CanvasLayer.new()
	_layer.layer = 50
	_layer.visible = false
	add_child(_layer)
	ui = EditorUI.new()
	_layer.add_child(ui)
	ui.build(self)
	thumbnails.made.connect(ui.on_thumbnail)
	ui.set_assets(_list_assets())
	var coords_layer := CanvasLayer.new()
	coords_layer.layer = 49
	add_child(coords_layer)
	_coords = Label.new()
	_coords.position = Vector2(14, 10)
	_coords.add_theme_font_size_override("font_size", 15)
	_coords.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_coords.add_theme_constant_override("outline_size", 6)
	_coords.visible = false
	coords_layer.add_child(_coords)


func _list_assets() -> Array[String]:
	var out: Array[String] = []
	for dir in [ASSETS_DIR, ASSETS_DIR + "details/"]:
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".tscn"):
				out.append(dir + f)
	var order := EditorUI.CATEGORIES
	out.sort_custom(func(a: String, b: String) -> bool:
		var ca := order.find(ui.asset_category_of(a))
		var cb := order.find(ui.asset_category_of(b))
		return ca < cb if ca != cb else ui.asset_name(a) < ui.asset_name(b))
	return out


func _asset_for(proto: String) -> String:
	for path in [ASSETS_DIR + proto + ".tscn", ASSETS_DIR + "details/" + proto + ".tscn"]:
		if ResourceLoader.exists(path):
			return path
	return ""


# ----------------------------------------------------------------------------
# Opening and closing
# ----------------------------------------------------------------------------
func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_F1:
			if active:
				close_editor()
			else:
				open_editor()
			get_viewport().set_input_as_handled()
		KEY_F12:
			_screenshot()
			get_viewport().set_input_as_handled()
		KEY_F4:
			if not active:
				_coords.visible = not _coords.visible
				get_viewport().set_input_as_handled()
		KEY_F2, KEY_F3:
			var n := get_tree().current_scene.get_node_or_null("InkOutline" if event.keycode == KEY_F2 else "Grass")
			if n is Node3D:
				n.visible = not n.visible
			get_viewport().set_input_as_handled()


func open_editor() -> void:
	var scene := get_tree().current_scene
	if active or scene == null:
		return
	active = true
	_layer.visible = true
	_coords.visible = false
	_overlay = EditorOverlay.new()
	scene.add_child(_overlay)
	_camera = EditorCamera.new()
	scene.add_child(_camera)
	var player := _player()
	var from := get_viewport().get_camera_3d()
	if from:
		_camera.copy_view(from)
	_camera.make_current()
	if player:
		player.process_mode = Node.PROCESS_MODE_DISABLED
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_load_pins()
	_overlay.set_grid(ui.grid_button.button_pressed)
	var cycle := _sun_cycle()
	if cycle:
		ui.show_look(cycle.look, cycle.running)
	set_tool(tool)
	_update_undo_buttons()


func close_editor() -> void:
	if not active:
		return
	_end_grab(false)
	_end_painting()
	_end_brush()
	set_tool_ghost(false)
	active = false
	_layer.visible = false
	_selection.clear()
	_hover = {}
	var player := _player()
	if player:
		player.process_mode = Node.PROCESS_MODE_INHERIT
		player.camera.make_current()
	if _camera:
		_camera.queue_free()
		_camera = null
	if _overlay:
		_overlay.queue_free()
		_overlay = null
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Puts the player where the middle of the screen points and closes.
func play_here() -> void:
	var player := _player()
	if player == null:
		return
	var hit := _ray_hit_screen(get_viewport().get_visible_rect().size / 2.0)
	var at: Vector3 = hit.position if hit else _camera.global_position
	player.global_position = at + Vector3.UP * 0.2
	player.velocity = Vector3.ZERO
	var f := -_camera.global_basis.z
	player.camera_pivot.rotation.y = atan2(-f.x, -f.z)
	close_editor()


# ----------------------------------------------------------------------------
# Every frame
# ----------------------------------------------------------------------------
func _process(delta: float) -> void:
	if not active:
		if _coords.visible:
			var player := _player()
			if player:
				var f: Vector3 = -player.camera.global_basis.z
				_coords.text = "%s   facing %s   (Ctrl+C copies)" % [Coordinates.text(player.global_position, true),
						Coordinates.compass(Vector2(f.x, f.z))]
		return
	if _camera == null or not is_instance_valid(_camera):
		return
	_camera.fly(delta, ui.typing(), _selection.is_empty() or tool != "select")
	_pick_wait -= delta
	if _pick_wait <= 0.0 and not ui.mouse_over_panels() and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		_pick_wait = 0.05
		var p := _pick(get_viewport().get_mouse_position(), not _grab.is_empty())
		_cursor = p.point
		_hover = p.ref if tool in ["select", "remove"] and _grab.is_empty() else {}
	if not _grab.is_empty():
		_update_grab()
	if _painting != 0:
		_paint_grass()
	if _brushing:
		_brush_dab()
	_update_ghost()
	_draw_overlay()
	_slow -= delta
	if _slow <= 0.0:
		_slow = 0.1
		_update_status()
		if ui.map_panel.visible:
			var f := -_camera.global_basis.z
			ui.minimap.camera_at = _camera.global_position
			ui.minimap.camera_dir = Vector2(f.x, f.z)
			var player := _player()
			ui.minimap.player_at = player.global_position if player else Vector3.INF
			ui.minimap.queue_redraw()
		var cycle := _sun_cycle()
		if cycle and cycle.running and tool == "light":
			ui.show_look(cycle.look, true)


func _update_status() -> void:
	ui.status_tool.text = HINTS.get(tool, "")
	if _cursor != Vector3.INF:
		var what := ""
		if not _hover.is_empty():
			what = "  " + _ref_name(_hover)
		ui.status_cursor.text = Coordinates.text(_cursor, true) + what
	else:
		ui.status_cursor.text = "(sky)"
	var c := _camera.global_position
	ui.status_camera.text = "Camera x %.0f, z %.0f, height %.0f   facing %s" % [c.x, c.z, c.y, _camera.facing()]
	var cycle := _sun_cycle()
	ui.status_info.text = "%s   %d fps" % [cycle.clock() if cycle else "", Engine.get_frames_per_second()]


func _draw_overlay() -> void:
	var boxes := []
	for ref: Dictionary in _selection:
		if _ref_valid(ref):
			var b := _ref_box(ref)
			boxes.append([b[0], b[1], EditorTheme.ACCENT_HOVER])
	if not _hover.is_empty() and _ref_valid(_hover) and not _is_selected(_hover):
		var b := _ref_box(_hover)
		boxes.append([b[0], b[1], EditorTheme.DANGER if tool == "remove" else Color(1, 1, 1, 0.8)])
	for ref: Dictionary in _brush_preview():
		var b := _ref_box(ref)
		boxes.append([b[0], b[1], EditorTheme.DANGER])
	_overlay.show_boxes(boxes)
	var ring_at := Vector3.INF
	var radius := 1.0
	var colour := EditorTheme.DANGER
	if tool == "grass" and _cursor != Vector3.INF:
		ring_at = _cursor
		radius = grass_brush
		colour = Color(0.95, 0.55, 0.2) if _grass_clearing() else Color(0.4, 1.0, 0.35)
	elif tool == "remove" and _cursor != Vector3.INF and (Input.is_key_pressed(KEY_SHIFT) or _brushing):
		ring_at = _cursor
		radius = brush
	_overlay.show_ring(ring_at, radius, colour)
	_overlay.update_labels(_camera)


# ----------------------------------------------------------------------------
# Input in the 3D view (the panels take their own clicks first)
# ----------------------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if not active:
		if _coords.visible and event is InputEventKey and event.pressed and event.ctrl_pressed \
				and event.keycode == KEY_C:
			var player := _player()
			if player:
				_copy("Micro 15 location: " + Coordinates.text(player.global_position, true))
		return
	if event is InputEventMouseMotion:
		if _camera.looking:
			_camera.look(event.relative)
		elif not _press.is_empty() and not _press.moved and event.position.distance_to(_press.pos) > 6.0:
			_press.moved = true
			if tool == "select" and _press.on_selected:
				start_grab(true)
	elif event is InputEventMouseButton:
		_mouse_button(event)
	elif event is InputEventKey and event.pressed:
		if _key(event):
			get_viewport().set_input_as_handled()
		return
	get_viewport().set_input_as_handled()


func _mouse_button(mb: InputEventMouseButton) -> void:
	if mb.pressed:
		get_viewport().gui_release_focus()
	match mb.button_index:
		MOUSE_BUTTON_RIGHT:
			if mb.pressed and not _grab.is_empty():
				_end_grab(false)
				return
			_camera.looking = mb.pressed
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if mb.pressed else Input.MOUSE_MODE_VISIBLE
		MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_left_down(mb)
			else:
				_left_up(mb)
		MOUSE_BUTTON_MIDDLE:
			if mb.pressed and tool == "place":
				var p := _pick(mb.position)
				if not p.ref.is_empty():
					var path := _ref_asset(p.ref)
					if not path.is_empty():
						choose_asset(path)
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
			if not mb.pressed:
				return
			var up := mb.button_index == MOUSE_BUTTON_WHEEL_UP
			if _camera.looking:
				_camera.speed = clampf(_camera.speed * (1.25 if up else 0.8), 2.0, 300.0)
				ui.say("flying speed %.0f m/s" % _camera.speed, 1.0)
			elif not _grab.is_empty():
				_grab.yaw += ROTATE_STEP if up else -ROTATE_STEP
			elif tool == "place":
				if mb.shift_pressed:
					_scale = clampf(_scale * (1.05 if up else 0.95), 0.1, 10.0)
				else:
					_yaw = wrapf(_yaw + (ROTATE_STEP if up else -ROTATE_STEP), -PI, PI)
			elif tool == "grass":
				_set_grass_brush(grass_brush * (1.1 if up else 0.9))
			elif tool == "remove" and mb.shift_pressed:
				ui.brush_slider.value = brush * (1.1 if up else 0.9)
			else:
				_camera.dolly(1.0 if up else -1.0)


func _left_down(mb: InputEventMouseButton) -> void:
	if not _grab.is_empty():
		_end_grab(true)
		return
	match tool:
		"select":
			var p := _pick(mb.position)
			_press = {"pos": mb.position, "moved": false, "ref": p.ref, "shift": mb.shift_pressed,
					"on_selected": not p.ref.is_empty() and _is_selected(p.ref)}
			if not p.ref.is_empty() and not _is_selected(p.ref) and not mb.shift_pressed:
				_set_selection([p.ref])               # drag a thing straight away
				_press.on_selected = true
		"place":
			_place()
		"remove":
			if mb.shift_pressed:
				_brushing = true
				_brush_refs.clear()
			else:
				var p := _pick(mb.position)
				if p.ref.is_empty():
					ui.say("Nothing to remove there")
				else:
					_remove_refs([p.ref], "Remove " + _ref_name(p.ref))
		"grass":
			_start_painting(-1 if _grass_clearing() else 1)
		"pins":
			var p := _pick(mb.position)
			if p.point != Vector3.INF:
				_pin_at = p.point
				ui.ask_pin_note(mb.position)


func _left_up(_mb: InputEventMouseButton) -> void:
	_end_painting()
	_end_brush()
	if not _grab.is_empty() and _grab.drag:
		_end_grab(true)
	elif tool == "select" and not _press.is_empty() and not _press.moved:
		var ref: Dictionary = _press.ref
		if ref.is_empty():
			if not _press.shift:
				_set_selection([])
		elif _press.shift:
			var sel := _selection.duplicate()
			var i := _find_ref(sel, ref)
			if i >= 0:
				sel.remove_at(i)
			else:
				sel.append(ref)
			_set_selection(sel)
		else:
			_set_selection([ref])
	_press = {}


func _key(event: InputEventKey) -> bool:
	if event.ctrl_pressed or event.meta_pressed:
		match event.keycode:
			KEY_Z:
				if event.shift_pressed:
					redo()
				else:
					undo()
			KEY_Y:
				redo()
			KEY_D:
				duplicate_selected()
			KEY_C:
				copy_location()
			_:
				return false
		return true
	if event.echo and not event.keycode in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_PAGEUP, KEY_PAGEDOWN]:
		return false
	match event.keycode:
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6:
			set_tool(EditorUI.TOOLS[event.keycode - KEY_1][0])
		KEY_ESCAPE:
			if not _grab.is_empty():
				_end_grab(false)
			elif ui.pin_popup.visible or ui.keys_panel.visible:
				ui.pin_popup.visible = false
				ui.keys_panel.visible = false
			else:
				clear_selection()
		KEY_DELETE, KEY_BACKSPACE:
			if not _selection.is_empty():
				delete_selected()
			elif not _hover.is_empty() and tool == "remove":
				_remove_refs([_hover], "Remove " + _ref_name(_hover))
		KEY_G:
			start_grab(false)
		KEY_R:
			var step := -ROTATE_STEP if event.shift_pressed else ROTATE_STEP
			if tool == "place":
				_yaw = wrapf(_yaw + step, -PI, PI)
			elif not _grab.is_empty():
				_grab.yaw += step
			else:
				_turn_selection(step)
		KEY_Z, KEY_X:
			var bigger := event.keycode == KEY_X
			if tool == "place":
				_scale = clampf(_scale * (1.1 if bigger else 0.9), 0.1, 10.0)
			elif tool == "grass":
				_set_grass_brush(grass_brush * (1.25 if bigger else 0.8))
			elif tool == "remove":
				ui.brush_slider.value = brush * (1.25 if bigger else 0.8)
		KEY_F:
			focus_selected()
		KEY_H:
			ui.grid_button.button_pressed = not ui.grid_button.button_pressed
			set_grid(ui.grid_button.button_pressed)
		KEY_M:
			ui.map_button.button_pressed = not ui.map_button.button_pressed
			set_map(ui.map_button.button_pressed)
		KEY_P:
			play_here()
		KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_PAGEUP, KEY_PAGEDOWN:
			if tool != "select" or _selection.is_empty():
				return false
			_nudge(event.keycode, 1.0 if event.shift_pressed else 0.1)
		KEY_COMMA, KEY_PERIOD:
			var cycle := _sun_cycle()
			if cycle:
				cycle.shift(0.5 if event.keycode == KEY_PERIOD else -0.5)
				ui.show_look(cycle.look, cycle.running)
		KEY_SLASH:
			var cycle := _sun_cycle()
			if cycle:
				set_day_running(not cycle.running)
				ui.show_look(cycle.look, cycle.running)
		_:
			return false
	return true


func set_tool(t: String) -> void:
	_end_grab(false)
	tool = t
	ui.show_tool(t)
	_hover = {}
	set_tool_ghost(t == "place")


# ----------------------------------------------------------------------------
# Picking: what is under the mouse
# ----------------------------------------------------------------------------
# A ref is one thing on the map:
#   {kind: "placed", node: Node3D}                         a child of Placed
#   {kind: "record", scatter: Scatter, r: int}             a map tree, lamp, window...
#   {kind: "part", model: StyledModel, mi: MeshInstance3D}  a whole building
func _ray_hit_screen(screen: Vector2, exclude: Array = []) -> Dictionary:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return {}
	var from := cam.project_ray_origin(screen)
	return _ray_hit(from, cam.project_ray_normal(screen), 2000.0, exclude)


func _ray_hit(from: Vector3, dir: Vector3, length: float, exclude: Array = []) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * length)
	var ex := exclude.duplicate()
	var player := _player()
	if player:
		ex.append(player.get_rid())
	query.exclude = ex
	return get_tree().current_scene.get_world_3d().direct_space_state.intersect_ray(query)


func _pick(screen: Vector2, ground_only := false) -> Dictionary:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return {"ref": {}, "point": Vector3.INF}
	return pick_ray(cam.project_ray_origin(screen), cam.project_ray_normal(screen), ground_only)


## The nearest thing along a ray: {ref, point (where the ray meets a solid
## surface), distance}. ground_only skips the things (for moving).
func pick_ray(from: Vector3, dir: Vector3, ground_only := false) -> Dictionary:
	var exclude: Array = _grab.get("rids", [])
	var hit := _ray_hit(from, dir, 2000.0, exclude)
	var out := {"ref": {}, "point": hit.position if hit else Vector3.INF, "distance": INF}
	if ground_only:
		return out
	var filters := ui.select_filters if tool == "select" else {}
	var allowed := func(category: String) -> bool:
		return not filters.has(category) or filters[category].button_pressed
	var limit := 2000.0
	var on_building := false
	if hit:
		var d := from.distance_to(hit.position)
		limit = d + 0.05
		var ref := _ref_from_collider(hit.collider)
		if not ref.is_empty() and allowed.call(_ref_category(ref)):
			out.ref = ref
			out.distance = d
			if ref.kind == "part":
				on_building = true
				limit = d + 0.8          # details sit on (or a little in) the walls
	for scatter in _scatters():
		var only := PackedStringArray()
		if scatter.format == "props":
			var plants: bool = allowed.call("plants")
			var street: bool = allowed.call("street")
			if not plants and not street:
				continue
			if plants != street:
				for proto in scatter._protos:
					if (proto in PLANTS) == plants:
						only.append(proto)
		elif not allowed.call("details"):
			continue
		var p := scatter.pick(from, dir, limit, only)
		if p.is_empty():
			continue
		if p[1] < out.distance or (on_building and p[1] < out.distance + 0.8):
			out.ref = {"kind": "record", "scatter": scatter, "r": p[0]}
			out.distance = p[1]
			on_building = false
			limit = p[1]
	if allowed.call("placed"):
		for node: Node in _placed_root().get_children():
			if not node is Node3D:
				continue
			var b := _ref_box({"kind": "placed", "node": node})
			var inv: Transform3D = b[1].affine_inverse()
			var at: Variant = (b[0] as AABB).intersects_ray(inv * from, inv.basis * dir)
			if at == null:
				continue
			var d := from.distance_to(b[1] * (at as Vector3))
			if d < out.distance:
				out.ref = {"kind": "placed", "node": node}
				out.distance = d
	return out


func _ref_from_collider(c: Object) -> Dictionary:
	var n := c as Node
	var root := _placed_root()
	while n:
		if n.get_parent() == root:
			return {"kind": "placed", "node": n}
		if n is StyledModel and not (n as StyledModel).removed_file.is_empty():
			var mi := (n as StyledModel).part_of(c as Node)
			return {"kind": "part", "model": n, "mi": mi} if mi else {}
		n = n.get_parent()
	return {}


func _ref_valid(ref: Dictionary) -> bool:
	match ref.kind:
		"placed":
			return is_instance_valid(ref.node) and ref.node.is_inside_tree()
		"record":
			return not ref.scatter.is_removed(ref.r)
		"part":
			return ref.mi.visible
	return false


func _same(a: Dictionary, b: Dictionary) -> bool:
	if a.kind != b.kind:
		return false
	match a.kind:
		"placed":
			return a.node == b.node
		"record":
			return a.scatter == b.scatter and a.r == b.r
	return a.mi == b.mi


func _find_ref(list: Array, ref: Dictionary) -> int:
	for i in list.size():
		if _same(list[i], ref):
			return i
	return -1


func _is_selected(ref: Dictionary) -> bool:
	return _find_ref(_selection, ref) >= 0


func _ref_name(ref: Dictionary) -> String:
	match ref.kind:
		"placed":
			return ui.asset_name(ref.node.scene_file_path)
		"record":
			return ui.asset_name(ref.scatter.record_proto(ref.r))
	return "Building"


func _ref_category(ref: Dictionary) -> String:
	match ref.kind:
		"placed":
			return "placed"
		"record":
			if ref.scatter.format == "details":
				return "details"
			return "plants" if ref.scatter.record_proto(ref.r) in PLANTS else "street"
	return "buildings"


func _ref_transform(ref: Dictionary) -> Transform3D:
	match ref.kind:
		"placed":
			return ref.node.global_transform
		"record":
			return ref.scatter.record_transform(ref.r)
	return ref.mi.global_transform


## [AABB in the thing's own space, its Transform3D]
func _ref_box(ref: Dictionary) -> Array:
	match ref.kind:
		"record":
			return [ref.scatter.record_aabb(ref.r), ref.scatter.record_transform(ref.r)]
		"part":
			return [ref.mi.get_aabb(), ref.mi.global_transform]
	var node: Node3D = ref.node
	var inv := node.global_transform.affine_inverse()
	var box := AABB(Vector3(-0.25, 0, -0.25), Vector3(0.5, 0.5, 0.5))
	var first := true
	var meshes := node.find_children("*", "MeshInstance3D", true, false)
	if node is MeshInstance3D:
		meshes.append(node)
	for mi: MeshInstance3D in meshes:
		var b: AABB = (inv * mi.global_transform) * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return [box, node.global_transform]


func _ref_asset(ref: Dictionary) -> String:
	match ref.kind:
		"placed":
			return ref.node.scene_file_path
		"record":
			return _asset_for(ref.scatter.record_proto(ref.r))
	return ""


# ----------------------------------------------------------------------------
# Selection
# ----------------------------------------------------------------------------
func _set_selection(refs: Array) -> void:
	_selection = refs.filter(func(r: Dictionary) -> bool: return _ref_valid(r))
	_show_inspector()


func clear_selection() -> void:
	_set_selection([])


func _show_inspector() -> void:
	if _selection.is_empty():
		ui.show_selection("", "", {}, "")
		return
	if _selection.size() > 1:
		ui.show_selection("%d things selected" % _selection.size(), "", {}, "Move, turn, copy or remove them together.")
		return
	var ref: Dictionary = _selection[0]
	var kind := ""
	var note := ""
	var values := {}
	match ref.kind:
		"placed":
			kind = "Placed asset (%s)" % ref.node.scene_file_path.get_file().get_basename()
		"record":
			kind = "Part of the map (%s). It becomes a placed asset when it is moved or changed." % \
					ref.scatter.record_proto(ref.r)
		"part":
			kind = "Building %s of the map" % String(ref.mi.name).trim_prefix("bld_")
			note = "Buildings can be removed (Del) but not moved."
	if ref.kind != "part":
		var t := _ref_transform(ref)
		values = {"x": t.origin.x, "y": t.origin.y, "z": t.origin.z,
				"turn": rad_to_deg(t.basis.orthonormalized().get_euler().y), "size": t.basis.get_scale().x}
	ui.show_selection(_ref_name(ref), kind, values, note)


func focus_selected() -> void:
	if _selection.is_empty():
		return
	var b := _ref_box(_selection[0])
	var centre: Vector3 = b[1] * (b[0] as AABB).get_center()
	var size: float = ((b[0] as AABB).size * b[1].basis.get_scale()).length()
	_camera.look_at_point(centre, clampf(size * 1.6, 4.0, 120.0))


# ----------------------------------------------------------------------------
# Undo and redo
# ----------------------------------------------------------------------------
## Runs do_fn (unless done is true) and keeps it for undo / redo.
func _commit(label: String, do_fn: Callable, undo_fn: Callable, done := false) -> void:
	if not done:
		do_fn.call()
	_undo.append([label, do_fn, undo_fn])
	_redo.clear()
	_update_undo_buttons()


func undo() -> void:
	if _undo.is_empty():
		ui.say("Nothing to undo")
		return
	var step: Array = _undo.pop_back()
	step[2].call()
	_redo.append(step)
	_after_change("Undone: " + step[0])


func redo() -> void:
	if _redo.is_empty():
		ui.say("Nothing to redo")
		return
	var step: Array = _redo.pop_back()
	step[1].call()
	_undo.append(step)
	_after_change("Redone: " + step[0])


func _after_change(message: String) -> void:
	_set_selection(_selection)
	_update_undo_buttons()
	ui.say(message, 2.0)


func _update_undo_buttons() -> void:
	ui.undo_button.disabled = _undo.is_empty()
	ui.redo_button.disabled = _redo.is_empty()
	ui.undo_button.tooltip_text = "Undo %s (Ctrl+Z)" % _undo.back()[0] if not _undo.is_empty() else "Nothing to undo"
	ui.redo_button.tooltip_text = "Redo %s (Ctrl+Y)" % _redo.back()[0] if not _redo.is_empty() else "Nothing to redo"


# ----------------------------------------------------------------------------
# Removing
# ----------------------------------------------------------------------------
func _detach(node: Node) -> void:
	if node.get_parent():
		node.get_parent().remove_child(node)


func _attach(node: Node3D, t: Transform3D) -> void:
	var root := _placed_root()
	if node.get_parent() != root:
		root.add_child(node, true)
	node.owner = root
	node.global_transform = t


## Takes things off the map as one undo step.
func _remove_refs(refs: Array, label: String, done := false) -> void:
	refs = refs.filter(func(r: Dictionary) -> bool: return done or _ref_valid(r))
	if refs.is_empty():
		return
	var places := {}
	for ref: Dictionary in refs:
		if ref.kind == "placed":
			places[ref.node] = ref.node.global_transform
	var do_fn := func() -> void:
		for ref: Dictionary in refs:
			match ref.kind:
				"placed":
					_detach(ref.node)
				"record":
					ref.scatter.remove_record(ref.r, false)
				"part":
					ref.model.remove_part(ref.mi)
		_saved(refs)
	var undo_fn := func() -> void:
		for ref: Dictionary in refs:
			match ref.kind:
				"placed":
					_attach(ref.node, places[ref.node])
				"record":
					ref.scatter.restore_record(ref.r, false)
				"part":
					ref.model.restore_part(ref.mi)
		_saved(refs)
	_commit(label if refs.size() == 1 else "Remove %d things" % refs.size(), do_fn, undo_fn, done)
	if done:
		_saved(refs)
	_set_selection(_selection)
	ui.say(label if refs.size() == 1 else "Removed %d things" % refs.size(), 2.0)


## Saves whatever the refs changed.
func _saved(refs: Array) -> void:
	var scatters := {}
	var placed := false
	for ref: Dictionary in refs:
		if ref.kind == "record":
			scatters[ref.scatter] = true
		elif ref.kind == "placed":
			placed = true
	if not save_enabled:
		return
	for s: Scatter in scatters:
		s.save_removed()
	if placed:
		_save_placed()


func delete_selected() -> void:
	if _selection.is_empty():
		return
	var refs := _selection.duplicate()
	_set_selection([])
	_remove_refs(refs, "Remove " + _ref_name(refs[0]))


## Everything ticked in the remove panel inside the ring.
func _brush_targets(at: Vector3) -> Array:
	var out := []
	if at == Vector3.INF:
		return out
	var f: Dictionary = ui.remove_filters
	for scatter in _scatters():
		var only := PackedStringArray()
		if scatter.format == "details":
			if not f.details.button_pressed:
				continue
		else:
			for proto in scatter._protos:
				if (proto in PLANTS and f.plants.button_pressed) or (not proto in PLANTS and f.street.button_pressed):
					only.append(proto)
			if only.is_empty():
				continue
		for r in scatter.records_near(at, brush, only):
			out.append({"kind": "record", "scatter": scatter, "r": r})
	if f.placed.button_pressed:
		for node: Node in _placed_root().get_children():
			if node is Node3D:
				var o: Vector3 = node.global_position
				if Vector2(o.x - at.x, o.z - at.z).length() <= brush:
					out.append({"kind": "placed", "node": node})
	return out


func _brush_preview() -> Array:
	if tool != "remove" or _brushing or not Input.is_key_pressed(KEY_SHIFT):
		return []
	return _brush_targets(_cursor)


func _brush_dab() -> void:
	var found := _brush_targets(_cursor)
	for ref: Dictionary in found:
		match ref.kind:
			"placed":
				ref["at"] = ref.node.global_transform
				_detach(ref.node)
			"record":
				ref.scatter.remove_record(ref.r, false)
		_brush_refs.append(ref)


func _end_brush() -> void:
	if not _brushing:
		return
	_brushing = false
	if _brush_refs.is_empty():
		return
	var refs := _brush_refs.duplicate()
	_brush_refs.clear()
	var places := {}
	for ref: Dictionary in refs:
		if ref.kind == "placed":
			places[ref.node] = ref.at
	var do_fn := func() -> void:
		for ref: Dictionary in refs:
			if ref.kind == "placed":
				_detach(ref.node)
			else:
				ref.scatter.remove_record(ref.r, false)
		_saved(refs)
	var undo_fn := func() -> void:
		for ref: Dictionary in refs:
			if ref.kind == "placed":
				_attach(ref.node, places[ref.node])
			else:
				ref.scatter.restore_record(ref.r, false)
		_saved(refs)
	_commit("Remove %d things" % refs.size(), do_fn, undo_fn, true)
	_saved(refs)
	ui.say("Removed %d things" % refs.size(), 2.0)


## Removes every map tree, bush, lamp and bench standing on a road, and the
## trees, bushes and benches in car parks, as one undo step.
func remove_props_on_roads() -> int:
	var found := []
	var ground := get_tree().current_scene.get_node_or_null("Ground") as StyledModel
	if ground == null:
		return 0
	for scatter in _scatters():
		if scatter.format != "props":
			continue
		for r in scatter.record_count():
			if scatter.is_removed(r):
				continue
			var o := scatter.record_transform(r).origin
			var hit := _ray_hit(Vector3(o.x, o.y + 1.0, o.z), Vector3.DOWN, 2.0)
			if hit.is_empty():
				continue
			var surface := ground.surface_at(hit.collider, hit.get("face_index", -1))
			if surface in ["C3_asphalt", "C3_line"] or (surface == "C3_parking" and scatter.record_proto(r) != "lamp"):
				found.append({"kind": "record", "scatter": scatter, "r": r})
	if found.is_empty():
		ui.say("Nothing of the map stands on a road")
		return 0
	_remove_refs(found, "Remove %d things on roads" % found.size())
	ui.say("Removed %d trees, lamps and benches that stood on roads (Ctrl+Z puts them back)" % found.size(), 5.0)
	return found.size()


# ----------------------------------------------------------------------------
# Moving and changing
# ----------------------------------------------------------------------------
## Placed nodes for the selection; map things (trees, details...) are first
## turned into placed assets, as one undo step. Buildings stay where they are.
func _movable() -> Array:
	var nodes := []
	var convert := []
	var skipped := 0
	for ref: Dictionary in _selection:
		match ref.kind:
			"placed":
				nodes.append(ref.node)
			"record":
				var path := _ref_asset(ref)
				if path.is_empty():
					skipped += 1
				else:
					convert.append([ref, path])
			"part":
				skipped += 1
	if skipped > 0:
		ui.say("Buildings can be removed but not moved" if convert.is_empty() and nodes.is_empty() \
				else "%d of the selected things cannot move" % skipped)
	if convert.is_empty():
		return nodes
	var made := []
	for c: Array in convert:
		var node: Node3D = load(c[1]).instantiate()
		node.name = c[1].get_file().get_basename()
		made.append([c[0], node, c[0].scatter.record_transform(c[0].r)])
	var do_fn := func() -> void:
		for m: Array in made:
			m[0].scatter.remove_record(m[0].r, false)
			_attach(m[1], m[2])
		_saved(made.map(func(m: Array) -> Dictionary: return m[0]) + [{"kind": "placed"}])
		_swap_selection(made, true)
	var undo_fn := func() -> void:
		for m: Array in made:
			_detach(m[1])
			m[0].scatter.restore_record(m[0].r, false)
		_saved(made.map(func(m: Array) -> Dictionary: return m[0]) + [{"kind": "placed"}])
		_swap_selection(made, false)
	_commit("Make %d map things movable" % made.size(), do_fn, undo_fn)
	for m: Array in made:
		nodes.append(m[1])
	return nodes


## Keeps the selection on the same things when they turn into placed assets
## (to_placed) or back into map records.
func _swap_selection(made: Array, to_placed: bool) -> void:
	var sel := _selection.duplicate()
	for m: Array in made:
		var from: Dictionary = m[0] if to_placed else {"kind": "placed", "node": m[1]}
		var to: Dictionary = {"kind": "placed", "node": m[1]} if to_placed else m[0]
		var i := _find_ref(sel, from)
		if i >= 0:
			sel[i] = to
	_selection = sel
	_show_inspector()


## Sets transforms of placed nodes as one undo step ([[node, before, after]]).
func _move_nodes(label: String, moves: Array, done := false) -> void:
	if moves.is_empty():
		return
	var do_fn := func() -> void:
		for m: Array in moves:
			if is_instance_valid(m[0]):
				m[0].global_transform = m[2]
		if save_enabled:
			_save_placed()
		_show_inspector()
	var undo_fn := func() -> void:
		for m: Array in moves:
			if is_instance_valid(m[0]):
				m[0].global_transform = m[1]
		if save_enabled:
			_save_placed()
		_show_inspector()
	_commit(label, do_fn, undo_fn, done)
	if done:
		do_fn.call()


func start_grab(drag := false) -> void:
	if _selection.is_empty() or not _grab.is_empty():
		return
	var nodes := _movable()
	if nodes.is_empty():
		return
	var rids := []
	for n: Node in nodes:
		for co in n.find_children("*", "CollisionObject3D", true, false) + ([n] if n is CollisionObject3D else []):
			rids.append((co as CollisionObject3D).get_rid())
	# dragging moves the things with the ground point under the mouse; with G
	# the first one jumps to the mouse
	var anchor: Vector3 = nodes[0].global_position
	if drag:
		_grab = {"rids": rids}
		var p := _pick(_press.get("pos", get_viewport().get_mouse_position()), true)
		if p.point != Vector3.INF:
			anchor = p.point
	_grab = {"nodes": nodes, "starts": nodes.map(func(n: Node3D) -> Transform3D: return n.global_transform),
			"anchor": anchor, "yaw": 0.0, "drag": drag, "rids": rids}
	ui.say("Moving: click to drop, right click or Esc to cancel, wheel or R to turn", 3.0)


func _update_grab() -> void:
	var p := _pick(get_viewport().get_mouse_position(), true)
	if p.point == Vector3.INF:
		return
	var anchor: Vector3 = _grab.anchor
	var target: Vector3 = p.point
	if ui.snap_box.button_pressed:
		target.x = snappedf(target.x, GRID)
		target.z = snappedf(target.z, GRID)
	var turn := Basis(Vector3.UP, _grab.yaw)
	for i in _grab.nodes.size():
		var start: Transform3D = _grab.starts[i]
		var node: Node3D = _grab.nodes[i]
		node.global_transform = Transform3D(turn * start.basis, target + turn * (start.origin - anchor))


func _end_grab(confirm: bool) -> void:
	if _grab.is_empty():
		return
	var g := _grab
	_grab = {}
	var moves := []
	for i in g.nodes.size():
		var node: Node3D = g.nodes[i]
		if confirm:
			moves.append([node, g.starts[i], node.global_transform])
		else:
			node.global_transform = g.starts[i]
	if confirm:
		_move_nodes("Move %d things" % moves.size() if moves.size() > 1 else "Move", moves, true)
	_show_inspector()


func _turn_selection(step: float) -> void:
	var nodes := _movable()
	if nodes.is_empty():
		return
	var centre := Vector3.ZERO
	for n: Node3D in nodes:
		centre += n.global_position
	centre /= nodes.size()
	var turn := Basis(Vector3.UP, step)
	var moves := []
	for n: Node3D in nodes:
		var t := n.global_transform
		moves.append([n, t, Transform3D(turn * t.basis, centre + turn * (t.origin - centre))])
	_move_nodes("Turn", moves)


func _nudge(key: Key, amount: float) -> void:
	var nodes := _movable()
	if nodes.is_empty():
		return
	var f := -_camera.global_basis.z
	var forward := Vector3(f.x, 0, f.z).normalized()
	if absf(forward.x) > absf(forward.z):          # nudge along the map axes nearest the view
		forward = Vector3(signf(forward.x), 0, 0)
	else:
		forward = Vector3(0, 0, signf(forward.z))
	var right := Vector3(-forward.z, 0, forward.x)
	var d: Vector3 = {KEY_UP: forward, KEY_DOWN: -forward, KEY_LEFT: -right, KEY_RIGHT: right,
			KEY_PAGEUP: Vector3.UP, KEY_PAGEDOWN: Vector3.DOWN}[key] * amount
	var moves := []
	for n: Node3D in nodes:
		var t := n.global_transform
		moves.append([n, t, t.translated(d)])
	_move_nodes("Nudge", moves)


## An exact value typed in the inspector: x, y, z, turn (degrees) or size.
func edit_selected(field: String, value: float) -> void:
	if _selection.size() != 1:
		return
	var nodes := _movable()
	if nodes.is_empty():
		return
	var node: Node3D = nodes[0]
	var t := node.global_transform
	var scale := t.basis.get_scale()
	var yaw := t.basis.orthonormalized().get_euler().y
	var after := t
	match field:
		"x":
			after.origin.x = value
		"y":
			after.origin.y = value
		"z":
			after.origin.z = value
		"turn":
			after.basis = Basis(Vector3.UP, deg_to_rad(value)) * Basis.from_scale(scale)
		"size":
			after.basis = Basis(Vector3.UP, yaw) * Basis.from_scale(scale * (value / maxf(scale.x, 0.001)))
	_move_nodes("Change %s" % field, [[node, t, after]])


func duplicate_selected() -> void:
	if _selection.is_empty():
		return
	var copies := []
	for ref: Dictionary in _selection:
		var path := _ref_asset(ref)
		if path.is_empty():
			continue
		var node: Node3D = load(path).instantiate()
		node.name = path.get_file().get_basename()
		copies.append([node, _ref_transform(ref)])
	if copies.is_empty():
		ui.say("Buildings cannot be copied")
		return
	var do_fn := func() -> void:
		for c: Array in copies:
			_attach(c[0], c[1])
		if save_enabled:
			_save_placed()
	var undo_fn := func() -> void:
		for c: Array in copies:
			_detach(c[0])
		if save_enabled:
			_save_placed()
	_commit("Copy %d things" % copies.size(), do_fn, undo_fn)
	_set_selection(copies.map(func(c: Array) -> Dictionary: return {"kind": "placed", "node": c[0]}))
	start_grab(false)


# ----------------------------------------------------------------------------
# Placing
# ----------------------------------------------------------------------------
func choose_asset(path: String) -> void:
	place_asset = path
	if tool != "place":
		set_tool("place")
	set_tool_ghost(true)
	ui.select_asset(path)
	ui.place_info.text = ui.asset_name(path)


func set_tool_ghost(on: bool) -> void:
	if _ghost:
		_ghost.queue_free()
		_ghost = null
	if not on or not active:
		return
	if place_asset.is_empty() and not ui.asset_paths.is_empty():
		place_asset = ui.asset_paths[0]
		ui.select_asset(place_asset)
	if place_asset.is_empty():
		return
	_ghost = load(place_asset).instantiate()
	for shape: CollisionShape3D in _ghost.find_children("*", "CollisionShape3D", true, false):
		shape.disabled = true
	if _ghost is CollisionObject3D:
		(_ghost as CollisionObject3D).collision_layer = 0
	get_tree().current_scene.add_child(_ghost)


func _update_ghost() -> void:
	if _ghost == null:
		return
	_ghost.visible = _cursor != Vector3.INF and not ui.mouse_over_panels()
	if _ghost.visible:
		_ghost.global_transform = _placement(_cursor)
	ui.place_info.text = "%s   turn %d°   size %.2f" % [ui.asset_name(place_asset), roundi(rad_to_deg(_yaw)), _scale]


func _placement(p: Vector3) -> Transform3D:
	if ui.snap_box.button_pressed:
		p.x = snappedf(p.x, GRID)
		p.z = snappedf(p.z, GRID)
	return Transform3D(Basis(Vector3.UP, _yaw).scaled(Vector3.ONE * _scale), p)


func _place() -> void:
	if _cursor == Vector3.INF or place_asset.is_empty():
		return
	var node: Node3D = load(place_asset).instantiate()
	node.name = place_asset.get_file().get_basename()
	var t := _placement(_cursor)
	var do_fn := func() -> void:
		_attach(node, t)
		_save_placed()
	var undo_fn := func() -> void:
		_detach(node)
		_save_placed()
	_commit("Place " + ui.asset_name(place_asset), do_fn, undo_fn)
	if ui.random_turn.button_pressed:
		_yaw = randf_range(-PI, PI)
	if ui.random_size.button_pressed:
		_scale = randf_range(0.9, 1.1)


# ----------------------------------------------------------------------------
# Grass
# ----------------------------------------------------------------------------
func _grass_clearing() -> bool:
	return Input.is_key_pressed(KEY_SHIFT) or ui.grass_clear.button_pressed


func _set_grass_brush(r: float) -> void:
	ui.grass_brush_slider.value = clampf(r, 0.5, 20.0)


func _start_painting(mode: int) -> void:
	var field := _grass_field()
	if field == null:
		ui.say("This level has no grass")
		return
	_painting = mode
	_stroke_start = field.stroke_count()
	_last_dab = Vector3.INF
	_paint_grass()


func _paint_grass() -> void:
	var field := _grass_field()
	if field == null or _cursor == Vector3.INF:
		return
	if _last_dab != Vector3.INF and _cursor.distance_to(_last_dab) < grass_brush * 0.35:
		return
	_last_dab = _cursor
	field.paint(_cursor.x, _cursor.z, grass_brush, _painting > 0)


func _end_painting() -> void:
	if _painting == 0:
		return
	var grew := _painting > 0
	_painting = 0
	var field := _grass_field()
	if field == null or field.stroke_count() <= _stroke_start:
		return
	var start := _stroke_start
	var strokes := field.strokes_after(start)
	_commit("Grow grass" if grew else "Clear grass", func() -> void: field.add_strokes(strokes),
			func() -> void: field.truncate_strokes(start), true)


# ----------------------------------------------------------------------------
# Coordinates, grid, map
# ----------------------------------------------------------------------------
func copy_location() -> void:
	var text := ""
	if not _selection.is_empty():
		var t := _ref_transform(_selection[0])
		text = "Micro 15: %s at %s" % [_ref_name(_selection[0]), Coordinates.text(t.origin, true)]
	elif _cursor != Vector3.INF:
		text = "Micro 15 location: " + Coordinates.text(_cursor, true)
	if text.is_empty():
		return
	_copy(text)


func _copy(text: String) -> void:
	DisplayServer.clipboard_set(text)
	if ui and active:
		ui.say("Copied: " + text)


func goto_text(s: String) -> void:
	var p := Coordinates.parse(s)
	if p == Vector2.INF:
		ui.say("Type a location as x, z (for example 357.6, 18.5)")
		return
	fly_over(p.x, p.y)


func fly_over(x: float, z: float) -> void:
	_camera.move_over(x, z, clampf(_camera.global_position.y, 25.0, 120.0))
	ui.say("Flew to " + Coordinates.text(Vector3(x, 0, z)), 2.0)


func set_grid(on: bool) -> void:
	if _overlay:
		_overlay.set_grid(on)


func set_map(on: bool) -> void:
	ui.map_panel.visible = on
	ui.minimap.pins = _pins
	if on and not _map_taken:
		_map_taken = true
		var scene := get_tree().current_scene
		var hide := []
		for n in ["Props", "Details", "Grass", "Player"]:
			var node := scene.get_node_or_null(n) as Node3D
			if node:
				hide.append(node)
		if _overlay:
			hide.append(_overlay)
		if _ghost:
			hide.append(_ghost)
		ui.minimap.capture(scene, hide)


# ----------------------------------------------------------------------------
# Pins
# ----------------------------------------------------------------------------
func _pins_file() -> String:
	var scene := get_tree().current_scene
	return scene.scene_file_path.get_base_dir().path_join("pins.json") if scene else ""


func _load_pins() -> void:
	_pins = []
	var f := _pins_file()
	if FileAccess.file_exists(f):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(f))
		if parsed is Array:
			for p: Dictionary in parsed:
				p.id = int(p.id)
				_pins.append(p)
	_show_pins()


func _show_pins() -> void:
	ui.show_pins(_pins)
	ui.minimap.pins = _pins
	if _overlay:
		_overlay.show_pins(_pins)


func _save_pins() -> void:
	_show_pins()
	if not save_enabled:
		return
	var f := FileAccess.open(_pins_file(), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_pins, "  "))


func pin_add_confirm(note: String) -> void:
	ui.pin_popup.visible = false
	if _pin_at == Vector3.INF:
		return
	var next := 1
	for p: Dictionary in _pins:
		next = maxi(next, int(p.id) + 1)
	var pin := {"id": next, "x": snappedf(_pin_at.x, 0.1), "y": snappedf(_pin_at.y, 0.1),
			"z": snappedf(_pin_at.z, 0.1), "note": note.strip_edges()}
	var do_fn := func() -> void:
		_pins.append(pin)
		_save_pins()
	var undo_fn := func() -> void:
		_pins.erase(pin)
		_save_pins()
	_commit("Add pin #%d" % next, do_fn, undo_fn)
	ui.say("Pin #%d at %s" % [next, Coordinates.text(_pin_at)])


func pin_delete(id: int) -> void:
	for p: Dictionary in _pins:
		if int(p.id) == id:
			var i := _pins.find(p)
			var do_fn := func() -> void:
				_pins.erase(p)
				_save_pins()
			var undo_fn := func() -> void:
				_pins.insert(mini(i, _pins.size()), p)
				_save_pins()
			_commit("Delete pin #%d" % id, do_fn, undo_fn)
			return


func pin_go(id: int) -> void:
	for p: Dictionary in _pins:
		if int(p.id) == id:
			_camera.look_at_point(Vector3(p.x, p.y + 1.0, p.z), 16.0)


func copy_pins() -> void:
	if _pins.is_empty():
		ui.say("No pins yet")
		return
	var lines := ["Micro 15 pins:"]
	for p: Dictionary in _pins:
		lines.append("#%d at %s: %s" % [p.id, Coordinates.text(Vector3(p.x, p.y, p.z), true), p.note])
	_copy("\n".join(lines))


# ----------------------------------------------------------------------------
# Sky & light
# ----------------------------------------------------------------------------
func look_set(key: String, value: Variant) -> void:
	var cycle := _sun_cycle()
	if cycle == null:
		return
	cycle.look[key] = value
	match key:
		"time":
			cycle.time_of_day = value
		"day_of_year":
			cycle.day_of_year = int(value)
		"north_offset":
			cycle.north_offset = value
	cycle.apply()


func look_preset(preset_name: String) -> void:
	var cycle := _sun_cycle()
	if cycle == null:
		return
	cycle.set_look(cycle.preset(preset_name))
	ui.show_look(cycle.look, cycle.running)
	ui.say("Look: " + preset_name, 2.0)


func look_save() -> void:
	var cycle := _sun_cycle()
	if cycle and save_enabled and cycle.save_look():
		ui.say("Saved: the game starts with this look now (%s)" % cycle.look_file)
	else:
		ui.say("This level has no look file to save to")


func look_reset() -> void:
	var cycle := _sun_cycle()
	if cycle == null:
		return
	if FileAccess.file_exists(cycle.look_file):
		cycle.set_look(SunCycle.look_from_json(FileAccess.get_file_as_string(cycle.look_file)))
	else:
		cycle.set_look(cycle.preset("Summer noon"))
	ui.show_look(cycle.look, cycle.running)
	ui.say("Back to the saved look", 2.0)


func look_copy() -> void:
	var cycle := _sun_cycle()
	if cycle:
		_copy("Micro 15 look:\n" + cycle.look_to_json())


func set_day_running(on: bool) -> void:
	var cycle := _sun_cycle()
	if cycle:
		cycle.running = on


func set_day_length(minutes: float) -> void:
	var cycle := _sun_cycle()
	if cycle:
		cycle.day_minutes = minutes


# ----------------------------------------------------------------------------
# Level helpers
# ----------------------------------------------------------------------------
func _screenshot() -> void:
	var dir := ProjectSettings.globalize_path("res://").path_join("../screenshots")
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join(Time.get_datetime_string_from_system().replace(":", "-") + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	if active:
		ui.say("Saved " + path)


func _scatters() -> Array[Scatter]:
	var out: Array[Scatter] = []
	var scene := get_tree().current_scene
	if scene:
		for n in scene.get_children():
			if n is Scatter:
				out.append(n)
	return out


func _grass_field() -> GrassField:
	for n in get_tree().current_scene.get_children():
		if n is GrassField:
			return n
	return null


func _sun_cycle() -> SunCycle:
	var scene := get_tree().current_scene
	return scene.get_node_or_null("SunCycle") as SunCycle if scene else null


func _player() -> CharacterBody3D:
	var scene := get_tree().current_scene
	return scene.get_node_or_null("Player") as CharacterBody3D if scene else null


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
func _save_placed() -> void:
	if not save_enabled:
		return
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
	if err != OK and active:
		ui.say("Could not save " + path)
