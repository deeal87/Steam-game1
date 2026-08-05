extends Node
## Achievements, kept locally and mirrored to Steam when Steam is there.
##
## Same shape as PlayerIdentity: the game owns the truth, the platform is an
## optional consumer of it. Everything here works with no Steam at all — unlocks
## persist to `user://achievements.cfg` and show in the pause menu — and if
## GodotSteam is present and initialised, each unlock is also pushed up with
## `setAchievement` / `storeStats`. Dropping the plugin in needs no change here.
##
## The API ids are what Steamworks calls them, and they are what you type into
## the partner site. Changing one after release orphans everybody's unlock, so
## they are deliberately dull and permanent while the display names are free to
## be rewritten.
##
## A note on what is *not* here: nothing unlocks for shooting people. The game
## has an opinion about that and handing out a trophy for it would undercut
## every cost the rest of the systems go to the trouble of charging.

signal unlocked(id: String, entry: Dictionary)

const SAVE_PATH := "user://achievements.cfg"

## id -> {name, desc, hidden}. `hidden` ones are not described until earned,
## because the description would give away the thing.
const CATALOGUE := {
	"FIRST_NIGHT": {
		"name": "Still Open",
		"desc": "Survive your first shift and make the rent.",
		"hidden": false,
	},
	"FIVE_NIGHTS": {
		"name": "Regular Hours",
		"desc": "Survive five nights.",
		"hidden": false,
	},
	"TEN_NIGHTS": {
		"name": "Nothing Else For A Mile",
		"desc": "Survive ten nights.",
		"hidden": false,
	},
	"CLEAN_READ": {
		"name": "Clean Read",
		"desc": "Get through a whole night without being wrong about anybody.",
		"hidden": false,
	},
	"SPOTLESS": {
		"name": "Spotless",
		"desc": "Finish a night with your name still at 100%.",
		"hidden": false,
	},
	"MADE_THE_RENT": {
		"name": "Made The Rent",
		"desc": "Pay the rent on shelf trade alone, with nothing sold under the counter.",
		"hidden": false,
	},
	"SURVIVED_RAID": {
		"name": "The Shutter Held",
		"desc": "Survive a raid without going down the manhole.",
		"hidden": false,
	},
	"NO_WITNESSES": {
		"name": "Tidy",
		"desc": "Deal with a body before anybody sees it.",
		"hidden": false,
	},
	"TUNNEL_RAT": {
		"name": "Tunnel Rat",
		"desc": "Find what is at the end of the spur.",
		"hidden": false,
	},
	"MASTER": {
		"name": "Master Of Master",
		"desc": "Find the thing at the end of the road.",
		"hidden": true,
	},
}

var _earned: Dictionary = {}
var _steam_warned: bool = false


func _ready() -> void:
	load_progress()


## Unlocks once and only once. Safe to call from anywhere, as often as you like —
## every caller below is a place the condition is *checked*, not a place someone
## has to remember whether it already fired.
func unlock(id: String) -> bool:
	if not CATALOGUE.has(id) or _earned.has(id):
		return false
	_earned[id] = true
	save_progress()
	_push_to_steam(id)
	var entry: Dictionary = CATALOGUE[id]
	Signals.notice.emit("Achievement: %s" % entry["name"], "good")
	Audio.play("chime", -12.0)
	unlocked.emit(id, entry)
	return true


func has(id: String) -> bool:
	return _earned.has(id)


func earned_count() -> int:
	return _earned.size()


## Everything, in catalogue order, with whether it is earned. Hidden ones keep
## their description back until then.
func listing() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in CATALOGUE:
		var entry: Dictionary = CATALOGUE[id]
		var got := _earned.has(id)
		out.append({
			"id": id,
			"name": str(entry["name"]) if got or not bool(entry["hidden"]) else "???",
			"desc": str(entry["desc"]) if got or not bool(entry["hidden"]) else "Not yet.",
			"earned": got,
			"hidden": bool(entry["hidden"]),
		})
	return out


# --- The conditions ----------------------------------------------------------
#
# Kept together so it is possible to read what the game rewards in one screen,
# rather than hunting unlock calls through eight files.

## Called at the end of every shift, with the summary the report is built from.
func check_night_end(summary: Dictionary) -> void:
	var rent_paid := bool(summary.get("rent_paid", false))
	var bill: Dictionary = summary.get("bill", {})
	var mistakes := int(bill.get("dismissed_count", 0)) + int(bill.get("killed_count", 0))
	var bodies: Dictionary = summary.get("bodies", {})
	var left_out := int(bodies.get("civilians", 0)) + int(bodies.get("officers", 0))

	if rent_paid:
		unlock("FIRST_NIGHT")
		# Rent covered without touching the stash. Hard on purpose — the whole
		# economy is tuned so that shelf trade alone does not quite do it.
		if int(summary.get("illicit", 0)) == 0:
			unlock("MADE_THE_RENT")

	if mistakes == 0 and left_out == 0 and int(summary.get("served", 0)) > 0:
		unlock("CLEAN_READ")
	if float(summary.get("reputation", 0.0)) >= 100.0 and int(summary.get("served", 0)) > 0:
		unlock("SPOTLESS")

	if GameState.nights_survived >= 5:
		unlock("FIVE_NIGHTS")
	if GameState.nights_survived >= 10:
		unlock("TEN_NIGHTS")


## Survived, rather than went down the ladder. The distinction is the point.
func check_raid_survived(fled: bool) -> void:
	if not fled:
		unlock("SURVIVED_RAID")


func check_body_disposed(was_seen: bool) -> void:
	if not was_seen:
		unlock("NO_WITNESSES")


# --- Persistence -------------------------------------------------------------

func save_progress() -> void:
	var cfg := ConfigFile.new()
	for id: String in _earned:
		cfg.set_value("earned", id, true)
	Persist.write(cfg, SAVE_PATH, "achievements")


func load_progress() -> void:
	var cfg := ConfigFile.new()
	if not Persist.read(cfg, SAVE_PATH, "achievements"):
		return
	for id: String in cfg.get_section_keys("earned") if cfg.has_section("earned") else []:
		if CATALOGUE.has(id):
			_earned[id] = true


## Wipes local progress. Only reachable from the pause menu, and only useful for
## testing — a run reset does not touch achievements.
func reset_all() -> void:
	_earned.clear()
	save_progress()


# --- Steam -------------------------------------------------------------------

## Mirrors an unlock up to Steam, if Steam is there.
##
## Guarded at every step the way PlayerIdentity is: the singleton may be absent,
## present but not initialised, or present with the client not running. None of
## those are errors — they are the normal case for a build running outside
## Steam, which is every build this repository produces today.
func _push_to_steam(id: String) -> bool:
	if not Engine.has_singleton("Steam"):
		return false
	var steam := Engine.get_singleton("Steam")
	if not steam.has_method("setAchievement"):
		return false
	if steam.has_method("isSteamRunning") and not steam.call("isSteamRunning"):
		return false
	steam.call("setAchievement", id)
	if steam.has_method("storeStats"):
		steam.call("storeStats")
	return true


## True when unlocks are actually reaching Steam, so the interface can say which
## it is rather than implying a connection the build does not have.
func steam_connected() -> bool:
	if not Engine.has_singleton("Steam"):
		return false
	var steam := Engine.get_singleton("Steam")
	if not steam.has_method("setAchievement"):
		return false
	if steam.has_method("isSteamRunning"):
		return bool(steam.call("isSteamRunning"))
	return true
