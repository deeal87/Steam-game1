class_name ReportUI
extends CanvasLayer
## Full-screen interstitials: the title, the shift report, the warning that
## arrives when an officer has walked away, and the screen you get when it
## finally goes wrong.

signal continued
signal restart_requested

## Which action abandons a run and starts from night one. Named once, so the
## handler and the line on screen cannot disagree about it again.
const RESTART_ACTION := "reload"
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
	# Starting over from the title, when there is a run to abandon. On `reload`,
	# which is R — the key the screen has always claimed and never used. It does
	# nothing else here, and R is where a player reaches to start over.
	if _mode == Mode.TITLE and GameState.has_save() and event.is_action_pressed(RESTART_ACTION):
		GameState.clear_save()
		GameState.reset_run()
		Audio.play("deny", -14.0)
		_present()
		get_viewport().set_input_as_handled()
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
	var col := _frame(Loc.t("KIOSK AT MIDNIGHT"),
		Loc.t("A lonely kiosk on a dark street. Nothing else for a mile in any direction."))

	for line: String in [
		Loc.t("You keep the shelves full and the lights on."),
		Loc.t("You also keep something under the counter, which is the only reason the rent gets paid."),
		"",
		Loc.t("Some of the people who come to the window are police, and they are here to buy from you once."),
		Loc.t("You have a scanner, a registry terminal, and however many questions they will stand for."),
		"",
		Loc.t("Work out who they are before you decide what to sell them."),
	]:
		var l := UIKit.label(line, UIKit.FONT_S, UIKit.WHITE)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(l)

	col.add_child(UIKit.spacer(16))

	# A run to go back to, if there is one. The game has always written the save
	# file and never read it, so every run started at night one however far the
	# last one got.
	# The keys are read off the input map rather than written into the sentence.
	#
	# This line said "[R] start again from the first night" and start-again was
	# on the restock action, which is Q — so the one instruction on the title
	# screen named a key that does nothing, and the key that does it was never
	# mentioned anywhere. Asking the map cannot drift, and it also follows
	# anybody who has rebound either of them in the settings.
	if GameState.has_save():
		var back := UIKit.label(Loc.f("[%s] carry on from night %d",
			[InputSetup.binding_label("interact"), GameState.saved_night()]),
			UIKit.FONT_M, UIKit.GREEN)
		back.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(back)
		var fresh := UIKit.label(Loc.f("[%s] start again from the first night",
			[InputSetup.binding_label(RESTART_ACTION)]), UIKit.FONT_S, UIKit.GREEN_DIM)
		fresh.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(fresh)
	else:
		var go := UIKit.label(Loc.f("[%s] open up",
			[InputSetup.binding_label("interact")]), UIKit.FONT_M, UIKit.GREEN)
		go.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(go)


func _build_report() -> void:
	var survived := bool(_payload.get("rent_paid", false))
	var col := _frame(Loc.f("SHIFT %d", [int(_payload.get("night", 1))]),
		Loc.t("05:00. You put the shutter down."))

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
	# Not a mistake and not billed — just trade that walked out of the door
	# because the queue was not moving. Shown so the number has somewhere to go.
	if int(_payload.get("gave_up", 0)) > 0:
		col.add_child(UIKit.field("Gave up waiting", str(int(_payload["gave_up"])), UIKit.AMBER))

	# Whatever you did not get down the manhole in time.
	var bodies: Dictionary = _payload.get("bodies", {})
	var left_out: int = int(bodies.get("civilians", 0)) + int(bodies.get("officers", 0))
	if left_out > 0:
		col.add_child(UIKit.field("Still on the floor at five",
			Loc.f("%d   +%d heat", [left_out, int(bodies.get("heat", 0))]), UIKit.RED))

	col.add_child(UIKit.field("Rent", "-%d" % int(_payload.get("rent", 0)), UIKit.WHITE))
	col.add_child(UIKit.field("In hand", str(GameState.money), UIKit.WHITE))

	var rep := float(_payload.get("reputation", 100.0))
	col.add_child(UIKit.field("Your name on the street", "%d%%" % int(rep),
		UIKit.GREEN if rep > 70.0 else (UIKit.AMBER if rep > 40.0 else UIKit.RED)))
	if rep < 95.0:
		var lost := int(round((1.0 - GameState.reputation_multiplier()) * 100.0))
		col.add_child(UIKit.label(
			Loc.f("    Fewer people will bother coming tomorrow — about %d%% down.", [lost]),
			UIKit.FONT_S, UIKit.GREEN_DIM))

	col.add_child(UIKit.spacer(8))
	col.add_child(UIKit.rule())

	var cops: int = int(_payload.get("cops", 0))
	if cops > 0:
		col.add_child(UIKit.label(Loc.f("Officers dealt with: %d", [cops]), UIKit.FONT_S, UIKit.GREEN))
	if not survived:
		col.add_child(UIKit.label("You are short on the rent. He will want it tomorrow, with interest.",
			UIKit.FONT_S, UIKit.RED))

	col.add_child(UIKit.spacer(12))
	var go := UIKit.label("[E] next night", UIKit.FONT_M, UIKit.GREEN)
	go.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(go)


func _build_raid_warning() -> void:
	var col := _frame(Loc.t("THEY'RE COMING BACK"), str(_payload.get("reason", "")))
	for line: String in [
		Loc.t("The radio behind you stops playing music and starts playing nothing."),
		"",
		Loc.f("There are %d of them forming up at the end of the street.",
			[int(_payload.get("squad", 4))]),
		Loc.t("The shutter will hold for a few seconds. Not many."),
		"",
		Loc.t("Get behind the counter and stay there."),
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
	var col := _frame(Loc.t("THE LIGHTS GO OUT"), str(_payload.get("cause", "")))
	col.add_child(UIKit.label(Loc.f(
		"You lasted %d night." if GameState.nights_survived == 1
			else Loc.t("You lasted %d nights."), [GameState.nights_survived]),
		UIKit.FONT_M, UIKit.WHITE))
	col.add_child(UIKit.spacer(16))

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 20)
	col.add_child(buttons)

	var again := Button.new()
	again.text = Loc.t("OPEN UP AGAIN")
	again.add_theme_font_size_override("font_size", UIKit.FONT_M)
	again.pressed.connect(func() -> void:
		close()
		restart_requested.emit())
	buttons.add_child(again)

	var quit := Button.new()
	quit.text = Loc.t("GO HOME")
	quit.add_theme_font_size_override("font_size", UIKit.FONT_M)
	quit.pressed.connect(func() -> void: quit_requested.emit())
	buttons.add_child(quit)
