class_name SewerDirector
extends Node
## Decides what is waiting in the tunnels.
##
## The rule the whole thing hangs on: **the first trip is nearly free, and every
## trip after it is worse.** One slow thing you can put down with a bat, then
## two, then two that are faster, and so on. Nothing down there resets.
##
## That is what makes the sewer a real decision rather than a free shortcut. It
## is the quiet way to the far end and it is the way out when the door goes —
## but every time you use it you are raising the price of using it again.

signal cleared

const SPAWN_MARGIN := 6.0
const MIN_SPAWN_DISTANCE := 9.0

var active: bool = false
var _world: World
var _player: Player
var _dwellers: Array[SewerDweller] = []


func setup(world: World, player: Player) -> void:
	_world = world
	_player = player


## Called when the player goes down a ladder. Counts the trip, then populates
## the tunnel for it.
func enter() -> void:
	if active:
		return
	active = true
	GameState.sewer_trips += 1
	GameState.save_run()

	var tier := GameState.sewer_tier()
	var count := GameState.sewer_dweller_count()
	_spawn(count, tier)

	if count == 0:
		Signals.notice.emit(Loc.t("Quiet down here. For now."), "info")
	elif GameState.sewer_trips == 1:
		Signals.notice.emit(Loc.t("Something is down here with you."), "warn")
	else:
		Signals.notice.emit(Loc.t("More of them than last time."), "bad")


## Called when the player climbs back out. Everything down there is forgotten;
## the next trip builds a fresh, worse set.
func leave() -> void:
	if not active:
		return
	active = false
	_despawn()


func stop() -> void:
	active = false
	_despawn()


func _despawn() -> void:
	for d in _dwellers:
		if is_instance_valid(d):
			d.queue_free()
	_dwellers.clear()


## Spread across the network, never right on top of the player.
##
## The spur gets one as soon as there is more than one to give, because the only
## reason to walk down a dead end is the crate at the end of it and the crate
## should not be free. Everything else is spaced along the main run, which is
## the stretch you have to cross whichever ladder you are heading for.
func _spawn(count: int, tier: int) -> void:
	if count <= 0 or _world == null or _player == null:
		return
	var y: float = World.SEWER_Y + 0.2
	var spots: Array[Vector3] = []

	if count > 1:
		spots.append(Vector3(World.SEWER_SPUR_X,
			y, World.SEWER_SPUR_END_Z - randf_range(2.0, 4.0)))

	var west: float = World.SEWER_EXIT.x + SPAWN_MARGIN
	var east: float = World.MANHOLE.x - SPAWN_MARGIN
	var along := count - spots.size()
	for i in along:
		var t := (float(i) + 0.5) / float(maxi(1, along))
		spots.append(Vector3(lerpf(east, west, t), y,
			World.MANHOLE.z + randf_range(-0.5, 0.5)))

	for pos in spots:
		# Never put one in the player's lap the moment they land.
		if pos.distance_to(_player.global_position) < MIN_SPAWN_DISTANCE:
			pos.x -= MIN_SPAWN_DISTANCE
		var d := SewerDweller.new()
		d.setup(_player, pos, tier)
		d.died.connect(_on_died)
		_world.add_child(d)
		# They live on the underground layer, so the tunnel lamps light them and
		# the street lamps do not. Assigned after the node is in the tree, since
		# the body only builds itself in _ready.
		World.assign_layer(d, World.LAYER_UNDERGROUND)
		_dwellers.append(d)


func _on_died(_d: SewerDweller) -> void:
	var left := alive_count()
	if left > 0:
		Signals.notice.emit(Loc.f("%d still moving.", [left]), "warn")
	else:
		Signals.notice.emit(Loc.t("Nothing else down here."), "good")
		cleared.emit()


func alive_count() -> int:
	var n := 0
	for d in _dwellers:
		if is_instance_valid(d) and d.state != SewerDweller.State.DEAD:
			n += 1
	return n


func spawned_count() -> int:
	return _dwellers.size()
