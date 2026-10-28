## The map editor's free camera. Hold the right mouse button and move the
## mouse to look around; WASD (or the arrow keys) move, while looking Q / E
## go down / up,
## Shift is faster, the mouse wheel moves forwards and back (while the right
## button is held it changes the flying speed instead).
class_name EditorCamera
extends Camera3D

var speed := 20.0
var looking := false
var _yaw := 0.0
var _pitch := -0.5
var _glide_to := Vector3.INF             # focus: glides here


func _ready() -> void:
	fov = 60.0
	far = 3000.0


## Starts from another camera's view.
func copy_view(other: Camera3D) -> void:
	global_position = other.global_position
	var f := -other.global_basis.z
	_yaw = atan2(-f.x, -f.z)
	_pitch = asin(clampf(f.y, -1.0, 1.0))
	_apply()


func look_at_point(target: Vector3, distance := 18.0) -> void:
	var f := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	_pitch = deg_to_rad(-35.0)
	var back := -(f * cos(_pitch) + Vector3.UP * sin(_pitch))
	_glide_to = target + back * distance
	_apply()


## Jumps to (x, z) on the map keeping the height above the ground and the view.
func move_over(x: float, z: float, height := 40.0) -> void:
	_glide_to = Vector3.INF
	var f := -global_basis.z
	var ahead := Vector2(f.x, f.z).normalized() * (height / maxf(tan(-_pitch), 0.3))
	global_position = Vector3(x - ahead.x, height, z - ahead.y)


func look(relative: Vector2) -> void:
	_yaw -= relative.x * 0.0035
	_pitch = clampf(_pitch - relative.y * 0.0035, -1.55, 1.55)
	_apply()


func _apply() -> void:
	basis = Basis.from_euler(Vector3(_pitch, _yaw, 0.0))


func facing() -> String:
	var f := -global_basis.z
	return Coordinates.compass(Vector2(f.x, f.z))


## arrows: whether the arrow keys move the camera (they nudge the selection
## instead while something is selected).
func fly(delta: float, typing: bool, arrows := true) -> void:
	if _glide_to != Vector3.INF:
		global_position = global_position.lerp(_glide_to, 1.0 - exp(-10.0 * delta))
		if global_position.distance_to(_glide_to) < 0.05:
			_glide_to = Vector3.INF
	if typing or Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META):
		return
	var move := Vector3.ZERO
	if Input.is_key_pressed(KEY_W) or (arrows and Input.is_key_pressed(KEY_UP)):
		move.z -= 1.0
	if Input.is_key_pressed(KEY_S) or (arrows and Input.is_key_pressed(KEY_DOWN)):
		move.z += 1.0
	if Input.is_key_pressed(KEY_A) or (arrows and Input.is_key_pressed(KEY_LEFT)):
		move.x -= 1.0
	if Input.is_key_pressed(KEY_D) or (arrows and Input.is_key_pressed(KEY_RIGHT)):
		move.x += 1.0
	if move == Vector3.ZERO and not (looking and (Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_E))):
		return
	_glide_to = Vector3.INF
	var v := global_basis * move
	if looking:
		if Input.is_key_pressed(KEY_E):
			v.y += 1.0
		if Input.is_key_pressed(KEY_Q):
			v.y -= 1.0
	var fast := 4.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0
	global_position += v.normalized() * speed * fast * delta


func dolly(amount: float) -> void:
	_glide_to = Vector3.INF
	global_position += -global_basis.z * amount * maxf(speed * 0.25, 1.0)
