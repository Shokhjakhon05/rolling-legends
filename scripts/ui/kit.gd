## Small helpers that build the interface in code, so every screen shares one look.
extends RefCounted

const INK := Color("0b1223")
const PANEL := Color("131c36")
const LINE := Color("2a3a66")
const TEXT := Color("f2f6ff")
const DIM := Color("9fb0d4")
const CYAN := Color("39e6ff")
const GOLD := Color("ffd23f")
const GREEN := Color("3ddc97")
const RED := Color("ff5d73")

static func box(color: Color, radius: int = 22, border: Color = Color.TRANSPARENT, border_w: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.border_color = border
	s.set_border_width_all(border_w)
	s.content_margin_left = 22
	s.content_margin_right = 22
	s.content_margin_top = 14
	s.content_margin_bottom = 14
	return s

## A label wraps only when it is the full width of its parent (centered text); a short label
## inside a row keeps its natural width.
static func label(text: String, size: int = 30, color: Color = TEXT, center: bool = true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if center:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if center:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

## kind: "primary" (the one thing to tap), "plain", "ghost" (quiet), "gold" (a reward).
static func button(text: String, kind: String = "plain", size: int = 32, min_height: int = 92) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, min_height)
	b.add_theme_font_size_override("font_size", size)
	var bg := Color("22305c")
	var fg := TEXT
	var border := LINE
	match kind:
		"primary":
			bg = CYAN
			fg = INK
			border = Color("b9f6ff")
		"gold":
			bg = GOLD
			fg = INK
			border = Color("fff0b0")
		"ghost":
			bg = Color(1, 1, 1, 0.06)
			border = Color(1, 1, 1, 0.14)
	b.add_theme_stylebox_override("normal", box(bg, 26, border, 2))
	b.add_theme_stylebox_override("hover", box(bg.lightened(0.06), 26, border, 2))
	b.add_theme_stylebox_override("pressed", box(bg.darkened(0.15), 26, border, 2))
	b.add_theme_stylebox_override("disabled", box(Color(1, 1, 1, 0.05), 26, Color(1, 1, 1, 0.08), 2))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(state, fg)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.35))
	b.pressed.connect(func() -> void: Sound.play("click"))
	return b

static func panel(color: Color = PANEL, radius: int = 30) -> PanelContainer:
	var p := PanelContainer.new()
	var s := box(color, radius, LINE, 2)
	s.content_margin_left = 30
	s.content_margin_right = 30
	s.content_margin_top = 30
	s.content_margin_bottom = 30
	p.add_theme_stylebox_override("panel", s)
	return p

static func vbox(gap: int = 16) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", gap)
	return v

static func hbox(gap: int = 12) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", gap)
	return h

static func spacer(height: int = 0, expand: bool = false) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	if expand:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c

## A full-screen dim layer with one panel in the middle.
static func overlay(content: Control, dim: float = 0.72) -> Control:
	var root := ColorRect.new()
	root.color = Color(0.02, 0.04, 0.1, dim)
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var p := panel()
	p.custom_minimum_size = Vector2(560, 0)
	p.add_child(content)
	center.add_child(p)
	return root

static func stars_text(n: int) -> String:
	return "★".repeat(n) + "☆".repeat(3 - n)

## Height taken by the status bar / camera cut-out, in interface units.
static func top_inset(node: Node) -> float:
	var screen := DisplayServer.screen_get_size()
	var safe := DisplayServer.get_display_safe_area()
	if screen.y <= 0:
		return 0.0
	var view := node.get_viewport().get_visible_rect().size
	return clampf(float(safe.position.y) / screen.y * view.y, 0.0, 120.0)
