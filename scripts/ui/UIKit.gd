class_name UIKit
extends RefCounted
## Shared look for every panel.
##
## The kiosk has one computer and it is old, so every interface in the game —
## the terminal, the notebook, even the supplier's order screen — is rendered
## as if it were coming off the same tired green monitor.

const GREEN := Color(0.52, 0.96, 0.60)
const GREEN_DIM := Color(0.26, 0.52, 0.32)
const AMBER := Color(0.96, 0.76, 0.32)
const RED := Color(0.96, 0.36, 0.34)
const WHITE := Color(0.88, 0.92, 0.88)
const PANEL_BG := Color(0.014, 0.045, 0.025, 0.96)
const PANEL_EDGE := Color(0.20, 0.58, 0.28)

## Interface is laid out against a fixed 1280x720 design space; the engine
## scales that whole space to whatever window the player has.
const DESIGN_W := 1280.0
const DESIGN_H := 720.0

const FONT_S := 15
const FONT_M := 18
const FONT_L := 26
const FONT_XL := 46


static func tone_colour(tone: String) -> Color:
	match tone:
		"good": return GREEN
		"warn": return AMBER
		"bad": return RED
		"watch": return Color(0.62, 0.78, 0.98)
		"info": return WHITE
	return WHITE


static func panel(bg: Color = PANEL_BG, edge: Color = PANEL_EDGE) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = edge
	sb.set_border_width_all(1)
	sb.set_content_margin_all(14)
	sb.corner_detail = 1
	return sb


static func label(text: String, size: int = FONT_M, colour: Color = GREEN) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	l.add_theme_constant_override("line_spacing", 3)
	return l


static func rich(text: String, size: int = FONT_M, colour: Color = GREEN) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.text = text
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size)
	r.add_theme_color_override("default_color", colour)
	return r


## A full-screen dim behind a modal panel.
static func scrim(alpha: float = 0.72) -> ColorRect:
	var c := ColorRect.new()
	c.color = Color(0, 0, 0, alpha)
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## Centred modal container with a header rule, sized as a share of the screen.
static func modal(title: String, width_ratio: float = 0.72, height_ratio: float = 0.80) -> Dictionary:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(scrim())

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(centre)

	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", panel())
	frame.custom_minimum_size = Vector2(DESIGN_W * width_ratio, DESIGN_H * height_ratio)
	centre.add_child(frame)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	frame.add_child(col)

	var head := label(title, FONT_L, GREEN)
	col.add_child(head)
	col.add_child(rule())

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)

	return {"root": root, "frame": frame, "column": col, "body": body, "title": head}


static func rule(colour: Color = PANEL_EDGE) -> ColorRect:
	var r := ColorRect.new()
	r.color = colour
	r.custom_minimum_size = Vector2(0, 1)
	return r


static func spacer(h: int = 6) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


## A selectable line in a menu. Number-keyed, because the whole game is played
## without ever letting go of the mouse.
static func option_row(index: int, text: String, enabled: bool = true, note: String = "") -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var key := label("[%d]" % index, FONT_M, GREEN if enabled else GREEN_DIM)
	key.custom_minimum_size = Vector2(34, 0)
	row.add_child(key)
	var body := label(text, FONT_M, WHITE if enabled else GREEN_DIM)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(body)
	if not note.is_empty():
		row.add_child(label(note, FONT_S, GREEN_DIM))
	return row


## Two-column key/value line, used all over the terminal.
static func field(key: String, value: String, value_colour: Color = WHITE) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var k := label(key, FONT_S, GREEN_DIM)
	k.custom_minimum_size = Vector2(190, 0)
	row.add_child(k)
	var v := label(value, FONT_S, value_colour)
	v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(v)
	return row


## Horizontal bar used for heat and health.
static func meter(value: float, maximum: float, width: int, colour: Color) -> Control:
	var back := ColorRect.new()
	back.color = Color(0.08, 0.14, 0.09, 0.85)
	back.custom_minimum_size = Vector2(width, 6)
	# Sized explicitly rather than by anchor, so it can be a plain child of the
	# track without a container fighting it over its width.
	var filled := width * clampf(value / maxf(maximum, 0.001), 0.0, 1.0)
	var fill := ColorRect.new()
	fill.color = colour
	fill.position = Vector2.ZERO
	fill.size = Vector2(filled, 6)
	fill.custom_minimum_size = Vector2(filled, 6)
	back.add_child(fill)
	return back
