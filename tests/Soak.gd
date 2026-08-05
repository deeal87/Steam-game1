extends Node
## Plays the game. Actually plays it, for several nights, and reports what
## happened.
##
##   godot --headless --path . res://tests/Soak.tscn -- --nights=5
##
## Everything else in tests/ checks a part in isolation or argues about numbers.
## Neither can catch the failure that matters most before shipping: a night that
## never ends. A customer wedged on a corner, a queue that stops advancing, a
## till that will not clear, a shift whose exit condition can never be met —
## all of those pass every unit test in the repository and make the game
## unplayable.
##
## So this drives the real Boot scene with a bot at the counter: it scans what
## is on the counter, works the till, restocks when the shelves run dry, and
## keeps going until the night ends or a watchdog decides it never will. The
## exit code is the point; the report is for reading afterwards.
##
## Time is scaled up rather than simulated, so the physics, the walk cycles and
## the queue all run for real — just faster. Anything that only breaks at normal
## speed would be missed, but anything that breaks because of *state* is caught,
## and state is where the softlocks are.

const BOOT := preload("res://scenes/Boot.tscn")

## Wall-clock seconds one night is allowed before it is declared stuck. A night
## is six compressed hours; at the speed-up below it should take well under a
## minute, so this is generous by design — a false stall report is worse than a
## slow test.
const NIGHT_BUDGET := 150.0
const SPEED := 6.0

var nights_wanted: int = 3
var game: Node
var _failures: Array[String] = []
var _log: Array[String] = []
var _due_at_start: int = 0
var _visit_starts: Dictionary = {}
var _visits: Array[float] = []


func _on_arrived(c: Customer) -> void:
	_visit_starts[c.get_instance_id()] = Time.get_ticks_msec()


func _on_departed(c: Node, _outcome: String) -> void:
	var id := c.get_instance_id()
	if _visit_starts.has(id):
		_visits.append(float(Time.get_ticks_msec() - int(_visit_starts[id])) / 1000.0)
		_visit_starts.erase(id)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--nights="):
			nights_wanted = maxi(1, int(arg.substr(9)))

	print("\n=== KIOSK AT MIDNIGHT · soak ===\n")
	print("Playing %d nights at %dx.\n" % [nights_wanted, int(SPEED)])

	Engine.time_scale = SPEED
	game = BOOT.instantiate()
	add_child(game)
	await _settle(60)

	# Through the title the way a player does.
	game.report._continue()
	await _settle(10)

	for night in range(1, nights_wanted + 1):
		var ok := await _play_night(night)
		if not ok:
			break
		if not await _clear_interstitials(night):
			break

	Engine.time_scale = 1.0
	_report()
	get_tree().quit(1 if not _failures.is_empty() else 0)


## Runs one shift to its end, working the counter as it goes.
func _play_night(night: int) -> bool:
	var director: NightDirector = game.night_director
	var checkout: Checkout = game.checkout
	var started := Time.get_ticks_msec()
	var served_at_start := GameState.customers_served
	# Counted from the director's own books rather than from a signal, because
	# the first customer can spawn before this coroutine gets its connection in
	# and an undercount here reads as "more served than arrived".
	_due_at_start = director._queue_remaining
	_visit_starts.clear()
	_visits.clear()
	if not director.customer_ready.is_connected(_on_arrived):
		director.customer_ready.connect(_on_arrived)
	if not Signals.customer_departed.is_connected(_on_departed):
		Signals.customer_departed.connect(_on_departed)
	var last_clock := director.minutes_left
	var stalled_clock := 0.0

	while director.running:
		await get_tree().process_frame
		_work_the_counter(checkout, director)

		var elapsed := float(Time.get_ticks_msec() - started) / 1000.0
		if elapsed > NIGHT_BUDGET:
			_fail("night %d never finished — %.0fs with %d in the shop, %d in line, clock at %.0f"
				% [night, elapsed, director.present_count(), director.waiting_count(),
					director.minutes_left])
			return false

		# The clock must keep moving while there is any left. Once it reaches
		# zero it legitimately stops, and the shop empties out under the
		# closing-time grace — so only a stalled *non-zero* clock is a fault.
		# The overall budget covers everything after five.
		if director.minutes_left > 0.0 and is_equal_approx(director.minutes_left, last_clock):
			stalled_clock += 0.016
			if stalled_clock > 6.0:
				_fail("night %d: the shift clock stopped at %.0f" % [night, director.minutes_left])
				return false
		else:
			stalled_clock = 0.0
			last_clock = director.minutes_left

	var served := GameState.customers_served - served_at_start
	var earned := GameState.takings + GameState.illicit_takings + GameState.tips
	var rent := GameState.rent_due()
	var never_sent := director._queue_remaining
	var stock := GameState.total_shelf_units() + _crates()
	_note("night %d · %.0fs · served %d of %d due · never sent %d · took %d of %d rent · stock left %d · in hand %d"
		% [night, float(Time.get_ticks_msec() - started) / 1000.0, served, _due_at_start,
			never_sent, earned, rent, stock, GameState.money])

	if not _visits.is_empty():
		var total := 0.0
		var longest := 0.0
		for v in _visits:
			total += v
			longest = maxf(longest, v)
		_note("        a visit takes %.0fs on average, worst %.0fs — the shift budgets %ds each"
			% [total / float(_visits.size()) * SPEED, longest * SPEED, 20])

	# A night is meant to deliver roughly the trade it promises — but only if
	# there is trade to do. A shop with nothing on the shelves and nothing in the
	# till has legitimately run out of game, and that is the economy working, not
	# the shift failing. This harness judges the engine, never the shopkeeping.
	var could_trade := stock > 4
	if _due_at_start > 0 and never_sent > _due_at_start / 2 and could_trade:
		_fail("night %d only sent %d of %d customers with %d stock on hand"
			% [night, _due_at_start - never_sent, _due_at_start, stock])
		return false
	if not could_trade:
		_note("        nothing left to sell — the shop is finished, which is the economy, not a fault")

	# A night where nobody was served is not a crash, but it is not a game
	# either — it means people are arriving and never reaching the counter.
	if served == 0:
		_fail("night %d served nobody at all" % night)
		return false
	return true


## The bot. Deliberately dim: it does the mechanical part of the job and makes
## no decisions, because the decisions are the game and a bot that made them
## would be testing itself rather than the shop.
func _work_the_counter(checkout: Checkout, director: NightDirector) -> void:
	# Mind the shop first, and unconditionally. This used to sit at the bottom
	# of the function behind three early returns, so it ran almost never — the
	# shelves emptied, customers arrived with nothing in their baskets, and the
	# takings looked like a game economy problem when they were a bot problem.
	for id: String in GameState.ITEMS:
		if GameState.shelf_units(id) <= 1:
			GameState.restock_one(id)

	var customer := director.current_customer()
	if customer == null:
		return

	# Shopping first. Refusing the ask makes them leave, so doing it before the
	# goods are rung up loses the sale — which is what a careless player does,
	# not what the game requires, and it made the takings look far worse than
	# they are.
	if checkout.active:
		for i in checkout.item_count():
			if not checkout.is_scanned(i):
				checkout.scan(i)
				return
		if checkout.all_scanned():
			checkout.take_payment()
			return

	# Then the ask. Somebody given no answer stands at the counter until their
	# patience runs out, which is most of a night. The bot always refuses — the
	# dim-but-legal play — because deciding *who they are* is the game, and a bot
	# guessing at it would be testing itself rather than the shop.
	if customer._asked_for_illicit and not customer.profile.sold_illicit:
		customer.refuse()


## Between nights the game shows a report, and sometimes a raid warning and a
## raid. The soak survives raids by refusing to fight: it goes down the manhole,
## which is a real thing a player can do and exercises the escape path.
func _clear_interstitials(night: int) -> bool:
	var started := Time.get_ticks_msec()
	while true:
		await get_tree().process_frame
		if float(Time.get_ticks_msec() - started) / 1000.0 > NIGHT_BUDGET:
			_fail("night %d: stuck between shifts in phase %d" % [night, game.phase])
			return false

		match game.phase:
			2:   # REPORT
				# Buy stock before opening up again. The back room does not
				# refill itself, and a shopkeeper who never calls the supplier
				# ends up with empty shelves, customers who find nothing worth
				# buying, and a night that looks broken when it is only badly
				# run. This is a real part of the loop and the soak has to do it.
				_buy_stock()
				game.report._continue()
			3:   # RAID_WARNING
				_note("   night %d ends in a raid" % night)
				game.report._continue()
			4:   # RAID
				# Run for it. Fighting properly needs aiming, which a bot has no
				# business faking, and the escape is the path more likely to be
				# broken because it crosses two scenes.
				await _settle(20)
				Signals.travel_requested.emit(
					game.world.anchors["sewer_shaft_bottom"], "soak: down the ladder", true)
				await _settle(60)
				# And back up. A player who flees does not spend the rest of the
				# run standing in a sewer, and leaving the bot down there made
				# every night after the first look broken when it was not.
				Signals.travel_requested.emit(
					game.world.anchors["manhole"] + Vector3(0, 0.2, -0.9),
					"soak: back up the ladder", false)
				await _settle(60)
			1:   # SHIFT — next night has started
				_note("   night %d starts · player at %.1f,%.1f,%.1f · sewer_y %.1f"
					% [night + 1, game.player.global_position.x,
						game.player.global_position.y, game.player.global_position.z,
						World.SEWER_Y])
				return true
			5:   # OVER
				_fail("night %d: the run ended (died or was raided out)" % night)
				return false
	return true


## Where everyone was standing when the shutter came down, and how many the
## night never even got round to sending. This is the difference between "the
## queue jammed" and "the shift was too short to send them all".
func _shop_census(director: NightDirector) -> String:
	var states := {"approaching": 0, "queueing": 0, "at counter": 0, "leaving": 0}
	for c in director._present:
		if not is_instance_valid(c):
			continue
		match c.state:
			Customer.State.APPROACHING: states["approaching"] += 1
			Customer.State.QUEUEING: states["queueing"] += 1
			Customer.State.AT_COUNTER: states["at counter"] += 1
			Customer.State.LEAVING: states["leaving"] += 1
	var bits: Array[String] = []
	for k: String in states:
		if int(states[k]) > 0:
			bits.append("%d %s" % [int(states[k]), k])
	bits.append("%d never sent" % director._queue_remaining)
	return ", ".join(bits)


## Restocks the back room the way the supplier screen does, cheapest first,
## while there is money for it.
func _crates() -> int:
	var n := 0
	for id: String in GameState.ITEMS:
		n += int(GameState.crate_stock.get(id, 0))
	return n


func _buy_stock() -> void:
	for id: String in GameState.ITEMS:
		var case_cost: int = int(GameState.ITEMS[id]["cost"]) * 6
		while int(GameState.crate_stock.get(id, 0)) < 8 and GameState.money >= case_cost:
			if not GameState.spend(case_cost):
				return
			GameState.crate_stock[id] = int(GameState.crate_stock.get(id, 0)) + 6


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _note(line: String) -> void:
	print("  " + line)
	_log.append(line)


func _fail(line: String) -> void:
	print("  FAIL  " + line)
	_failures.append(line)


func _report() -> void:
	print("\n=== %s ===\n" % ("SOAK CLEAN" if _failures.is_empty()
		else "%d PROBLEM(S)" % _failures.size()))
	for f in _failures:
		print("  · " + f)
