class_name Body
extends Node3D
## Somebody you shot, still on the floor.
##
## Bodies used to delete themselves after three and a half seconds, and a bag
## was spent automatically to knock a little heat off. That made "shoot them"
## a decision with no follow-through: the worst thing you can do in this game
## took less work than ringing up a packet of crisps.
##
## Now it stays until you deal with it, and dealing with it is three steps under
## time pressure, because the queue does not stop:
##
##   1. **Bag it.** Costs a bag. An unbagged body is the thing customers see.
##   2. **Pick it up.** It fills your hands and slows you to a walk.
##   3. **Put it down the manhole.** That is the only place it goes.
##
## Leave one out and every customer who gets near it bolts, which costs you heat
## and your name. Leave one out at 05:00 and it is evidence, which is a raid.

signal disposed(body: Body)

## How close somebody has to get before they notice. Deliberately generous —
## a body on the floor of a ten-metre room is not subtle, and making players
## rely on exact sightlines here would be fussy rather than tense.
const NOTICE_RANGE := 4.2

var bagged: bool = false
var carried: bool = false
## Whether this was somebody who had done nothing. Kept so the end-of-night
## reckoning can tell the difference between a dead officer and a dead customer.
var was_civilian: bool = true
var who: String = "Someone"

var _zone: StaticBody3D
var _visual: Node3D
var _seen_by: Dictionary = {}   ## customer instance id -> true, so each only bolts once


func setup(at: Vector3, civilian: bool, name_of: String, seed_value: int) -> void:
	position = at
	was_civilian = civilian
	who = name_of
	_build(seed_value)


func _build(seed_value: int) -> void:
	name = "Body"
	_visual = Node3D.new()
	add_child(_visual)

	# The person, face down. Reusing the same generator the living use means a
	# body looks like the customer it was rather than like a prop.
	var figure := ProcMesh.human(seed_value, 1.0, 1.05)
	figure.rotation.x = deg_to_rad(-88.0)
	figure.position.y = 0.12
	_visual.add_child(figure)

	_zone = _make_zone()
	add_child(_zone)


func _make_zone() -> StaticBody3D:
	var zone := StaticBody3D.new()
	zone.collision_layer = 0
	zone.set_collision_layer_value(4, true)
	zone.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.9, 1.1, 1.9)
	shape.shape = box
	shape.position = Vector3(0, 0.55, 0)
	zone.add_child(shape)
	zone.set_meta("interact", "body")
	zone.set_meta("body_ref", self)
	return zone


func prompt() -> String:
	if carried:
		return ""
	if not bagged:
		if GameState.body_bags <= 0:
			return Loc.f("[E] %s — no bags left", [who])
		return Loc.f("[E] Bag them (%d left)", [GameState.body_bags])
	return Loc.t("[E] Pick them up")


## Costs a bag. After this nobody panics at it, but it is still in your shop.
func bag() -> bool:
	if bagged or GameState.body_bags <= 0:
		return false
	GameState.body_bags -= 1
	bagged = true
	for child in _visual.get_children():
		child.queue_free()
	# A bag reads as a bag: one long dark shape, no limbs. The pack has a
	# photograph of a heavy sealed bag with a zip up it, which is close enough to
	# what this is, and the alternative was a flat black box.
	var bag_art := ProcTex.painted("gear_evidence_bag")
	_visual.add_child(ProcMesh.box(Vector3(0.62, 0.42, 1.85), Vector3(0, 0.21, 0),
		ProcMesh.mat(bag_art, 1.0) if bag_art != null
			else ProcMesh.mat(ProcTex.flat(Color(0.045, 0.05, 0.055))), "Bagged"))
	Audio.play_at("click", global_position + Vector3(0, 0.4, 0), -12.0)
	Signals.notice.emit(Loc.t("Bagged. Now it has to go somewhere."), "info")
	return true


func take_up() -> bool:
	if not bagged or carried:
		return false
	carried = true
	visible = false
	_zone.get_child(0).set_deferred("disabled", true)
	return true


func put_down(at: Vector3) -> void:
	carried = false
	visible = true
	position = at
	_zone.get_child(0).set_deferred("disabled", false)


## Down the manhole. This is the only way one of these leaves the building.
func dispose() -> void:
	Signals.notice.emit(Loc.t("Gone. You hear it land."), "good")
	Audio.play("impact", -20.0)
	# Whether anybody saw them before they went is the difference between having
	# handled it and having been caught handling it.
	Achievements.check_body_disposed(not _seen_by.is_empty())
	disposed.emit(self)
	queue_free()


## Anyone who gets close enough to an unbagged body leaves, and tells people.
##
## Charged once per customer per body, or standing next to one would drain your
## name at the frame rate.
func notice_check(customer: Node3D) -> bool:
	if bagged or carried:
		return false
	var id := customer.get_instance_id()
	if _seen_by.has(id):
		return false
	if customer.global_position.distance_to(global_position) > NOTICE_RANGE:
		return false
	_seen_by[id] = true
	return true
