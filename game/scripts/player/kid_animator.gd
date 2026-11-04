## Drives the boy's animations through an AnimationTree built here from the
## clips in kid.glb (see blender/build_character.py):
##
## * a locomotion blend space (idle, walk, jog, run) whose cycles all last
##   the same time, so they blend in step; one time scale matches the stride
##   to the ground speed, so the feet do not slide;
## * a crouch blend space, and whole-body loops for sitting, swinging,
##   sliding, pushing, carrying and idling (`set_mode`);
## * one-shot actions on top (jump, land, punches, sit down, climb, kick,
##   throw, fidgets...; `play`), which fade back into the current mode;
## * a hand layer that lays a pose (fist, grip, point, open) over the
##   fingers only (`set_hands`).
##
## It also keeps the gait phase, so footsteps can be played when a foot
## comes down (signal `footstep`).
class_name KidAnimator
extends Node

signal footstep(side: String, strength: float)
signal action_finished(clip: String)

const MODES := ["loco", "crouch", "fall", "sit", "swing", "slide", "push", "carry", "arms", "lean"]
const MODE_CLIPS := {"fall": "fall", "sit": "sit_idle", "swing": "swing_pump", "slide": "slide_loop",
		"push": "push", "carry": "carry_walk", "arms": "idle_arms", "lean": "idle_lean"}
## blend space points: clip, ground speed (m/s) it stands for
const LOCO := [["idle", 0.0], ["walk", 1.3], ["jog", 2.6], ["run", 4.3]]
const CROUCH := [["crouch_idle", 0.0], ["crouch_walk", 0.6]]
const HAND_POSES := ["hand_relaxed", "hand_fist", "hand_grip", "hand_point", "hand_open"]

var tree: AnimationTree
var player: AnimationPlayer
var skeleton: Skeleton3D
var info: Dictionary
var mode := "loco"
var action := ""                      ## the one-shot playing, "" when none
var action_left := 0.0                ## seconds of it still to play
var gait_phase := 0.0                 ## 0..1 through the current gait cycle
var _speed := 0.0
var _crouch_speed := 0.0
var _hands := 0.0
var _hands_target := 0.0
var _strikes := {}                    # gait: {side: phase}
var _last_phase := 0.0


func setup(model: Node3D, kid_info: Dictionary) -> void:
	info = kid_info
	player = model.find_child("AnimationPlayer", true, false)
	skeleton = model.find_child("Skeleton3D", true, false)
	for anim_name: String in info.get("loops", []):
		if player.has_animation(anim_name):
			player.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
	_strikes = info.get("foot_strikes", {})
	player.stop()
	tree = AnimationTree.new()
	tree.name = "AnimationTree"
	player.get_parent().add_child(tree)
	tree.root_node = tree.get_path_to(player.get_node(player.root_node))
	tree.anim_player = tree.get_path_to(player)
	tree.tree_root = _build()
	tree.active = true
	set_mode("loco")


func _anim(clip: String) -> AnimationNodeAnimation:
	var n := AnimationNodeAnimation.new()
	n.animation = clip
	return n


func _build() -> AnimationNodeBlendTree:
	var bt := AnimationNodeBlendTree.new()
	var loco := AnimationNodeBlendSpace1D.new()
	loco.min_space = 0.0
	loco.max_space = 4.3
	loco.sync = true
	for p: Array in LOCO:
		loco.add_blend_point(_anim(p[0]), p[1], -1, p[0])
	bt.add_node("loco", loco)
	bt.add_node("loco_scale", AnimationNodeTimeScale.new())
	bt.connect_node("loco_scale", 0, "loco")
	var crouch := AnimationNodeBlendSpace1D.new()
	crouch.max_space = 0.6
	crouch.sync = true
	for p: Array in CROUCH:
		crouch.add_blend_point(_anim(p[0]), p[1], -1, p[0])
	bt.add_node("crouch", crouch)
	bt.add_node("crouch_scale", AnimationNodeTimeScale.new())
	bt.connect_node("crouch_scale", 0, "crouch")
	var modes := AnimationNodeTransition.new()
	modes.xfade_time = 0.25
	modes.input_count = MODES.size()
	for i in MODES.size():
		modes.set_input_name(i, MODES[i])
	bt.add_node("mode", modes)
	bt.connect_node("mode", 0, "loco_scale")
	bt.connect_node("mode", 1, "crouch_scale")
	for i in range(2, MODES.size()):
		var m: String = MODES[i]
		bt.add_node("m_" + m, _anim(MODE_CLIPS[m]))
		bt.connect_node("mode", i, "m_" + m)
	var shot := AnimationNodeOneShot.new()
	shot.fadein_time = 0.12
	shot.fadeout_time = 0.22
	bt.add_node("action", shot)
	bt.add_node("action_clip", _anim("interact"))
	bt.connect_node("action", 0, "mode")
	bt.connect_node("action", 1, "action_clip")
	# hand poses over the fingers only
	var hands := AnimationNodeBlend2.new()
	hands.filter_enabled = true
	var root := player.get_node(player.root_node)
	var skel_path := String(root.get_path_to(skeleton))
	for side: String in info.get("fingers", {}):
		for b: String in info.fingers[side]:
			hands.set_filter_path(NodePath("%s:%s" % [skel_path, b]), true)
	bt.add_node("hands", hands)
	var poses := AnimationNodeTransition.new()
	poses.xfade_time = 0.15
	poses.input_count = HAND_POSES.size()
	for i in HAND_POSES.size():
		poses.set_input_name(i, HAND_POSES[i])
		bt.add_node(HAND_POSES[i], _anim(HAND_POSES[i]))
	bt.add_node("hand_pose", poses)
	for i in HAND_POSES.size():
		bt.connect_node("hand_pose", i, HAND_POSES[i])
	bt.connect_node("hands", 0, "action")
	bt.connect_node("hands", 1, "hand_pose")
	bt.connect_node("output", 0, "hands")
	return bt


## Switches the whole-body loop: one of MODES.
func set_mode(new_mode: String) -> void:
	if new_mode == mode and tree.get("parameters/mode/current_state") == new_mode:
		return
	if new_mode in ["loco", "crouch"] and mode not in ["loco", "crouch"]:
		gait_phase = 0.0
	mode = new_mode
	tree.set("parameters/mode/transition_request", new_mode)


## Locomotion: ground speed in m/s (sets the blend and the stride pace).
func set_speed(speed: float, delta: float) -> void:
	_speed = speed
	if mode == "loco":
		tree.set("parameters/loco/blend_position", minf(speed, 4.3))
		var cycle_speed := _cycle_speed(speed)
		var scale := 1.0
		if speed > 0.05:
			scale = clampf(speed / cycle_speed, 0.4, 2.6)
		tree.set("parameters/loco_scale/scale", scale)
		_advance_phase(scale * delta / float(info.get("cycle", 1.0)) if speed > 0.05 else 0.0,
				_gait_for(speed), clampf(speed / 3.0, 0.3, 1.2))
	elif mode == "crouch":
		tree.set("parameters/crouch/blend_position", minf(speed, 0.6))
		var cs: float = info.gait_speed.get("crouch_walk", 0.35)
		var scale := clampf(speed / cs, 0.5, 2.0) if speed > 0.05 else 1.0
		tree.set("parameters/crouch_scale/scale", scale)
		var length := player.get_animation("crouch_walk").length if player.has_animation("crouch_walk") else 2.0
		_advance_phase(scale * delta / length if speed > 0.05 else 0.0, "crouch_walk", 0.2)


## Ground speed of the blended cycle at a time scale of 1, for a speed.
func _cycle_speed(speed: float) -> float:
	var pts := []
	for p: Array in LOCO:
		if p[0] != "idle":
			pts.append([p[1], float(info.gait_speed.get(p[0], 1.0))])
	if speed <= pts[0][0]:
		return pts[0][1]
	for i in pts.size() - 1:
		if speed <= pts[i + 1][0]:
			var t: float = (speed - pts[i][0]) / (pts[i + 1][0] - pts[i][0])
			return lerpf(pts[i][1], pts[i + 1][1], t)
	return pts[-1][1]


func _gait_for(speed: float) -> String:
	if speed < 1.9:
		return "walk"
	return "jog" if speed < 3.5 else "run"


func _advance_phase(step: float, gait: String, strength: float) -> void:
	if step <= 0.0:
		return
	var before := gait_phase
	gait_phase = fposmod(gait_phase + step, 1.0)
	var strikes: Dictionary = _strikes.get(gait, {"L": 0.0, "R": 0.5})
	for side: String in strikes:
		var at: float = strikes[side]
		var crossed := (before < at and gait_phase >= at) if gait_phase >= before \
				else (before < at or gait_phase >= at)
		if crossed:
			footstep.emit(side, strength)


## Plays a one-shot clip over the current mode; returns its length in
## seconds (0 if there is no such clip). speed scales its playback.
func play(clip: String, speed := 1.0) -> float:
	if not player.has_animation(clip):
		return 0.0
	var node := (tree.tree_root as AnimationNodeBlendTree).get_node("action_clip") as AnimationNodeAnimation
	node.animation = clip
	tree.set("parameters/action/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	action = clip
	var length := player.get_animation(clip).length / maxf(speed, 0.01)
	action_left = length
	return length


## Fades a one-shot out early.
func stop_action() -> void:
	if action != "":
		tree.set("parameters/action/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)
		action = ""
		action_left = 0.0


func is_playing(clip := "") -> bool:
	return action != "" and (clip == "" or action == clip)


## Lays a hand pose over the fingers; weight 0 hands them back to the clips.
func set_hands(pose: String, weight := 1.0) -> void:
	if pose in HAND_POSES:
		tree.set("parameters/hand_pose/transition_request", pose)
	_hands_target = weight


func _process(delta: float) -> void:
	if tree == null:
		return
	if action != "":
		action_left -= delta
		if action_left <= 0.0:
			var done := action
			action = ""
			action_finished.emit(done)
	_hands = move_toward(_hands, _hands_target, delta * 5.0)
	tree.set("parameters/hands/blend_amount", _hands)


## Freezes the boy in one frame of a clip (preview renders).
func show_pose(clip: String, time: float) -> void:
	tree.active = false
	player.play(clip)
	player.seek(time, true)
	player.pause()


## Name of what is showing now, for tests: the action, else the mode and
## (for locomotion) the nearest gait.
func current() -> String:
	if action != "":
		return action
	if mode == "loco":
		return "idle" if _speed < 0.2 else _gait_for(_speed)
	if mode == "crouch":
		return "crouch_idle" if _speed < 0.15 else "crouch_walk"
	return MODE_CLIPS.get(mode, mode)
