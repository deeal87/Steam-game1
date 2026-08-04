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
var _next_grumble: float = 0.0
var _shift_phase: float = 0.0
var _time_at_counter: float = 0.0
var _asked_for_illicit: bool = false
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

	var caps := CapsuleShape3D.new()
	caps.radius = 0.30
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
	_path.append({"pos": World.DOOR_OUTSIDE, "take": ""})
	_path.append({"pos": World.DOOR_INSIDE, "take": ""})

	var last := Vector3.INF
	for id: String in profile.order:
		var point: Vector3 = world.browse_point(id) if world != null else World.CUSTOMER_STAND
		# Two things off the same rack is one stop, not two.
		if point.distance_to(last) < 0.6 and not _path.is_empty():
			_path.append({"pos": point + Vector3(randf_range(-0.25, 0.25), 0, 0.2), "take": id})
		else:
			_path.append({"pos": point, "take": id})
		last = point

	# The path stops at the aisle. Where they stand after that depends on how
	# many people are already in front of them, which is not knowable yet.
	_path.append({"pos": World.AISLE, "take": ""})


func _build_outbound_path() -> void:
	_path.clear()
	_path_index = 0
	_path.append({"pos": World.AISLE, "take": ""})
	_path.append({"pos": World.DOOR_INSIDE, "take": ""})
	_path.append({"pos": World.DOOR_OUTSIDE, "take": ""})
	_path.append({"pos": World.CUSTOMER_EXIT, "take": ""})


func interaction_prompt() -> String:
	if state == State.DEAD:
		return ""
	if state == State.LEAVING:
		return "%s — leaving" % profile.full_name.split(" ")[0]
	if state == State.APPROACHING:
		return "%s — shopping" % profile.full_name.split(" ")[0]
	if state == State.QUEUEING:
		return "[E] Talk  (%s, %d in line)" % [profile.full_name.split(" ")[0], queue_index]
	return "[E] Talk"


func _physics_process(delta: float) -> void:
	match state:
		State.APPROACHING:
			_follow_path(delta, WALK_SPEED)
		State.QUEUEING:
			_hold_position(delta)
		State.AT_COUNTER:
			_face_toward(Vector3(0, 0, 1))
			_time_at_counter += delta
			_idle_animation(delta)
			if _time_at_counter > patience_seconds:
				Signals.notice.emit("%s got tired of waiting." % profile.full_name.split(" ")[0], "warn")
				_leave("impatient")
		State.LEAVING:
			_follow_path(delta, FLEE_SPEED if outcome == "fled" else WALK_SPEED)
		State.DEAD:
			pass


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
		Audio.play("click", -24.0)
		if world != null:
			world.refresh_shelves()
	else:
		Signals.customer_spoke.emit(profile.full_name,
			"You're out of %s." % str(GameState.ITEMS[item_id]["name"]).to_lower())
		Signals.notice.emit("Empty shelf cost you a sale.", "warn")


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
		Signals.notice.emit("%s gave up waiting in the queue." % profile.full_name.split(" ")[0], "warn")
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


func _arrive() -> void:
	state = State.AT_COUNTER
	global_position = World.CUSTOMER_STAND
	_face_toward(Vector3(0, 0, 1))
	if _spoke_greeting:
		return
	_spoke_greeting = true
	Audio.play("chime", -18.0)
	Signals.customer_spoke.emit(profile.full_name, profile.greeting)
	# The director puts the basket on the counter in response to this.
	Signals.customer_arrived.emit(self)

	if not _observed_behaviour:
		_observed_behaviour = true
		get_tree().create_timer(2.4).timeout.connect(_reveal_behaviour)


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
			Signals.notice.emit(str(Tells.get_tell(id)["label"]), "watch")


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
		Signals.notice.emit("Tip: %d" % tip, "good")
	Signals.customer_spoke.emit(profile.full_name, "Keep it." if tip > 0 else "Ta.")

	if profile.wants_illicit and not _asked_for_illicit:
		get_tree().create_timer(1.5).timeout.connect(_ask_for_illicit)
	else:
		get_tree().create_timer(2.0).timeout.connect(func() -> void: _leave("served"))


func _ask_for_illicit() -> void:
	if state != State.AT_COUNTER:
		return
	_asked_for_illicit = true
	Signals.customer_spoke.emit(profile.full_name, ProfileGenerator.illicit_line(profile))
	Signals.notice.emit("They're asking. Decide.", "warn")


func receive_illicit(units: int) -> void:
	if state != State.AT_COUNTER:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = profile.seed_value + 77
	var total := GameState.illicit_unit_price(rng) * units
	GameState.add_money(total, "illicit")
	GameState.add_heat(2.5 * float(units))
	profile.sold_illicit = true
	Audio.play("register", -10.0)

	if profile.kind == CustomerProfile.Kind.UNDERCOVER:
		Signals.customer_spoke.emit(profile.full_name, "That's everything. Thanks.")
		Signals.notice.emit("They put it straight in their pocket. They didn't even look at it.", "bad")
	else:
		Signals.customer_spoke.emit(profile.full_name, "You're a lifesaver.")
	get_tree().create_timer(2.2).timeout.connect(func() -> void: _leave("sold"))


func refuse() -> void:
	if state != State.AT_COUNTER:
		return
	if profile.kind == CustomerProfile.Kind.UNDERCOVER:
		Signals.customer_spoke.emit(profile.full_name, "Fine. Have a good night.")
	else:
		Signals.customer_spoke.emit(profile.full_name, "Right. Worth asking.")
	get_tree().create_timer(1.6).timeout.connect(func() -> void: _leave("refused"))


func dismiss() -> void:
	if state != State.AT_COUNTER:
		return
	Signals.customer_spoke.emit(profile.full_name, "Alright, alright. I'm going.")
	_leave("dismissed")


# --- Devices -----------------------------------------------------------------

func on_interact(_player: Node) -> void:
	if state == State.DEAD:
		return
	if state == State.LEAVING:
		Signals.notice.emit("They're already going.", "info")
		return
	if state == State.APPROACHING:
		Signals.notice.emit("They're still shopping.", "info")
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
		Signals.notice.emit("Sweep clean. Nothing on them.", "info")
	else:
		Signals.notice.emit("%d reading%s." % [findings.size(), "" if findings.size() == 1 else "s"], "bad")
		if profile.kind == CustomerProfile.Kind.UNDERCOVER:
			Signals.customer_spoke.emit(profile.full_name, "Is that necessary?")
		else:
			Signals.customer_spoke.emit(profile.full_name, "What is that thing?")
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
			Signals.customer_spoke.emit(profile.full_name, "—!")
			_leave("fled")
		return
	_die()


func _die() -> void:
	state = State.DEAD
	outcome = "killed"
	collision_layer = 0
	Audio.play("impact", -8.0)

	var tw := create_tween()
	tw.tween_property(_body, "rotation:x", deg_to_rad(-88.0), 0.45).set_trans(Tween.TRANS_BOUNCE)
	tw.parallel().tween_property(_body, "position:y", 0.12, 0.45)

	if profile.kind == CustomerProfile.Kind.UNDERCOVER:
		GameState.cops_identified += 1
		GameState.add_heat(6.0)
		Signals.notice.emit("A badge falls out of their coat. You were right.", "good")
	else:
		GameState.civilians_killed += 1
		GameState.add_heat(22.0)
		GameState.evidence_against_you += 1
		Signals.notice.emit("No badge. No wire. Nothing. You just shot a customer.", "bad")

	if GameState.body_bags > 0:
		GameState.body_bags -= 1
		GameState.add_heat(-6.0)
		Signals.notice.emit("You drag them in and bag them. (%d bags left)" % GameState.body_bags, "info")
	else:
		GameState.add_heat(8.0)
		Signals.notice.emit("No bags left. They're lying on the shop floor.", "bad")

	get_tree().create_timer(3.5).timeout.connect(func() -> void: finished.emit(self, "killed"))


# --- Leaving -----------------------------------------------------------------

func _leave(why: String) -> void:
	if state == State.DEAD or state == State.LEAVING:
		return
	state = State.LEAVING
	outcome = why
	_pause = 0.0
	_build_outbound_path()

	if profile.kind == CustomerProfile.Kind.UNDERCOVER:
		if profile.sold_illicit:
			GameState.evidence_against_you += 2
			GameState.raid_reason = "You sold to an officer."
		else:
			GameState.evidence_against_you += 1
			GameState.raid_reason = "An officer left with suspicions but no buy."
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
