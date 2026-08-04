extends Node
## Everything that survives from one night to the next.
##
## The economy is deliberately tight: legitimate trade almost exactly covers
## rent, so the only way to afford the weapons that keep you alive during a
## raid is to sell what you keep under the counter. That pressure is the game.

const SAVE_PATH := "user://kiosk_save.cfg"

# --- Run state ---
var night: int = 1
var money: int = 85
var heat: float = 0.0          ## 0-100. Drives undercover ratio and raid size.
var alive: bool = true
var nights_survived: int = 0
## Persisted across runs — finding it once is finding it.
var found_easter_egg: bool = false
var fled_through_sewer: bool = false
## Every trip down the ladder, counted for the whole run. The tunnels get worse
## and they never get better.
var sewer_trips: int = 0
## How the street sees you, 0-100. Being wrong about ordinary people is what
## takes it down, and it is slow to come back.
var reputation: float = 100.0

# --- Consumables ---
var drug_stock: int = 6        ## Units under the counter.
var shelf_stock: Dictionary = {}   ## item_id -> units on the shelf
var crate_stock: Dictionary = {}   ## item_id -> units in the back room

# --- Owned hardware ---
var weapons: Array[String] = []
var equipped_weapon: String = ""
var ammo: Dictionary = {}          ## weapon_id -> rounds
var defenses: Array[String] = []
var body_bags: int = 0

# --- Per-night bookkeeping, reset at the start of each shift ---
var takings: int = 0               ## Legitimate revenue this night.
var illicit_takings: int = 0
var tips: int = 0
var customers_served: int = 0
var cops_identified: int = 0
var civilians_killed: int = 0
var civilians_dismissed: int = 0
var customers_gave_up: int = 0
var evidence_against_you: int = 0  ## >0 at shift end means a raid.
var raid_reason: String = ""

# --- Catalogue ---------------------------------------------------------------

const ITEMS := {
	"smokes":   {"name": "Cigarettes", "price": 9,  "cost": 6, "shelf": 0},
	"soda":     {"name": "Cola",       "price": 3,  "cost": 1, "shelf": 1},
	"crisps":   {"name": "Crisps",     "price": 4,  "cost": 2, "shelf": 1},
	"beer":     {"name": "Beer",       "price": 6,  "cost": 4, "shelf": 2},
	"noodles":  {"name": "Pot Noodles","price": 3,  "cost": 1, "shelf": 2},
	"batteries":{"name": "Batteries",  "price": 7,  "cost": 4, "shelf": 0},
	"lighter":  {"name": "Lighter",    "price": 2,  "cost": 1, "shelf": 0},
	"coffee":   {"name": "Coffee",     "price": 3,  "cost": 1, "shelf": 1},
}

const WEAPONS := {
	"bat":     {"name": "Baseball Bat",  "price": 55,  "melee": true,  "damage": 42, "rate": 0.8, "mag": 0,  "spread": 0.0},
	"revolver":{"name": ".38 Revolver",  "price": 230, "melee": false, "damage": 46, "rate": 0.55,"mag": 6,  "spread": 0.018},
	"shotgun": {"name": "Pump Shotgun",  "price": 495, "melee": false, "damage": 22, "rate": 0.95,"mag": 5,  "spread": 0.075, "pellets": 7},
	"rifle":   {"name": "Carbine",       "price": 940, "melee": false, "damage": 30, "rate": 0.12,"mag": 24, "spread": 0.03},
}

const AMMO_PRICE := {"revolver": 12, "shotgun": 18, "rifle": 22}
const AMMO_PER_BOX := {"revolver": 12, "shotgun": 10, "rifle": 30}

const DEFENSES := {
	"door_bar":   {"name": "Shop Door Barricade", "price": 95,  "desc": "Shuts the shop door. They all have to come through the hatch."},
	"window_bars":{"name": "Hatch Bars",          "price": 150, "desc": "Shuts the serving hatch. They all have to come through the door."},
	"floor_trap": {"name": "Bear Trap",           "price": 80,  "desc": "Takes the first one through, whichever way that is."},
	"camera":     {"name": "Street Camera",       "price": 120, "desc": "Warns you a few seconds before the breach."},
}


func _ready() -> void:
	reset_run()


func reset_run() -> void:
	night = 1
	money = 85
	heat = 0.0
	alive = true
	nights_survived = 0
	fled_through_sewer = false
	sewer_trips = 0
	reputation = 100.0
	drug_stock = 6
	weapons = ["bat"]
	equipped_weapon = ""
	ammo = {}
	defenses = []
	body_bags = 1
	shelf_stock = {}
	crate_stock = {}
	for id: String in ITEMS:
		shelf_stock[id] = 4
		crate_stock[id] = 8
	reset_night_tally()


func reset_night_tally() -> void:
	takings = 0
	illicit_takings = 0
	tips = 0
	customers_served = 0
	cops_identified = 0
	civilians_killed = 0
	civilians_dismissed = 0
	customers_gave_up = 0
	evidence_against_you = 0
	raid_reason = ""


# --- Money -------------------------------------------------------------------

func add_money(amount: int, category: String = "takings") -> void:
	money += amount
	match category:
		"takings": takings += amount
		"illicit": illicit_takings += amount
		"tips": tips += amount
	Signals.money_changed.emit(money)


func spend(amount: int) -> bool:
	if money < amount:
		return false
	money -= amount
	Signals.money_changed.emit(money)
	return true


func add_heat(amount: float) -> void:
	heat = clampf(heat + amount, 0.0, 100.0)
	Signals.heat_changed.emit(heat)


## Going down the manhole while they are coming through the door.
##
## You live, but the kiosk does not: they take what is under the counter and
## whatever was in the till, and the heat stays exactly where it was. Running is
## meant to be the expensive way out, not the free one — otherwise the weapons
## and the fittings would never be worth buying.
func flee_through_sewer() -> Dictionary:
	var lost_cash := takings + illicit_takings + tips
	var lost_stash := drug_stock
	money = maxi(0, money - lost_cash)
	drug_stock = 0
	takings = 0
	illicit_takings = 0
	tips = 0
	fled_through_sewer = true
	evidence_against_you = 0
	raid_reason = ""
	add_heat(6.0)
	Signals.money_changed.emit(money)
	return {"cash": lost_cash, "stash": lost_stash}


# --- Being wrong about people ------------------------------------------------
#
# Throwing someone out and shooting someone were both, until now, free. That
# made "refuse everybody" the safest way to play, which is the opposite of what
# this game is about — the whole point is that you have to decide, and deciding
# wrongly has to cost something.
#
# Two costs. Word gets round the street, which thins out tomorrow's custom; and
# there is a bill at the end of the night for the mess.

const DISMISS_REPUTATION := 7.0
const DISMISS_FINE := 30
const KILL_REPUTATION := 28.0
const KILL_FINE := 110
## A clean night with people served earns a little back.
const CLEAN_NIGHT_RECOVERY := 5.0
## Being too slow is not the same as being wrong, and is priced accordingly.
const ABANDON_REPUTATION := 2.5


func add_reputation(amount: float) -> void:
	reputation = clampf(reputation + amount, 0.0, 100.0)
	Signals.reputation_changed.emit(reputation)


## You told an ordinary customer to get out. They tell people.
func note_wrong_dismissal() -> void:
	civilians_dismissed += 1
	add_reputation(-DISMISS_REPUTATION)


## Worse.
func note_wrong_killing() -> void:
	add_reputation(-KILL_REPUTATION)


## Somebody put their basket down and walked out rather than keep queueing.
##
## Not a mistake — you were not wrong about anybody, you were just slow — so it
## stays out of the end-of-night bill. It still costs a little of your name,
## because a shop where people give up waiting is a thing people mention. Small
## enough that a clean night's recovery still outweighs one of them.
func note_gave_up_waiting() -> void:
	customers_gave_up += 1
	add_reputation(-ABANDON_REPUTATION)


## What tonight's mistakes cost, settled at the end of the shift alongside rent.
func mistake_bill() -> Dictionary:
	var dismissed := civilians_dismissed * DISMISS_FINE
	var killed := civilians_killed * KILL_FINE
	return {
		"dismissed_count": civilians_dismissed,
		"dismissed": dismissed,
		"killed_count": civilians_killed,
		"killed": killed,
		"total": dismissed + killed,
	}


## Reputation thins the queue rather than emptying it: at rock bottom you still
## get a bit over half the trade, which is enough to claw back from but not
## enough to make rent on.
func reputation_multiplier() -> float:
	return 0.55 + 0.45 * (reputation / 100.0)


# --- Difficulty curve --------------------------------------------------------

## Rent due at the end of the shift. It rises faster than shelf trade can,
## which is the entire economic argument for keeping a stash.
func rent_due() -> int:
	return 135 + (night - 1) * 42


## What one unit under the counter fetches.
##
## The price climbs faster than the supplier's does, because the street gets
## hotter and the people still willing to deal get scarcer. That widening
## margin is deliberate: it keeps the business viable as the share of officers
## in the queue rises, so the late game is dangerous rather than merely broke.
func illicit_unit_price(rng: RandomNumberGenerator) -> int:
	return rng.randi_range(38, 66) + night * 7


## What the supplier charges per unit, before his batch discount.
func illicit_unit_cost() -> int:
	return 21 + int(float(night) * 1.2)


## How many customers walk in tonight. A bad name on the street costs you trade
## before you have even opened.
func customer_count() -> int:
	var base := clampi(9 + night, 9, 22)
	return maxi(4, int(round(float(base) * reputation_multiplier())))


## Share of tonight's customers who are police. Heat makes them take notice.
func undercover_ratio() -> float:
	var base := 0.10 + 0.035 * float(night - 1)
	return clampf(base + heat / 520.0, 0.0, 0.42)


## Undercover officers get better at hiding as the nights go on, so the number
## of tells they leak shrinks. Night 1 is generous on purpose.
func tells_for_undercover() -> int:
	return clampi(5 - int(float(night - 1) / 2.5), 2, 5)


## Civilians occasionally look guilty. This is what makes the job hard.
func false_tells_for_civilian() -> int:
	if randf() < 0.42 + 0.02 * float(night):
		return 1 if randf() < 0.72 else 2
	return 0


## How dangerous the tunnels are, from how often you have used them. The first
## trip is deliberately near-free: the sewer has to be safe enough once that
## you are willing to try it again.
func sewer_tier() -> int:
	return maxi(0, sewer_trips - 1)


func sewer_dweller_count() -> int:
	if sewer_trips <= 1:
		return 1
	return clampi(1 + int(float(sewer_trips - 1) * 0.7), 1, 6)


func raid_squad_size() -> int:
	return clampi(3 + int(float(night) * 0.9) + int(heat / 28.0), 3, 12)


# --- Stock -------------------------------------------------------------------

func shelf_units(item: String) -> int:
	return int(shelf_stock.get(item, 0))


func take_from_shelf(item: String) -> bool:
	if shelf_units(item) <= 0:
		return false
	shelf_stock[item] = shelf_units(item) - 1
	return true


## Moves one unit from the back-room crate onto the shelf. Returns false when
## the crate is empty, which is the player's cue to buy stock between shifts.
func restock_one(item: String) -> bool:
	if int(crate_stock.get(item, 0)) <= 0:
		return false
	crate_stock[item] = int(crate_stock[item]) - 1
	shelf_stock[item] = shelf_units(item) + 1
	return true


func total_shelf_units() -> int:
	var n := 0
	for id: String in shelf_stock:
		n += int(shelf_stock[id])
	return n


func empty_shelf_items() -> Array[String]:
	var out: Array[String] = []
	for id: String in ITEMS:
		if shelf_units(id) <= 0:
			out.append(id)
	return out


# --- Weapons -----------------------------------------------------------------

func has_weapon(id: String) -> bool:
	return weapons.has(id)


func ammo_for(id: String) -> int:
	if WEAPONS.get(id, {}).get("melee", false):
		return 999
	return int(ammo.get(id, 0))


func spend_ammo(id: String, n: int = 1) -> bool:
	if WEAPONS.get(id, {}).get("melee", false):
		return true
	if ammo_for(id) < n:
		return false
	ammo[id] = ammo_for(id) - n
	return true


func add_ammo(id: String, n: int) -> void:
	ammo[id] = ammo_for(id) + n


func best_weapon() -> String:
	var order := ["rifle", "shotgun", "revolver", "bat"]
	for id: String in order:
		if has_weapon(id) and ammo_for(id) > 0:
			return id
	return "bat"


# --- Persistence -------------------------------------------------------------

func save_run() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("run", "night", night)
	cfg.set_value("run", "money", money)
	cfg.set_value("run", "heat", heat)
	cfg.set_value("run", "nights_survived", nights_survived)
	cfg.set_value("run", "found_easter_egg", found_easter_egg)
	cfg.set_value("run", "sewer_trips", sewer_trips)
	cfg.set_value("run", "reputation", reputation)
	cfg.set_value("stock", "drugs", drug_stock)
	cfg.set_value("stock", "shelf", shelf_stock)
	cfg.set_value("stock", "crate", crate_stock)
	cfg.set_value("gear", "weapons", weapons)
	cfg.set_value("gear", "ammo", ammo)
	cfg.set_value("gear", "defenses", defenses)
	cfg.set_value("gear", "body_bags", body_bags)
	cfg.save(SAVE_PATH)


func load_run() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return false
	night = cfg.get_value("run", "night", 1)
	money = cfg.get_value("run", "money", 85)
	heat = cfg.get_value("run", "heat", 0.0)
	nights_survived = cfg.get_value("run", "nights_survived", 0)
	found_easter_egg = cfg.get_value("run", "found_easter_egg", false)
	sewer_trips = cfg.get_value("run", "sewer_trips", 0)
	reputation = cfg.get_value("run", "reputation", 100.0)
	drug_stock = cfg.get_value("stock", "drugs", 6)
	shelf_stock = cfg.get_value("stock", "shelf", shelf_stock)
	crate_stock = cfg.get_value("stock", "crate", crate_stock)
	var w: Array = cfg.get_value("gear", "weapons", ["bat"])
	weapons.clear()
	for id: Variant in w:
		weapons.append(str(id))
	ammo = cfg.get_value("gear", "ammo", {})
	var d: Array = cfg.get_value("gear", "defenses", [])
	defenses.clear()
	for id: Variant in d:
		defenses.append(str(id))
	body_bags = cfg.get_value("gear", "body_bags", 1)
	alive = true
	return true


func clear_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
