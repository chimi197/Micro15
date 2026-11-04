## A memory: a place in the neighbourhood with a story. Made from the map
## editor's pins whose note starts with "MEMORY:" (F1, pin tool), so Johnny
## writes them where they happened. The first line after "MEMORY:" is the
## title, the rest the story; a few motes of light hang there until it has
## been read, and it stays in the journal afterwards.
class_name MemorySpot
extends Interactable

var id := ""
var title := ""
var text := ""
var _motes: GPUParticles3D


func _init() -> void:
	prompt = "Remember"
	reach = 2.0
	needs_facing = false


static func parse(note: String) -> Array:
	var body := note.substr(note.find(":") + 1).strip_edges()
	var lines := body.split("\n", false, 1)
	var t := lines[0].strip_edges() if lines.size() > 0 else "A memory"
	var rest := lines[1].strip_edges() if lines.size() > 1 else ""
	if rest == "" and t.length() > 48:
		rest = t
		t = "A memory"
	return [t, rest]


func _ready() -> void:
	_motes = GPUParticles3D.new()
	_motes.amount = 14
	_motes.lifetime = 3.5
	_motes.visibility_aabb = AABB(Vector3(-1.5, -0.5, -1.5), Vector3(3, 3, 3))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.6
	pm.gravity = Vector3(0, 0.08, 0)
	pm.initial_velocity_min = 0.02
	pm.initial_velocity_max = 0.08
	pm.direction = Vector3.UP
	pm.spread = 180.0
	pm.scale_min = 0.6
	pm.scale_max = 1.0
	var curve := CurveTexture.new()
	var c := Curve.new()
	c.add_point(Vector2(0, 0))
	c.add_point(Vector2(0.3, 1))
	c.add_point(Vector2(1, 0))
	curve.curve = c
	pm.scale_curve = curve
	_motes.process_material = pm
	var mote := SphereMesh.new()
	mote.radius = 0.018
	mote.height = 0.036
	mote.radial_segments = 8
	mote.rings = 4
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.92, 0.7)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.85, 0.55)
	m.emission_energy_multiplier = 2.0
	mote.material = m
	_motes.draw_pass_1 = mote
	_motes.position = Vector3.UP * 0.9
	add_child(_motes)
	_motes.emitting = not Save.has_memory(id)


func prompt_for(_kid: Node3D) -> String:
	return "Remember: " + title


func interact(kid: Node3D) -> void:
	super.interact(kid)
	var first := Save.remember(id)
	_motes.emitting = false
	kid.face.express("happy", 4.0)
	get_tree().call_group("hud", "show_memory", title, text, first)
