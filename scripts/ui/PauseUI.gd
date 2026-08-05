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
## Which action is waiting for a key, or "" when nothing is.
var _listening: String = ""
var _listen_label: Label
## Two panes: the settings, and the key list.
var _page: String = "settings"


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

	# While waiting for a key, swallow everything: the next press is the binding,
	# not a menu command. Escape cancels rather than binding itself.
	if not _listening.is_empty():
		if event is InputEventKey and event.pressed and not event.is_echo():
			get_viewport().set_input_as_handled()
			var code := (event as InputEventKey).physical_keycode
			if code == KEY_ESCAPE:
				_listening = ""
				_rebuild()
				return
			var bind := InputEventKey.new()
			bind.physical_keycode = code
			var action := _listening
			_listening = ""
			if InputSetup.rebind(action, bind):
				Audio.play("confirm", -16.0)
			else:
				Audio.play("deny", -14.0)
				Signals.notice.emit(Loc.t("That key is already doing something else."), "warn")
			_rebuild()
		return

	if event.is_action_pressed("cancel"):
		close()
		get_viewport().set_input_as_handled()


func _rebuild() -> void:
	for child in get_children():
		child.queue_free()

	var m := UIKit.modal("PAUSED", 0.68, 0.92)
	_body = m["body"]
	add_child(m["root"])

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	for conf: Array in [["settings", Loc.t("SETTINGS")], ["keys", Loc.t("CONTROLS")],
			["awards", Loc.t("ACHIEVEMENTS")]]:
		var b := Button.new()
		b.text = Loc.t(conf[1])
		b.flat = true
		b.add_theme_font_size_override("font_size", UIKit.FONT_S)
		b.add_theme_color_override("font_color",
			UIKit.GREEN if _page == conf[0] else UIKit.GREEN_DIM)
		b.pressed.connect(func() -> void:
			_page = conf[0]
			_listening = ""
			Audio.play("click", -20.0)
			_rebuild())
		tabs.add_child(b)
	_body.add_child(tabs)
	_body.add_child(UIKit.rule())

	if _page == "keys":
		_build_keys()
		_build_footer()
		return

	if _page == "awards":
		_build_awards()
		_build_footer()
		return

	# --- Display ---
	#
	# Players run 1440p, ultrawides, 144Hz panels and handhelds. A game that
	# offers none of this reads as unfinished before anybody has played a minute.
	_body.add_child(UIKit.label("DISPLAY", UIKit.FONT_S, UIKit.GREEN_DIM))
	_cycler(Loc.t("Window"), [Loc.t("Windowed"), Loc.t("Borderless"), Loc.t("Fullscreen")],
		Settings.window_mode,
		func(i: int) -> void:
			Settings.window_mode = i
			Settings.apply()
			Settings.save_settings()
			_rebuild())

	if Settings.window_mode == Settings.WindowMode.WINDOWED:
		var sizes: Array[String] = []
		for r: Vector2i in Settings.RESOLUTIONS:
			sizes.append(Loc.done("%d x %d" % [r.x, r.y]))
		_cycler(Loc.t("Size"), sizes, Settings.resolution_index,
			func(i: int) -> void:
				Settings.resolution_index = i
				Settings.apply()
				Settings.save_settings()
				_rebuild())

	_cycler(Loc.t("Vertical sync"), [Loc.t("Off"), Loc.t("On")], 1 if Settings.vsync else 0,
		func(i: int) -> void:
			Settings.vsync = i == 1
			Settings.apply()
			Settings.save_settings()
			_rebuild())

	var caps: Array[String] = []
	for c: int in Settings.FPS_CAPS:
		caps.append(Loc.t("Unlimited") if c == 0 else Loc.f("%d fps", [c]))
	var cap_index: int = maxi(0, Settings.FPS_CAPS.find(Settings.fps_cap))
	_cycler(Loc.t("Frame limit"), caps, cap_index,
		func(i: int) -> void:
			Settings.fps_cap = Settings.FPS_CAPS[i]
			Settings.apply()
			Settings.save_settings()
			_rebuild())

	# Only worth a row once there is something to choose between. A shipped
	# build with no translations beside the English shows nothing here rather
	# than a chooser with one entry in it.
	var codes := Loc.locales()
	if codes.size() > 1:
		var names: Array[String] = []
		for code: String in codes:
			names.append(Loc.locale_name(code))
		var here: int = maxi(0, Array(codes).find(Loc.locale()))
		_cycler("Language", names, here,
			func(i: int) -> void:
				Settings.locale = codes[clampi(i, 0, codes.size() - 1)]
				Settings.apply()
				Settings.save_settings()
				# Every panel is built from strings, so the menu you are
				# standing in has to be rebuilt in the language you just chose.
				_rebuild())

	_body.add_child(UIKit.spacer(8))
	_body.add_child(UIKit.label("PRESENTATION", UIKit.FONT_S, UIKit.GREEN_DIM))
	_slider(Loc.t("Screen effect"), Settings.crt_intensity, 0.0, 1.0,
		Loc.t("Scanlines, grain and colour fringing. Set to zero for a clean image."),
		func(v: float) -> void: Settings.crt_intensity = v)
	_slider(Loc.t("Retro geometry"), Settings.retro_intensity, 0.0, 1.0,
		Loc.t("Vertex jitter and texture warping. Set to zero for stable, modern rendering."),
		func(v: float) -> void: Settings.retro_intensity = v)
	_slider(Loc.t("Field of view"), Settings.field_of_view, 60.0, 100.0,
		"", func(v: float) -> void: Settings.field_of_view = v, 1.0)

	_body.add_child(UIKit.spacer(8))
	_body.add_child(UIKit.label("SOUND AND INPUT", UIKit.FONT_S, UIKit.GREEN_DIM))
	_slider(Loc.t("Volume"), Settings.master_volume, 0.0, 1.0, "",
		func(v: float) -> void: Settings.master_volume = v)
	_slider(Loc.t("Music"), Settings.music_volume, 0.0, 1.0, "",
		func(v: float) -> void: Settings.music_volume = v)
	_slider(Loc.t("Effects"), Settings.sfx_volume, 0.0, 1.0, "",
		func(v: float) -> void: Settings.sfx_volume = v)
	_slider(Loc.t("Mouse sensitivity"), Settings.mouse_sensitivity, 0.25, 3.0, "",
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
	subs.text = Loc.t("Subtitles")
	subs.button_pressed = Settings.subtitles
	subs.add_theme_font_size_override("font_size", UIKit.FONT_S)
	subs.add_theme_color_override("font_color", UIKit.WHITE)
	subs.toggled.connect(func(on: bool) -> void:
		Settings.subtitles = on
		Settings.apply())
	_body.add_child(subs)

	# Hints explain controls, never decisions, and each one appears once ever.
	# Off for anyone who would rather work it out, and resettable for anyone who
	# wants to be shown again.
	var hints := CheckBox.new()
	hints.text = Loc.t("Hints")
	hints.button_pressed = Tutor.enabled
	hints.add_theme_font_size_override("font_size", UIKit.FONT_S)
	hints.add_theme_color_override("font_color", UIKit.WHITE)
	hints.toggled.connect(func(on: bool) -> void:
		Tutor.enabled = on
		Tutor.save_progress())
	_body.add_child(hints)

	var again := Button.new()
	again.text = Loc.t("Show the hints again")
	again.flat = true
	again.add_theme_font_size_override("font_size", UIKit.FONT_S)
	again.add_theme_color_override("font_color", UIKit.GREEN_DIM)
	again.pressed.connect(func() -> void:
		Tutor.reset()
		Audio.play("click", -20.0)
		Signals.notice.emit(Loc.t("Hints reset."), "info"))
	_body.add_child(again)

	_build_footer()


## Achievements. They work with no Steam at all — the list is the game's own
## record — and the header says which it is rather than implying a connection
## the build does not have.
func _build_awards() -> void:
	var listing := Achievements.listing()
	var got := Achievements.earned_count()
	_body.add_child(UIKit.label(Loc.f("%d of %d", [got, listing.size()]),
		UIKit.FONT_M, UIKit.GREEN))
	_body.add_child(UIKit.label(
		"Synced with Steam." if Achievements.steam_connected()
			else "Stored on this machine. No Steam client running.",
		UIKit.FONT_S, UIKit.GREEN_DIM))
	_body.add_child(UIKit.spacer(6))

	for a: Dictionary in listing:
		var earned := bool(a["earned"])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.add_child(UIKit.label("[x]" if earned else "[ ]", UIKit.FONT_S,
			UIKit.GREEN if earned else UIKit.GREEN_DIM))
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 0)
		col.add_child(UIKit.label(str(a["name"]), UIKit.FONT_S,
			UIKit.WHITE if earned else UIKit.GREEN_DIM))
		var desc := UIKit.label(str(a["desc"]), UIKit.FONT_S, UIKit.GREEN_DIM)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size = Vector2(520, 0)
		col.add_child(desc)
		row.add_child(col)
		_body.add_child(row)


## A left/right chooser for settings that are a short list rather than a range.
## Buttons rather than a slider, because "Borderless" is not a number and
## pretending it is makes a menu you have to squint at.
func _cycler(label: String, options: Array, index: int, on_change: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var name_label := UIKit.label(label, UIKit.FONT_S, UIKit.WHITE)
	name_label.custom_minimum_size = Vector2(190, 0)
	row.add_child(name_label)

	var safe := clampi(index, 0, maxi(0, options.size() - 1))

	var back := Button.new()
	back.text = "<"
	back.add_theme_font_size_override("font_size", UIKit.FONT_S)
	back.pressed.connect(func() -> void:
		Audio.play("click", -22.0)
		on_change.call(wrapi(safe - 1, 0, options.size())))
	row.add_child(back)

	var value := UIKit.label(Loc.done(str(options[safe])) if not options.is_empty() else "—",
		UIKit.FONT_S, UIKit.GREEN)
	value.custom_minimum_size = Vector2(150, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(value)

	var forward := Button.new()
	forward.text = ">"
	forward.add_theme_font_size_override("font_size", UIKit.FONT_S)
	forward.pressed.connect(func() -> void:
		Audio.play("click", -22.0)
		on_change.call(wrapi(safe + 1, 0, options.size())))
	row.add_child(forward)

	_body.add_child(row)


func _build_keys() -> void:
	_body.add_child(UIKit.label(
		"Click a key to change it. Bindings are stored by physical key, so a "
		+ "QWERTZ or AZERTY keyboard already works without touching anything.",
		UIKit.FONT_S, UIKit.GREEN_DIM))
	_body.add_child(UIKit.spacer(4))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 330)
	_body.add_child(scroll)

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 2)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	for entry: Array in InputSetup.REBINDABLE:
		var action: String = entry[0]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var name_label := UIKit.label(Loc.t(str(entry[1])), UIKit.FONT_S, UIKit.WHITE)
		name_label.custom_minimum_size = Vector2(280, 0)
		row.add_child(name_label)

		var b := Button.new()
		var waiting := _listening == action
		b.text = Loc.t("press a key…") if waiting else InputSetup.binding_label(action)
		b.custom_minimum_size = Vector2(170, 0)
		b.add_theme_font_size_override("font_size", UIKit.FONT_S)
		b.add_theme_color_override("font_color", UIKit.AMBER if waiting else UIKit.GREEN)
		b.pressed.connect(func() -> void:
			_listening = action
			Audio.play("beep", -18.0)
			_rebuild())
		row.add_child(b)
		list.add_child(row)

	_body.add_child(UIKit.spacer(6))
	var reset := _button("Reset all keys", func() -> void:
		InputSetup.reset_bindings()
		_listening = ""
		Audio.play("click", -18.0)
		_rebuild())
	_body.add_child(reset)


func _build_footer() -> void:
	_body.add_child(UIKit.spacer(10))
	_body.add_child(UIKit.rule())

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_body.add_child(row)
	row.add_child(_button(Loc.t("Back to the counter"), func() -> void: close()))
	row.add_child(_button(Loc.t("Defaults"), func() -> void:
		Settings.reset()
		_rebuild()))
	row.add_child(_button(Loc.t("Abandon the run"), func() -> void:
		close()
		restart_requested.emit()))
	row.add_child(_button(Loc.t("Quit"), func() -> void:
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

	var readout := UIKit.label(Loc.done(_format(value, lo, hi)), UIKit.FONT_S, UIKit.GREEN)
	readout.custom_minimum_size = Vector2(60, 0)
	row.add_child(readout)

	slider.value_changed.connect(func(v: float) -> void:
		on_change.call(v)
		readout.text = _format(v, lo, hi)
		Settings.apply())

	_body.add_child(row)
	if not note.is_empty():
		var n := UIKit.label(Loc.f("    %s", [Loc.t(note)]), UIKit.FONT_S, UIKit.GREEN_DIM)
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
	b.text = Loc.t(text)
	b.add_theme_font_size_override("font_size", UIKit.FONT_S)
	b.pressed.connect(on_press)
	return b
