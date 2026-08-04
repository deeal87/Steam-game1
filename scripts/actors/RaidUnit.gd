class_name RaidUnit
extends CharacterBody3D
## One member of the door team.
##
## They are not clever. They advance to a firing position, they shoot at where
## you are, and they keep doing it. What makes them dangerous is that there are
## several of them and the room is four metres wide.

signal died(unit: RaidUnit)

enum State { ADVANCING, ENGAGING, BREACHING, DEAD }

const ADVANCE_SPEED := 2.4
const BREACH_SPEED := 1.9

var state: State = State.ADVANCING
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
var _spawn: Vector3
var _muzzle: OmniLight3D


## Called before the unit is in the tree, so the spawn point is stored and
## applied in `_ready` rather than written to `global_position` here.
func setup(player: Player, spawn: Vector3, target: Vector3, tier: int) -> void:
	_player = player
	_target = target
	_spawn = spawn
	# Later nights send better-equipped teams.
	health = 90.0 + float(tier) * 16.0
	damage = 8.0 + float(tier) * 1.6
	fire_interval = maxf(0.55, 1.20 - float(tier) * 0.07)
	accuracy = minf(0.90, 0.58 + float(tier) * 0.035)


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


## Black kit, a helmet, and a torch on the weapon. It reads as a silhouette in
## the dark until the torch swings onto you, which is the intended effect.
func _apply_kit() -> void:
	var black := ProcMesh.mat(ProcTex.metal(Color(0.055, 0.058, 0.065), 909))
	for child in _body.get_children():
		if child is MeshInstance3D and child.name in ["Torso", "Waist"]:
			(child as MeshInstance3D).material_override = black
		for grandchild in child.get_children():
			if grandchild is MeshInstance3D and grandchild.name in ["Leg", "Arm", "Shoe", "Hand"]:
				(grandchild as MeshInstance3D).material_override = black

	var head := _body.get_node_or_null("Head")
	if head != null:
		for child in head.get_children():
			if child is MeshInstance3D:
				(child as MeshInstance3D).material_override = black
		head.add_child(ProcMesh.box(Vector3(0.22, 0.06, 0.02), Vector3(0, 0.13, 0.11),
			ProcMesh.mat(ProcTex.flat(Color(0.25, 0.55, 0.35)), 1.0, Color(0.2, 0.9, 0.4), 0.9), "Visor"))

	var torch := SpotLight3D.new()
	torch.position = Vector3(0.16, 1.30, -0.28)
	torch.light_color = Color(0.92, 0.96, 1.0)
	torch.light_energy = 4.5
	torch.spot_range = 14.0
	torch.spot_angle = 26.0
	add_child(torch)


func _physics_process(delta: float) -> void:
	if state == State.DEAD or _player == null or _player.dead:
		return

	match state:
		State.ADVANCING:
			_move_to(_target, ADVANCE_SPEED, delta)
			if global_position.distance_to(_target) < 0.6:
				state = State.ENGAGING
		State.ENGAGING:
			_face_player()
			_idle(delta)
			_try_fire(delta)
		State.BREACHING:
			_move_to(_target, BREACH_SPEED, delta)
			_try_fire(delta)
			if global_position.distance_to(_target) < 0.7:
				state = State.ENGAGING

	_muzzle.light_energy = maxf(0.0, _muzzle.light_energy - delta * 30.0)


## Called by the director once the shutter fails.
func breach(entry: Vector3) -> void:
	if state == State.DEAD:
		return
	_target = entry
	state = State.BREACHING


func _try_fire(delta: float) -> void:
	_fire_timer -= delta
	if _fire_timer > 0.0:
		return
	_fire_timer = fire_interval * randf_range(0.85, 1.30)

	# They only shoot when they can actually see you, so crouching behind the
	# counter genuinely works.
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3(0, 1.35, 0)
	var to := _player.global_position + Vector3(0, 1.2, 0)
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 1
	q.exclude = [get_rid()]
	var blocked := space.intersect_ray(q)
	if not blocked.is_empty():
		return

	Audio.play("gunshot", -10.0, randf_range(0.95, 1.08))
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


func _die() -> void:
	state = State.DEAD
	collision_layer = 0
	Audio.play("impact", -10.0)
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
