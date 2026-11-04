## Esc (or Start): pauses the game and shows Resume, the settings (look
## speed, invert, field of view, volume, prompts, camera shake), the
## controls and Quit. Settings are saved straight away (Save).
class_name PauseMenu
extends Control

var hud: Hud
var _panel: PanelContainer
var _main: VBoxContainer
var _settings: VBoxContainer
var _controls: VBoxContainer
var _resume: Button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.06, 0.08, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.custom_minimum_size = Vector2(440, 0)
	add_child(_panel)
	var stack := VBoxContainer.new()
	_panel.add_child(stack)
	_main = _column(stack)
	var title := Label.new()
	title.text = "Micro 15"
	title.add_theme_font_size_override("font_size", 30)
	_main.add_child(title)
	_resume = _button(_main, "Resume", toggle)
	_button(_main, "Settings", _show.bind("settings"))
	_button(_main, "Controls", _show.bind("controls"))
	_button(_main, "Quit", func() -> void:
		Save.write_now()
		get_tree().quit())
	_settings = _column(stack)
	_build_settings()
	_controls = _column(stack)
	_build_controls()
	_show("main")


func _column(parent: Node) -> VBoxContainer:
	var c := VBoxContainer.new()
	c.add_theme_constant_override("separation", 10)
	parent.add_child(c)
	return c


func _button(parent: Node, text: String, call: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(call)
	parent.add_child(b)
	return b


func _show(page: String) -> void:
	_main.visible = page == "main"
	_settings.visible = page == "settings"
	_controls.visible = page == "controls"
	var first: Control = {"main": _resume, "settings": _settings.get_child(1),
			"controls": _controls.get_child(_controls.get_child_count() - 1)}[page]
	if visible and first:
		first.grab_focus.call_deferred()


func toggle() -> void:
	visible = not visible
	get_tree().paused = visible
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if visible else Input.MOUSE_MODE_CAPTURED
	if visible:
		_show("main")
	else:
		Save.write_now()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel") and not _main.visible:
		_show("main")
		get_viewport().set_input_as_handled()


func _slider(label: String, key: String, lo: float, hi: float, step: float, fmt: String) -> void:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size.x = 170
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = float(Save.setting(key))
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(s)
	var v := Label.new()
	v.custom_minimum_size.x = 56
	v.text = fmt % s.value
	row.add_child(v)
	s.value_changed.connect(func(x: float) -> void:
		v.text = fmt % x
		Save.set_setting(key, x))
	_settings.add_child(row)


func _check(label: String, key: String) -> void:
	var c := CheckBox.new()
	c.text = label
	c.button_pressed = bool(Save.setting(key))
	c.toggled.connect(func(on: bool) -> void: Save.set_setting(key, on))
	_settings.add_child(c)


func _build_settings() -> void:
	var title := Label.new()
	title.text = "Settings"
	title.add_theme_font_size_override("font_size", 26)
	_settings.add_child(title)
	_slider("Mouse look speed", "mouse_sensitivity", 0.0008, 0.008, 0.0001, "%.4f")
	_slider("Stick look speed", "stick_sensitivity", 1.0, 5.0, 0.1, "%.1f")
	_check("Invert looking up and down", "invert_y")
	_slider("Field of view", "fov", 50.0, 80.0, 1.0, "%.0f°")
	_slider("Volume", "volume_master", 0.0, 1.0, 0.05, "%.2f")
	_slider("Ambience", "volume_ambience", 0.0, 1.0, 0.05, "%.2f")
	_slider("Effects", "volume_effects", 0.0, 1.0, 0.05, "%.2f")
	_check("Show what the use button does", "show_prompts")
	_check("Camera dips on hard landings", "camera_shake")
	_button(_settings, "Back", _show.bind("main"))


func _build_controls() -> void:
	var title := Label.new()
	title.text = "Controls"
	title.add_theme_font_size_override("font_size", 26)
	_controls.add_child(title)
	var rows := [
		["Move", "W A S D", "Left stick"],
		["Look", "Mouse", "Right stick"],
		["Jog / sprint", "Shift / tap twice", "LT / click stick"],
		["Jump, double jump, climb", "Space", "A"],
		["Crouch", "Ctrl or C", "B"],
		["Use (sit, swing, buy...)", "E", "X"],
		["Punch, kick a ball", "Left click or F", "Y"],
		["Photo mode", "V", "Back"],
		["Journal", "Tab (hold)", "R3"],
		["Map editor", "F1", ""],
	]
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 6)
	for r: Array in rows:
		for i in 3:
			var l := Label.new()
			l.text = r[i]
			if i > 0:
				l.add_theme_color_override("font_color", GameTheme.ACCENT if i == 1 else Color(0.78, 0.76, 0.72))
			grid.add_child(l)
	_controls.add_child(grid)
	_button(_controls, "Back", _show.bind("main"))
