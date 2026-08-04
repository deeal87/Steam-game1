class_name PauseUI
extends CanvasLayer
## Pause and settings.
##
## The world keeps running behind most panels in this game — a customer can
## walk out on you while you read their file, and that is deliberate. This one
## is the exception: it genuinely stops the tree, because a menu that costs you
## a sale is a menu people resent opening.

signal closed
signal restart_requested

var open: bool = false
var _body: VBoxContainer


func _ready() -> void:
	layer = 12
	visible = false
	# Must keep receiving input while the rest of the tree is frozen.
	process_mode = Node.PROCESS_MODE_ALWAYS


func show_pause() -> void:
	open = true
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Audio.play("beep_low", -18.0)
	_rebuild()


func close() -> void:
	open = false
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Settings.save_settings()
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not open:
		return
	if event.is_action_pressed("cancel"):
		close()
		get_viewport().set_input_as_handled()


func _rebuild() -> void:
	for child in get_children():
		child.queue_free()

	var m := UIKit.modal("PAUSED", 0.62, 0.88)
	_body = m["body"]
	add_child(m["root"])

	_body.add_child(UIKit.label("PRESENTATION", UIKit.FONT_S, UIKit.GREEN_DIM))
	_slider("Screen effect", Settings.crt_intensity, 0.0, 1.0,
		"Scanlines, grain and colour fringing. Set to zero for a clean image.",
		func(v: float) -> void: Settings.crt_intensity = v)
	_slider("Retro geometry", Settings.retro_intensity, 0.0, 1.0,
		"Vertex jitter and texture warping. Set to zero for stable, modern rendering.",
		func(v: float) -> void: Settings.retro_intensity = v)
	_slider("Field of view", Settings.field_of_view, 60.0, 100.0,
		"", func(v: float) -> void: Settings.field_of_view = v, 1.0)

	_body.add_child(UIKit.spacer(8))
	_body.add_child(UIKit.label("SOUND AND INPUT", UIKit.FONT_S, UIKit.GREEN_DIM))
	_slider("Volume", Settings.master_volume, 0.0, 1.0, "",
		func(v: float) -> void: Settings.master_volume = v)
	_slider("Mouse sensitivity", Settings.mouse_sensitivity, 0.25, 3.0, "",
		func(v: float) -> void: Settings.mouse_sensitivity = v, 0.05)

	# What the board at the end of the road calls you. Left blank it works it
	# out from Steam, or failing that from the OS account.
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 10)
	var name_label := UIKit.label("Name", UIKit.FONT_S, UIKit.WHITE)
	name_label.custom_minimum_size = Vector2(200, 0)
	name_row.add_child(name_label)
	var name_field := LineEdit.new()
	name_field.text = Settings.player_name
	name_field.placeholder_text = PlayerIdentity.display_name()
	name_field.custom_minimum_size = Vector2(280, 0)
	name_field.add_theme_font_size_override("font_size", UIKit.FONT_S)
	name_field.text_changed.connect(func(v: String) -> void:
		Settings.player_name = v)
	name_row.add_child(name_field)
	_body.add_child(name_row)
	_body.add_child(UIKit.label(
		"    Leave blank to use your Steam name, or your computer's account name.",
		UIKit.FONT_S, UIKit.GREEN_DIM))

	var subs := CheckBox.new()
	subs.text = "Subtitles"
	subs.button_pressed = Settings.subtitles
	subs.add_theme_font_size_override("font_size", UIKit.FONT_S)
	subs.add_theme_color_override("font_color", UIKit.WHITE)
	subs.toggled.connect(func(on: bool) -> void:
		Settings.subtitles = on
		Settings.apply())
	_body.add_child(subs)

	_body.add_child(UIKit.spacer(10))
	_body.add_child(UIKit.rule())

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_body.add_child(row)
	row.add_child(_button("Back to the counter", func() -> void: close()))
	row.add_child(_button("Defaults", func() -> void:
		Settings.reset()
		_rebuild()))
	row.add_child(_button("Abandon the run", func() -> void:
		close()
		restart_requested.emit()))
	row.add_child(_button("Quit", func() -> void:
		get_tree().paused = false
		get_tree().quit()))

	_body.add_child(UIKit.spacer(6))
	_body.add_child(UIKit.label("[ESC] back to the counter", UIKit.FONT_S, UIKit.GREEN_DIM))


func _slider(label: String, value: float, lo: float, hi: float, note: String,
		on_change: Callable, step: float = 0.01) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var name_label := UIKit.label(label, UIKit.FONT_S, UIKit.WHITE)
	name_label.custom_minimum_size = Vector2(200, 0)
	row.add_child(name_label)

	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	slider.value = value
	slider.custom_minimum_size = Vector2(280, 18)
	row.add_child(slider)

	var readout := UIKit.label(_format(value, lo, hi), UIKit.FONT_S, UIKit.GREEN)
	readout.custom_minimum_size = Vector2(60, 0)
	row.add_child(readout)

	slider.value_changed.connect(func(v: float) -> void:
		on_change.call(v)
		readout.text = _format(v, lo, hi)
		Settings.apply())

	_body.add_child(row)
	if not note.is_empty():
		var n := UIKit.label("    " + note, UIKit.FONT_S, UIKit.GREEN_DIM)
		n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_body.add_child(n)


## Percentages read better than raw floats for everything except the field of
## view, which players think about in degrees.
func _format(v: float, lo: float, hi: float) -> String:
	if hi > 10.0:
		return "%d°" % int(v)
	if hi > 2.0:
		return "%.2f" % v
	return "%d%%" % int(round(v / hi * 100.0))


func _button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", UIKit.FONT_S)
	b.pressed.connect(on_press)
	return b
