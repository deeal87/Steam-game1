extends Node
## Teaches the game while you play it.
##
## There is a lot to know here — a scanner, a registry terminal, a questioning
## system with three kinds of answer, a till that refuses until everything is
## rung up, a stockroom, a stash, a sewer, and bodies that have to be carried
## somewhere. The title screen has one paragraph, and after that a new player is
## alone with all of it. For a game that expects you to make judgement calls,
## being confused about the *controls* is the worst possible reason to lose.
##
## So: no modal tutorial, no forced first night on rails. Each hint fires **once,
## ever**, the first time the situation it explains actually comes up, as a line
## in the same notice stream everything else uses. Then it never speaks again —
## progress is stored in `user://hints.cfg`, so a second run is silent from the
## start and a returning player is never taught anything twice.
##
## The rule for writing one: explain the *control*, never the decision. Which
## key sweeps somebody is a thing the game should tell you. Whether to sell to
## them is the entire game and it stays yours.

const SAVE_PATH := "user://hints.cfg"

## id -> the line. Kept to one sentence each because they share the notice
## column with everything else that happens, and a paragraph there is a wall.
const HINTS := {
	"open": "Scanner's on the counter — [E] picks it up. [F] sweeps whoever you are looking at.",
	"scan_goods": "Their shopping is on the counter. [E] on each item rings it up; the till will not take payment until they all are.",
	"till_ready": "All rung up. Work the till to take the money.",
	"asked": "They want what is under the counter. Sweep them, pull their file on the terminal, and talk to them before you decide.",
	"first_tell": "That is a tell — something that needs explaining. Talk to them and it unlocks a question about it.",
	"first_answer": "Confirmed means they contradicted themselves. Cleared means it holds up. Unclear means they would not say, which innocent people do often enough that it proves nothing on its own.",
	"empty_shelf": "That run is empty. [Q] while looking at a shelf restocks it from the back.",
	"first_body": "Bag them before anybody walks in, then carry them to the manhole in the stockroom. Nothing else gets rid of one.",
	"low_bags": "You are out of body bags. The supplier sells them, and you cannot bag anybody without one.",
	"can_afford": "You have enough to call the supplier. Weapons, fittings for the doors, and bags.",
	"torch": "Past the door it is genuinely dark. [T] is the torch.",
	"sewer": "The tunnels get worse every time you use them, and they never get better.",
}

## Turned off from the pause menu by anyone who does not want them.
var enabled: bool = true

var _shown: Dictionary = {}


func _ready() -> void:
	load_progress()
	Signals.checkout_changed.connect(_on_checkout)
	Signals.scan_completed.connect(_on_scan)
	Signals.evidence_logged.connect(_on_evidence)
	Signals.body_dropped.connect(_on_body)
	Signals.night_started.connect(_on_night_started)
	Signals.money_changed.connect(_on_money)


## Shows a hint the first time and never again. Safe to call from anywhere as
## often as you like, which is the point — callers check a *situation*, not
## whether they have already mentioned it.
func fire(id: String) -> bool:
	if not enabled or not HINTS.has(id) or _shown.has(id):
		return false
	_shown[id] = true
	save_progress()
	Signals.notice.emit(str(HINTS[id]), "watch")
	return true


func seen(id: String) -> bool:
	return _shown.has(id)


func seen_count() -> int:
	return _shown.size()


# --- Triggers ----------------------------------------------------------------

func _on_night_started(night: int) -> void:
	if night == 1:
		fire("open")


func _on_checkout(scanned: int, total_items: int, _price: int) -> void:
	if total_items <= 0:
		return
	if scanned < total_items:
		fire("scan_goods")
	else:
		fire("till_ready")


func _on_scan(findings: Array) -> void:
	if not findings.is_empty():
		fire("first_tell")


func _on_evidence(_entry: Dictionary) -> void:
	fire("first_answer")


func _on_body(_body: Node3D) -> void:
	if GameState.body_bags <= 0:
		fire("low_bags")
	else:
		fire("first_body")


## Fires the first time you could actually act on it, rather than at a fixed
## number — being told about the supplier while broke is noise.
func _on_money(amount: int) -> void:
	if amount >= int(GameState.WEAPONS["bat"]["price"]):
		fire("can_afford")


# --- Persistence -------------------------------------------------------------

func save_progress() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("hints", "enabled", enabled)
	for id: String in _shown:
		cfg.set_value("shown", id, true)
	cfg.save(SAVE_PATH)


func load_progress() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	enabled = bool(cfg.get_value("hints", "enabled", true))
	if not cfg.has_section("shown"):
		return
	for id: String in cfg.get_section_keys("shown"):
		if HINTS.has(id):
			_shown[id] = true


## For anybody who wants to be taught it again, and for the tests.
func reset() -> void:
	_shown.clear()
	save_progress()
