extends Node
## Headless checks on the parts of the game that are arguments about numbers
## rather than things you can see by looking.
##
##   godot --headless --path . res://tests/BalanceTest.tscn
##
## It runs as a scene rather than via --script because the generators lean on
## the GameState autoload, and autoloads only exist once a scene tree does.
##
## The question that matters: does investigating actually work? A player who
## sweeps, pulls the file and spends their questions well should end up with a
## clear read most of the time, and a player who does none of that should not.

const SAMPLE := 4000

var failures: Array[String] = []


func _ready() -> void:
	print("\n=== KIOSK AT MIDNIGHT · balance ===\n")
	test_undercover_ratio()
	test_tell_assignment()
	test_separation()
	test_lazy_player()
	test_economy()
	test_strategies()
	_report()
	get_tree().quit(1 if not failures.is_empty() else 0)


func _check(ok: bool, label: String) -> void:
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures.append(label)


# --- How many of them are police ---------------------------------------------

func test_undercover_ratio() -> void:
	print("Undercover share by night (heat 0):")
	GameState.heat = 0.0
	for night: int in [1, 3, 5, 8, 12]:
		GameState.night = night
		var ratio := GameState.undercover_ratio()
		var cops := 0
		for i in 800:
			var p := ProfileGenerator.generate(i * 31 + night * 7, night, ratio)
			if p.kind == CustomerProfile.Kind.UNDERCOVER:
				cops += 1
		var observed := float(cops) / 800.0
		print("   night %2d · target %.2f · observed %.2f · %d customers · ~%.1f officers" %
			[night, ratio, observed, GameState.customer_count(), observed * GameState.customer_count()])
		_check(absf(observed - ratio) < 0.06, "night %d ratio within tolerance" % night)

	# Night 1 must be survivable for someone who has not learned the game yet.
	GameState.night = 1
	_check(GameState.undercover_ratio() < 0.15, "night 1 is forgiving")


# --- Tell assignment ---------------------------------------------------------

func test_tell_assignment() -> void:
	print("\nTell assignment:")
	var no_non_scanner := 0
	var cop_tell_counts: Array[int] = []
	var civ_with_tells := 0
	var civ_total := 0

	for night: int in [1, 4, 8, 12]:
		GameState.night = night
		for i in 500:
			var p := ProfileGenerator.generate(i * 17 + night * 991, night, 0.5)
			if p.kind == CustomerProfile.Kind.UNDERCOVER:
				cop_tell_counts.append(p.tells.size())
				var non_scanner := 0
				for id: String in p.tells:
					if Tells.get_tell(id)["channel"] != Tells.CHANNEL_SCANNER:
						non_scanner += 1
				if non_scanner == 0:
					no_non_scanner += 1
			else:
				civ_total += 1
				if p.tells.size() > 0:
					civ_with_tells += 1

	_check(no_non_scanner == 0, "every officer leaks at least one non-scanner tell (%d violations)" % no_non_scanner)

	var avg := 0.0
	for n in cop_tell_counts:
		avg += float(n)
	avg /= maxf(1.0, float(cop_tell_counts.size()))
	print("   officers carry %.2f tells on average" % avg)
	_check(avg >= 2.0, "officers are never tell-free")

	var civ_rate := float(civ_with_tells) / maxf(1.0, float(civ_total))
	print("   %.0f%% of civilians look guilty about something" % (civ_rate * 100.0))
	_check(civ_rate > 0.30 and civ_rate < 0.75, "false positives are common but not universal")


# --- The player who does the work --------------------------------------------

## Sweeps, pulls the file, watches them, then spends every question they have
## on the heaviest unexplained tell first.
func _investigate(p: CustomerProfile, ask: bool) -> int:
	for id: String in p.tells:
		p.discover(id)   # scanner + terminal + watching them stand there
	if ask:
		while p.patience > 0:
			var options := p.available_questions()
			if options.is_empty():
				break
			# Evidence questions resolve a tell outright, so they come first.
			var best: Dictionary = {}
			var best_weight := -1
			for q in options:
				var w := -1
				if q["kind"] == "tell":
					w = int(Tells.get_tell(q["tell"])["weight"]) + 10
				else:
					w = 1
				if w > best_weight:
					best_weight = w
					best = q
			if best.is_empty():
				break
			p.ask(best)
	return p.suspicion_score()


func test_separation() -> void:
	print("\nA player who investigates properly:")
	GameState.night = 4
	var cop_scores: Array[int] = []
	var civ_scores: Array[int] = []

	for i in SAMPLE:
		var p := ProfileGenerator.generate(i * 13 + 5, 4, 0.5)
		var score := _investigate(p, true)
		if p.kind == CustomerProfile.Kind.UNDERCOVER:
			cop_scores.append(score)
		else:
			civ_scores.append(score)

	_print_spread("   officers ", cop_scores)
	_print_spread("   civilians", civ_scores)

	# Pick the threshold a player would actually use: anything scoring above
	# zero after questioning has an unexplained or confirmed problem.
	var threshold := 1
	var caught := _share_at_or_above(cop_scores, threshold)
	var wrongly := _share_at_or_above(civ_scores, threshold)
	print("   at score >= %d · officers caught %.0f%% · civilians wrongly flagged %.0f%%" %
		[threshold, caught * 100.0, wrongly * 100.0])
	_check(caught > 0.75, "investigating catches most officers")
	_check(wrongly < 0.30, "investigating usually clears innocent people")

	# Doing the work has to be clearly better than guessing, but it must not
	# resolve to certainty. If no officer ever scores as low as an innocent
	# person, there is no judgement left to make and the game is a checklist.
	var overlap := _share_at_or_above(civ_scores, cop_scores.min())
	print("   %.0f%% of civilians score at least as badly as the best-covered officer" % (overlap * 100.0))
	_check(overlap > 0.02, "the bands overlap — a clean read is never guaranteed")
	_check(caught - wrongly > 0.45, "investigating is decisively better than guessing")


# --- The player who does not --------------------------------------------------

func test_lazy_player() -> void:
	print("\nA player who scans and reads but never asks:")
	var cop_scores: Array[int] = []
	var civ_scores: Array[int] = []
	for i in SAMPLE:
		var p := ProfileGenerator.generate(i * 13 + 5, 4, 0.5)
		var score := _investigate(p, false)
		if p.kind == CustomerProfile.Kind.UNDERCOVER:
			cop_scores.append(score)
		else:
			civ_scores.append(score)

	_print_spread("   officers ", cop_scores)
	_print_spread("   civilians", civ_scores)
	var caught := _share_at_or_above(cop_scores, 1)
	var wrongly := _share_at_or_above(civ_scores, 1)
	print("   at score >= 1 · officers caught %.0f%% · civilians wrongly flagged %.0f%%" %
		[caught * 100.0, wrongly * 100.0])
	# The whole design rests on this gap: without questions, the same threshold
	# that catches officers also condemns a lot of innocent customers.
	_check(wrongly > 0.30, "not asking questions produces a lot of false positives")


func _share_at_or_above(scores: Array[int], threshold: int) -> float:
	var n := 0
	for s in scores:
		if s >= threshold:
			n += 1
	return float(n) / maxf(1.0, float(scores.size()))


func _print_spread(label: String, scores: Array[int]) -> void:
	if scores.is_empty():
		return
	var sorted := scores.duplicate()
	sorted.sort()
	var total := 0
	for s in sorted:
		total += s
	print("%s n=%4d  min %3d  median %3d  mean %5.1f  max %3d" %
		[label, sorted.size(), sorted[0], sorted[int(sorted.size() / 2)],
		float(total) / float(sorted.size()), sorted[-1]])


# --- Can the rent be paid? ---------------------------------------------------

func test_economy() -> void:
	print("\nEconomy, per night:")
	for night: int in [1, 3, 6, 10]:
		GameState.night = night
		GameState.heat = 0.0
		var customers := GameState.customer_count()
		var rent := GameState.rent_due()

		# Legitimate trade only: every customer served, nothing under the counter.
		# Shelf goods are counted at margin, not at sticker price, since you had
		# to buy the case from the supplier first.
		var legit := 0.0
		var illicit := 0.0
		var samples := 400
		var unit_cost := float(GameState.illicit_unit_cost())
		for i in samples:
			var basket := 0
			var p := ProfileGenerator.generate(i * 5 + night, night, GameState.undercover_ratio())
			for id: String in p.order:
				basket += int(GameState.ITEMS[id]["price"]) - int(GameState.ITEMS[id]["cost"])
			legit += float(basket)
			# Only civilians can be sold to safely, and every unit had to be
			# bought in first, so this is profit rather than turnover.
			if p.wants_illicit and p.kind == CustomerProfile.Kind.CIVILIAN:
				var avg_price := (38.0 + 66.0) / 2.0 + float(night) * 7.0
				illicit += (avg_price - unit_cost) * 1.5
		legit = legit / float(samples) * float(customers)
		illicit = illicit / float(samples) * float(customers)

		var tips := float(customers) * 0.45 * 4.0 + 20.0
		print("   night %2d · rent %4d · shelf margin ~%4.0f · tips/finds ~%3.0f · stash profit ~%4.0f" %
			[night, rent, legit, tips, illicit])
		# Trading straight should never comfortably cover the rent — that
		# pressure is the reason the stash exists.
		var surplus := legit + tips + illicit - float(rent)
		print("        surplus after rent, playing it as safely as possible: ~%.0f" % surplus)
		_check(legit + tips < float(rent) * 1.15, "night %d cannot be coasted legitimately" % night)
		# Enough left over to arm yourself, but never so much that money stops
		# being a reason to take the next risky sale.
		_check(surplus > 60.0, "night %d leaves something to spend" % night)
		_check(surplus < float(rent) * 1.3, "night %d does not make you rich" % night)


## The rule this exists to prove.
##
## Before there was a penalty for it, throwing everybody out was the safest way
## to play: no sale to an officer, no raid, no risk. It was also the least
## interesting way, because it skipped the entire decision the game is about.
## Refusing has to be survivable-but-poor, and refusing *everybody* has to be
## ruinous, or the detective work is optional.
func test_strategies() -> void:
	print("\nThree ways to play, five nights each:")

	var results := {}
	for strategy: String in ["serve", "cautious", "paranoid"]:
		GameState.reset_run()
		var broke_on := 0
		var missed := 0
		# Money in hand is a bad yardstick here: a night that comes up short zeroes
		# the till, so two strategies that both fail end up indistinguishable at 0.
		# What separates them is how much they earned and how long they lasted.
		var gross := 0
		for night in range(1, 6):
			GameState.night = night
			GameState.reset_night_tally()
			var customers := GameState.customer_count()
			var rng := RandomNumberGenerator.new()
			rng.seed = 900 + night

			for i in customers:
				var p := ProfileGenerator.generate(night * 1000 + i * 7, night,
					GameState.undercover_ratio())
				var civilian := p.kind == CustomerProfile.Kind.CIVILIAN

				if strategy == "paranoid":
					# Everyone goes, no exceptions.
					if civilian:
						GameState.note_wrong_dismissal()
					continue

				# Otherwise they get served their shelf goods.
				var basket := 0
				for id: String in p.order:
					basket += int(GameState.ITEMS[id]["price"]) - int(GameState.ITEMS[id]["cost"])
				GameState.add_money(basket, "takings")
				if rng.randf() < 0.45:
					GameState.add_money(rng.randi_range(1, 7), "tips")

				if not p.wants_illicit:
					continue
				if strategy == "cautious":
					# Refuse the ask. Costs nothing but the margin.
					continue
				# "serve" sells to anyone who asks, which is how you get raided.
				var units := p.illicit_units
				GameState.add_money(
					(GameState.illicit_unit_price(rng) - GameState.illicit_unit_cost()) * units,
					"illicit")

			gross += GameState.takings + GameState.illicit_takings + GameState.tips

			var bill := GameState.mistake_bill()
			GameState.money = maxi(0, GameState.money - int(bill["total"]))
			if not GameState.spend(GameState.rent_due()):
				GameState.money = 0
				missed += 1
				if broke_on == 0:
					broke_on = night
			if int(bill["total"]) == 0:
				GameState.add_reputation(GameState.CLEAN_NIGHT_RECOVERY)

		results[strategy] = {
			"money": GameState.money,
			"reputation": GameState.reputation,
			"broke_on": broke_on,
			"missed": missed,
			"gross": gross,
		}
		print("   %-9s · earned %5d over 5 nights · %4d in hand · name %3d%% · missed rent %d/5%s" % [
			strategy, gross, GameState.money, int(GameState.reputation), missed,
			"" if broke_on == 0 else " (first on night %d)" % broke_on])

	var paranoid: Dictionary = results["paranoid"]
	var cautious: Dictionary = results["cautious"]
	var serve: Dictionary = results["serve"]

	_check(int(paranoid["broke_on"]) > 0, "throwing everybody out cannot pay the rent")
	_check(float(paranoid["reputation"]) < 30.0, "and ruins your name")

	# Refusing the ask is a worse night than serving it, but it is a night. Both
	# of these have to hold or "throw everybody out" is still on the table:
	# refusing everybody has to earn less and fail sooner.
	_check(int(cautious["gross"]) > int(paranoid["gross"]),
		"refusing the ask out-earns refusing everybody (%d vs %d)"
			% [int(cautious["gross"]), int(paranoid["gross"])])
	_check(int(cautious["missed"]) < int(paranoid["missed"]),
		"and survives longer (missed %d nights vs %d)"
			% [int(cautious["missed"]), int(paranoid["missed"])])
	_check(int(paranoid["broke_on"]) <= int(cautious["broke_on"]),
		"paranoia hits the wall first (night %d vs night %d)"
			% [int(paranoid["broke_on"]), int(cautious["broke_on"])])
	_check(int(serve["gross"]) > int(cautious["gross"]),
		"and taking the risk beats playing it safe (%d vs %d)"
			% [int(serve["gross"]), int(cautious["gross"])])
	# The point of the whole design: the safe play must be *poor*, not *dead*.
	_check(int(cautious["broke_on"]) > 0,
		"but playing it safe still cannot make the rent on shelf trade alone")
	GameState.reset_run()


func _report() -> void:
	print("\n=== %s ===\n" % ("ALL CHECKS PASSED" if failures.is_empty() else "%d FAILED" % failures.size()))
	for f in failures:
		print("  · " + f)
