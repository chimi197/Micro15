## The map editor's map: a picture of the whole neighbourhood seen from
## straight above (taken once, the first time it is shown), with the
## coordinate grid every 100 m, the camera, the player and the pins on it.
## Click to fly the camera there; the mouse shows the coordinates under it.
class_name EditorMinimap
extends Control

signal clicked(x: float, z: float)
signal hovered(x: float, z: float)

## the square of the map shown: x and z from -HALF to +HALF metres
const HALF := 650.0
const RESOLUTION := 1024

var texture: Texture2D
var camera_at := Vector3.ZERO
var camera_dir := Vector2(0, -1)
var player_at := Vector3.INF
var pins: Array = []                      # [{id, x, z, note}, ...]
var _hover := Vector2.INF


## Renders the picture from above with the given nodes hidden (trees,
## grass...), so the map reads as a plan of streets and buildings.
func capture(world_root: Node3D, hide: Array) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var vp := SubViewport.new()
	vp.size = Vector2i(RESOLUTION, RESOLUTION)
	vp.world_3d = world_root.get_world_3d()
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = HALF * 2.0
	cam.near = 1.0
	cam.far = 1200.0
	cam.position = Vector3(0, 600, 0)
	cam.rotation_degrees = Vector3(-90, 0, 0)          # up on the picture is north (-z)
	vp.add_child(cam)
	add_child(vp)
	var was := []
	for n: Node3D in hide:
		was.append(n.visible)
		n.visible = false
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	for i in hide.size():
		hide[i].visible = was[i]
	texture = ImageTexture.create_from_image(vp.get_texture().get_image())
	vp.queue_free()
	queue_redraw()


func to_map(p: Vector2) -> Vector2:          # screen (local) -> world x, z
	return (p / size - Vector2(0.5, 0.5)) * HALF * 2.0


func to_screen(x: float, z: float) -> Vector2:
	return (Vector2(x, z) / (HALF * 2.0) + Vector2(0.5, 0.5)) * size


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover = to_map(event.position)
		hovered.emit(_hover.x, _hover.y)
		queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var p := to_map(event.position)
		clicked.emit(p.x, p.y)
		accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_hover = Vector2.INF
		queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color(0.32, 0.4, 0.3))
	if texture:
		draw_texture_rect(texture, r, false)
	var font := get_theme_default_font()
	for v in range(-600, 601, 100):
		var a := to_screen(v, -HALF)
		var b := to_screen(v, HALF)
		draw_line(a, b, Color(1, 1, 1, 0.35 if v != 0 else 0.7), 1.0)
		draw_line(to_screen(-HALF, v), to_screen(HALF, v), Color(1, 1, 1, 0.35 if v != 0 else 0.7), 1.0)
		if v % 200 == 0:
			draw_string(font, to_screen(v, -HALF) + Vector2(2, 12), str(v), HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
					EditorTheme.YELLOW)
			draw_string(font, to_screen(-HALF, v) + Vector2(2, -2), str(v), HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
					EditorTheme.YELLOW)
	draw_string(font, Vector2(size.x - 14, 14), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
	for pin: Dictionary in pins:
		var p := to_screen(pin.x, pin.z)
		draw_circle(p, 4.0, EditorTheme.DANGER)
		draw_string(font, p + Vector2(5, 4), "#%d" % pin.id, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)
	if player_at != Vector3.INF:
		draw_circle(to_screen(player_at.x, player_at.z), 4.0, Color(0.3, 0.9, 0.4))
	var c := to_screen(camera_at.x, camera_at.z)
	var d := camera_dir.normalized()
	var side := Vector2(-d.y, d.x)
	draw_colored_polygon(PackedVector2Array([c + d * 9.0, c - d * 5.0 + side * 5.0, c - d * 5.0 - side * 5.0]),
			EditorTheme.ACCENT_HOVER)
	if _hover != Vector2.INF:
		var label := "x %d, z %d" % [roundi(_hover.x), roundi(_hover.y)]
		draw_string(font, Vector2(6, size.y - 6), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
