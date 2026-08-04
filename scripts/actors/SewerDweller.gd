class_name SewerDweller
extends CharacterBody3D
## Something living in the tunnels.
##
## Not police, not a customer. It has been down here a long time and it does not
## like the light. The first one is barely a threat — a bat handles it — and
## that is deliberate: the tunnel has to be safe enough the first time that you
## are willing to use it again.
##
## They notice you sooner when the torch is on, which is the one real decision
## down here: see where you are going, or not be seen.

signal died(dweller: SewerDweller)

enum State { LURKING, HUNTING, STRIKING, DEAD }

const WANDER_SPEED := 0.7
const HUNT_SPEED := 2.1
const STRIKE_RANGE := 1.5
const NOTICE_RANGE := 9.0
const NOTICE_RANGE_TORCH := 16.0

var state: State = State.LURKING
var health: float = 40.0
var max_health: float = 40.0
var damage: float = 7.0
var strike_interval: float = 1.6
var speed_scale: float = 1.0

var _player: Player
var _spawn: Vector3
var _home: Vector3
var _strike_timer: float = 0.0
var _body: Node3D
var _hips: Array[Node3D] = []
var _shoulders: Array[Node3D] = []
var _walk_phase: float = 0.0
var _eyes: OmniLight3D
var _growl_timer: float = 0.0


## `tier` is how many times the player has been down here. Everything scales
## off it and nothing else, so the difficulty curve is one readable number.
func setup(player: Player, spawn: Vector3, tier: int) -> void:
	_player = player
	_spawn = spawn
	_home = spawn
	max_health = 34.0 + float(tier) * 13.0
	health = max_health
	damage = 5.0 + float(tier) * 2.4
	strike_interval = maxf(0.65, 1.70 - float(tier) * 0.11)
	speed_scale = minf(1.85, 0.85 + float(tier) * 0.10)


func _ready() -> void:
	name = "SewerDweller"
	collision_layer = 0
	set_collision_layer_value(3, true)
	collision_mask = 1
	global_position = _spawn

	var caps := CapsuleShape3D.new()
	caps.radius = 0.30
	caps.height = 1.45
	var cs := CollisionShape3D.new()
	cs.shape = caps
	cs.position = Vector3(0, 0.75, 0)
	add_child(cs)

	# Hunched, pale and wrong. Same builder as everyone else, bent over.
	_body = ProcMesh.human(randi(), 0.82, 0.92)
	_body.rotation.x = deg_to_rad(14.0)
	add_child(_body)
	for child in _body.get_children():
		if child.name.begins_with("Hip"):
			_hips.append(child)
		elif child.name.begins_with("Shoulder"):
			_shoulders.append(child)
	_apply_look()

	_eyes = OmniLight3D.new()
	_eyes.position = Vector3(0, 1.30, -0.18)
	_eyes.light_color = Color(0.55, 1.0, 0.62)
	_eyes.light_energy = 0.55
	_eyes.omni_range = 2.4
	add_child(_eyes)


func _apply_look() -> void:
	var pale := ProcMesh.mat(ProcTex.grime(Color(0.44, 0.47, 0.40), 0.5, 313))
	var rag := ProcMesh.mat(ProcTex.grime(Color(0.19, 0.20, 0.17), 0.6, 317))
	for child in _body.get_children():
		if child is MeshInstance3D:
			(child as MeshInstance3D).material_override = rag
		for grandchild in child.get_children():
			if grandchild is MeshInstance3D:
				(grandchild as MeshInstance3D).material_override = \
					pale if grandchild.name in ["Hand", "Neck"] else rag
	var head := _body.get_node_or_null("Head")
	if head != null:
		for child in head.get_children():
			if child is MeshInstance3D:
				(child as MeshInstance3D).material_override = pale


func _physics_process(delta: float) -> void:
	if state == State.DEAD or _player == null or _player.dead:
		return

	var to_player := _player.global_position - global_position
	var distance := to_player.length()
	var notice := NOTICE_RANGE_TORCH if _player.torch_on else NOTICE_RANGE

	match state:
		State.LURKING:
			_wander(delta)
			if distance < notice:
				state = State.HUNTING
				Audio.play("beep_low", -26.0, 0.35)
		State.HUNTING:
			_move_toward_player(delta)
			if distance <= STRIKE_RANGE:
				state = State.STRIKING
				_strike_timer = 0.35
			elif distance > notice * 1.7:
				state = State.LURKING
		State.STRIKING:
			_face_toward(to_player)
			_strike(delta, distance)

	_growl_timer -= delta
	if _growl_timer <= 0.0 and state != State.LURKING:
		_growl_timer = randf_range(2.5, 6.0)
		Audio.play("swing", -30.0, randf_range(0.35, 0.55))


func _wander(delta: float) -> void:
	# Shuffles a little around where it started. Mostly it just stands there.
	var drift := sin(float(Time.get_ticks_msec()) * 0.0004 + float(get_instance_id() % 100)) * 2.2
	var target := _home + Vector3(drift, 0, 0)
	_step(target, WANDER_SPEED * speed_scale, delta)


func _move_toward_player(delta: float) -> void:
	_step(_player.global_position, HUNT_SPEED * speed_scale, delta)


func _strike(delta: float, distance: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	if not is_on_floor():
		velocity.y -= 18.0 * delta
	move_and_slide()

	if distance > STRIKE_RANGE * 1.4:
		state = State.HUNTING
		return

	_strike_timer -= delta
	if _strike_timer > 0.0:
		return
	_strike_timer = strike_interval

	# Both arms come forward, then it hits you.
	for s in _shoulders:
		s.rotation.x = -1.6
	Audio.play("swing", -12.0, 0.7)
	Audio.play("impact", -14.0)
	_player.take_damage(damage)


func take_damage(amount: float, _source: Object = null) -> void:
	if state == State.DEAD:
		return
	health -= amount
	if health <= 0.0:
		_die()
		return
	# Being hit makes it commit rather than back off.
	if state == State.LURKING:
		state = State.HUNTING
	_strike_timer = maxf(_strike_timer, 0.35)


func _die() -> void:
	state = State.DEAD
	collision_layer = 0
	Audio.play("impact", -12.0, 0.8)
	if _eyes != null:
		_eyes.light_energy = 0.0
	var tw := create_tween()
	tw.tween_property(_body, "rotation:x", deg_to_rad(-86.0), 0.4).set_trans(Tween.TRANS_BOUNCE)
	tw.parallel().tween_property(_body, "position:y", 0.08, 0.4)
	died.emit(self)


# --- Motion ------------------------------------------------------------------

func _step(target: Vector3, speed: float, delta: float) -> void:
	var dir := Vector3(target.x - global_position.x, 0, target.z - global_position.z)
	if dir.length() > 0.15:
		dir = dir.normalized()
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
		_face_toward(dir)
	else:
		velocity.x = move_toward(velocity.x, 0.0, delta * 8.0)
		velocity.z = move_toward(velocity.z, 0.0, delta * 8.0)
	if not is_on_floor():
		velocity.y -= 18.0 * delta
	else:
		velocity.y = 0.0
	move_and_slide()

	_walk_phase += delta * speed * 4.0
	var swing := sin(_walk_phase) * 0.6
	for i in _hips.size():
		_hips[i].rotation.x = swing * (1.0 if i == 0 else -1.0)
	for i in _shoulders.size():
		_shoulders[i].rotation.x = lerpf(_shoulders[i].rotation.x, -0.7 + swing * 0.3, delta * 5.0)


func _face_toward(dir: Vector3) -> void:
	var flat := Vector3(dir.x, 0, dir.z)
	if flat.length_squared() < 0.001:
		return
	rotation.y = lerp_angle(rotation.y, atan2(flat.x, flat.z), 0.14)
