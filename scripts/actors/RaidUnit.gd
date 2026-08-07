class_name RaidUnit
extends CharacterBody3D
## One member of the door team.
##
## They are still not clever, but they work in pairs now, and the pair has a job
## each. The **point** closes on you, going wide round the counter island rather
## than up the middle. His **cover** stops just inside the door with a line
## across the room and shoots the moment you show yourself.
##
## That pairing is the whole difficulty of the fight. Against two people with no
## plan you could hold one angle and win. Against a point and a cover, staying
## still gets you flushed and moving gets you shot, so you have to choose which
## one to spend your shells on — and if you choose the point, his cover stops
## covering and comes on himself.
##
## They also share what they see. Breaking line of sight with the one in front
## of you no longer means the one behind him has lost you.

signal died(unit: RaidUnit)

enum State { ADVANCING, ENGAGING, BREACHING, SEARCHING, DEAD }
## POINT closes, COVER holds an angle. Before the shutter goes they are all
## APPROACH — outside, forming up, with no job yet.
enum Role { APPROACH, POINT, COVER }

const ADVANCE_SPEED := 2.4
## How long a cover man will hold his angle with no contact before he gives up
## on it and joins the search.
const COVER_PATIENCE := 7.0
const BREACH_SPEED := 1.9
## A cover man does not walk into the room, so he needs to be able to hit across
## it. A point man is moving, so he should not.
const COVER_ACCURACY_BONUS := 0.12
const POINT_ACCURACY_PENALTY := 0.18

var state: State = State.ADVANCING
var role: Role = Role.APPROACH
var health: float = 100.0
var damage: float = 9.0
var fire_interval: float = 1.15
var accuracy: float = 0.62

var _player: Player
var _body: Node3D
var _hips: Array[Node3D] = []
var _shoulders: Array[Node3D] = []
var _walk_phase: float = 0.0
var _fire_timer: float = 1.4
var _target: Vector3
## How long this one has gone without seeing anybody, used to decide when
## holding an angle has stopped being tactics and started being furniture.
var _hold: float = 0.0
var _spawn: Vector3
var _muzzle: OmniLight3D

## Where they last actually saw the player. They push to this rather than
## tracking you through the counter, so crouching and moving genuinely breaks
## their aim instead of merely delaying it.
var _last_known: Vector3
var _has_contact: bool = false
## Time between seeing you and firing. Without it, stepping into a doorway is
## instant death and the fight has no texture.
var _acquire: float = 0.0

## The squad they belong to, for calling out contacts and asking where the
## player was last seen. Null for a unit tested on its own.
var _squad: Node = null
## The waypoint a point man swings through on his way in, so he arrives from the
## side rather than walking up the middle of the room into your shotgun.
var _flank: Vector3 = Vector3.ZERO
var _has_flank: bool = false
## Which door this one was sent through. Kept because `_target` is the next
## waypoint, which for a point man is the end of the counter rather than the way
## he came in — so it is not something the entry can be read back out of.
var entry_used: Vector3 = Vector3.ZERO


## Called before the unit is in the tree, so the spawn point is stored and
## applied in `_ready` rather than written to `global_position` here.
## Where in the squad this one is. Decides which kit they were issued, and who
## goes through the door behind the shield.
var squad_index: int = 0


func setup(player: Player, spawn: Vector3, target: Vector3, tier: int,
		index: int = 0) -> void:
	_player = player
	_target = target
	_spawn = spawn
	squad_index = index
	# Later nights send better-equipped teams.
	health = 90.0 + float(tier) * 16.0
	damage = 8.0 + float(tier) * 1.6
	fire_interval = maxf(0.55, 1.20 - float(tier) * 0.07)
	accuracy = minf(0.90, 0.58 + float(tier) * 0.035)
	_last_known = target


func _ready() -> void:
	name = "RaidUnit"
	global_position = _spawn
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

	_body = ProcMesh.human(randi(), 1.02, 1.14)
	add_child(_body)
	for child in _body.get_children():
		if child.name.begins_with("Hip"):
			_hips.append(child)
		elif child.name.begins_with("Shoulder"):
			_shoulders.append(child)

	_apply_kit()

	_muzzle = OmniLight3D.new()
	_muzzle.light_color = Color(1.0, 0.82, 0.5)
	_muzzle.light_energy = 0.0
	_muzzle.omni_range = 5.0
	_muzzle.position = Vector3(0, 1.35, 0)
	add_child(_muzzle)


## Black kit, a vest, a helmet, a mask and a torch on the weapon. It reads as a
## silhouette in the dark until the torch swings onto you, which is the intended
## effect.
##
## The kit is real now. It used to be a plain black box for a body and a green
## strip for a visor — the silhouette was right and everything inside it was
## nothing — and the pack's police gear sheet has the vest, the armour, the
## helmet, the mask and the shield. Which of them a given officer is wearing
## comes off their place in the squad rather than off a die, so a team looks like
## a team that was issued kit rather than like five people who dressed at random.
func _apply_kit() -> void:
	var black := ProcMesh.mat(ProcTex.metal(Color(0.055, 0.058, 0.065), 909))
	for child in _body.get_children():
		if child is MeshInstance3D and child.name in ["Torso", "Waist"]:
			(child as MeshInstance3D).material_override = black
		for grandchild in child.get_children():
			if grandchild is MeshInstance3D and grandchild.name in ["Leg", "Arm", "Shoe", "Hand"]:
				(grandchild as MeshInstance3D).material_override = black

	# The vest goes on as a panel over the chest rather than as the torso's own
	# texture: the torso is a box and would wear the photograph on all six faces,
	# including the back and the top of the shoulders.
	var torso := _body.get_node_or_null("Torso") as MeshInstance3D
	if torso != null:
		var kit := _painted("police_vest" if squad_index % 2 == 0 else "body_armor")
		if kit != null:
			var vest := ProcMesh.box(Vector3(0.46, 0.56, 0.04),
				torso.position + Vector3(0, 0.02, -0.14), kit, "Vest")
			_body.add_child(vest)

	var head := _body.get_node_or_null("Head")
	if head != null:
		for child in head.get_children():
			if child is MeshInstance3D:
				(child as MeshInstance3D).material_override = black
		var helmet := _painted("police_helmet")
		if helmet != null:
			head.add_child(ProcMesh.box(Vector3(0.24, 0.20, 0.24),
				Vector3(0, 0.20, 0), helmet, "Helmet"))
		# The mask replaces the green visor strip, and keeps a little of its
		# glow. The strip existed so there is something to catch your eye in a
		# dark room, and a photograph of a gas mask is very dark indeed.
		var mask := ProcTex.painted("gas_mask")
		head.add_child(ProcMesh.box(Vector3(0.20, 0.18, 0.03), Vector3(0, 0.11, 0.11),
			ProcMesh.mat(mask, 1.0, Color(0.2, 0.9, 0.4), 0.22) if mask != null
				else ProcMesh.mat(ProcTex.flat(Color(0.25, 0.55, 0.35)), 1.0,
					Color(0.2, 0.9, 0.4), 0.9), "Visor"))

	# A radio on the shoulder, which is what the crackle you can hear is coming
	# out of.
	var radio := _painted("police_radio")
	if radio != null:
		_body.add_child(ProcMesh.box(Vector3(0.07, 0.16, 0.05),
			Vector3(0.20, 1.34, -0.06), radio, "ShoulderRadio"))

	# Whoever goes through the door first carries the shield.
	if squad_index == 0:
		var shield := _painted("riot_shield")
		if shield != null:
			_body.add_child(ProcMesh.box(Vector3(0.52, 0.78, 0.05),
				Vector3(-0.10, 1.05, -0.34), shield, "Shield"))

	var torch := SpotLight3D.new()
	torch.position = Vector3(0.16, 1.30, -0.28)
	torch.light_color = Color(0.92, 0.96, 1.0)
	torch.light_energy = 4.5
	torch.spot_range = 14.0
	torch.spot_angle = 26.0
	add_child(torch)


## A material for a painted piece of kit, or null if the pack has not got one.
## Kit is optional on purpose: without the pack this is the same black
## silhouette it has always been, rather than a missing texture.
static func _painted(name: String) -> Material:
	var tex := ProcTex.painted(name)
	return ProcMesh.mat(tex, 1.0) if tex != null else null


func _physics_process(delta: float) -> void:
	if state == State.DEAD or _player == null or _player.dead:
		return

	match state:
		State.ADVANCING:
			_move_to(_target, ADVANCE_SPEED, delta)
			if global_position.distance_to(_target) < 0.6:
				state = State.ENGAGING
		State.ENGAGING:
			_idle(delta)
			if _sees_player():
				_face_player()
				_try_fire(delta)
			else:
				# Lost them. Push to where they were last seen.
				_acquire = 0.0
				state = State.SEARCHING
		State.BREACHING:
			_move_to(_target, BREACH_SPEED, delta)
			if _sees_player():
				_try_fire(delta)
			if global_position.distance_to(_target) < 0.7:
				if _has_flank:
					# Round the end of the counter, now go for them.
					_has_flank = false
					_target = _aim_point()
				else:
					state = State.ENGAGING
		State.SEARCHING:
			if _sees_player():
				_hold = 0.0
				state = State.ENGAGING
			else:
				_hold += delta
				# A cover man holds his angle rather than going looking — leaving
				# it is how a doorway becomes free. But he does not hold it
				# forever. Nobody stands in a four-metre room for half a minute
				# watching a door while the man they came for is behind the
				# counter, and from the other side of that counter it reads as
				# the police having switched off.
				if role == Role.COVER and _hold < COVER_PATIENCE:
					_idle(delta)
					_face_dir(_watch_direction())
					return
				var goal := _search_goal()
				_move_to(goal, BREACH_SPEED, delta)
				if global_position.distance_to(goal) < 0.8:
					# Nothing here. Pick somewhere else rather than standing on
					# the spot: an empty search goal used to mean idle forever,
					# which is the whole of "they just stand there doing
					# nothing". The room is small, so a few of these and they
					# will have swept all of it.
					_last_known = _sweep_point()

	_muzzle.light_energy = maxf(0.0, _muzzle.light_energy - delta * 30.0)


## Called by the director once the shutter fails. Kept for the plain case and
## for tests; a raid proper goes through assign_point / assign_cover.
func breach(entry: Vector3) -> void:
	if state == State.DEAD:
		return
	_target = entry
	state = State.BREACHING


## First through: comes in and closes, round the side of the counter island.
func assign_point(entry: Vector3, squad: Node = null) -> void:
	if state == State.DEAD:
		return
	_squad = squad
	role = Role.POINT
	entry_used = entry
	accuracy = maxf(0.10, accuracy - POINT_ACCURACY_PENALTY)
	_plan_flank(entry)
	_target = _flank if _has_flank else entry
	state = State.BREACHING


## Second through: stops inside the door and watches the room.
func assign_cover(entry: Vector3, squad: Node = null) -> void:
	if state == State.DEAD:
		return
	_squad = squad
	role = Role.COVER
	entry_used = entry
	accuracy = minf(0.95, accuracy + COVER_ACCURACY_BONUS)
	_has_flank = false
	# A pace or two inside, not in the doorway itself — a man standing in the
	# gap is a silhouette and blocks his own team.
	_target = entry + Vector3(0.0, 0.0, 0.9)
	state = State.BREACHING


## His point man is down. Stop watching the door and go in.
func promote_to_point() -> void:
	if state == State.DEAD or role == Role.POINT:
		return
	role = Role.POINT
	accuracy = maxf(0.10, accuracy - COVER_ACCURACY_BONUS - POINT_ACCURACY_PENALTY)
	_plan_flank(global_position)
	_target = _flank if _has_flank else _aim_point()
	state = State.BREACHING


## Picks the end of the counter furthest from the player and routes through it.
##
## The shop is one room with a counter island across the middle, so "flanking"
## here is not clever pathing — it is going round the correct end. Straight down
## the middle is the shot you were waiting for, and them never taking it is what
## makes the room's geometry worth using.
func _plan_flank(entry: Vector3) -> void:
	_has_flank = false
	if _player == null:
		return
	var left := Vector3(World.CHECKOUT_MIN_X - 0.9, 0.0, World.CHECKOUT_Z - 0.2)
	var right := Vector3(World.CHECKOUT_MAX_X + 0.9, 0.0, World.CHECKOUT_Z - 0.2)
	# Round the end the player is *not* nearest to.
	var pick := left if _player.global_position.x > 0.0 else right
	# Unless that end is a long way past the door they came in by, in which case
	# taking it would mean crossing the whole room in the open first.
	if absf(pick.x - entry.x) > 7.0:
		pick = right if pick == left else left
	_flank = pick
	_has_flank = true


## Where a point man ends up: close, but not inside the player.
func _aim_point() -> Vector3:
	if _player == null:
		return global_position
	var to_me := (global_position - _player.global_position)
	to_me.y = 0.0
	if to_me.length() < 0.1:
		to_me = Vector3(0, 0, 1)
	return _player.global_position + to_me.normalized() * 1.9


## True when there is a clear line from their eyeline to the player's chest.
## Crouching behind the counter breaks it, which is the room's one real defence.
func _sees_player() -> bool:
	if _player == null or _player.dead:
		return false
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3(0, 1.35, 0)
	var to := _player.global_position + Vector3(0, 1.2, 0)
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 1
	q.exclude = [get_rid()]
	if not space.intersect_ray(q).is_empty():
		_has_contact = false
		return false
	_last_known = _player.global_position
	_has_contact = true
	# Call it in. Everyone else now knows where you are, whether or not they can
	# see you themselves.
	if _squad != null and is_instance_valid(_squad) and _squad.has_method("report_contact"):
		_squad.report_contact(_last_known)
	return true


## Where to look when you have lost them: what the squad last called in, if it
## is still fresh, otherwise the last place this unit saw them itself.
##
## Fresher intel wins. A team where everybody converges on the newest sighting
## is a team you have to keep moving to escape, rather than one you can shake by
## stepping behind the counter once.
## Somewhere else in the room worth looking. Deliberately loose — it is a sweep,
## not a homing missile, and the error is what gives you room to move.
func _sweep_point() -> Vector3:
	if _player == null or not is_instance_valid(_player):
		return _last_known
	var spread := 2.2
	return _player.global_position + Vector3(
		randf_range(-spread, spread), 0.0, randf_range(-spread, spread))


func _search_goal() -> Vector3:
	if _squad != null and is_instance_valid(_squad) and _squad.has_method("shared_intel"):
		var intel: Dictionary = _squad.shared_intel()
		if not intel.is_empty():
			return intel["at"]
	return _last_known


## A cover man faces the middle of the room, or the last called-in position if
## there is one.
func _watch_direction() -> Vector3:
	var goal := _search_goal()
	var dir := goal - global_position
	dir.y = 0.0
	if dir.length() < 0.2:
		dir = Vector3(0, 0, 1)
	return dir.normalized()


func _try_fire(delta: float) -> void:
	# A beat between acquiring you and pulling the trigger.
	_acquire += delta
	if _acquire < 0.38:
		return
	_fire_timer -= delta
	if _fire_timer > 0.0:
		return
	_fire_timer = fire_interval * randf_range(0.85, 1.30)

	Audio.play_at("gunshot", global_position + Vector3(0, 1.35, 0), -10.0, randf_range(0.95, 1.08))
	_muzzle.light_energy = 2.6
	if randf() < accuracy:
		_player.take_damage(damage)


func take_damage(amount: float, _source: Object = null) -> void:
	if state == State.DEAD:
		return
	health -= amount
	if health <= 0.0:
		_die()
	else:
		# Getting hit throws their aim off for a moment.
		_fire_timer = maxf(_fire_timer, 0.5)
		_acquire = minf(_acquire, 0.15)


func _die() -> void:
	state = State.DEAD
	collision_layer = 0
	Audio.play_at("impact", global_position + Vector3(0, 1.0, 0), -10.0)
	var tw := create_tween()
	tw.tween_property(_body, "rotation:x", deg_to_rad(-88.0), 0.4).set_trans(Tween.TRANS_BOUNCE)
	tw.parallel().tween_property(_body, "position:y", 0.10, 0.4)
	died.emit(self)


# --- Motion ------------------------------------------------------------------

func _move_to(target: Vector3, speed: float, delta: float) -> void:
	var dir := Vector3(target.x - global_position.x, 0, target.z - global_position.z)
	if dir.length() > 0.1:
		dir = dir.normalized()
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
		_face_dir(dir)
	else:
		velocity.x = 0.0
		velocity.z = 0.0
	if not is_on_floor():
		velocity.y -= 18.0 * delta
	else:
		velocity.y = 0.0
	move_and_slide()

	_walk_phase += delta * speed * 3.6
	var swing := sin(_walk_phase) * 0.5
	for i in _hips.size():
		_hips[i].rotation.x = swing * (1.0 if i == 0 else -1.0)


func _idle(delta: float) -> void:
	for i in _hips.size():
		_hips[i].rotation.x = lerpf(_hips[i].rotation.x, 0.0, delta * 6.0)
	# Weapon up, both arms forward.
	for s in _shoulders:
		s.rotation.x = lerpf(s.rotation.x, -1.35, delta * 6.0)


func _face_player() -> void:
	if _player == null:
		return
	_face_dir(_player.global_position - global_position)


func _face_dir(dir: Vector3) -> void:
	var flat := Vector3(dir.x, 0, dir.z)
	if flat.length_squared() < 0.001:
		return
	rotation.y = lerp_angle(rotation.y, atan2(flat.x, flat.z), 0.18)
