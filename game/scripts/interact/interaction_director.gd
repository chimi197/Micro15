## Makes the neighbourhood usable: finds the things that can be used (placed
## with the map editor or part of the map) and gives each its Interactable.
## Nothing is saved into the level: the interactables are made fresh every
## run, so the map editor's files stay exactly as Johnny left them.
##
## * benches (placed and the map's own), chess table stools, picnic tables:
##   Seat
## * swings: the seats and chains are cut off the mesh (MeshSplit) and hung
##   as SwingSeats; the seesaw beam likewise (SeesawSeat)
## * the slide: SlideUse; the carpet beater: a LeanSpot by its post
## * kiosk, ice cream freezer, drinks fridge, fruit stand, corner shop: Shop
## * a ball at each playground and by each goal or hoop (Ball, GoalZone)
## * bottle caps (CapField) and memories (pins whose note starts with
##   "MEMORY:", MemorySpot)
##
## Things placed while the game runs (map editor) get theirs at once.
class_name InteractionDirector
extends Node3D

## asset: [[position, yaw (0 = facing +z), width], ...] in the asset's space
const SEATS := {
	"bench": [[Vector3(0, 0.48, -0.03), 0.0, 1.7]],
	"bench_wood": [[Vector3(0, 0.485, 0.0), 0.0, 1.7]],
	"chess_table": [[Vector3(0, 0.46, -0.75), 0.0, 0.4], [Vector3(0, 0.46, 0.75), PI, 0.4]],
	"picnic_table": [[Vector3(0, 0.48, -0.645), 0.0, 1.7], [Vector3(0, 0.48, 0.645), PI, 1.7]],
}
const SHOPS := ["kiosk", "ice_cream_freezer", "drinks_fridge", "fruit_stand", "mini_market"]
const PLAYGROUND := ["swing", "slide", "seesaw", "sandbox", "carpet_beater"]

@export var placed_path := NodePath("../Placed")
@export var props_path := NodePath("../Props")
@export var boundary_path := NodePath("../Boundary")
@export var cap_count := 60

var caps: CapField
var memories: Array[MemorySpot] = []
var balls: Array[Ball] = []
var _done := {}                          # instance id of placed things already set up
var _anchors: Array[Vector3] = []


func _ready() -> void:
	_setup.call_deferred()


func _setup() -> void:
	var placed := get_node_or_null(placed_path)
	if placed:
		for child in placed.get_children():
			_setup_thing(child)
		placed.child_entered_tree.connect(func(n: Node) -> void: _setup_thing.call_deferred(weakref(n)))
	_setup_map_benches()
	_setup_memories()
	await get_tree().physics_frame        # colliders in place before the caps look for ground
	caps = CapField.new()
	caps.name = "Caps"
	add_child(caps)
	caps.scatter(_anchors, cap_count, _inside)


func _inside(p: Vector2) -> bool:
	var b := get_node_or_null(boundary_path) as Boundary
	return b == null or b.polygon.size() < 3 or b.contains(p)


func _setup_thing(n: Variant) -> void:
	if n is WeakRef:
		n = (n as WeakRef).get_ref()
	if not is_instance_valid(n):
		return
	var thing := n as Node3D
	if thing == null or _done.has(thing.get_instance_id()) or not thing.is_inside_tree():
		return
	var kind := thing.scene_file_path.get_file().get_basename()
	if kind == "":
		return
	_done[thing.get_instance_id()] = true
	if SEATS.has(kind):
		for s: Array in SEATS[kind]:
			var seat := Seat.new()
			seat.position = s[0]
			seat.rotation.y = s[1]
			seat.seat_height = (s[0] as Vector3).y
			seat.width = s[2]
			thing.add_child(seat)
		_anchors.append(thing.global_position)
	elif kind == "swing":
		_setup_swing(thing)
	elif kind == "seesaw":
		_setup_seesaw(thing)
	elif kind == "slide":
		var use := SlideUse.new()
		thing.add_child(use)
	elif kind == "carpet_beater":
		var spot := LeanSpot.new()
		spot.position = Vector3(-1.3, 0, 0.22)
		thing.add_child(spot)
	elif kind in SHOPS:
		var shop := Shop.new()
		shop.kind = kind
		var box := _model_box(thing)
		shop.position = Vector3(box.get_center().x, 1.0, box.end.z + 0.25)
		thing.add_child(shop)
		_anchors.append(thing.to_global(shop.position))
	elif kind == "football_goal":
		var goal := GoalZone.new()
		goal.size = Vector3(2.9, 1.9, 0.8)
		goal.position = Vector3(0, 0.95, -0.45)
		goal.label = "Goal!"
		thing.add_child(goal)
		_add_ball(thing.to_global(Vector3(0.6, 0.3, 4.0)))
	elif kind == "basketball_hoop":
		var hoop := GoalZone.new()
		hoop.size = Vector3(0.3, 0.12, 0.3)
		hoop.position = Vector3(0, 2.78, 0.05)
		hoop.label = "Basket!"
		thing.add_child(hoop)
		_add_ball(thing.to_global(Vector3(0.8, 0.3, 2.5)))
	if kind in PLAYGROUND:
		_anchors.append(thing.global_position)
		_ball_for_playground(thing)


func _model_box(thing: Node3D) -> AABB:
	var mi := thing.get_node_or_null("Model") as MeshInstance3D
	return mi.get_aabb() if mi else AABB(Vector3(-0.5, 0, -0.5), Vector3(1, 1, 1))


func _setup_swing(thing: Node3D) -> void:
	var model := thing.get_node_or_null("Model") as MeshInstance3D
	if model == null or model.mesh == null:
		return
	var parts := MeshSplit.split(model.mesh, 3, "swing", func(c: Vector3) -> int:
		if c.y < 2.12 and c.y > 0.3 and absf(absf(c.x) - 0.55) < 0.3:
			return 1 if c.x < 0.0 else 2
		return 0)
	var pivots := MeshSplit.apply(thing, parts, [null, Vector3(-0.55, 2.16, 0), Vector3(0.55, 2.16, 0)])
	for i in pivots.size():
		var seat := SwingSeat.new()
		seat.position = (pivots[i] as Node3D).position
		seat.seat = pivots[i]
		thing.add_child(seat)
		seat.creaked.connect(func(s: float) -> void:
			get_tree().call_group("sound", "play_at", "creak", seat.global_position, s))


func _setup_seesaw(thing: Node3D) -> void:
	var model := thing.get_node_or_null("Model") as MeshInstance3D
	if model == null or model.mesh == null:
		return
	var parts := MeshSplit.split(model.mesh, 2, "seesaw", func(c: Vector3) -> int:
		return 1 if c.y > 0.56 and absf(c.x) > 0.07 else 0)
	var pivots := MeshSplit.apply(thing, parts, [null, Vector3(0, 0.6, 0)])
	var ends: Array[SeesawSeat] = []
	for side in [1, -1]:
		var s := SeesawSeat.new()
		s.side = side
		s.position = Vector3(0, 0.6, 0)
		s.beam = pivots[0]
		thing.add_child(s)
		s.bumped.connect(func(k: float) -> void:
			get_tree().call_group("sound", "play_at", "thump", s.global_position, k))
		ends.append(s)
	ends[0].other = ends[1]
	ends[1].other = ends[0]


func _ball_for_playground(thing: Node3D) -> void:
	for b in balls:
		if b.spot.distance_to(thing.global_position) < 30.0:
			return
	if balls.size() >= 8:
		return
	_add_ball(thing.to_global(Vector3(2.2, 0.3, 1.8)))


func _add_ball(at: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 3.0, at + Vector3.DOWN * 5.0)
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		at = hit.position + Vector3.UP * (Ball.RADIUS + 0.02)
	var ball := Ball.new()
	ball.name = "Ball%d" % balls.size()
	ball.position = at
	add_child(ball)
	ball.spot = at
	balls.append(ball)


## The map's own benches (Props scatter records) inside the play area.
func _setup_map_benches() -> void:
	var props := get_node_or_null(props_path)
	if props == null or not props.has_method("record_count"):
		return
	for r in props.record_count():
		if props.record_proto(r) != "bench" or props.is_removed(r):
			continue
		var xf: Transform3D = props.record_transform(r)
		if not _inside(Vector2(xf.origin.x, xf.origin.z)):
			continue
		var seat := Seat.new()
		seat.transform = xf * Transform3D(Basis(), Vector3(0, 0.48, -0.03))
		seat.width = 1.7
		seat.scatter = props
		seat.record = r
		add_child(seat)
		_anchors.append(xf.origin)


func _setup_memories() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var path := scene.scene_file_path.get_base_dir().path_join("pins.json")
	if not FileAccess.file_exists(path):
		return
	var pins: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not pins is Array:
		return
	for pin: Dictionary in pins:
		var note: String = pin.get("note", "")
		if not note.to_upper().begins_with("MEMORY"):
			continue
		var parsed := MemorySpot.parse(note)
		var m := MemorySpot.new()
		m.id = "memory_%s" % pin.get("id", memories.size())
		m.title = parsed[0]
		m.text = parsed[1]
		m.position = Vector3(pin.x, pin.y, pin.z)
		add_child(m)
		memories.append(m)


## Counts a ball going through (a goal mouth, a hoop): a toast and a cheer.
class GoalZone extends Area3D:
	var size := Vector3.ONE
	var label := "Goal!"
	var _last := -10.0

	func _ready() -> void:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		add_child(shape)
		monitoring = true
		body_entered.connect(func(b: Node) -> void:
			if b is Ball and Time.get_ticks_msec() / 1000.0 - _last > 2.0:
				_last = Time.get_ticks_msec() / 1000.0
				get_tree().call_group("hud", "toast", label)
				get_tree().call_group("sound", "play_at", "score", global_position, 1.0)
				var kid := get_tree().get_first_node_in_group("player")
				if kid:
					kid.face.express("grin", 2.0))
