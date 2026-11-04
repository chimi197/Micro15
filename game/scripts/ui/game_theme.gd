## The in-game look of menus and messages: warm off-white text on soft dark
## glass, rounded, larger type than the map editor's (EditorTheme).
class_name GameTheme
extends RefCounted

const PANEL := Color(0.09, 0.1, 0.12, 0.78)
const BUTTON := Color(1, 1, 1, 0.08)
const BUTTON_HOVER := Color(1, 1, 1, 0.16)
const ACCENT := Color(1.0, 0.8, 0.42)
const TEXT := Color(0.96, 0.94, 0.89)


static func box(colour: Color, radius := 10, margin := 12.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = colour
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(margin)
	s.content_margin_left = margin * 1.4
	s.content_margin_right = margin * 1.4
	s.anti_aliasing = true
	return s


static func make() -> Theme:
	var t := Theme.new()
	t.default_font_size = 18
	t.set_stylebox("panel", "PanelContainer", box(PANEL, 12, 10.0))
	t.set_stylebox("normal", "Button", box(BUTTON, 8, 9.0))
	t.set_stylebox("hover", "Button", box(BUTTON_HOVER, 8, 9.0))
	t.set_stylebox("pressed", "Button", box(Color(ACCENT, 0.5), 8, 9.0))
	t.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), 8, 9.0))
	var focus := box(Color(0, 0, 0, 0), 8, 9.0)
	focus.set_border_width_all(2)
	focus.border_color = ACCENT
	t.set_stylebox("focus", "Button", focus)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_focus_color", "Button", Color.WHITE)
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_color", "CheckBox", TEXT)
	t.set_font_size("font_size", "Button", 19)
	return t
