class_name NightDirector
extends Node
## Runs a single shift: the clock, the shop floor, and the tally at the end.
##
## Several people are in the shop at once now. They arrive, do their own
## shopping at their own pace, and join the back of the queue when they are
## done — which means the order they reach your counter is not the order they
## came in, and somebody is always watching you work.
##
## Only the person at the front is served. Everyone behind them can still be
## swept with the scanner and looked up on the terminal while they wait, which
## is the point of having a queue at all: it buys you time to do the reading
## before you have to make the decision.

signal shift_finished(summary: Dictionary)
signal customer_ready(customer: Customer)

const SHIFT_MINUTES := 360.0
const GAP_MIN := 3.0
const GAP_MAX := 7.5
## How many people will be in the shop at once. The queue has four marks, so
## this is one being served plus three waiting.
const MAX_IN_SHOP := 4

var running: bool = false
var minutes_left: float = SHIFT_MINUTES
var _minutes_per_second: float = 1.0
var _queue_remaining: int = 0
var _gap: float = 2.0
var _rng := RandomNumberGenerator.new()
var _world: World
var _seed_counter: int = 0

## Everyone currently in the shop, in the order they walked in.
var _present: Array[Customer] = []
## Those who have finished shopping, in the order they joined the line.
var _line: Array[Customer] = []


func setup(world: World) -> void:
	_world = world


func start_night() -> void:
	GameState.reset_night_tally()
	_rng.seed = hash("night-%d-%d" % [GameState.night, Time.get_unix_time_from_system()])
	_seed_counter = _rng.randi()
	_queue_remaining = GameState.customer_count()
	minutes_left = SHIFT_MINUTES

	var expected_seconds := 24.0 + float(_queue_remaining) * 20.0
	_minutes_per_second = SHIFT_MINUTES / expected_seconds

	_gap = 2.0
	_clear_everyone()
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
	_clear_everyone()


func _clear_everyone() -> void:
	for c in _present:
		if is_instance_valid(c):
			c.queue_free()
	_present.clear()
	_line.clear()


func _process(delta: float) -> void:
	if not running:
		return

	minutes_left = maxf(0.0, minutes_left - _minutes_per_second * delta)
	Signals.shift_clock.emit(minutes_left)

	_prune()
	_consider_pushing()
	_reassign_line()

	if _queue_remaining > 0 and minutes_left > 12.0 and _present.size() < MAX_IN_SHOP:
		_gap -= delta
		if _gap <= 0.0:
			_spawn_next()
			_gap = _rng.randf_range(GAP_MIN, GAP_MAX)
	elif _queue_remaining <= 0 and _present.is_empty():
		_finish()


## Drops anyone who has left or been freed.
func _prune() -> void:
	var kept: Array[Customer] = []
	for c in _present:
		if is_instance_valid(c):
			kept.append(c)
	_present = kept

	var kept_line: Array[Customer] = []
	for c in _line:
		# Once they start leaving they are out of the line, so the person behind
		# them steps up immediately rather than waiting for them to reach the door.
		if is_instance_valid(c) and c.state in [Customer.State.QUEUEING, Customer.State.AT_COUNTER]:
			kept_line.append(c)
	_line = kept_line


## Hands out queue positions. Whoever is at the front gets served.
func _reassign_line() -> void:
	for i in _line.size():
		var c := _line[i]
		if c.queue_index > i:
			c.note_moved_up()
		c.queue_index = i


## Lets an impatient person step in front of the one ahead of them.
##
## Two rules keep this from turning the queue into noise. It never touches the
## person at the front — they are at the counter with their shopping on it, and
## stepping in front of *that* is not queue-jumping, it is a robbery. And only
## one swap happens per frame, so a line can shuffle but it can never invert in
## a single tick.
##
## Checked from the back forwards, because the person who has been stuck
## longest is at the back and should get first refusal on the idea.
func _consider_pushing() -> void:
	for i in range(_line.size() - 1, 1, -1):
		var behind := _line[i]
		var ahead := _line[i - 1]
		if not is_instance_valid(behind) or not is_instance_valid(ahead):
			continue
		if behind.ready_to_push(ahead):
			_line[i] = ahead
			_line[i - 1] = behind
			return


func _spawn_next() -> void:
	_queue_remaining -= 1
	_seed_counter += 7919

	var profile := ProfileGenerator.generate(_seed_counter, GameState.night, GameState.undercover_ratio())
	var c := Customer.new()
	c.setup(profile, _world)
	c.finished.connect(_on_customer_finished)
	c.finished_shopping.connect(_on_finished_shopping)
	_world.add_child(c)
	_present.append(c)
	customer_ready.emit(c)


func _on_finished_shopping(customer: Customer) -> void:
	if not _line.has(customer):
		_line.append(customer)
	_reassign_line()
	if _line.size() > 1:
		Signals.notice.emit("%d waiting." % _line.size(), "info")


func _on_customer_finished(customer: Customer, outcome: String) -> void:
	Signals.customer_departed.emit(customer, outcome)
	_present.erase(customer)
	_line.erase(customer)
	if is_instance_valid(customer):
		customer.queue_free()
	_reassign_line()


func _finish() -> void:
	if not running:
		return
	running = false
	Audio.stop_ambience()

	var earned := GameState.takings + GameState.illicit_takings + GameState.tips
	var rent := GameState.rent_due()

	# The night's mistakes are settled before the rent is, because the people
	# you were wrong about do not wait for the landlord.
	var bill := GameState.mistake_bill()
	if int(bill["total"]) > 0:
		GameState.money = maxi(0, GameState.money - int(bill["total"]))
		Signals.money_changed.emit(GameState.money)
	elif GameState.customers_served > 0:
		# A clean night earns a little of your name back.
		GameState.add_reputation(GameState.CLEAN_NIGHT_RECOVERY)

	var paid := GameState.spend(rent)
	if not paid:
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
		"dismissed": GameState.civilians_dismissed,
		"gave_up": GameState.customers_gave_up,
		"bill": bill,
		"reputation": GameState.reputation,
		"evidence": GameState.evidence_against_you,
		"raid_reason": GameState.raid_reason,
	}
	Signals.night_ended.emit(summary)
	shift_finished.emit(summary)


## The person actually at the counter, or null when nobody is.
func current_customer() -> Customer:
	if _line.is_empty():
		return null
	var front := _line[0]
	if is_instance_valid(front) and front.state == Customer.State.AT_COUNTER:
		return front
	return null


func waiting_count() -> int:
	return _line.size()


func present_count() -> int:
	return _present.size()
