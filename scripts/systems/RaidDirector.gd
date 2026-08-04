class_name RaidDirector
extends Node
## The door team.
##
## This is what the rest of the game is a countdown to. An officer who walks
## away from the window sends people back between shifts, and how many of them
## there are depends on what they left with.

signal raid_over(survived: bool)

enum Phase { IDLE, FORMING, PRESSING, FLASH, BREACHED, DONE }

const FORM_TIME := 5.5
## The beat between the shutter failing and the first man through. Without it
## the breach is a jump-scare rather than a fight you get to prepare for.
const FLASH_TIME := 1.5
## They come through in pairs, not as one crowd. Eight people arriving at once
## in a room four metres wide is not a firefight, it is a cutscene where you
## lose — this is what makes the room's geometry worth using.
const WAVE_SIZE := 2
const WAVE_GAP := 3.4

var phase: Phase = Phase.IDLE
var _world: World
var _player: Player
var _units: Array[RaidUnit] = []
var _timer: float = 0.0
var _shutter_hp: float = 0.0
var _trap_armed: bool = false
var _entries: Array[Vector3] = []
var _queue: Array[RaidUnit] = []
var _wave_timer: float = 0.0


func setup(world: World, player: Player) -> void:
	_world = world
	_player = player


## `evidence` is 1 for an officer who left empty-handed, 2 for one who left
## with a buy, plus 1 for every civilian shot.
func start(evidence: int, night: int) -> void:
	if phase != Phase.IDLE:
		return
	phase = Phase.FORMING
	_timer = FORM_TIME
	_units.clear()
	_queue.clear()
	_wave_timer = 0.0

	_world.set_shutter_closed(true)
	_world.anchors["shutter_is_closed"] = true

	# The shutter is the only thing between you and them. A barricade roughly
	# doubles how long it lasts.
	_shutter_hp = 9.0
	if GameState.defenses.has("door_bar"):
		_shutter_hp += 8.0
	if GameState.defenses.has("window_bars"):
		_shutter_hp += 5.0
	_trap_armed = GameState.defenses.has("floor_trap")

	# The shop has two ways in from the street: the serving hatch and the side
	# door onto the pavement. Each fitting closes one of them, and closing one
	# forces the whole team through the other — which is a far easier thing to
	# point a shotgun at than two open approaches.
	#
	# Barring both does not make you safe. It makes them spend longer on the
	# shutter and then come through the hatch anyway.
	_entries = []
	var hatch_barred := GameState.defenses.has("window_bars")
	var side_barred := GameState.defenses.has("door_bar")
	if not hatch_barred:
		_entries.append(Vector3(0.0, 0.0, -World.SHOP_HALF_Z + 0.9))
	if not side_barred:
		_entries.append(Vector3(World.SHOP_HALF_X - 0.9, 0.0, World.SIDE_DOOR_Z))
	if _entries.is_empty():
		_shutter_hp += 10.0
		_entries.append(Vector3(0.0, 0.0, -World.SHOP_HALF_Z + 0.9))

	var squad := clampi(GameState.raid_squad_size() + evidence - 1, 3, 14)
	var tier := night + int(GameState.heat / 30.0)
	var points := _world.breach_points()

	for i in squad:
		var spawn: Vector3 = points[i % points.size()] + Vector3(
			randf_range(-2.2, 2.2), 0.0, randf_range(-1.5, 3.5))
		var hold: Vector3 = points[i % points.size()] + Vector3(
			randf_range(-1.6, 1.6), 0.0, randf_range(-0.4, 1.2))
		var u := RaidUnit.new()
		u.setup(_player, spawn, hold, tier)
		u.died.connect(_on_unit_died)
		_world.add_child(u)
		_units.append(u)

	Audio.play("radio", -12.0)
	Audio.play("breach", -14.0)
	Signals.raid_incoming.emit(GameState.raid_reason)
	Signals.notice.emit("%d of them. Shutter's down." % squad, "bad")

	if GameState.defenses.has("camera"):
		Signals.notice.emit("Camera: they're stacking on the left side of the door.", "watch")


func stop() -> void:
	for u in _units:
		if is_instance_valid(u):
			u.queue_free()
	_units.clear()
	_queue.clear()
	phase = Phase.IDLE


func _process(delta: float) -> void:
	if phase == Phase.IDLE or phase == Phase.DONE:
		return
	if _player == null or _player.dead:
		return

	match phase:
		Phase.FORMING:
			_timer -= delta
			if _timer <= 0.0:
				phase = Phase.PRESSING
				Signals.notice.emit("They're on the shutter.", "bad")
		Phase.PRESSING:
			_shutter_hp -= delta * _live_count()
			if int(_shutter_hp) % 2 == 0:
				Audio.play("impact", -22.0)
			if _shutter_hp <= 0.0:
				_open_up()
		Phase.FLASH:
			_timer -= delta
			if _timer <= 0.0:
				_breach()
		Phase.BREACHED:
			_wave_timer -= delta
			if _wave_timer <= 0.0 and not _queue.is_empty():
				_send_wave()

	if _live_count() <= 0 and _queue.is_empty() and phase != Phase.DONE:
		_finish(true)


## The shutter fails. They throw something in before they follow it.
func _open_up() -> void:
	phase = Phase.FLASH
	_timer = FLASH_TIME
	Audio.play("breach", -6.0)
	_world.set_shutter_closed(false)
	_world.anchors["shutter_is_closed"] = false
	Signals.notice.emit("Shutter's gone. Something lands on the floor.", "bad")
	Signals.flashbang.emit()

	_queue.clear()
	for u in _units:
		if is_instance_valid(u) and u.state != RaidUnit.State.DEAD:
			_queue.append(u)
	_queue.shuffle()


func _breach() -> void:
	phase = Phase.BREACHED
	Audio.play("breach", -10.0)
	_send_wave()


func _send_wave() -> void:
	var sent := 0
	while sent < WAVE_SIZE and not _queue.is_empty():
		var u: RaidUnit = _queue.pop_front()
		if not is_instance_valid(u) or u.state == RaidUnit.State.DEAD:
			continue
		var entry: Vector3 = _entries[randi() % _entries.size()]
		entry += Vector3(randf_range(-0.6, 0.6), 0.0, randf_range(-0.2, 0.2))
		u.breach(entry)
		sent += 1

		if _trap_armed:
			_trap_armed = false
			GameState.defenses.erase("floor_trap")
			u.take_damage(500.0)
			Audio.play("impact", -8.0)
			Signals.notice.emit("The trap takes the first one through.", "good")

	_wave_timer = WAVE_GAP
	if sent > 0 and not _queue.is_empty():
		Signals.notice.emit("More coming.", "warn")


func _live_count() -> int:
	var n := 0
	for u in _units:
		if is_instance_valid(u) and u.state != RaidUnit.State.DEAD:
			n += 1
	return n


func _on_unit_died(_unit: RaidUnit) -> void:
	var left := _live_count()
	if left > 0:
		Signals.notice.emit("%d left." % left, "warn")


func _finish(survived: bool) -> void:
	if phase == Phase.DONE:
		return
	phase = Phase.DONE
	Audio.stop_ambience()
	if survived:
		GameState.evidence_against_you = 0
		GameState.raid_reason = ""
		GameState.add_heat(-18.0)
		Signals.notice.emit("It's quiet. You are still standing.", "good")
	Signals.raid_resolved.emit(survived)
	raid_over.emit(survived)
