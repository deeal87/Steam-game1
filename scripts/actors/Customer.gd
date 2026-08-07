class_name Customer
extends CharacterBody3D
## A person in the shop.
##
## They come off the street, through the front door, round the aisle to whatever
## they came for, take it off the shelf themselves, and bring it to the counter.
## From there it is your problem: scan it, bag it, take the money — while
## deciding whether the person on the other side of the till is police.
##
## Pathing is a short list of waypoints rather than a navigation mesh. The shop
## is one room with three racks in known places, so corners are the only thing
## that needs solving and a hand-written path solves them exactly.

signal wants_conversation(customer: Customer)
signal finished_shopping(customer: Customer)
signal finished(customer: Customer, outcome: String)

enum State { APPROACHING, QUEUEING, AT_COUNTER, LEAVING, DEAD }

const WALK_SPEED := 1.45
const FLEE_SPEED := 3.6
const BROWSE_PAUSE := 1.1
const ARRIVE_RADIUS := 0.38

var profile: CustomerProfile
var state: State = State.APPROACHING
var health: float = 60.0
var outcome: String = ""
var world: World

## What they actually managed to get off the shelves. Anything out of stock is
## simply not in here, which is what makes restocking matter.
var basket: Array[String] = []
var served_items: Array[String] = []
var paid: bool = false

## Position in the queue. 0 is being served, -1 means still shopping.
var queue_index: int = -1
var patience_seconds: float = 110.0
## Waiting in line burns patience too, just more slowly than being ignored at
## the counter does.
var _time_queued: float = 0.0
## Time spent walking the shop floor, so somebody who cannot get where they are
## going does not stand there all night holding a slot open.
var _time_shopping: float = 0.0
## Builds while they are standing behind somebody and resets when they move up.
## Once it crosses PUSH_AT they will step in front of the person ahead — see
## NightDirector, which owns the line and does the actual swapping.
var _push_pressure: float = 0.0
var _next_grumble: float = 0.0
var _shift_phase: float = 0.0
var _time_at_counter: float = 0.0
var _asked_for_illicit: bool = false
## Set once they have walked in on a body. They stay and keep shopping — it has
## already cost you heat and your name — but they are never charged for it twice.
var seen_a_body: bool = false
var _body: Node3D
var _hips: Array[Node3D] = []
var _shoulders: Array[Node3D] = []
var _walk_phase: float = 0.0
var _spoke_greeting: bool = false
var _observed_behaviour: bool = false

## Waypoints, each {pos, take} where `take` is an item id to pick up there.
var _path: Array[Dictionary] = []
var _path_index: int = 0
var _pause: float = 0.0


func setup(p: CustomerProfile, w: World = null) -> void:
	profile = p
	world = w


func _ready() -> void:
	name = "Customer"
	collision_layer = 0
	set_collision_layer_value(3, true)
	collision_mask = 1

	# Wide enough to hold the person drawn on it.
	#
	# `ProcMesh.human` builds a body 0.42 * bulk across at the torso and puts the
	# arms outside that, so the widest point is about 0.30 * bulk — which at any
	# bulk above 1.0 is outside a fixed 0.30 capsule. The capsule stopped at the
	# shelf and the shoulder carried on into it.
	var caps := CapsuleShape3D.new()
	caps.radius = maxf(0.30, 0.302 * profile.bulk_scale)
	caps.height = 1.70
	var cs := CollisionShape3D.new()
	cs.shape = caps
	cs.position = Vector3(0, 0.90, 0)
	add_child(cs)

	_body = ProcMesh.human(profile.seed_value, profile.height_scale, profile.bulk_scale)
	add_child(_body)
	for child in _body.get_children():
		if child.name.begins_with("Hip"):
			_hips.append(child)
		elif child.name.begins_with("Shoulder"):
			_shoulders.append(child)

	global_position = World.CUSTOMER_ENTRY
	_build_inbound_path()


## Street, front door, then one stop at each rack they need, then the counter.
func _build_inbound_path() -> void:
	_path.clear()
	_path_index = 0
	_step(World.DOOR_OUTSIDE)
	_step(World.DOOR_INSIDE)

	var last := Vector3.INF
	for id: String in profile.order:
		var point: Vector3 = world.browse_point(id) if world != null else World.CUSTOMER_STAND
		# Two things off the same rack is one stop, not two.
		if point.distance_to(last) < 0.6 and not _path.is_empty():
			_step(point + Vector3(randf_range(-0.25, 0.25), 0, 0.2), id)
		else:
			_step(point, id)
		last = point

	# The path stops at the aisle. Where they stand after that depends on how
	# many people are already in front of them, which is not knowable yet.
	_step(World.AISLE)


func _build_outbound_path() -> void:
	_path.clear()
	_path_index = 0
	_step(World.AISLE)
	_step(World.DOOR_INSIDE)
	_step(World.DOOR_OUTSIDE)
	_step(World.CUSTOMER_EXIT)


## Adds a stop, and whatever it takes to walk to it without going through the
## shelving on the way.
##
## Steering is a straight line at the next stop and a slide off anything hit, so
## a leg that crosses a rack is a customer pressed into the side of it for as
## long as the leg lasts. The world knows where its shelving is; it hands back
## the corner to go round, and that corner becomes a stop of its own.
func _step(pos: Vector3, take: String = "") -> void:
	if world != null and not _path.is_empty():
		var from: Vector3 = _path[_path.size() - 1]["pos"]
		for via: Vector3 in world.detour(from, pos):
			_path.append({"pos": via, "take": ""})
	_path.append({"pos": pos, "take": take})


func interaction_prompt() -> String:
	if state == State.DEAD:
		return ""
	if state == State.LEAVING:
		return Loc.f("%s — leaving", [profile.full_name.split(" ")[0]])
	if state == State.APPROACHING:
		return Loc.f("%s — shopping", [profile.full_name.split(" ")[0]])
	if state == State.QUEUEING:
		return Loc.f("[E] Talk  (%s, %d in line)", [profile.full_name.split(" ")[0], queue_index])
	return Loc.t("[E] Talk")


func _physics_process(delta: float) -> void:
	match state:
		State.APPROACHING:
			_follow_path(delta, WALK_SPEED)
			_watch_for_getting_stuck(delta)
		State.QUEUEING:
			_hold_position(delta)
		State.AT_COUNTER:
			_face_toward(Vector3(0, 0, 1))
			_time_at_counter += delta
			_idle_animation(delta)
			if _time_at_counter > patience_seconds:
				Signals.notice.emit(Loc.f("%s got tired of waiting.",
					[profile.full_name.split(" ")[0]]), "warn")
				_leave("impatient")
		State.LEAVING:
			_follow_path(delta, FLEE_SPEED if outcome == "fled" else WALK_SPEED)
		State.DEAD:
			pass


## How long somebody will keep trying to get round the shop before giving up.
## Generous — a full trip measures at about forty seconds — but finite.
const SHOPPING_LIMIT := 95.0


## Nobody browses forever.
##
## Queueing and standing at the counter both had patience timeouts; walking the
## shop floor had none, so a customer who could not reach their next waypoint
## stayed in APPROACHING for the whole night. Because arrivals are gated on how
## many people are already inside, four of those filled the shop and stopped
## anybody else coming in at all — the soak caught three nights in a row where
## the same four people stood there from opening to close while eleven more
## never got through the door.
##
## Anything can cause it: a shelf tucked behind a rack, an awkward corner, or —
## most likely in practice — the player standing in the aisle, which is not a
## thing the game can forbid. So this does not try to diagnose the obstruction.
## It just makes sure a customer who is not getting anywhere eventually leaves,
## the same way the night itself eventually ends.
func _watch_for_getting_stuck(delta: float) -> void:
	_time_shopping += delta
	if _time_shopping < SHOPPING_LIMIT:
		return
	GameState.note_gave_up_waiting()
	Signals.notice.emit(Loc.f("%s couldn't get round the shop and left.",
		[profile.full_name.split(" ")[0]]), "warn")
	_leave("stuck")


func _follow_path(delta: float, speed: float) -> void:
	if _pause > 0.0:
		_pause -= delta
		velocity.x = 0.0
		velocity.z = 0.0
		_idle_animation(delta)
		move_and_slide()
		return

	if _path_index >= _path.size():
		if state == State.APPROACHING:
			# Done shopping. The director decides where in the line they stand.
			state = State.QUEUEING
			finished_shopping.emit(self)
		else:
			finished.emit(self, outcome)
		return

	var step: Dictionary = _path[_path_index]
	var target: Vector3 = step["pos"]
	_walk_toward(target, speed, delta)

	var flat := Vector2(target.x - global_position.x, target.z - global_position.z)
	if flat.length() < ARRIVE_RADIUS:
		var take := str(step["take"])
		if not take.is_empty():
			_take_from_shelf(take)
			_pause = BROWSE_PAUSE
		_path_index += 1


## They help themselves. An empty shelf is a lost sale and they say so.
func _take_from_shelf(item_id: String) -> void:
	if GameState.take_from_shelf(item_id):
		basket.append(item_id)
		Audio.play_at("click", global_position + Vector3(0, 1.2, 0), -24.0)
		if world != null:
			world.refresh_shelves()
	else:
		Signals.customer_spoke.emit(profile.full_name,
			Loc.f("You're out of %s.",
				[Loc.t(str(GameState.ITEMS[item_id]["name"])).to_lower()]))
		Signals.notice.emit(Loc.t("Empty shelf cost you a sale."), "warn")


## Walks to their slot in the line and waits there. Once they are at the front
## and standing on the mark, the counter opens for them.
func _hold_position(delta: float) -> void:
	var slot: int = clampi(queue_index, 0, World.QUEUE_SLOTS.size() - 1)
	var target: Vector3 = World.QUEUE_SLOTS[slot]
	var flat := Vector2(target.x - global_position.x, target.z - global_position.z)

	if flat.length() > 0.22:
		_walk_toward(target, WALK_SPEED, delta)
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		if not is_on_floor():
			velocity.y -= 18.0 * delta
		move_and_slide()
		_face_toward(Vector3(0, 0, 1))
		_idle_animation(delta)
		if queue_index == 0:
			_arrive()
			return
		_wait_behaviour(delta)

	_time_queued += delta
	if _time_queued > patience_seconds * 1.4:
		GameState.note_gave_up_waiting()
		Signals.notice.emit(Loc.f("%s put their basket down and walked out.",
			[profile.full_name.split(" ")[0]]), "warn")
		_leave("impatient")


## What somebody does while they stand in a queue at four in the morning.
##
## Two reasons this exists beyond decoration. A line of statues reads as broken,
## and — more usefully — the longer somebody waits the more they say, which is
## free information about a person you have not reached yet.
func _wait_behaviour(delta: float) -> void:
	# Shift weight from foot to foot, more as the wait drags.
	_shift_phase += delta * (0.7 + _time_queued * 0.02)
	var restless: float = minf(1.0, _time_queued / 30.0)
	_body.position.x = sin(_shift_phase) * 0.035 * (0.4 + restless)
	# Glance around: they look at the counter, then away, then back.
	var glance := sin(_shift_phase * 0.43) * 0.5 * restless
	rotation.y = lerp_angle(rotation.y, glance, delta * 2.0)

	# Standing behind somebody is what winds them up. Somebody easy-going barely
	# accumulates; somebody at the top of the range gets there in about half a
	# minute.
	_push_pressure += delta * profile.pushiness

	_next_grumble -= delta
	if _next_grumble > 0.0:
		return
	# The first complaint is a long way in; after that they get quicker.
	_next_grumble = randf_range(16.0, 26.0) * (1.0 - restless * 0.5)
	if _time_queued < 12.0:
		return
	Signals.customer_spoke.emit(profile.full_name, _grumble(restless))


const GRUMBLES_MILD := [
	"Any chance?",
	"Take your time.",
	"Is it always like this?",
	"I've only got the two things.",
]
const GRUMBLES_SHARP := [
	"I have been stood here ten minutes.",
	"There is one of me and one of you. How is this hard?",
	"Right. I'm going to put these back.",
	"Do you actually work here?",
]

func _grumble(restless: float) -> String:
	var pool: Array = GRUMBLES_SHARP if restless > 0.6 else GRUMBLES_MILD
	return pool[randi() % pool.size()]


# --- Stepping in front of people ---------------------------------------------

## How much standing-behind-somebody it takes before they stop putting up with
## it. A pushiness of 1.0 gets there in about half a minute; below about 0.35
## they will never get there before the queue moves on its own.
const PUSH_AT := 9.0

const PUSH_LINES := [
	"You don't mind, do you.",
	"I'm only after the one thing.",
	"'Scuse me.",
	"I'll be quicker than you, mate.",
]
const PUSHED_BACK_LINES := [
	"Oi. I was here.",
	"Are you serious?",
	"Right, lovely. Thanks.",
	"Did you not see the queue?",
]


## Whether they are ready to step in front of `ahead`, and if so, doing it.
## The line itself is reordered by NightDirector — this only decides and
## performs the bit of it that is about these two people.
func ready_to_push(ahead: Customer) -> bool:
	if state != State.QUEUEING or profile == null:
		return false
	if _push_pressure < PUSH_AT:
		return false
	if not is_instance_valid(ahead) or ahead.state != State.QUEUEING:
		return false
	_push_pressure = 0.0
	Signals.customer_spoke.emit(profile.full_name, PUSH_LINES[randi() % PUSH_LINES.size()])
	ahead.on_pushed_past(self)
	Signals.notice.emit(Loc.f("%s stepped in front of %s.",
		[profile.full_name.split(" ")[0], ahead.profile.full_name.split(" ")[0]]), "warn")
	Audio.play("click", -20.0)
	return true


## Being stepped in front of. It costs them patience, and it makes them readier
## to do the same thing to somebody else — which is how a queue churns instead
## of just swapping one pair over and settling.
func on_pushed_past(_by: Customer) -> void:
	_time_queued += patience_seconds * 0.18
	_push_pressure += PUSH_AT * 0.5
	_next_grumble = 0.6
	Signals.customer_spoke.emit(profile.full_name,
		PUSHED_BACK_LINES[randi() % PUSHED_BACK_LINES.size()])


## Moving up resets the grievance. Somebody who has just got closer to the
## counter is not, at that moment, angry about being far from it.
func note_moved_up() -> void:
	_push_pressure = 0.0


func _arrive() -> void:
	state = State.AT_COUNTER
	global_position = World.CUSTOMER_STAND
	_face_toward(Vector3(0, 0, 1))
	if _spoke_greeting:
		return
	_spoke_greeting = true
	Audio.play_at("chime", global_position + Vector3(0, 1.5, 0), -18.0)
	Signals.customer_spoke.emit(profile.full_name, profile.greeting)
	# The director puts the basket on the counter in response to this.
	Signals.customer_arrived.emit(self)

	if not _observed_behaviour:
		_observed_behaviour = true
		get_tree().create_timer(2.4).timeout.connect(_reveal_behaviour)

	# Somebody who found nothing on the shelves has nothing to ring up, so the
	# till never opens and `on_paid` never fires — which used to mean they stood
	# at the counter for their full hundred and ten seconds of patience with no
	# way to move them on but a dismissal, and a dismissal costs your name. Being
	# punished twice for an empty shelf, once in lost trade and once in
	# reputation, is not a trade-off; it is a trap.
	#
	# They complain and go. If they were here for the other thing as well, they
	# still get to ask, because that is what they came for.
	if basket.is_empty():
		if profile.wants_illicit:
			get_tree().create_timer(1.5).timeout.connect(_ask_for_illicit)
		else:
			Signals.customer_spoke.emit(profile.full_name, _empty_handed())
			Signals.notice.emit(Loc.f("%s found nothing worth buying.",
				[profile.full_name.split(" ")[0]]), "warn")
			get_tree().create_timer(2.4).timeout.connect(_leave.bind("nothing_to_buy"))


const EMPTY_HANDED := [
	"You've got nothing. I'll try the garage.",
	"Shelves are bare, mate.",
	"Don't bother restocking on my account.",
	"Is this a shop or a storage unit?",
]

func _empty_handed() -> String:
	return EMPTY_HANDED[randi() % EMPTY_HANDED.size()]


func _reveal_behaviour() -> void:
	if state != State.AT_COUNTER or profile == null:
		return
	for id: String in profile.tells_on_channel(Tells.CHANNEL_BEHAVIOUR):
		if profile.discover(id):
			Signals.evidence_logged.emit({
				"tell": id,
				"label": Tells.get_tell(id)["label"],
				"source": "watching",
			})
			Signals.notice.emit(Loc.t(str(Tells.get_tell(id)["label"])), "watch")


## Called by the checkout once the till has been rung.
func on_paid(total: int) -> void:
	if paid or state != State.AT_COUNTER:
		return
	paid = true
	served_items = basket.duplicate()

	var rng := RandomNumberGenerator.new()
	rng.seed = profile.seed_value + int(Time.get_ticks_msec())
	var tip := 0
	if rng.randf() < 0.45:
		tip = rng.randi_range(1, 7)
		# An officer paying out of the department's float has no reason to be
		# careful with it. Suggestive, never conclusive.
		if profile.kind == CustomerProfile.Kind.UNDERCOVER and rng.randf() < 0.5:
			tip += rng.randi_range(3, 9)
	if tip > 0:
		GameState.add_money(tip, "tips")
		Signals.notice.emit(Loc.f("Tip: %d", [tip]), "good")
	Signals.customer_spoke.emit(profile.full_name, Loc.t("Keep it.") if tip > 0 else "Ta.")

	if profile.wants_illicit and not _asked_for_illicit:
		get_tree().create_timer(1.5).timeout.connect(_ask_for_illicit)
	else:
		get_tree().create_timer(2.0).timeout.connect(_leave.bind("served"))


func _ask_for_illicit() -> void:
	if state != State.AT_COUNTER:
		return
	_asked_for_illicit = true
	var line := ProfileGenerator.illicit_line(profile)
	Signals.customer_spoke.emit(profile.full_name, line)
	# The ask is the moment the whole game turns on, and it used to go past in
	# the same notice column as "2 waiting" and a subtitle that fades after four
	# seconds. It stays over their head now until you have decided.
	Signals.customer_asks.emit(self, line)
	Signals.notice.emit(Loc.t("They're asking. Decide."), "warn")
	Tutor.fire("asked")


func receive_illicit(units: int) -> void:
	if state != State.AT_COUNTER:
		return
	Signals.customer_asks.emit(self, "")
	var rng := RandomNumberGenerator.new()
	rng.seed = profile.seed_value + 77
	var total := GameState.illicit_unit_price(rng) * units
	GameState.add_money(total, "illicit")
	GameState.add_heat(2.5 * float(units))
	profile.sold_illicit = true
	Audio.play("register", -10.0)

	if profile.kind == CustomerProfile.Kind.UNDERCOVER:
		Signals.customer_spoke.emit(profile.full_name, Loc.t("That's everything. Thanks."))
		Signals.notice.emit(Loc.t("They put it straight in their pocket. They didn't even look at it."), "bad")
	else:
		Signals.customer_spoke.emit(profile.full_name, Loc.t("You're a lifesaver."))
	get_tree().create_timer(2.2).timeout.connect(_leave.bind("sold"))


func refuse() -> void:
	Signals.customer_asks.emit(self, "")
	if state != State.AT_COUNTER:
		return
	if profile.kind == CustomerProfile.Kind.UNDERCOVER:
		Signals.customer_spoke.emit(profile.full_name, Loc.t("Fine. Have a good night."))
	else:
		Signals.customer_spoke.emit(profile.full_name, Loc.t("Right. Worth asking."))
	get_tree().create_timer(1.6).timeout.connect(_leave.bind("refused"))


## Telling someone to get out. Free when you are right; expensive when the
## person you threw out was only ever here for cigarettes.
func dismiss() -> void:
	Signals.customer_asks.emit(self, "")
	if state not in [State.AT_COUNTER, State.QUEUEING]:
		return
	if profile.kind == CustomerProfile.Kind.CIVILIAN:
		GameState.note_wrong_dismissal()
		Signals.customer_spoke.emit(profile.full_name, Loc.t("...You're joking. I come in here every night."))
		Signals.notice.emit(Loc.t("You threw out a regular. Word gets round."), "bad")
	else:
		Signals.customer_spoke.emit(profile.full_name, Loc.t("Alright, alright. I'm going."))
	_leave("dismissed")


# --- Devices -----------------------------------------------------------------

func on_interact(_player: Node) -> void:
	if state == State.DEAD:
		return
	if state == State.LEAVING:
		Signals.notice.emit(Loc.t("They're already going."), "info")
		return
	if state == State.APPROACHING:
		Signals.notice.emit(Loc.t("They're still shopping."), "info")
		return
	wants_conversation.emit(self)


func on_scan(_player: Node) -> void:
	if state == State.DEAD or profile == null:
		return
	profile.scanned = true
	var findings: Array = []
	for id: String in profile.tells_on_channel(Tells.CHANNEL_SCANNER):
		var fresh := profile.discover(id)
		findings.append({"tell": id, "label": Tells.get_tell(id)["label"], "fresh": fresh})
		if fresh:
			Signals.evidence_logged.emit({
				"tell": id, "label": Tells.get_tell(id)["label"], "source": "scanner"})
	Signals.scan_completed.emit(findings)
	if findings.is_empty():
		Signals.notice.emit(Loc.t("Sweep clean. Nothing on them."), "info")
	else:
		Signals.notice.emit(Loc.f("%d reading." if findings.size() == 1 else "%d readings.",
			[findings.size()]), "bad")
		if profile.kind == CustomerProfile.Kind.UNDERCOVER:
			Signals.customer_spoke.emit(profile.full_name, Loc.t("Is that necessary?"))
		else:
			Signals.customer_spoke.emit(profile.full_name, Loc.t("What is that thing?"))
		profile.patience -= 1
		if profile.patience <= 0:
			profile.aborted = true
			_leave("spooked")


func on_lookup() -> void:
	if profile == null:
		return
	profile.looked_up = true
	for id: String in profile.tells_on_channel(Tells.CHANNEL_TERMINAL):
		if profile.discover(id):
			Signals.evidence_logged.emit({
				"tell": id, "label": Tells.get_tell(id)["label"], "source": "terminal"})


# --- Violence ----------------------------------------------------------------

func take_damage(amount: float, _source: Object = null) -> void:
	if state == State.DEAD:
		return
	health -= amount
	if health > 0.0:
		if state != State.LEAVING:
			Signals.customer_spoke.emit(profile.full_name, Loc.t("—!"))
			_leave("fled")
		return
	_die()


func _die() -> void:
	state = State.DEAD
	outcome = "killed"
	collision_layer = 0
	Audio.play_at("impact", global_position + Vector3(0, 0.5, 0), -8.0)

	var tw := create_tween()
	tw.tween_property(_body, "rotation:x", deg_to_rad(-88.0), 0.45).set_trans(Tween.TRANS_BOUNCE)
	tw.parallel().tween_property(_body, "position:y", 0.12, 0.45)

	if profile.kind == CustomerProfile.Kind.UNDERCOVER:
		GameState.cops_identified += 1
		GameState.add_heat(6.0)
		Signals.notice.emit(Loc.t("A badge falls out of their coat. You were right."), "good")
		_drop_badge()
	else:
		GameState.civilians_killed += 1
		GameState.add_heat(22.0)
		GameState.evidence_against_you += 1
		GameState.note_wrong_killing()
		Signals.notice.emit(Loc.t("No badge. No wire. Nothing. You just shot a customer."), "bad")

	# They stay where they fell. Bagging and getting rid of them is a job you
	# have to do, with the queue still coming in — see Body.gd.
	Signals.notice.emit(Loc.t("They're on the floor. Anyone who walks in will see that."), "bad")
	var corpse := Body.new()
	corpse.setup(global_position, profile.kind == CustomerProfile.Kind.CIVILIAN,
		profile.full_name.split(" ")[0], profile.seed_value)
	Signals.body_dropped.emit(corpse)

	get_tree().create_timer(1.2).timeout.connect(_report_killed)


## The badge, on the floor beside them.
##
## The line "a badge falls out of their coat" has been in this game for a long
## time and nothing fell out of anything — it was a sentence in the notice strip
## at the bottom of the screen, which is also where the weather and the rent go.
## It is the one moment that tells you that you were right about somebody, and it
## deserves to be a thing lying on the floor next to what you did.
##
## Parented to the world rather than to the customer, or it would be freed with
## them a second and a half later.
func _drop_badge() -> void:
	var art := ProcTex.painted("id_badge")
	if art == null or world == null:
		return
	var badge := ProcMesh.box(Vector3(0.12, 0.012, 0.15), Vector3.ZERO,
		ProcMesh.mat(art, 1.0, Color(0.5, 0.55, 0.6), 0.12), "Badge")
	badge.rotation_degrees = Vector3(0, randf_range(0.0, 360.0), 0)
	world.add_child(badge)
	badge.global_position = global_position + Vector3(
		randf_range(-0.4, 0.4), 0.03, randf_range(-0.4, 0.4))


## Told to the director a beat after the shot, so the body is on the floor
## before the slot is given away.
##
## A method rather than the lambda this used to be. A `SceneTreeTimer` outlives
## the thing that started it, and a lambda captures by value — so when a night
## ended between the shot and the beat, the timer fired into a customer that had
## already been freed and the log filled with "Lambda capture at index 0 was
## freed". A callable bound to an object is disconnected when that object goes,
## which is exactly the behaviour wanted, and the same change applies to the four
## leave timers above.
func _report_killed() -> void:
	finished.emit(self, "killed")


# --- Leaving -----------------------------------------------------------------

func _leave(why: String) -> void:
	Signals.customer_asks.emit(self, "")
	if state == State.DEAD or state == State.LEAVING:
		return
	state = State.LEAVING
	outcome = why
	_pause = 0.0
	_build_outbound_path()

	if profile.kind == CustomerProfile.Kind.UNDERCOVER:
		if profile.sold_illicit:
			GameState.evidence_against_you += 2
			GameState.raid_reason = Loc.t("You sold to an officer.")
		else:
			GameState.evidence_against_you += 1
			GameState.raid_reason = Loc.t("An officer left with suspicions but no buy.")
		GameState.add_heat(9.0)


# --- Motion ------------------------------------------------------------------

func _walk_toward(target: Vector3, speed: float, delta: float) -> void:
	var dir := Vector3(target.x - global_position.x, 0, target.z - global_position.z)
	if dir.length() > 0.05:
		dir = dir.normalized()
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
		_face_toward(dir)
	else:
		velocity.x = 0.0
		velocity.z = 0.0
	if not is_on_floor():
		velocity.y -= 18.0 * delta
	else:
		velocity.y = 0.0
	move_and_slide()

	_walk_phase += delta * speed * 3.4
	var swing := sin(_walk_phase) * 0.55
	for i in _hips.size():
		_hips[i].rotation.x = swing * (1.0 if i == 0 else -1.0)
	for i in _shoulders.size():
		_shoulders[i].rotation.x = -swing * 0.7 * (1.0 if i == 0 else -1.0)


func _idle_animation(delta: float) -> void:
	_walk_phase += delta * 1.2
	var sway := sin(_walk_phase) * 0.035
	_body.position.x = sway
	for i in _shoulders.size():
		_shoulders[i].rotation.x = lerpf(_shoulders[i].rotation.x, sway * 0.4, delta * 4.0)
	for i in _hips.size():
		_hips[i].rotation.x = lerpf(_hips[i].rotation.x, 0.0, delta * 4.0)


func _face_toward(dir: Vector3) -> void:
	var flat := Vector3(dir.x, 0, dir.z)
	if flat.length_squared() < 0.001:
		return
	rotation.y = lerp_angle(rotation.y, atan2(flat.x, flat.z), 0.16)
