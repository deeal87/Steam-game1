class_name ReportUI
extends CanvasLayer
## Full-screen interstitials: the title, the shift report, the warning that
## arrives when an officer has walked away, and the screen you get when it
## finally goes wrong.

signal continued
signal restart_requested
signal quit_requested

enum Mode { TITLE, REPORT, RAID_WARNING, GAME_OVER }

var open: bool = false
var _mode: Mode = Mode.TITLE
var _payload: Dictionary = {}


func _ready() -> void:
	layer = 10
	visible = false


func show_title() -> void:
	_mode = Mode.TITLE
	_present()


func show_report(summary: Dictionary) -> void:
	_mode = Mode.REPORT
	_payload = summary
	_present()


func show_raid_warning(reason: String, squad: int) -> void:
	_mode = Mode.RAID_WARNING
	_payload = {"reason": reason, "squad": squad}
	_present()


func show_game_over(cause: String) -> void:
	_mode = Mode.GAME_OVER
	_payload = {"cause": cause}
	_present()


func close() -> void:
	open = false
	visible = false


func _present() -> void:
	open = true
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for child in get_children():
		child.queue_free()
	match _mode:
		Mode.TITLE: _build_title()
		Mode.REPORT: _build_report()
		Mode.RAID_WARNING: _build_raid_warning()
		Mode.GAME_OVER: _build_game_over()


func _unhandled_input(event: InputEvent) -> void:
	if not open:
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("jump"):
		if _mode == Mode.GAME_OVER:
			return
		_continue()
		get_viewport().set_input_as_handled()


func _continue() -> void:
	close()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	continued.emit()


func _frame(title: String, subtitle: String = "") -> VBoxContainer:
	var back := ColorRect.new()
	back.color = Color(0.01, 0.02, 0.015, 1.0)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(back)

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(centre)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.custom_minimum_size = Vector2(820, 0)
	centre.add_child(col)

	var t := UIKit.label(title, UIKit.FONT_XL, UIKit.GREEN)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(t)
	if not subtitle.is_empty():
		var s := UIKit.label(subtitle, UIKit.FONT_S, UIKit.GREEN_DIM)
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(s)
	col.add_child(UIKit.spacer(10))
	col.add_child(UIKit.rule())
	col.add_child(UIKit.spacer(6))
	return col


func _build_title() -> void:
	var col := _frame("KIOSK AT MIDNIGHT",
		"A lonely kiosk on a dark street. Nothing else for a mile in any direction.")

	for line: String in [
		"You keep the shelves full and the lights on.",
		"You also keep something under the counter, which is the only reason the rent gets paid.",
		"",
		"Some of the people who come to the window are police, and they are here to buy from you once.",
		"You have a scanner, a registry terminal, and however many questions they will stand for.",
		"",
		"Work out who they are before you decide what to sell them.",
	]:
		var l := UIKit.label(line, UIKit.FONT_S, UIKit.WHITE)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(l)

	col.add_child(UIKit.spacer(16))
	var go := UIKit.label("[E] open up", UIKit.FONT_M, UIKit.GREEN)
	go.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(go)


func _build_report() -> void:
	var survived := bool(_payload.get("rent_paid", false))
	var col := _frame("SHIFT %d" % int(_payload.get("night", 1)), "05:00. You put the shutter down.")

	var bill: Dictionary = _payload.get("bill", {})
	col.add_child(UIKit.field("Customers served", str(_payload.get("served", 0)), UIKit.WHITE))
	col.add_child(UIKit.field("Over the counter", str(_payload.get("takings", 0)), UIKit.WHITE))
	col.add_child(UIKit.field("Under the counter", str(_payload.get("illicit", 0)), UIKit.WHITE))
	col.add_child(UIKit.field("Tips and loose cash", str(_payload.get("tips", 0)), UIKit.WHITE))

	# The bill for being wrong about people, itemised, because a lump sum
	# labelled "penalty" teaches the player nothing.
	if int(bill.get("dismissed_count", 0)) > 0:
		col.add_child(UIKit.field("Customers you threw out",
			"%d   -%d" % [int(bill["dismissed_count"]), int(bill["dismissed"])], UIKit.RED))
	if int(bill.get("killed_count", 0)) > 0:
		col.add_child(UIKit.field("People you were wrong about",
			"%d   -%d" % [int(bill["killed_count"]), int(bill["killed"])], UIKit.RED))

	col.add_child(UIKit.field("Rent", "-%d" % int(_payload.get("rent", 0)), UIKit.WHITE))
	col.add_child(UIKit.field("In hand", str(GameState.money), UIKit.WHITE))

	var rep := float(_payload.get("reputation", 100.0))
	col.add_child(UIKit.field("Your name on the street", "%d%%" % int(rep),
		UIKit.GREEN if rep > 70.0 else (UIKit.AMBER if rep > 40.0 else UIKit.RED)))
	if rep < 95.0:
		var lost := int(round((1.0 - GameState.reputation_multiplier()) * 100.0))
		col.add_child(UIKit.label(
			"    Fewer people will bother coming tomorrow — about %d%% down." % lost,
			UIKit.FONT_S, UIKit.GREEN_DIM))

	col.add_child(UIKit.spacer(8))
	col.add_child(UIKit.rule())

	var cops: int = int(_payload.get("cops", 0))
	if cops > 0:
		col.add_child(UIKit.label("Officers dealt with: %d" % cops, UIKit.FONT_S, UIKit.GREEN))
	if not survived:
		col.add_child(UIKit.label("You are short on the rent. He will want it tomorrow, with interest.",
			UIKit.FONT_S, UIKit.RED))

	col.add_child(UIKit.spacer(12))
	var go := UIKit.label("[E] next night", UIKit.FONT_M, UIKit.GREEN)
	go.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(go)


func _build_raid_warning() -> void:
	var col := _frame("THEY'RE COMING BACK", str(_payload.get("reason", "")))
	for line: String in [
		"The radio behind you stops playing music and starts playing nothing.",
		"",
		"There are %d of them forming up at the end of the street." % int(_payload.get("squad", 4)),
		"The shutter will hold for a few seconds. Not many.",
		"",
		"Get behind the counter and stay there.",
	]:
		var l := UIKit.label(line, UIKit.FONT_S, UIKit.WHITE)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(l)
	col.add_child(UIKit.spacer(14))
	var go := UIKit.label("[E] wait for them", UIKit.FONT_M, UIKit.RED)
	go.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(go)


func _build_game_over() -> void:
	var col := _frame("THE LIGHTS GO OUT", str(_payload.get("cause", "")))
	col.add_child(UIKit.label("You lasted %d night%s." %
		[GameState.nights_survived, "" if GameState.nights_survived == 1 else "s"],
		UIKit.FONT_M, UIKit.WHITE))
	col.add_child(UIKit.spacer(16))

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 20)
	col.add_child(buttons)

	var again := Button.new()
	again.text = "OPEN UP AGAIN"
	again.add_theme_font_size_override("font_size", UIKit.FONT_M)
	again.pressed.connect(func() -> void:
		close()
		restart_requested.emit())
	buttons.add_child(again)

	var quit := Button.new()
	quit.text = "GO HOME"
	quit.add_theme_font_size_override("font_size", UIKit.FONT_M)
	quit.pressed.connect(func() -> void: quit_requested.emit())
	buttons.add_child(quit)
