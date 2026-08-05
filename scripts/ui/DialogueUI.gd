class_name DialogueUI
extends CanvasLayer
## Talking to whoever is at the hatch.
##
## Questions cost patience, and patience is finite. That constraint is what
## stops the game becoming a checklist: you cannot ask everything, so you have
## to decide which contradiction is worth spending a question on.

signal closed

## There are nine choice keys, so nine is every option that can exist on screen.
## The actions are laid out first and always fit; questions take what is left and
## page if there are more of them. Nothing the player needs to reach — refusing,
## selling, telling somebody to move on — can ever be pushed off the list by a
## long enough list of questions.
const MAX_OPTIONS := 9

var open: bool = false
var _customer: Customer
var _player: Player
var _body: VBoxContainer
var _root: Control
var _options: Array[Dictionary] = []
var _last_answer: String = ""
var _last_note: String = ""
var _last_tone: String = ""
var _question_page: int = 0
## Which row the gamepad cursor is on. Ignored entirely on a keyboard, where the
## number beside each row is faster than any cursor.
var _cursor: int = 0
var _pad_active: bool = false


func _ready() -> void:
	layer = 8
	visible = false


func show_for(customer: Customer, player: Player) -> void:
	_customer = customer
	_player = player
	_last_answer = ""
	_last_note = ""
	_question_page = 0
	_cursor = 0
	# The cursor only appears once somebody actually uses a pad, so a keyboard
	# player never sees a selection they did not ask for.
	_pad_active = not Input.get_connected_joypads().is_empty()
	open = true
	visible = true
	_rebuild()


func close() -> void:
	open = false
	visible = false
	_customer = null
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not open:
		return
	if event.is_action_pressed("cancel"):
		close()
		get_viewport().set_input_as_handled()
		return
	# Gamepad: a cursor stepped with the d-pad and taken with the south button.
	if event.is_action_pressed("choice_next") or event.is_action_pressed("choice_prev"):
		if _options.is_empty():
			return
		_pad_active = true
		var step := 1 if event.is_action_pressed("choice_next") else -1
		_cursor = wrapi(_cursor + step, 0, _options.size())
		Audio.play("click", -26.0)
		_rebuild()
		get_viewport().set_input_as_handled()
		return
	if _pad_active and event.is_action_pressed("choice_take"):
		if _cursor >= 0 and _cursor < _options.size():
			_choose(_options[_cursor])
			get_viewport().set_input_as_handled()
		return

	var pick := InputSetup.choice_pressed()
	if pick > 0 and pick <= _options.size():
		_choose(_options[pick - 1])
		get_viewport().set_input_as_handled()


func _rebuild() -> void:
	for child in get_children():
		child.queue_free()
	_options.clear()
	# Asking a question removes it from the menu, so the row under the cursor
	# moves. Clamped after the rebuild below; clamped here too so the first pass
	# never indexes past the end.
	_cursor = maxi(0, _cursor)

	if _customer == null or _customer.profile == null:
		close()
		return
	var p := _customer.profile

	var m := UIKit.modal(Loc.done(p.full_name) if p.looked_up
		else Loc.t("The person at the window"), 0.84, 0.90)
	_root = m["root"]
	_body = m["body"]
	add_child(_root)

	# --- What they just said ---
	if not _last_answer.is_empty():
		var quote := UIKit.rich(Loc.f("[i]\"%s\"[/i]", [Loc.t(_last_answer)]),
			UIKit.FONT_M, UIKit.WHITE)
		_body.add_child(quote)
		if not _last_note.is_empty():
			_body.add_child(UIKit.label(Loc.f("→ %s", [Loc.t(_last_note)]),
				UIKit.FONT_S, UIKit.tone_colour(_last_tone)))
		_body.add_child(UIKit.spacer(6))
		_body.add_child(UIKit.rule())

	# --- Where you stand ---
	var status := HBoxContainer.new()
	status.add_theme_constant_override("separation", 18)
	status.add_child(UIKit.label(Loc.f("Patience %d/%d", [p.patience, p.patience_max]), UIKit.FONT_S,
		UIKit.RED if p.patience <= 1 else UIKit.GREEN_DIM))
	status.add_child(UIKit.label(p.read_out(), UIKit.FONT_S, _read_colour(p)))
	if not p.scanned:
		status.add_child(UIKit.label("not swept", UIKit.FONT_S, UIKit.GREEN_DIM))
	if not p.looked_up:
		status.add_child(UIKit.label("no file pulled", UIKit.FONT_S, UIKit.GREEN_DIM))
	_body.add_child(status)
	_body.add_child(UIKit.spacer(4))

	# --- Questions ---
	#
	# The actions are counted before a single question is laid out, because the
	# actions are the decisions and they must always be reachable. Questions get
	# whatever room is left and page if they overflow.
	var questions := p.available_questions()
	var room := MAX_OPTIONS - _action_count()
	var paged := questions.size() > room
	if paged:
		room -= 1   # the last slot becomes "more questions"

	if questions.is_empty():
		_body.add_child(UIKit.label("Nothing left to ask.", UIKit.FONT_S, UIKit.GREEN_DIM))
	elif p.patience <= 0:
		_body.add_child(UIKit.label("They are done answering questions.",
			UIKit.FONT_S, UIKit.GREEN_DIM))
	else:
		_body.add_child(UIKit.label("ASK", UIKit.FONT_S, UIKit.GREEN_DIM))
		var pages: int = maxi(1, int(ceil(float(questions.size()) / float(maxi(1, room)))))
		_question_page = _question_page % pages
		var start: int = _question_page * room
		for i in range(start, mini(start + room, questions.size())):
			var q: Dictionary = questions[i]
			var note: String = "" if q["kind"] == "base" else Loc.t("· on the evidence")
			_add_option({"type": "ask", "entry": q}, Loc.t(str(q["prompt"])), true, note)
		if paged:
			_add_option({"type": "page"}, Loc.t("More questions"), true,
				Loc.f("· page %d of %d", [_question_page + 1, pages]))

	# --- Actions ---
	_body.add_child(UIKit.spacer(6))
	_body.add_child(UIKit.rule())
	_body.add_child(UIKit.label("DO", UIKit.FONT_S, UIKit.GREEN_DIM))

	if _player.held_illicit > 0:
		_add_option({"type": "sell"},
			Loc.f("Sell them what's in your hand (%d)", [_player.held_illicit]),
			_customer._asked_for_illicit,
			"" if _customer._asked_for_illicit else Loc.t("· they haven't asked"))

	if _customer._asked_for_illicit and not p.sold_illicit:
		_add_option({"type": "refuse"}, Loc.t("Tell them you don't do that here"), true)

	_add_option({"type": "dismiss"}, Loc.t("Tell them to move on"), true)
	_add_option({"type": "close"}, Loc.t("Step back"), true)

	# --- What you have on them ---
	var evidence := p.evidence_lines()
	if not evidence.is_empty():
		_body.add_child(UIKit.spacer(6))
		_body.add_child(UIKit.rule())
		_body.add_child(UIKit.label("WHAT YOU HAVE", UIKit.FONT_S, UIKit.GREEN_DIM))
		for line in evidence:
			var l := UIKit.label(Loc.t(line), UIKit.FONT_S, UIKit.WHITE)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_body.add_child(l)

	# Asking a question takes it off the menu, so the list shrinks under the
	# cursor. Clamped here, after the rows exist, so the next press lands on a
	# row that is really there rather than off the end of the list.
	_cursor = clampi(_cursor, 0, maxi(0, _options.size() - 1))

	_body.add_child(UIKit.spacer(6))
	_body.add_child(UIKit.label(
		"[D-pad] move   ·   [A] choose   ·   [B] step back" if _pad_active
			else Loc.t("[1-9] choose   ·   [ESC] step back"),
		UIKit.FONT_S, UIKit.GREEN_DIM))


func _read_colour(p: CustomerProfile) -> Color:
	var s := p.suspicion_score()
	if s <= 0:
		return UIKit.GREEN
	elif s <= 7:
		return UIKit.AMBER
	return UIKit.RED


## How many action rows this rebuild will produce. Worked out before the
## questions are laid out so they can be given the space that is genuinely left,
## and kept next to `_rebuild` because the two have to agree exactly.
func _action_count() -> int:
	var n := 2   # move on, step back — always there
	if _player != null and _player.held_illicit > 0:
		n += 1
	if _customer != null and _customer._asked_for_illicit and not _customer.profile.sold_illicit:
		n += 1
	return n


func _add_option(data: Dictionary, text: String, enabled: bool, note: String = "") -> void:
	_options.append({"data": data, "enabled": enabled})
	_body.add_child(UIKit.option_row(_options.size(), text, enabled, note,
		_pad_active and _options.size() - 1 == _cursor))


func _choose(option: Dictionary) -> void:
	if not bool(option["enabled"]):
		Audio.play("deny", -16.0)
		return
	var data: Dictionary = option["data"]
	var p := _customer.profile

	match str(data["type"]):
		"ask":
			var result := p.ask(data["entry"])
			_last_answer = str(result["text"])
			_last_note = str(result["note"])
			_last_tone = _note_tone(str(result["outcome"]))
			Audio.play("beep_low", -22.0)
			if bool(result["aborted"]):
				Signals.notice.emit(Loc.t("They've had enough of the questions."), "warn")
				_customer._leave("spooked")
				close()
				return
			_rebuild()
		"page":
			# Turning the page is not talking to them, so it costs nothing.
			_question_page += 1
			Audio.play("click", -24.0)
			_rebuild()
		"sell":
			var units := _player.held_illicit
			_player.clear_hands()
			_customer.receive_illicit(units)
			close()
		"refuse":
			_customer.refuse()
			close()
		"dismiss":
			_customer.dismiss()
			close()
		"close":
			close()


func _note_tone(outcome: String) -> String:
	match outcome:
		"cleared": return "good"
		"confirmed": return "bad"
		"contradiction": return "bad"
		"consistent": return "good"
		"unclear": return "warn"
	return "info"
