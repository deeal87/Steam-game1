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
## Below this many minutes on the clock, nobody new comes in.
const LAST_ORDERS := 12.0
## How long the person actually at the counter gets after five, before the
## shutter comes down on them too.
const CLOSING_GRACE := 6.0
## Real seconds of shift per customer the night intends to send. A visit is
## roughly 140 seconds door to door and MAX_IN_SHOP of them overlap, so the shop
## clears about one person every 140/4 seconds and the shift has to be at least
## that long per head or it cannot deliver its own custom.
const SECONDS_PER_CUSTOMER := 35.0
## After closing time, how long the stragglers get to walk out before the night
## ends without them. A backstop, not a schedule — normally the shop is empty
## well before this.
const LOCK_UP := 10.0
## A little at the top of the night before the first one walks in.
const OPENING_SLACK := 24.0

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
## Seconds since the clock hit zero, for the closing-time grace.
var _closing: float = 0.0
var _called_time: bool = false
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

	# Long enough to actually serve the people it is about to send.
	#
	# This used to budget twenty seconds a customer, a figure that predates
	# customers shopping the floor for themselves. A visit now measures at
	# 130-160 seconds door to door, and only MAX_IN_SHOP of them fit at once, so
	# the shift was ending with a third of the night's custom never sent — while
	# the rent went on scaling against the full count. The soak found it; the
	# number below comes from what it measured rather than from taste.
	var expected_seconds := OPENING_SLACK + float(_queue_remaining) * SECONDS_PER_CUSTOMER
	_minutes_per_second = SHIFT_MINUTES / expected_seconds

	_gap = 2.0
	_closing = 0.0
	_called_time = false
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

	# Nobody new comes in near closing time.
	#
	# This used to read `_queue_remaining <= 0 and _present.is_empty()` on the
	# other branch, which could never become true once the clock had run out
	# with people still due to arrive: arrivals stopped below LAST_ORDERS and
	# nothing decremented `_queue_remaining` again, so the shift hung forever.
	# The clock is calibrated at about twenty seconds a customer, and anybody who
	# actually reads the files and asks questions takes longer than that, so this
	# was reachable by playing carefully. The end of the night is now a property
	# of the clock, not of a counter that stops moving.
	var still_arriving := _queue_remaining > 0 and minutes_left > LAST_ORDERS

	if still_arriving:
		if _present.size() < MAX_IN_SHOP:
			_gap -= delta
			if _gap <= 0.0:
				_spawn_next()
				_gap = _rng.randf_range(GAP_MIN, GAP_MAX)
		return

	if minutes_left <= 0.0:
		_close_up(delta)
	# The shift ends when the shop empties — or when it has had long enough to,
	# whichever comes first. Waiting on `_present` alone means one customer who
	# cannot reach the door holds the night open forever, and there is no state
	# a shop can be in at five in the morning that justifies never closing.
	if _present.is_empty() or _closing > CLOSING_GRACE + LOCK_UP:
		_finish()


## 05:00. The shutter comes down whether you are finished or not.
##
## Anyone still browsing or queueing goes straight away. Whoever is actually at
## the counter gets a few seconds to be dealt with first, because having a sale
## snatched out of your hands on the last frame is a rotten way to lose one —
## but they go too when it runs out. Nothing may hold the shift open
## indefinitely, including a customer wedged on a corner.
func _close_up(delta: float) -> void:
	_closing += delta
	if not _called_time:
		_called_time = true
		Signals.notice.emit("Five o'clock. Shutter's coming down.", "info")
	for c in _present:
		if not is_instance_valid(c):
			continue
		if c.state == Customer.State.AT_COUNTER and _closing < CLOSING_GRACE:
			continue
		c._leave("closing")


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
