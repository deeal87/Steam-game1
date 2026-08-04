class_name Customer
extends CharacterBody3D
## A person at the hatch.
##
## They walk out of the fog, ask for a few things off the shelf, and — often
## enough — ask for the thing that is not on the shelf. Everything you can
## learn about them lives on their `profile`; this node is only the body that
## carries it to the counter and takes it away again.

signal wants_conversation(customer: Customer)
signal finished(customer: Customer, outcome: String)

enum State { APPROACHING, AT_COUNTER, LEAVING, DEAD }

const WALK_SPEED := 1.35
const FLEE_SPEED := 3.4

var profile: CustomerProfile
var state: State = State.APPROACHING
var health: float = 60.0
var outcome: String = ""
var served_items: Array[String] = []
var paid: bool = false

## Seconds they will stand there before giving up and walking off. Being slow
## costs you the sale; being slow with an officer costs you nothing at all.
var patience_seconds: float = 95.0
var _time_at_counter: float = 0.0
var _asked_for_illicit: bool = false
var _body: Node3D
var _hips: Array[Node3D] = []
var _shoulders: Array[Node3D] = []
var _walk_phase: float = 0.0
var _target: Vector3
var _spoke_greeting: bool = false
var _observed_behaviour: bool = false


func setup(p: CustomerProfile) -> void:
	profile = p


func _ready() -> void:
	name = "Customer"
	collision_layer = 0
	set_collision_layer_value(3, true)
	collision_mask = 1

	var caps := CapsuleShape3D.new()
	caps.radius = 0.32
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

	_target = World.CUSTOMER_STAND
	global_position = World.CUSTOMER_ENTRY


func interaction_prompt() -> String:
	if state == State.DEAD:
		return ""
	if state == State.LEAVING:
		return "%s — leaving" % profile.full_name.split(" ")[0]
	return "[E] Talk"


func _physics_process(delta: float) -> void:
	match state:
		State.APPROACHING:
			_walk_toward(_target, WALK_SPEED, delta)
			if global_position.distance_to(_target) < 0.25:
				_arrive()
		State.AT_COUNTER:
			_face(Vector3(0, 0, 1))
			_time_at_counter += delta
			_idle_animation(delta)
			if _time_at_counter > patience_seconds and not profile.wants_illicit:
				_leave("impatient")
			elif _time_at_counter > patience_seconds * 1.6:
				_leave("impatient")
		State.LEAVING:
			_walk_toward(_target, FLEE_SPEED if outcome == "fled" else WALK_SPEED, delta)
			if global_position.distance_to(_target) < 1.0:
				_depart()
		State.DEAD:
			pass


func _arrive() -> void:
	state = State.AT_COUNTER
	global_position = _target
	_face(Vector3(0, 0, 1))
	if not _spoke_greeting:
		_spoke_greeting = true
		Audio.play("chime", -18.0)
		Signals.customer_spoke.emit(profile.full_name, profile.greeting)
		Signals.customer_arrived.emit(self)
		# Give them a beat, then let them say what they came for.
		get_tree().create_timer(1.6).timeout.connect(_state_order)


func _state_order() -> void:
	if state != State.AT_COUNTER:
		return
	var names: Array[String] = []
	for id: String in profile.order:
		names.append(str(GameState.ITEMS[id]["name"]).to_lower())
	var line := ""
	match names.size():
		1: line = "Just the %s." % names[0]
		2: line = "%s and %s." % [names[0].capitalize(), names[1]]
		_: line = "%s, %s, and %s." % [names[0].capitalize(), names[1], names[2]]
	Signals.customer_spoke.emit(profile.full_name, line)

	# Behavioural tells are the ones you get for free, just by watching. They
	# surface a few seconds after they start talking.
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


# --- The transaction ---------------------------------------------------------

## The player has put a shelf item on the counter.
func receive_item(item_id: String) -> bool:
	if state != State.AT_COUNTER:
		return false
	if not profile.order.has(item_id) or served_items.has(item_id):
		Signals.customer_spoke.emit(profile.full_name, "I didn't ask for that.")
		return false
	served_items.append(item_id)
	Audio.play("click", -18.0)
	if served_items.size() >= profile.order.size():
		_settle_up()
	else:
		Signals.customer_spoke.emit(profile.full_name, "And the rest?")
	return true


func _settle_up() -> void:
	if paid:
		return
	paid = true
	var total := 0
	for id: String in served_items:
		total += int(GameState.ITEMS[id]["price"])
	GameState.add_money(total, "takings")
	GameState.customers_served += 1
	Audio.play("register", -12.0)

	# Tips are genuinely random, and an officer paying from the department's
	# float has no reason to be stingy, which is a tell in itself if you notice
	# it — though never a reliable one.
	var tip := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = profile.seed_value + int(Time.get_ticks_msec())
	if rng.randf() < 0.45:
		tip = rng.randi_range(1, 7)
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


## The player has handed over units from under the counter.
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


## The player has said no.
func refuse() -> void:
	if state != State.AT_COUNTER:
		return
	if profile.kind == CustomerProfile.Kind.UNDERCOVER:
		Signals.customer_spoke.emit(profile.full_name, "Fine. Have a good night.")
	else:
		Signals.customer_spoke.emit(profile.full_name, "Right. Worth asking.")
	get_tree().create_timer(1.6).timeout.connect(func() -> void: _leave("refused"))


## The player has told them to leave.
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
	wants_conversation.emit(self)


func on_scan(_player: Node) -> void:
	if state == State.DEAD or profile == null:
		return
	profile.scanned = true
	var findings: Array = []
	for id: String in profile.tells_on_channel(Tells.CHANNEL_SCANNER):
		var fresh := profile.discover(id)
		findings.append({
			"tell": id,
			"label": Tells.get_tell(id)["label"],
			"fresh": fresh,
		})
		if fresh:
			Signals.evidence_logged.emit({
				"tell": id,
				"label": Tells.get_tell(id)["label"],
				"source": "scanner",
			})
	Signals.scan_completed.emit(findings)
	if findings.is_empty():
		Signals.notice.emit("Sweep clean. Nothing on them.", "info")
	else:
		Signals.notice.emit("%d reading%s." % [findings.size(), "" if findings.size() == 1 else "s"], "bad")
		# Being swept is not normal, and they know it.
		if profile.kind == CustomerProfile.Kind.UNDERCOVER:
			Signals.customer_spoke.emit(profile.full_name, "Is that necessary?")
		else:
			Signals.customer_spoke.emit(profile.full_name, "What is that thing?")
		profile.patience -= 1
		if profile.patience <= 0:
			profile.aborted = true
			_leave("spooked")


## The terminal has pulled their file. Terminal-channel tells become visible.
func on_lookup() -> void:
	if profile == null:
		return
	profile.looked_up = true
	for id: String in profile.tells_on_channel(Tells.CHANNEL_TERMINAL):
		if profile.discover(id):
			Signals.evidence_logged.emit({
				"tell": id,
				"label": Tells.get_tell(id)["label"],
				"source": "terminal",
			})


# --- Violence ----------------------------------------------------------------

func take_damage(amount: float, _source: Object = null) -> void:
	if state == State.DEAD:
		return
	health -= amount
	if health > 0.0:
		# Wounded and not dead is the worst outcome: they run, and whatever
		# they know goes with them.
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

	# A body bag means it is off the street before anyone drives past.
	if GameState.body_bags > 0:
		GameState.body_bags -= 1
		GameState.add_heat(-6.0)
		Signals.notice.emit("You drag them in and bag them. (%d bags left)" % GameState.body_bags, "info")
	else:
		GameState.add_heat(8.0)
		Signals.notice.emit("No bags left. They're lying in the road.", "bad")

	get_tree().create_timer(3.5).timeout.connect(func() -> void: finished.emit(self, "killed"))


# --- Leaving -----------------------------------------------------------------

func _leave(why: String) -> void:
	if state == State.DEAD or state == State.LEAVING:
		return
	state = State.LEAVING
	outcome = why
	_target = World.CUSTOMER_EXIT

	if profile.kind == CustomerProfile.Kind.UNDERCOVER:
		# The user's rule: an officer who walks away brings a door team back.
		# How hard that team hits depends on whether they left with anything.
		if profile.sold_illicit:
			GameState.evidence_against_you += 2
			GameState.raid_reason = "You sold to an officer."
		else:
			GameState.evidence_against_you += 1
			GameState.raid_reason = "An officer left with suspicions but no buy."
		GameState.add_heat(9.0)


func _depart() -> void:
	finished.emit(self, outcome)


# --- Motion ------------------------------------------------------------------

func _walk_toward(target: Vector3, speed: float, delta: float) -> void:
	var flat := Vector3(target.x, global_position.y, target.z)
	var dir := (flat - global_position)
	dir.y = 0.0
	if dir.length() > 0.05:
		dir = dir.normalized()
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
		_face(dir)
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


func _face(dir: Vector3) -> void:
	var flat := Vector3(dir.x, 0, dir.z)
	if flat.length_squared() < 0.001:
		return
	var target_yaw := atan2(flat.x, flat.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, 0.16)
