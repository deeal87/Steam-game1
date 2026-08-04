class_name NightDirector
extends Node
## Runs a single shift: the clock, the queue at the window, and the tally at
## the end of it.
##
## Only one person is ever at the hatch. That is a design choice rather than a
## limitation — it means every customer gets your full attention and every
## mistake is unambiguously yours.

signal shift_finished(summary: Dictionary)
signal customer_ready(customer: Customer)

const SHIFT_MINUTES := 360.0          ## 23:00 to 05:00.
const GAP_MIN := 2.4
const GAP_MAX := 5.5

var running: bool = false
var minutes_left: float = SHIFT_MINUTES
var _minutes_per_second: float = 1.0
var _queue_remaining: int = 0
var _current: Customer = null
var _gap: float = 2.0
var _rng := RandomNumberGenerator.new()
var _world: World
var _seed_counter: int = 0


func setup(world: World) -> void:
	_world = world


func start_night() -> void:
	GameState.reset_night_tally()
	_rng.seed = hash("night-%d-%d" % [GameState.night, Time.get_unix_time_from_system()])
	_seed_counter = _rng.randi()
	_queue_remaining = GameState.customer_count()
	minutes_left = SHIFT_MINUTES

	# Pace the clock so the shift runs out at roughly the moment the queue
	# does, with enough slack that a careful player is never cut off mid-sale.
	var expected_seconds := 24.0 + float(_queue_remaining) * 26.0
	_minutes_per_second = SHIFT_MINUTES / expected_seconds

	_gap = 2.0
	_current = null
	running = true

	if _world != null:
		_world.scatter_cash(_rng)
		_world.refresh_shelves()

	Audio.start_ambience()
	Signals.night_started.emit(GameState.night)
	Signals.quota_changed.emit(0, GameState.rent_due())
	Signals.notice.emit("Night %d. Rent is %d by five." % [GameState.night, GameState.rent_due()], "info")


func stop() -> void:
	running = false
	if _current != null and is_instance_valid(_current):
		_current.queue_free()
	_current = null


func _process(delta: float) -> void:
	if not running:
		return

	minutes_left = maxf(0.0, minutes_left - _minutes_per_second * delta)
	Signals.shift_clock.emit(minutes_left)

	if _current == null or not is_instance_valid(_current):
		_gap -= delta
		if _gap <= 0.0:
			if _queue_remaining > 0 and minutes_left > 12.0:
				_spawn_next()
			elif _queue_remaining <= 0:
				_finish()
	elif minutes_left <= 0.0 and _current.state != Customer.State.AT_COUNTER:
		_finish()


func _spawn_next() -> void:
	_queue_remaining -= 1
	_seed_counter += 7919

	var profile := ProfileGenerator.generate(_seed_counter, GameState.night, GameState.undercover_ratio())
	var c := Customer.new()
	c.setup(profile, _world)
	c.finished.connect(_on_customer_finished)
	_world.add_child(c)
	_current = c
	customer_ready.emit(c)


func _on_customer_finished(customer: Customer, outcome: String) -> void:
	Signals.customer_departed.emit(customer, outcome)
	if is_instance_valid(customer):
		customer.queue_free()
	if customer == _current:
		_current = null
	_gap = _rng.randf_range(GAP_MIN, GAP_MAX)


func _finish() -> void:
	if not running:
		return
	running = false
	Audio.stop_ambience()

	var earned := GameState.takings + GameState.illicit_takings + GameState.tips
	var rent := GameState.rent_due()
	var paid := GameState.spend(rent)
	if not paid:
		# Falling short does not end the run on its own. It puts you in debt to
		# someone who will be back, which is what the heat is for.
		GameState.money = 0
		GameState.add_heat(14.0)
		Signals.money_changed.emit(GameState.money)

	var summary := {
		"night": GameState.night,
		"served": GameState.customers_served,
		"takings": GameState.takings,
		"illicit": GameState.illicit_takings,
		"tips": GameState.tips,
		"rent": rent,
		"earned": earned,
		"rent_paid": paid,
		"cops": GameState.cops_identified,
		"civilians": GameState.civilians_killed,
		"evidence": GameState.evidence_against_you,
		"raid_reason": GameState.raid_reason,
	}
	Signals.night_ended.emit(summary)
	shift_finished.emit(summary)


func current_customer() -> Customer:
	return _current if is_instance_valid(_current) else null
