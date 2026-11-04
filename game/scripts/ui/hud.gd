## What is drawn over the game: the "use" prompt, bottle caps, short
## messages, the memory card, the journal (Tab) and the pause menu (Esc).
## Photo mode (V) is its own node (PhotoMode) that hides all of this.
##
## Other scripts talk to it through the "hud" group, so they need no
## reference: get_tree().call_group("hud", "toast", "Goal!").
class_name Hud
extends CanvasLayer

const INK := Color(0.96, 0.94, 0.89)
const MUTED := Color(0.78, 0.76, 0.72)
const PANEL := Color(0.09, 0.1, 0.12, 0.78)
const WARM := Color(1.0, 0.8, 0.42)

var player: Node3D
var photo: PhotoMode
var _prompt: PanelContainer
var _prompt_key: Label
var _prompt_text: Label
var _caps: PanelContainer
var _caps_label: Label
var _caps_show := 0.0
var _toasts: VBoxContainer
var _memory: PanelContainer
var _memory_title: Label
var _memory_text: Label
var _memory_left := 0.0
var _journal: PanelContainer
var _journal_text: RichTextLabel
var _pause: Control
var _pad := false                         # last input came from a gamepad
var _root: Control


func _ready() -> void:
	add_to_group("hud")
	layer = 5
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = GameTheme.make()
	add_child(_root)
	_build_prompt()
	_build_caps()
	_build_toasts()
	_build_memory()
	_build_journal()
	_pause = PauseMenu.new()
	_pause.hud = self
	_root.add_child(_pause)
	photo = PhotoMode.new()
	photo.player = player
	photo.hud = self
	add_child(photo)
	Save.caps_changed.connect(func(_t: int) -> void: _flash_caps())
	Save.settings_changed.connect(apply_settings)
	apply_settings()
	if "--shots" in OS.get_cmdline_user_args() or "--editor-shots" in OS.get_cmdline_user_args():
		_root.visible = false


func _label(size: int, colour := INK) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.35))
	l.add_theme_constant_override("shadow_offset_y", 1)
	return l


func _build_prompt() -> void:
	_prompt = PanelContainer.new()
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_prompt.position.y -= 64
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_prompt_key = _label(17, Color(0.1, 0.1, 0.12))
	var key_box := PanelContainer.new()
	key_box.add_theme_stylebox_override("panel", GameTheme.box(INK, 6, 4.0))
	_prompt_key.custom_minimum_size.x = 18
	_prompt_key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key_box.add_child(_prompt_key)
	row.add_child(key_box)
	_prompt_text = _label(19)
	row.add_child(_prompt_text)
	_prompt.add_child(row)
	_prompt.visible = false
	_root.add_child(_prompt)


func _build_caps() -> void:
	_caps = PanelContainer.new()
	_caps.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_caps.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_caps.position = Vector2(-24, 24)
	_caps.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var dot := ColorRect.new()
	dot.color = Color("#c8312b")
	dot.custom_minimum_size = Vector2(14, 14)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(dot)
	_caps_label = _label(20)
	row.add_child(_caps_label)
	_caps.add_child(row)
	_caps.modulate.a = 0.0
	_root.add_child(_caps)


func _build_toasts() -> void:
	_toasts = VBoxContainer.new()
	_toasts.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toasts.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toasts.position.y = 28
	_toasts.alignment = BoxContainer.ALIGNMENT_BEGIN
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toasts.add_theme_constant_override("separation", 6)
	_root.add_child(_toasts)


func _build_memory() -> void:
	_memory = PanelContainer.new()
	_memory.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	_memory.grow_vertical = Control.GROW_DIRECTION_BOTH
	_memory.position.x = 48
	_memory.custom_minimum_size = Vector2(420, 0)
	_memory.add_theme_stylebox_override("panel", GameTheme.box(Color(0.98, 0.95, 0.88, 0.95), 4, 22.0))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	var kicker := _label(13, Color(0.55, 0.42, 0.25))
	kicker.text = "A MEMORY"
	col.add_child(kicker)
	_memory_title = _label(24, Color(0.16, 0.14, 0.12))
	_memory_title.remove_theme_color_override("font_shadow_color")
	_memory_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_memory_title)
	_memory_text = _label(17, Color(0.25, 0.22, 0.2))
	_memory_text.remove_theme_color_override("font_shadow_color")
	_memory_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_memory_text.custom_minimum_size.x = 380
	col.add_child(_memory_text)
	_memory.add_child(col)
	_memory.visible = false
	_root.add_child(_memory)


func _build_journal() -> void:
	_journal = PanelContainer.new()
	_journal.set_anchors_preset(Control.PRESET_CENTER)
	_journal.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_journal.grow_vertical = Control.GROW_DIRECTION_BOTH
	_journal.custom_minimum_size = Vector2(560, 420)
	_journal.add_theme_stylebox_override("panel", GameTheme.box(Color(0.98, 0.95, 0.88, 0.97), 4, 26.0))
	_journal_text = RichTextLabel.new()
	_journal_text.bbcode_enabled = true
	_journal_text.fit_content = true
	_journal_text.add_theme_color_override("default_color", Color(0.22, 0.2, 0.18))
	_journal_text.add_theme_font_size_override("normal_font_size", 17)
	_journal_text.add_theme_font_size_override("bold_font_size", 22)
	_journal.add_child(_journal_text)
	_journal.visible = false
	_root.add_child(_journal)


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.4):
		_pad = true
	elif event is InputEventKey or event is InputEventMouseButton:
		_pad = false


func _unhandled_input(event: InputEvent) -> void:
	if Admin.active or photo.active:
		return
	if event.is_action_pressed("pause"):
		if _memory.visible:
			_memory.visible = false
		else:
			_pause.toggle()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("journal") and not get_tree().paused:
		_show_journal(true)
		get_viewport().set_input_as_handled()
	elif event.is_action_released("journal"):
		_show_journal(false)
	elif event.is_action_pressed("photo") and not get_tree().paused and player and player.attached == null:
		photo.enter()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_update_prompt()
	if _caps_show > 0.0:
		_caps_show -= delta
	var want := 1.0 if _caps_show > 0.0 or _journal.visible else 0.0
	_caps.modulate.a = move_toward(_caps.modulate.a, want, delta * 3.0)
	if _memory.visible:
		_memory_left -= delta
		if _memory_left <= 0.0:
			_memory.visible = false


func _key(action: String) -> String:
	if _pad:
		return {"interact": "X", "jump": "A", "crouch": "B", "punch": "Y"}.get(action, "?")
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			return OS.get_keycode_string((e as InputEventKey).physical_keycode)
	return "?"


func _update_prompt() -> void:
	var text := ""
	var action := "interact"
	if player and not Admin.active and not get_tree().paused and Save.setting("show_prompts"):
		if player.attached:
			text = {"Seat": "Get up", "SwingSeat": "Get off  ·  W / S to swing", "SeesawSeat": "Get off  ·  Space to push off",
					"LeanSpot": "Stop leaning", "SlideUse": ""}.get(_class_of(player.attached), "Get off")
		elif player.carrying:
			text = "Throw"
		elif player.focus:
			text = player.focus.prompt_for(player)
	_prompt.visible = text != ""
	if _prompt.visible:
		_prompt_text.text = text
		_prompt_key.text = _key(action)


func _class_of(n: Object) -> String:
	var s: Script = n.get_script()
	return s.get_global_name() if s else ""


func _flash_caps() -> void:
	_caps_label.text = "%d" % Save.caps()
	_caps_show = 4.0


func toast(text: String, seconds := 3.0) -> void:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := _label(18)
	l.text = text
	p.add_child(l)
	_toasts.add_child(p)
	if _toasts.get_child_count() > 3:
		_toasts.get_child(0).queue_free()
	var tw := p.create_tween()
	p.modulate.a = 0.0
	tw.tween_property(p, "modulate:a", 1.0, 0.2)
	tw.tween_interval(seconds)
	tw.tween_property(p, "modulate:a", 0.0, 0.5)
	tw.tween_callback(p.queue_free)


func show_memory(title: String, text: String, first: bool) -> void:
	_memory_title.text = title
	_memory_text.text = text
	_memory_text.visible = text != ""
	_memory.visible = true
	_memory_left = 8.0 + text.length() * 0.05
	if first:
		toast("Added to your journal (Tab)", 2.5)


func _show_journal(on: bool) -> void:
	_journal.visible = on
	if not on:
		return
	_caps_label.text = "%d" % Save.caps()
	var d: Dictionary = Save.data
	var level := get_tree().current_scene
	var director: InteractionDirector = level.get_node_or_null("Interactions") if level else null
	var t := "[b]Micro 15[/b]\n\n"
	var found: int = (d.caps_found as Array).size()
	var total := director.caps.total() if director and director.caps else 0
	t += "Bottle caps: %d in your pocket, %d of %d found\n" % [Save.caps(), found, total]
	t += "Photos taken: %d\n" % (d.photos as Array).size()
	t += "Time out playing: %d min\n\n" % int(float(d.get("played_seconds", 0.0)) / 60.0)
	t += "[b]Memories[/b]\n"
	var any := false
	if director:
		for m in director.memories:
			if Save.has_memory(m.id):
				t += "•  %s\n" % m.title
				any = true
		if director.memories.size() > 0:
			t += "\n%d of %d found" % [(d.memories as Array).size(), director.memories.size()]
	if not any:
		t += "None yet. Memories are places with a story: look for motes of light."
	_journal_text.text = t


func apply_settings() -> void:
	if player:
		player.input.mouse_sensitivity = Save.setting("mouse_sensitivity")
		player.input.stick_sensitivity = Save.setting("stick_sensitivity")
		player.input.invert_y = Save.setting("invert_y")
		player.rig.base_fov = Save.setting("fov")
		player.rig.sprint_fov = float(Save.setting("fov")) + 8.0
		player.rig.set_sprinting(false)
	var master := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(master, linear_to_db(maxf(float(Save.setting("volume_master")), 0.0001)))


func set_visible_all(on: bool) -> void:
	_root.visible = on
