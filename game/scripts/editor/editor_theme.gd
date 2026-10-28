## The map editor's look: dark, slightly see-through panels with rounded
## corners, a blue accent for the active tool and pressed buttons.
class_name EditorTheme
extends RefCounted

const PANEL := Color(0.105, 0.115, 0.135, 0.94)
const PANEL_LIGHT := Color(0.16, 0.175, 0.2, 1.0)
const BUTTON := Color(0.2, 0.215, 0.245)
const BUTTON_HOVER := Color(0.26, 0.28, 0.32)
const ACCENT := Color(0.27, 0.55, 0.92)
const ACCENT_HOVER := Color(0.34, 0.62, 0.98)
const DANGER := Color(0.85, 0.32, 0.28)
const TEXT := Color(0.92, 0.93, 0.95)
const MUTED := Color(0.62, 0.65, 0.7)
const YELLOW := Color(1.0, 0.82, 0.25)


static func box(colour: Color, radius := 8, margin := 8.0, border := Color.TRANSPARENT) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = colour
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(margin)
	if border.a > 0.0:
		s.set_border_width_all(1)
		s.border_color = border
	s.anti_aliasing = true
	return s


static func make() -> Theme:
	var t := Theme.new()
	t.default_font_size = 14
	t.set_stylebox("panel", "PanelContainer", box(PANEL, 10, 10.0))
	t.set_stylebox("panel", "Panel", box(PANEL, 10, 10.0))
	for state in ["normal", "disabled"]:
		t.set_stylebox(state, "Button", box(BUTTON, 6, 6.0))
	t.set_stylebox("hover", "Button", box(BUTTON_HOVER, 6, 6.0))
	t.set_stylebox("pressed", "Button", box(ACCENT, 6, 6.0))
	t.set_stylebox("hover_pressed", "Button", box(ACCENT_HOVER, 6, 6.0))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_hover_pressed_color", "Button", Color.WHITE)
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_color", "CheckBox", TEXT)
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		t.set_stylebox(state, "CheckBox", box(Color.TRANSPARENT, 4, 2.0))
	t.set_stylebox("focus", "CheckBox", StyleBoxEmpty.new())
	t.set_stylebox("normal", "LineEdit", box(PANEL_LIGHT, 6, 6.0, Color(1, 1, 1, 0.08)))
	t.set_stylebox("focus", "LineEdit", box(PANEL_LIGHT, 6, 6.0, ACCENT))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", MUTED)
	t.set_stylebox("panel", "ItemList", box(Color(0, 0, 0, 0.18), 6, 4.0))
	t.set_stylebox("focus", "ItemList", StyleBoxEmpty.new())
	t.set_stylebox("selected", "ItemList", box(ACCENT, 6, 2.0))
	t.set_stylebox("selected_focus", "ItemList", box(ACCENT, 6, 2.0))
	t.set_stylebox("hovered", "ItemList", box(BUTTON_HOVER, 6, 2.0))
	t.set_color("font_color", "ItemList", TEXT)
	t.set_color("font_selected_color", "ItemList", Color.WHITE)
	t.set_constant("h_separation", "ItemList", 6)
	t.set_constant("v_separation", "ItemList", 6)
	t.set_stylebox("slider", "HSlider", box(PANEL_LIGHT, 3, 0.0))
	t.set_stylebox("grabber_area", "HSlider", box(ACCENT, 3, 0.0))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(ACCENT_HOVER, 3, 0.0))
	t.set_stylebox("panel", "TooltipPanel", box(Color(0.06, 0.07, 0.08, 0.96), 6, 6.0))
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_stylebox("tab_selected", "TabBar", box(ACCENT, 6, 6.0))
	t.set_stylebox("tab_unselected", "TabBar", box(BUTTON, 6, 6.0))
	t.set_stylebox("tab_hovered", "TabBar", box(BUTTON_HOVER, 6, 6.0))
	t.set_constant("separation", "HBoxContainer", 6)
	t.set_constant("separation", "VBoxContainer", 6)
	return t


## A small grey heading for a section of a panel.
static func heading(text: String) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_color_override("font_color", MUTED)
	l.add_theme_font_size_override("font_size", 12)
	return l


static func hint(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", MUTED)
	l.add_theme_font_size_override("font_size", 12)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l
