## The map editor's screen: tool bar along the top, the active tool's panel
## on the left (asset browser, remove and grass options, pins, sky & light),
## the inspector of the selection and the map on the right, and the status
## bar with the coordinates along the bottom. It only builds and shows the
## controls; what they do is in scripts/admin.gd (editor).
class_name EditorUI
extends Control

const TOOLS := [
	["select", "Select", "1"], ["place", "Place", "2"], ["remove", "Remove", "3"],
	["grass", "Grass", "4"], ["pins", "Pins", "5"], ["light", "Sky & light", "6"],
]
## asset file name: [shown name, category]
const ASSET_INFO := {
	"tree_a": ["Broadleaf tree", "Plants"], "tree_b": ["Big broadleaf tree", "Plants"],
	"tree_c": ["Small broadleaf tree", "Plants"], "poplar": ["Poplar", "Plants"],
	"tree_birch": ["Birch", "Plants"], "tree_pine": ["Spruce", "Plants"], "bush_a": ["Bush", "Plants"],
	"bush_b": ["Flowering bush", "Plants"], "hedge": ["Hedge", "Plants"], "planter": ["Planter", "Plants"],
	"lamp": ["Street lamp", "Street"], "bench": ["Bench", "Street"], "bench_wood": ["Wooden bench", "Street"],
	"bollard": ["Bollard", "Street"], "trash_bin": ["Litter bin", "Street"], "dumpster": ["Dumpster", "Street"],
	"bike_rack": ["Bike rack", "Street"], "fence_low": ["Low fence", "Street"],
	"fence_metal": ["Metal fence", "Street"], "slide": ["Slide", "Play"], "swing": ["Swing", "Play"],
	"carpet_beater": ["Carpet beater", "Play"], "chess_table": ["Chess table", "Play"],
	"win": ["Window", "Building"], "win_brown": ["Wooden window", "Building"],
	"baldoor": ["Balcony door", "Building"], "balcony_open": ["Open balcony", "Building"],
	"balcony_closed": ["Glazed balcony", "Building"], "curtain": ["Curtain", "Building"],
	"vent": ["Basement vent", "Building"], "ac": ["Air conditioner", "Building"],
	"pots": ["Flower pots", "Building"], "entrance": ["Entrance and steps", "Building"],
	"roof_hut": ["Roof hut", "Building"], "antenna": ["TV antenna", "Building"],
	"dish": ["Satellite dish", "Building"], "pipe": ["Drain pipe", "Building"],
	"shopfront": ["Shop front", "Building"], "garage_door": ["Garage door", "Building"],
	"kiosk": ["Kiosk", "Shops"], "mini_market": ["Mini market", "Shops"],
	"shop_window": ["Shop window", "Shops"], "drinks_fridge": ["Drinks fridge", "Shops"],
	"ice_cream_freezer": ["Ice cream freezer", "Shops"], "fruit_stand": ["Fruit stall", "Shops"],
	"terrace_table": ["Café table", "Shops"], "bus_stop": ["Bus stop", "Street"],
	"recycling_bins": ["Recycling bins", "Street"], "clothes_dryer": ["Clothes line", "Play"],
}
const CATEGORIES := ["All", "Plants", "Street", "Shops", "Play", "Building"]
const MONTHS := ["January", "February", "March", "April", "May", "June", "July", "August", "September",
	"October", "November", "December"]

var editor: Node                           # the Admin autoload

var tool_buttons := {}
var pages := {}
var left_panel: PanelContainer
var inspector: PanelContainer
var map_panel: PanelContainer
var minimap: EditorMinimap
var keys_panel: PanelContainer
var grid_button: Button
var map_button: Button
var undo_button: Button
var redo_button: Button
var status_tool: Label
var status_cursor: Label
var status_camera: Label
var status_info: Label
var goto_edit: LineEdit
var toast: PanelContainer
var toast_label: Label
var _toast_time := 0.0

# place
var asset_list: ItemList
var asset_search: LineEdit
var asset_category := "All"
var asset_paths: Array[String] = []        # every placeable asset
var _shown_assets: Array[String] = []      # in the list, in order
var place_info: Label
var random_turn: CheckBox
var random_size: CheckBox
var snap_box: CheckBox
var _placeholder: Texture2D
# select / remove / grass
var select_filters := {}                   # category: CheckBox
var remove_filters := {}
var brush_slider: HSlider
var brush_label: Label
var grass_brush_slider: HSlider
var grass_clear: CheckBox
# inspector
var insp_title: Label
var insp_kind: Label
var insp_fields := {}                      # x, y, z, turn, size: SpinBox
var insp_single: Control
var insp_note: Label
# pins
var pin_list: VBoxContainer
var pin_popup: PanelContainer
var pin_note: LineEdit
# light
var look_widgets := {}                     # key: [widget, value label or null, format]
var day_running: CheckBox
var day_length: HSlider


func build(admin: Node) -> void:
	editor = admin
	theme = EditorTheme.make()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var img := Image.create(96, 96, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0.06))
	_placeholder = ImageTexture.create_from_image(img)
	_build_top_bar()
	_build_left_panel()
	_build_inspector()
	_build_map()
	_build_status_bar()
	_build_toast()
	_build_keys_panel()
	_build_pin_popup()


func _process(delta: float) -> void:
	if _toast_time > 0.0:
		_toast_time -= delta
		toast.modulate.a = clampf(_toast_time / 0.4, 0.0, 1.0)
		toast.visible = _toast_time > 0.0


func say(text: String, seconds := 3.5) -> void:
	toast_label.text = text
	toast.visible = true
	toast.modulate.a = 1.0
	_toast_time = seconds


## True while the mouse is over one of the editor's panels.
func mouse_over_panels() -> bool:
	var hovered := get_viewport().gui_get_hovered_control()
	return hovered != null and hovered != self and is_ancestor_of(hovered)


func typing() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	return f is LineEdit or f is TextEdit or f is SpinBox


# ----------------------------------------------------------------------------
# Top bar
# ----------------------------------------------------------------------------
func _build_top_bar() -> void:
	var bar := PanelContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.offset_left = 8
	bar.offset_right = -8
	bar.offset_top = 8
	add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	bar.add_child(row)
	var title := Label.new()
	title.text = "MICRO 15  EDITOR"
	title.add_theme_color_override("font_color", EditorTheme.ACCENT_HOVER)
	title.add_theme_font_size_override("font_size", 15)
	row.add_child(title)
	row.add_child(_spacer(14))
	var group := ButtonGroup.new()
	for t: Array in TOOLS:
		var b := Button.new()
		b.text = "%s  %s" % [t[1], t[2]]
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = "%s tool (key %s)" % [t[1], t[2]]
		b.pressed.connect(editor.set_tool.bind(t[0]))
		row.add_child(b)
		tool_buttons[t[0]] = b
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(fill)
	undo_button = _bar_button(row, "Undo", "Undo (Ctrl+Z)", editor.undo)
	redo_button = _bar_button(row, "Redo", "Redo (Ctrl+Y or Ctrl+Shift+Z)", editor.redo)
	row.add_child(_spacer(8))
	grid_button = _bar_button(row, "Grid", "Coordinate grid on the ground (H)", func() -> void:
		editor.set_grid(grid_button.button_pressed))
	grid_button.toggle_mode = true
	map_button = _bar_button(row, "Map", "Map of the neighbourhood (M)", func() -> void:
		editor.set_map(map_button.button_pressed))
	map_button.toggle_mode = true
	_bar_button(row, "Keys", "All the keyboard shortcuts (F1 closes the editor)", func() -> void:
		keys_panel.visible = not keys_panel.visible)
	row.add_child(_spacer(8))
	var play := _bar_button(row, "Play here", "Walk from where the camera looks (P); F1 goes back to where you were",
			editor.play_here)
	play.add_theme_stylebox_override("normal", EditorTheme.box(EditorTheme.ACCENT, 6, 6.0))
	_bar_button(row, "Close  F1", "Back to the game where you left the player", editor.close_editor)


func _bar_button(row: Control, text: String, tip: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(action)
	row.add_child(b)
	return b


func _spacer(w: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, 0)
	return c


func show_tool(tool: String) -> void:
	for t: String in tool_buttons:
		tool_buttons[t].set_pressed_no_signal(t == tool)
	for p: String in pages:
		pages[p].visible = p == tool
	left_panel.visible = pages.has(tool)
	pin_popup.visible = false
	if tool == "place":
		editor.thumbnails.request(_shown_assets)


# ----------------------------------------------------------------------------
# Left panel: one page per tool
# ----------------------------------------------------------------------------
func _build_left_panel() -> void:
	left_panel = PanelContainer.new()
	left_panel.anchor_top = 0.0
	left_panel.anchor_bottom = 1.0
	left_panel.offset_left = 8
	left_panel.offset_right = 338
	left_panel.offset_top = 64
	left_panel.offset_bottom = -56
	add_child(left_panel)
	var stack := VBoxContainer.new()
	left_panel.add_child(stack)
	pages["select"] = _page_select()
	pages["place"] = _page_place()
	pages["remove"] = _page_remove()
	pages["grass"] = _page_grass()
	pages["pins"] = _page_pins()
	pages["light"] = _page_light()
	for p: String in pages:
		pages[p].size_flags_vertical = Control.SIZE_EXPAND_FILL
		stack.add_child(pages[p])


func _page() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	return v


func _filters(parent: Control, into: Dictionary, labels: Array, on := true) -> void:
	for l: Array in labels:
		var c := CheckBox.new()
		c.text = l[1]
		c.button_pressed = on if l.size() < 3 else l[2]
		c.focus_mode = Control.FOCUS_NONE
		parent.add_child(c)
		into[l[0]] = c


func _page_select() -> VBoxContainer:
	var v := _page()
	v.add_child(EditorTheme.heading("Select and move"))
	v.add_child(EditorTheme.hint("Click a thing to select it, Shift+click to add more. Drag a selected thing "
			+ "to move it, or press G and click where it should go. R turns it, the arrow keys nudge it "
			+ "(Page Up / Down: height), Delete removes it, Ctrl+D copies it, F flies to it. The panel on "
			+ "the right sets exact numbers.\n\nTrees and details of the map become placed things the "
			+ "first time they are moved, so they can be changed freely."))
	v.add_child(EditorTheme.heading("Things that can be picked"))
	_filters(v, select_filters, [["placed", "Placed things"], ["plants", "Trees and bushes of the map"],
			["street", "Lamps and benches of the map"], ["details", "Windows, balconies and other details"],
			["buildings", "Whole buildings"]])
	return v


func _page_place() -> VBoxContainer:
	var v := _page()
	v.add_child(EditorTheme.heading("Assets"))
	asset_search = LineEdit.new()
	asset_search.placeholder_text = "Search assets..."
	asset_search.clear_button_enabled = true
	asset_search.text_changed.connect(func(_t: String) -> void: refresh_assets())
	v.add_child(asset_search)
	var cats := HBoxContainer.new()
	cats.add_theme_constant_override("separation", 4)
	var group := ButtonGroup.new()
	for c: String in CATEGORIES:
		var b := Button.new()
		b.text = c
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = c == asset_category
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 12)
		b.pressed.connect(func() -> void:
			asset_category = c
			refresh_assets())
		cats.add_child(b)
	v.add_child(cats)
	asset_list = ItemList.new()
	asset_list.icon_mode = ItemList.ICON_MODE_TOP
	asset_list.fixed_icon_size = Vector2i(84, 84)
	asset_list.max_columns = 3
	asset_list.same_column_width = true
	asset_list.fixed_column_width = 92
	asset_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	asset_list.focus_mode = Control.FOCUS_NONE
	asset_list.add_theme_font_size_override("font_size", 11)
	asset_list.item_selected.connect(func(i: int) -> void: editor.choose_asset(_shown_assets[i]))
	v.add_child(asset_list)
	place_info = Label.new()
	place_info.add_theme_font_size_override("font_size", 12)
	v.add_child(place_info)
	random_turn = CheckBox.new()
	random_turn.text = "Random turn for each one"
	random_size = CheckBox.new()
	random_size.text = "Random size (90 to 110%)"
	snap_box = CheckBox.new()
	snap_box.text = "Snap to a 0.5 m grid"
	for c in [random_turn, random_size, snap_box]:
		c.focus_mode = Control.FOCUS_NONE
		v.add_child(c)
	v.add_child(EditorTheme.hint("Click to place. Wheel or R turns, Shift+wheel or Z / X sizes, "
			+ "middle click on a thing picks the same asset."))
	return v


func set_assets(paths: Array[String]) -> void:
	asset_paths = paths
	refresh_assets()


func asset_name(path: String) -> String:
	var key := path.get_file().get_basename()
	return ASSET_INFO[key][0] if ASSET_INFO.has(key) else key.capitalize()


func asset_category_of(path: String) -> String:
	var key := path.get_file().get_basename()
	return ASSET_INFO[key][1] if ASSET_INFO.has(key) else "All"


func refresh_assets() -> void:
	var query := asset_search.text.strip_edges().to_lower()
	_shown_assets.clear()
	asset_list.clear()
	for path in asset_paths:
		if asset_category != "All" and asset_category_of(path) != asset_category:
			continue
		var shown := asset_name(path)
		if not query.is_empty() and not query in shown.to_lower() and not query in path.get_file().to_lower():
			continue
		_shown_assets.append(path)
		var tex: Texture2D = editor.thumbnails.done.get(path, _placeholder)
		asset_list.add_item(shown, tex)
		asset_list.set_item_tooltip(asset_list.item_count - 1, path.get_file().get_basename())
		if path == editor.place_asset:
			asset_list.select(asset_list.item_count - 1)
	if visible and pages["place"].visible:
		editor.thumbnails.request(_shown_assets)


func on_thumbnail(path: String, tex: Texture2D) -> void:
	var i := _shown_assets.find(path)
	if i >= 0:
		asset_list.set_item_icon(i, tex)


func select_asset(path: String) -> void:
	var i := _shown_assets.find(path)
	if i >= 0:
		asset_list.select(i)
		asset_list.ensure_current_is_visible()
	else:
		asset_list.deselect_all()


func _page_remove() -> VBoxContainer:
	var v := _page()
	v.add_child(EditorTheme.heading("Remove"))
	v.add_child(EditorTheme.hint("Click a thing to remove it: placed things, trees, bushes, lamps, benches, "
			+ "windows, balconies, whole buildings. The red box shows what a click removes.\n"
			+ "Hold Shift and drag to remove everything ticked below inside the ring. Ctrl+Z brings it back."))
	v.add_child(EditorTheme.heading("Brush (Shift + drag)"))
	var row := HBoxContainer.new()
	brush_slider = HSlider.new()
	brush_slider.min_value = 0.5
	brush_slider.max_value = 25.0
	brush_slider.step = 0.5
	brush_slider.value = 3.0
	brush_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brush_slider.focus_mode = Control.FOCUS_NONE
	brush_label = Label.new()
	brush_label.custom_minimum_size = Vector2(56, 0)
	brush_slider.value_changed.connect(func(x: float) -> void:
		brush_label.text = "%.1f m" % x
		editor.brush = x)
	brush_label.text = "3.0 m"
	row.add_child(brush_slider)
	row.add_child(brush_label)
	v.add_child(row)
	_filters(v, remove_filters, [["placed", "Placed things"], ["plants", "Trees and bushes"],
			["street", "Lamps and benches"], ["details", "Building details", false]])
	v.add_child(EditorTheme.heading("Clean up"))
	var roads := Button.new()
	roads.text = "Remove map things standing on roads"
	roads.focus_mode = Control.FOCUS_NONE
	roads.pressed.connect(func() -> void: editor.remove_props_on_roads())
	v.add_child(roads)
	v.add_child(EditorTheme.hint("Finds the map's trees, bushes, lamps and benches standing on asphalt (and "
			+ "in car parks, except lamps) and removes them in one step; one Ctrl+Z puts them all back."))
	return v


func _page_grass() -> VBoxContainer:
	var v := _page()
	v.add_child(EditorTheme.heading("Grass brush"))
	v.add_child(EditorTheme.hint("Hold the left mouse button to grow 3D grass, with Clear ticked (or Shift held) "
			+ "to clear it. Wheel or Z / X changes the size."))
	var row := HBoxContainer.new()
	grass_brush_slider = HSlider.new()
	grass_brush_slider.min_value = 0.5
	grass_brush_slider.max_value = 20.0
	grass_brush_slider.step = 0.5
	grass_brush_slider.value = 3.0
	grass_brush_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grass_brush_slider.focus_mode = Control.FOCUS_NONE
	var label := Label.new()
	label.custom_minimum_size = Vector2(56, 0)
	label.text = "3.0 m"
	grass_brush_slider.value_changed.connect(func(x: float) -> void:
		label.text = "%.1f m" % x
		editor.grass_brush = x)
	row.add_child(grass_brush_slider)
	row.add_child(label)
	v.add_child(row)
	grass_clear = CheckBox.new()
	grass_clear.text = "Clear grass instead of growing it"
	grass_clear.focus_mode = Control.FOCUS_NONE
	v.add_child(grass_clear)
	return v


func _page_pins() -> VBoxContainer:
	var v := _page()
	v.add_child(EditorTheme.heading("Pins"))
	v.add_child(EditorTheme.hint("Click anywhere to drop a numbered pin with a note, for example "
			+ "\"move this tree\". Pins are saved with the level (levels/micro15/pins.json), so you can just "
			+ "say \"pin 3\" when you ask for a change, or copy the list below and paste it in the chat."))
	var copy := Button.new()
	copy.text = "Copy all pins as text"
	copy.focus_mode = Control.FOCUS_NONE
	copy.pressed.connect(editor.copy_pins)
	v.add_child(copy)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pin_list = VBoxContainer.new()
	pin_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(pin_list)
	v.add_child(scroll)
	return v


func show_pins(pins: Array) -> void:
	for c in pin_list.get_children():
		c.queue_free()
	if pins.is_empty():
		pin_list.add_child(EditorTheme.hint("No pins yet."))
	for pin: Dictionary in pins:
		var row := HBoxContainer.new()
		var l := Label.new()
		l.text = "#%d  %s\n%s" % [pin.id, pin.note, Coordinates.text(Vector3(pin.x, pin.y, pin.z))]
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_font_size_override("font_size", 12)
		row.add_child(l)
		var go := Button.new()
		go.text = "Go"
		go.focus_mode = Control.FOCUS_NONE
		go.pressed.connect(editor.pin_go.bind(pin.id))
		row.add_child(go)
		var del := Button.new()
		del.text = "X"
		del.tooltip_text = "Delete this pin"
		del.focus_mode = Control.FOCUS_NONE
		del.pressed.connect(editor.pin_delete.bind(pin.id))
		row.add_child(del)
		pin_list.add_child(row)


func _build_pin_popup() -> void:
	pin_popup = PanelContainer.new()
	pin_popup.visible = false
	pin_popup.custom_minimum_size = Vector2(280, 0)
	add_child(pin_popup)
	var v := VBoxContainer.new()
	pin_popup.add_child(v)
	v.add_child(EditorTheme.heading("New pin"))
	pin_note = LineEdit.new()
	pin_note.placeholder_text = "Note (what should change here?)"
	pin_note.text_submitted.connect(func(_t: String) -> void: editor.pin_add_confirm(pin_note.text))
	v.add_child(pin_note)
	var row := HBoxContainer.new()
	var ok := Button.new()
	ok.text = "Add pin"
	ok.pressed.connect(func() -> void: editor.pin_add_confirm(pin_note.text))
	row.add_child(ok)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(func() -> void: pin_popup.visible = false)
	row.add_child(cancel)
	v.add_child(row)


func ask_pin_note(at_screen: Vector2) -> void:
	pin_popup.visible = true
	pin_popup.position = (at_screen + Vector2(16, 16)).clamp(Vector2.ZERO, size - Vector2(300, 120))
	pin_note.text = ""
	pin_note.grab_focus()


# ----------------------------------------------------------------------------
# Sky & light
# ----------------------------------------------------------------------------
func _page_light() -> VBoxContainer:
	var v := _page()
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 5)
	scroll.add_child(body)
	body.add_child(EditorTheme.heading("Presets"))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	for p: String in SunCycle.PRESETS:
		var b := Button.new()
		b.text = p
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 12)
		b.pressed.connect(editor.look_preset.bind(p))
		grid.add_child(b)
	body.add_child(grid)
	body.add_child(EditorTheme.heading("Sun and time"))
	_look_slider(body, "time", "Time of day", 0.0, 24.0, 0.05, func(x: float) -> String:
		return "%02d:%02d" % [int(x), int(fmod(x, 1.0) * 60.0)])
	_look_slider(body, "day_of_year", "Season", 1.0, 365.0, 1.0, func(x: float) -> String:
		return MONTHS[clampi(int((x - 1.0) / 30.42), 0, 11)].left(3))
	_look_slider(body, "north_offset", "Sun path turn", -180.0, 180.0, 1.0, func(x: float) -> String:
		return "%d°" % x)
	_look_slider(body, "sun_energy", "Sun strength", 0.0, 3.0, 0.05)
	_look_colour(body, "sun_colour", "Sun colour")
	_look_slider(body, "shadow_softness", "Soft shadows", 0.2, 8.0, 0.1)
	var row := HBoxContainer.new()
	day_running = CheckBox.new()
	day_running.text = "Day cycle"
	day_running.focus_mode = Control.FOCUS_NONE
	day_running.toggled.connect(editor.set_day_running)
	row.add_child(day_running)
	day_length = HSlider.new()
	day_length.min_value = 1.0
	day_length.max_value = 60.0
	day_length.step = 1.0
	day_length.value = 24.0
	day_length.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	day_length.focus_mode = Control.FOCUS_NONE
	day_length.tooltip_text = "Real minutes for a whole day"
	var day_label := Label.new()
	day_label.text = "24 min"
	day_label.custom_minimum_size = Vector2(52, 0)
	day_length.value_changed.connect(func(x: float) -> void:
		day_label.text = "%d min" % x
		editor.set_day_length(x))
	row.add_child(day_length)
	row.add_child(day_label)
	body.add_child(row)
	body.add_child(EditorTheme.heading("Sky"))
	_look_colour(body, "sky_top", "Sky colour")
	_look_colour(body, "sky_horizon", "Horizon colour")
	_look_colour(body, "ground_bottom", "Below the horizon")
	_look_slider(body, "sky_energy", "Sky brightness", 0.2, 2.0, 0.05)
	_look_slider(body, "clouds", "Clouds", 0.0, 1.0, 0.01)
	_look_colour(body, "cloud_colour", "Cloud colour")
	body.add_child(EditorTheme.heading("Light in the shade and fog"))
	_look_slider(body, "ambient", "Shade light", 0.0, 2.5, 0.05)
	_look_colour(body, "ambient_colour", "Shade colour")
	_look_slider(body, "ambient_sky", "Sky tint in shade", 0.0, 1.0, 0.05)
	_look_slider(body, "fog", "Fog", 0.00005, 0.03, 0.00005, func(x: float) -> String:
		return "%.2f" % (x * 1000.0), true)
	_look_colour(body, "fog_colour", "Fog colour")
	body.add_child(EditorTheme.heading("Camera"))
	_look_slider(body, "exposure", "Exposure", 0.3, 3.0, 0.05)
	_look_slider(body, "contrast", "Contrast", 0.5, 1.8, 0.01)
	_look_slider(body, "saturation", "Colour", 0.0, 2.0, 0.01)
	_look_slider(body, "glow", "Glow", 0.0, 1.5, 0.05)
	_look_slider(body, "ssao", "Contact shadows", 0.0, 3.0, 0.05)
	body.add_child(EditorTheme.heading("Keep it"))
	var save := Button.new()
	save.text = "Save as the level's look"
	save.tooltip_text = "The game starts with this look from now on (levels/micro15/lighting.json)"
	save.pressed.connect(editor.look_save)
	body.add_child(save)
	var row2 := HBoxContainer.new()
	var reset := Button.new()
	reset.text = "Back to saved"
	reset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset.pressed.connect(editor.look_reset)
	row2.add_child(reset)
	var copy := Button.new()
	copy.text = "Copy settings"
	copy.tooltip_text = "Copies the look as text, to paste in the chat"
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.pressed.connect(editor.look_copy)
	row2.add_child(copy)
	body.add_child(row2)
	for b in [save, reset, copy]:
		b.focus_mode = Control.FOCUS_NONE
	return v


func _look_row(parent: Control, label: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(118, 0)
	l.add_theme_font_size_override("font_size", 12)
	row.add_child(l)
	parent.add_child(row)
	return row


func _look_slider(parent: Control, key: String, label: String, lo: float, hi: float, step: float,
		fmt := Callable(), exp_edit := false) -> void:
	var row := _look_row(parent, label)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.exp_edit = exp_edit
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.focus_mode = Control.FOCUS_NONE
	var value := Label.new()
	value.custom_minimum_size = Vector2(46, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.add_theme_font_size_override("font_size", 12)
	if not fmt.is_valid():
		fmt = func(x: float) -> String: return "%.2f" % x
	s.value_changed.connect(func(x: float) -> void:
		value.text = fmt.call(x)
		editor.look_set(key, x))
	row.add_child(s)
	row.add_child(value)
	look_widgets[key] = [s, value, fmt]


func _look_colour(parent: Control, key: String, label: String) -> void:
	var row := _look_row(parent, label)
	var c := ColorPickerButton.new()
	c.edit_alpha = false
	c.custom_minimum_size = Vector2(0, 24)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.focus_mode = Control.FOCUS_NONE
	c.color_changed.connect(func(col: Color) -> void: editor.look_set(key, col))
	row.add_child(c)
	look_widgets[key] = [c, null, Callable()]


## Shows a look's values on the sliders and colour buttons.
func show_look(look: Dictionary, running: bool) -> void:
	for key: String in look_widgets:
		if not look.has(key):
			continue
		var w: Array = look_widgets[key]
		if w[0] is HSlider:
			(w[0] as HSlider).set_value_no_signal(look[key])
			(w[1] as Label).text = w[2].call(float(look[key]))
		else:
			(w[0] as ColorPickerButton).color = look[key]
	day_running.set_pressed_no_signal(running)


# ----------------------------------------------------------------------------
# Inspector (right)
# ----------------------------------------------------------------------------
func _build_inspector() -> void:
	inspector = PanelContainer.new()
	inspector.anchor_left = 1.0
	inspector.anchor_right = 1.0
	inspector.offset_left = -378
	inspector.offset_right = -8
	inspector.offset_top = 64
	inspector.visible = false
	add_child(inspector)
	var v := VBoxContainer.new()
	inspector.add_child(v)
	insp_title = Label.new()
	insp_title.add_theme_font_size_override("font_size", 16)
	v.add_child(insp_title)
	insp_kind = Label.new()
	insp_kind.add_theme_color_override("font_color", EditorTheme.MUTED)
	insp_kind.add_theme_font_size_override("font_size", 12)
	insp_kind.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(insp_kind)
	var single := VBoxContainer.new()
	insp_single = single
	v.add_child(single)
	single.add_child(EditorTheme.heading("Position (metres)"))
	var pos := HBoxContainer.new()
	for axis in ["x", "y", "z"]:
		var l := Label.new()
		l.text = axis if axis != "y" else "h"
		l.tooltip_text = "height" if axis == "y" else axis
		pos.add_child(l)
		insp_fields[axis] = _spin(pos, -2000.0, 2000.0, 0.01, axis)
	single.add_child(pos)
	var tr := HBoxContainer.new()
	var l1 := Label.new()
	l1.text = "Turn"
	tr.add_child(l1)
	insp_fields["turn"] = _spin(tr, -360.0, 360.0, 1.0, "turn")
	var l2 := Label.new()
	l2.text = "Size"
	tr.add_child(l2)
	insp_fields["size"] = _spin(tr, 0.05, 20.0, 0.01, "size")
	single.add_child(tr)
	insp_note = EditorTheme.hint("")
	v.add_child(insp_note)
	var actions := GridContainer.new()
	actions.columns = 2
	actions.add_theme_constant_override("h_separation", 4)
	actions.add_theme_constant_override("v_separation", 4)
	for a: Array in [["Move  G", editor.start_grab], ["Copy  Ctrl+D", editor.duplicate_selected],
			["Fly to  F", editor.focus_selected], ["Copy location", editor.copy_location],
			["Remove  Del", editor.delete_selected], ["Deselect  Esc", editor.clear_selection]]:
		var b := Button.new()
		b.text = a[0]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(a[1])
		if a[0].begins_with("Remove"):
			b.add_theme_stylebox_override("normal", EditorTheme.box(EditorTheme.DANGER.darkened(0.25), 6, 6.0))
		actions.add_child(b)
	v.add_child(actions)


func _spin(parent: Control, lo: float, hi: float, step: float, field: String) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.allow_greater = true
	s.allow_lesser = true
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.select_all_on_focus = true
	s.value_changed.connect(func(x: float) -> void: editor.edit_selected(field, x))
	parent.add_child(s)
	return s


## refs' details: title, kind text, and for a single movable thing its
## transform ([] hides the fields).
func show_selection(title: String, kind: String, values: Dictionary, note: String) -> void:
	inspector.visible = not title.is_empty()
	insp_title.text = title
	insp_kind.text = kind
	insp_single.visible = not values.is_empty()
	for key: String in values:
		(insp_fields[key] as SpinBox).set_value_no_signal(values[key])
	insp_note.text = note
	insp_note.visible = not note.is_empty()


# ----------------------------------------------------------------------------
# Map (bottom right)
# ----------------------------------------------------------------------------
func _build_map() -> void:
	map_panel = PanelContainer.new()
	map_panel.anchor_left = 1.0
	map_panel.anchor_right = 1.0
	map_panel.anchor_top = 1.0
	map_panel.anchor_bottom = 1.0
	map_panel.offset_left = -378
	map_panel.offset_right = -8
	map_panel.offset_top = -404
	map_panel.offset_bottom = -56
	map_panel.visible = false
	add_child(map_panel)
	var v := VBoxContainer.new()
	map_panel.add_child(v)
	var head := HBoxContainer.new()
	head.add_child(EditorTheme.heading("Map  (click to fly there)"))
	v.add_child(head)
	minimap = EditorMinimap.new()
	minimap.custom_minimum_size = Vector2(350, 300)
	minimap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	minimap.mouse_filter = Control.MOUSE_FILTER_STOP
	minimap.clicked.connect(editor.fly_over)
	minimap.hovered.connect(func(x: float, z: float) -> void:
		status_cursor.text = "Map: x %.0f, z %.0f" % [x, z])
	v.add_child(minimap)


# ----------------------------------------------------------------------------
# Status bar, toast, keys
# ----------------------------------------------------------------------------
func _build_status_bar() -> void:
	var bar := PanelContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_left = 8
	bar.offset_right = -8
	bar.offset_bottom = -8
	bar.offset_top = -48
	bar.add_theme_stylebox_override("panel", EditorTheme.box(EditorTheme.PANEL, 10, 6.0))
	add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	bar.add_child(row)
	status_tool = Label.new()
	status_tool.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_tool.clip_text = true
	status_tool.add_theme_color_override("font_color", EditorTheme.MUTED)
	status_tool.add_theme_font_size_override("font_size", 12)
	row.add_child(status_tool)
	status_cursor = Label.new()
	status_cursor.custom_minimum_size = Vector2(250, 0)
	status_cursor.add_theme_color_override("font_color", EditorTheme.YELLOW)
	status_cursor.tooltip_text = "Where the mouse points (Ctrl+C copies it)"
	status_cursor.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(status_cursor)
	status_camera = Label.new()
	status_camera.custom_minimum_size = Vector2(230, 0)
	status_camera.add_theme_font_size_override("font_size", 12)
	row.add_child(status_camera)
	goto_edit = LineEdit.new()
	goto_edit.placeholder_text = "Go to  x, z"
	goto_edit.custom_minimum_size = Vector2(150, 0)
	goto_edit.tooltip_text = "Type a location like 357.6, 18.5 and press Enter"
	goto_edit.text_submitted.connect(func(t: String) -> void:
		editor.goto_text(t)
		goto_edit.release_focus())
	row.add_child(goto_edit)
	var copy := Button.new()
	copy.text = "Copy location"
	copy.tooltip_text = "Copies where the mouse points, or the selection (Ctrl+C)"
	copy.focus_mode = Control.FOCUS_NONE
	copy.pressed.connect(editor.copy_location)
	row.add_child(copy)
	status_info = Label.new()
	status_info.custom_minimum_size = Vector2(120, 0)
	status_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status_info.add_theme_font_size_override("font_size", 12)
	row.add_child(status_info)


func _build_toast() -> void:
	toast = PanelContainer.new()
	toast.anchor_left = 0.5
	toast.anchor_right = 0.5
	toast.anchor_top = 1.0
	toast.anchor_bottom = 1.0
	toast.offset_top = -100
	toast.offset_bottom = -64
	toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.visible = false
	toast.add_theme_stylebox_override("panel", EditorTheme.box(Color(0.05, 0.06, 0.07, 0.92), 8, 10.0,
			EditorTheme.ACCENT))
	add_child(toast)
	toast_label = Label.new()
	toast.add_child(toast_label)


func _build_keys_panel() -> void:
	keys_panel = PanelContainer.new()
	keys_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	keys_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	keys_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	keys_panel.visible = false
	add_child(keys_panel)
	var v := VBoxContainer.new()
	keys_panel.add_child(v)
	v.add_child(EditorTheme.heading("Keyboard and mouse"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	for k: Array in [
		["F1", "open / close the editor"], ["1 - 6", "tools: select, place, remove, grass, pins, sky & light"],
		["Right mouse + move", "look around"], ["W A S D / arrows", "fly (Shift: faster)"],
		["Right mouse + Q / E", "down / up"], ["Wheel", "forward / back (with right mouse: flying speed)"],
		["Click / Shift+click", "select / add to the selection"], ["Drag, or G then click", "move the selection"],
		["R / Shift+R", "turn by 15 degrees"], ["Arrows, Page Up / Down", "nudge by 10 cm (Shift: 1 m)"],
		["Delete", "remove"], ["Ctrl+D", "copy"], ["F", "fly to the selection"],
		["Ctrl+Z / Ctrl+Y", "undo / redo"], ["Ctrl+C", "copy the location under the mouse"],
		["H", "coordinate grid"], ["M", "map"], ["P", "play from here"], ["F12", "screenshot"],
		["F4 (in the game)", "show the player's coordinates"],
	]:
		var a := Label.new()
		a.text = k[0]
		a.add_theme_color_override("font_color", EditorTheme.YELLOW)
		grid.add_child(a)
		var b := Label.new()
		b.text = k[1]
		grid.add_child(b)
	v.add_child(grid)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(func() -> void: keys_panel.visible = false)
	v.add_child(close)
