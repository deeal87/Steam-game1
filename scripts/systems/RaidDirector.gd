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

## Shared contact. Whoever sees you tells everybody, which is the single thing
## that most makes them read as a team rather than as eight people who happen to
## be in the same room: breaking line of sight with the one in front of you no
## longer means the one behind him has lost you too.
var squad_last_known: Vector3 = Vector3.ZERO
var squad_contact_age: float = 999.0
## How long a called-out position stays worth walking to.
const INTEL_LIFETIME := 6.0


## Called by any unit with eyes on the player.
func report_contact(at: Vector3) -> void:
	squad_last_known = at
	squad_contact_age = 0.0


## The squad's best guess, or nothing if it has gone stale. Stale intel matters:
## a team that walks forever towards a five-minute-old sighting is a team you can
## lead round in circles, and one that never forgets is one you can never escape.
func shared_intel() -> Dictionary:
	if squad_contact_age > INTEL_LIFETIME:
		return {}
	return {"at": squad_last_known, "age": squad_contact_age}


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
	squad_contact_age = 999.0
	squad_last_known = Vector3.ZERO

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
	var door_barred := GameState.defenses.has("door_bar")
	if not hatch_barred:
		_entries.append(Vector3(World.HATCH_X, 0.0, -World.SHOP_HALF_Z + 1.0))
	if not door_barred:
		_entries.append(Vector3(World.FRONT_DOOR_X, 0.0, -World.SHOP_HALF_Z + 1.0))
	if _entries.is_empty():
		_shutter_hp += 10.0
		_entries.append(Vector3(World.HATCH_X, 0.0, -World.SHOP_HALF_Z + 1.0))

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
	Signals.notice.emit(Loc.f("%d of them. Shutter's down.", [squad]), "bad")

	if GameState.defenses.has("camera"):
		Signals.notice.emit(Loc.t("Camera: they're stacking on the left side of the door."), "watch")


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

	# Intel goes stale on its own. Nobody has to remember to forget.
	squad_contact_age += delta

	match phase:
		Phase.FORMING:
			_timer -= delta
			if _timer <= 0.0:
				phase = Phase.PRESSING
				Signals.notice.emit(Loc.t("They're on the shutter."), "bad")
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
	Signals.notice.emit(Loc.t("Shutter's gone. Something lands on the floor."), "bad")
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


## A wave is a pair, and the pair has a job each.
##
## The first through is the **point**: he closes on you, going wide round the
## counter island rather than straight up the middle. The second is his **cover**:
## he stops just inside the doorway with a line across the room and shoots the
## moment you show yourself.
##
## That is what makes two of them worse than two of them used to be. Against a
## pair with no plan you could hold one angle and win. Against a point and a
## cover, staying still gets you flushed and moving gets you shot, and you have
## to decide which of the two to spend your shells on.
##
## When there are two ways in they take one each, so you cannot face both.
func _send_wave() -> void:
	var sending: Array[RaidUnit] = []
	while sending.size() < WAVE_SIZE and not _queue.is_empty():
		var u: RaidUnit = _queue.pop_front()
		if is_instance_valid(u) and u.state != RaidUnit.State.DEAD:
			sending.append(u)

	for i in sending.size():
		var u := sending[i]
		# Split the pair across the available doors. With one door open they
		# come through the same hole, which is exactly why closing one is worth
		# paying for.
		var entry: Vector3 = _entries[i % _entries.size()]
		entry += Vector3(randf_range(-0.6, 0.6), 0.0, randf_range(-0.2, 0.2))
		if i == 0:
			u.assign_point(entry, self)
		else:
			u.assign_cover(entry, self)

		if _trap_armed:
			_trap_armed = false
			GameState.defenses.erase("floor_trap")
			u.take_damage(500.0)
			Audio.play("impact", -8.0)
			Signals.notice.emit(Loc.t("The trap takes the first one through."), "good")

	_wave_timer = WAVE_GAP
	if sending.size() > 1:
		Signals.notice.emit(Loc.t("Two of them. One's holding the door."), "bad")
	if not sending.is_empty() and not _queue.is_empty():
		Signals.notice.emit(Loc.t("More coming."), "warn")


func _live_count() -> int:
	var n := 0
	for u in _units:
		if is_instance_valid(u) and u.state != RaidUnit.State.DEAD:
			n += 1
	return n


func _on_unit_died(_unit: RaidUnit) -> void:
	var left := _live_count()
	if left > 0:
		Signals.notice.emit(Loc.f("%d left.", [left]), "warn")
	_promote_cover()


## If the point man goes down, whoever was covering him stops covering and comes
## on himself.
##
## Without this, shooting the point is the whole fight: his cover would sit in
## the doorway watching an empty room forever, and the correct play would be to
## kill one man per wave and then walk away.
func _promote_cover() -> void:
	var has_point := false
	for u in _units:
		if is_instance_valid(u) and u.state != RaidUnit.State.DEAD and u.role == RaidUnit.Role.POINT:
			has_point = true
			break
	if has_point:
		return
	for u in _units:
		if is_instance_valid(u) and u.state != RaidUnit.State.DEAD and u.role == RaidUnit.Role.COVER:
			u.promote_to_point()
			Signals.notice.emit(Loc.t("The one on the door is moving up."), "bad")
			return


func _finish(survived: bool) -> void:
	if phase == Phase.DONE:
		return
	phase = Phase.DONE
	Audio.stop_ambience()
	if survived:
		GameState.evidence_against_you = 0
		GameState.raid_reason = ""
		GameState.add_heat(-18.0)
		Signals.notice.emit(Loc.t("It's quiet. You are still standing."), "good")
	Signals.raid_resolved.emit(survived)
	raid_over.emit(survived)
