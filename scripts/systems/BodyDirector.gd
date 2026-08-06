class_name BodyDirector
extends Node
## Keeps track of what is on the floor.
##
## Owns every Body in the world, runs the check that makes customers bolt when
## they walk in on one, and settles up at 05:00 for anything still lying there.
##
## The point of all of it is that shooting somebody has to be *work*. It was the
## worst thing you could do in this game and it cost a mouse click and an
## automatic bag. Now it costs you a bag, a trip to the manhole, and every
## customer who walks in while you are still carrying them.

## What one horrified customer does to you. They leave without paying, they tell
## people, and somebody somewhere makes a phone call.
const WITNESS_HEAT := 9.0
const WITNESS_REPUTATION := 6.0
## Left on the floor at close of business. A dead customer is far worse than a
## dead officer, because there is nobody to explain why it happened.
const LEFTOVER_HEAT_CIVILIAN := 26.0
const LEFTOVER_HEAT_OFFICER := 10.0

var _world: World
var _bodies: Array[Body] = []
var _check_timer: float = 0.0


func setup(world: World) -> void:
	_world = world
	Signals.body_dropped.connect(adopt)


func adopt(body: Node3D) -> void:
	if _world == null or body == null:
		return
	var b := body as Body
	if b == null:
		return
	_world.add_child(b)
	b.disposed.connect(_on_disposed)
	_bodies.append(b)


func _on_disposed(body: Body) -> void:
	_bodies.erase(body)
	# Getting rid of one properly takes the edge off, but never all of it. The
	# heat that came from pulling the trigger is not refundable — only the extra
	# that comes from leaving them where they fell.
	GameState.add_heat(-7.0)


func clear() -> void:
	for b in _bodies:
		if is_instance_valid(b):
			b.queue_free()
	_bodies.clear()


func count() -> int:
	var n := 0
	for b in _bodies:
		if is_instance_valid(b):
			n += 1
	return n


func visible_count() -> int:
	var n := 0
	for b in _bodies:
		if is_instance_valid(b) and not b.bagged and not b.carried:
			n += 1
	return n


## The nearest body the player could act on, for the interaction prompt.
func nearest_to(at: Vector3, within: float) -> Body:
	var best: Body = null
	var best_d := within
	for b in _bodies:
		if not is_instance_valid(b) or b.carried:
			continue
		var d := b.global_position.distance_to(at)
		if d < best_d:
			best_d = d
			best = b
	return best


## Anyone who walks in on an unbagged body leaves and takes your name with them.
## Run on a timer rather than every frame — this is a proximity sweep over every
## customer against every body, and it does not need to be exact.
func _process(delta: float) -> void:
	if _bodies.is_empty() or _world == null:
		return
	_check_timer -= delta
	if _check_timer > 0.0:
		return
	_check_timer = 0.35

	for b in _bodies:
		if not is_instance_valid(b) or b.bagged or b.carried:
			continue
		for node in _world.get_children():
			var c := node as Customer
			if c == null or not is_instance_valid(c):
				continue
			if c.state == Customer.State.DEAD or c.state == Customer.State.LEAVING:
				continue
			if c.seen_a_body:
				continue
			if b.notice_check(c):
				_witness(c)


## Somebody has walked in on a body.
##
## They used to turn round and go, which sounds right and played badly: one
## mistake at the wrong moment emptied the shop, and the night was over before
## you could do anything about it. Now they say what they saw, it costs you heat
## and your name on the street, and they stay — shaken, and still a customer.
##
## The pressure is unchanged and the punishment is still real. What has gone is
## the part where a single body cascades into an empty shop and no way back.
func _witness(c: Customer) -> void:
	Signals.customer_spoke.emit(c.profile.full_name, Loc.t("...What is that. What is that on the floor."))
	Signals.notice.emit(Loc.f("%s saw it. They will remember that.",
		[c.profile.full_name.split(" ")[0]]), "bad")
	GameState.add_heat(WITNESS_HEAT)
	GameState.add_reputation(-WITNESS_REPUTATION)
	GameState.evidence_against_you += 1
	if GameState.raid_reason.is_empty():
		GameState.raid_reason = Loc.t("Somebody walked in on a body on your floor.")
	# Marked so the sweep does not charge for the same body twice a second.
	c.seen_a_body = true


## Called at the end of the shift. Anything still here is a problem you did not
## solve, and it is counted before the rent is.
func settle_night() -> Dictionary:
	var civilians := 0
	var officers := 0
	for b in _bodies:
		if not is_instance_valid(b):
			continue
		if b.was_civilian:
			civilians += 1
		else:
			officers += 1

	var heat := float(civilians) * LEFTOVER_HEAT_CIVILIAN + float(officers) * LEFTOVER_HEAT_OFFICER
	if heat > 0.0:
		GameState.add_heat(heat)
		GameState.evidence_against_you += civilians + officers
		if GameState.raid_reason.is_empty():
			GameState.raid_reason = Loc.f(
				"You closed up with %d of them still on the floor.",
				[civilians + officers])
	return {"civilians": civilians, "officers": officers, "heat": heat}
