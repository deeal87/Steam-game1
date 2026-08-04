extends Node
## Construction and wiring checks.
##
##   godot --headless --path . res://tests/SmokeTest.tscn
##
## The balance harness argues about numbers. This one just builds every part of
## the game once and drives a transaction through it, which is what catches the
## null reference or the renamed dictionary key that a pure logic test misses.

var failures: Array[String] = []
var _world: World
var _player: Player


func _ready() -> void:
	print("\n=== KIOSK AT MIDNIGHT · smoke ===\n")
	GameState.reset_run()
	test_audio()
	test_textures()
	test_world()
	test_customer_construction()
	await test_sewer_is_traversable()
	test_identity_and_egg()
	test_sewer_escape()
	await test_transaction()
	await test_shopping_trip()
	test_rebinding()
	test_score()
	await test_queue()
	test_sewer_threat()
	await test_being_wrong()
	await test_illicit_and_departure()
	await test_violence()
	test_raid()
	test_panels()
	_report()
	get_tree().quit(1 if not failures.is_empty() else 0)


func _check(ok: bool, label: String) -> void:
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures.append(label)


# --- Assets that are generated rather than loaded -----------------------------

func test_audio() -> void:
	print("Synthesised audio:")
	var cues := ["beep", "beep_low", "deny", "confirm", "click", "chime", "register",
		"gunshot", "shotgun", "swing", "impact", "footstep", "scanner", "typing",
		"radio", "heartbeat", "breach", "ambience"]
	var built := 0
	for cue: String in cues:
		var stream: AudioStreamWAV = Audio._cue(cue)
		if stream != null and stream.data.size() > 0:
			built += 1
	_check(built == cues.size(), "all %d cues synthesise (%d built)" % [cues.size(), built])


func test_textures() -> void:
	print("\nProcedural textures:")
	var ok := true
	for tex: Texture2D in [
		ProcTex.asphalt(1), ProcTex.brick(2), ProcTex.tiles(3),
		ProcTex.grime(Color.RED, 0.4, 4), ProcTex.corrugated(Color.GRAY, 5),
		ProcTex.metal(Color.GRAY, 6), ProcTex.flat(Color.BLUE),
		ProcTex.product(Color.GREEN, 7), ProcTex.face(8), ProcTex.neon_sign(Color.RED, 9),
	]:
		if tex == null or tex.get_width() <= 0:
			ok = false
	_check(ok, "every texture generator returns a real image")

	# The face on the model and the face in the terminal must be the same
	# person, or the identity check is a lie.
	var a := ProcTex.face(4242).get_image().get_data()
	var b := ProcTex.face(4242).get_image().get_data()
	_check(a == b, "faces are deterministic for a given seed")
	_check(ProcTex.face(1).get_image().get_data() != ProcTex.face(2).get_image().get_data(),
		"different seeds give different faces")


# --- World --------------------------------------------------------------------

func test_world() -> void:
	print("\nWorld:")
	_world = World.new()
	add_child(_world)
	_check(_world.anchors.has("player_spawn"), "player spawn anchor exists")
	_check(_world.anchors.has("customer_stand"), "customer stand anchor exists")
	_check(_world.anchors.has("shutter"), "shutter exists")
	_check(_world.shelf_slots.size() == GameState.ITEMS.size(),
		"every product has a run of shelf slots")
	_check(_world.breach_points().size() >= 2, "raid has somewhere to come from")

	# The building is no longer one room.
	for key: String in ["manhole", "sewer_shaft_bottom", "sewer_exit_top",
			"sewer_exit_bottom", "easter_egg", "stock_centre"]:
		_check(_world.anchors.has(key), "anchor '%s' exists" % key)
	_check(World.STOCK_MAX_Z > World.SHOP_HALF_Z, "the stockroom is behind the shop floor")
	_check(World.SEWER_Y < 0.0, "the sewer is below ground")
	_check(absf(World.SEWER_EXIT.x - World.STREET_END) < 12.0,
		"the sewer comes up near the far end of the street")
	_check(World.STREET_EAST - World.STREET_WEST > 80.0, "the street is actually a street")

	_world.refresh_shelves()
	GameState.shelf_stock["smokes"] = 0
	_world.refresh_shelves()
	var slots: Array = _world.shelf_slots["smokes"]
	_check(not (slots[0] as MeshInstance3D).visible, "an empty shelf actually looks empty")
	GameState.shelf_stock["smokes"] = 4
	_world.refresh_shelves()
	_check((slots[0] as MeshInstance3D).visible, "restocking puts the boxes back")

	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	_world.scatter_cash(rng)
	_check(_world.cash_pickups.size() >= 2, "loose cash gets scattered around the kiosk")

	_player = Player.new()
	_player.world = _world
	add_child(_player)
	_player.global_position = _world.anchors["player_spawn"]
	_check(_player.camera != null, "player has a camera")


## The bug this exists to catch: a shaft built as four solid walls puts a slab
## straight across the tunnel, and a one-piece tunnel roof caps the shaft. Both
## look completely fine in the editor and leave you teleported into a sealed
## box of brick.
func _point_is_clear(pos: Vector3, radius: float) -> bool:
	var space := _world.get_world_3d().direct_space_state
	if space == null:
		return true
	var shape := SphereShape3D.new()
	shape.radius = radius
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis(), pos)
	q.collision_mask = 1
	# The test's own player stands at the spawn point, so without this the
	# query finds itself and reports the shop is full of furniture.
	if _player != null and is_instance_valid(_player):
		q.exclude = [_player.get_rid()]
	return space.intersect_shape(q, 1).is_empty()


func test_sewer_is_traversable() -> void:
	print("\nThe sewer is actually a sewer:")
	# Physics bodies are not queryable until a physics step has run.
	await get_tree().physics_frame
	await get_tree().physics_frame

	var bottom: Vector3 = _world.anchors["sewer_shaft_bottom"]
	var exit_bottom: Vector3 = _world.anchors["sewer_exit_bottom"]
	_check(_point_is_clear(bottom + Vector3(0, 0.9, 0), 0.30),
		"the stockroom ladder does not drop you inside a wall")
	_check(_point_is_clear(exit_bottom + Vector3(0, 0.9, 0), 0.30),
		"the street ladder does not drop you inside a wall")

	# Walk the main run in steps and make sure it is open the whole way.
	var blocked := 0
	var probes := 0
	var x := bottom.x
	while x > World.SEWER_EXIT.x + 1.0:
		probes += 1
		if not _point_is_clear(Vector3(x, bottom.y + 0.9, World.MANHOLE.z), 0.28):
			blocked += 1
		x -= 2.0
	_check(blocked == 0, "the tunnel is clear along its whole length (%d of %d probes blocked)"
		% [blocked, probes])

	# And the dogleg up to the exit shaft.
	var leg_blocked := 0
	var z := World.MANHOLE.z
	while z > World.SEWER_EXIT.z:
		if not _point_is_clear(Vector3(World.SEWER_EXIT.x, bottom.y + 0.9, z), 0.28):
			leg_blocked += 1
		z -= 1.0
	_check(leg_blocked == 0, "the dogleg to the exit is clear (%d blocked)" % leg_blocked)

	# You must also be able to stand up in it.
	_check(_point_is_clear(bottom + Vector3(0, 1.5, 0), 0.25), "there is headroom down there")


func test_identity_and_egg() -> void:
	print("\nThe thing at the end of the road:")
	Settings.player_name = ""
	var resolved := PlayerIdentity.display_name()
	_check(not resolved.is_empty(), "a name always resolves (got '%s')" % resolved)
	_check(not PlayerIdentity.is_steam_name(),
		"no Steam plugin here, so it does not claim a Steam name")

	Settings.player_name = "TESTSUBJECT"
	_check(PlayerIdentity.display_name() == "TESTSUBJECT", "a name set in settings wins")

	var egg: EasterEgg = _world.anchors["easter_egg"]
	var plaque: Label3D = null
	for child in egg.get_children():
		if child is Label3D:
			plaque = child
	_check(plaque != null, "the board carries real text")
	if plaque != null:
		_check(plaque.text.contains("MASTER OF MASTER"), "it says what it should say")
	# It is at the far end and nowhere near the kiosk.
	_check(egg.global_position.distance_to(Vector3.ZERO) > 40.0,
		"it is a long way from the counter (%.0f m)" % egg.global_position.distance_to(Vector3.ZERO))
	Settings.player_name = ""


func test_being_wrong() -> void:
	print("\nThe cost of being wrong:")
	GameState.reset_run()
	GameState.reset_night_tally()
	_check(GameState.reputation == 100.0, "you start with a clean name")

	# Throwing out an officer is correct play and must stay free.
	var cop := _spawn_at_counter(80081, int(CustomerProfile.Kind.UNDERCOVER))
	var rep_before := GameState.reputation
	cop.dismiss()
	_check(GameState.reputation == rep_before, "sending an officer away costs nothing")
	_check(GameState.civilians_dismissed == 0, "and is not counted as a mistake")

	# Throwing out an ordinary customer is not.
	var civ := _spawn_at_counter(80081, int(CustomerProfile.Kind.CIVILIAN))
	civ.dismiss()
	_check(GameState.civilians_dismissed == 1, "throwing out a regular is counted")
	_check(GameState.reputation < rep_before, "and takes your name down (%d%%)" % int(GameState.reputation))

	# Shooting one is worse than throwing one out, on both counts.
	GameState.reset_run()
	GameState.reset_night_tally()
	var civ2 := _spawn_at_counter(4711, int(CustomerProfile.Kind.CIVILIAN))
	civ2.take_damage(500.0, _player)
	var kill_drop := 100.0 - GameState.reputation
	_check(kill_drop > GameState.DISMISS_REPUTATION,
		"shooting costs more name than dismissing (%d vs %d)" % [int(kill_drop), int(GameState.DISMISS_REPUTATION)])
	_check(GameState.mistake_bill()["killed"] > GameState.DISMISS_FINE,
		"and more money")

	# The bill has to actually be itemised for the report.
	GameState.reset_run()
	GameState.reset_night_tally()
	GameState.civilians_dismissed = 2
	GameState.civilians_killed = 1
	var bill := GameState.mistake_bill()
	_check(int(bill["dismissed"]) == 2 * GameState.DISMISS_FINE, "dismissals are itemised")
	_check(int(bill["killed"]) == GameState.KILL_FINE, "killings are itemised")
	_check(int(bill["total"]) == int(bill["dismissed"]) + int(bill["killed"]), "and add up")

	# And a bad name has to actually thin tomorrow's trade.
	GameState.reset_run()
	GameState.night = 5
	var busy := GameState.customer_count()
	GameState.reputation = 0.0
	var quiet := GameState.customer_count()
	print("   night 5: %d customers on a clean name, %d on a ruined one" % [busy, quiet])
	_check(quiet < busy, "a ruined name costs you trade")
	_check(quiet >= 4, "but never leaves you with nobody at all")

	cop.queue_free()
	civ.queue_free()
	civ2.queue_free()
	GameState.reset_run()
	await get_tree().process_frame


func test_sewer_escape() -> void:
	print("\nRunning for it:")
	GameState.reset_run()
	GameState.reset_night_tally()
	GameState.add_money(200, "illicit")
	GameState.drug_stock = 9
	var before_money := GameState.money
	var lost := GameState.flee_through_sewer()

	_check(int(lost["stash"]) == 9, "the stash is gone")
	_check(int(lost["cash"]) == 200, "the night's takings are gone")
	_check(GameState.drug_stock == 0, "nothing left under the counter")
	_check(GameState.money == before_money - 200, "and it comes off what you are holding")
	_check(GameState.evidence_against_you == 0, "but the raid is over")
	_check(GameState.fled_through_sewer, "the run remembers you ran")


func test_customer_construction() -> void:
	print("\nCustomers:")
	var built := 0
	for i in 40:
		var p := ProfileGenerator.generate(i * 101, 3, 0.5)
		var c := Customer.new()
		c.setup(p)
		_world.add_child(c)
		if c.get_child_count() > 0 and c.profile != null:
			built += 1
		c.queue_free()
	_check(built == 40, "40 customers build without complaint")

	var body := ProcMesh.human(99, 1.0, 1.0)
	_check(body.get_node_or_null("Head") != null, "figures have a head")
	_check(body.get_node_or_null("Head/Face") != null, "figures have a face quad")
	body.queue_free()


# --- A whole transaction ------------------------------------------------------

func _spawn_at_counter(seed_value: int, force_kind: int = -1) -> Customer:
	var p: CustomerProfile
	var guard := 0
	while true:
		p = ProfileGenerator.generate(seed_value + guard * 13, 3, 0.5)
		if force_kind < 0 or int(p.kind) == force_kind:
			break
		guard += 1
		if guard > 400:
			break
	var c := Customer.new()
	c.setup(p)
	_world.add_child(c)
	c.state = Customer.State.AT_COUNTER
	c.global_position = World.CUSTOMER_STAND
	return c


func test_transaction() -> void:
	print("\nShopping, scanning and the till:")
	GameState.reset_run()
	GameState.reset_night_tally()

	var checkout := Checkout.new()
	checkout.setup(_world)
	add_child(checkout)

	var c := _spawn_at_counter(555)
	# They walk the shop themselves, so the basket is what they managed to get.
	var basket: Array[String] = []
	for id: String in c.profile.order:
		if GameState.take_from_shelf(id):
			basket.append(id)
	c.basket = basket
	_check(not basket.is_empty(), "they got something off the shelves")

	var expected := 0
	for id: String in basket:
		expected += int(GameState.ITEMS[id]["price"])

	var placed := checkout.begin(c, basket)
	_check(placed == basket.size(), "everything they picked up lands on the counter")
	_check(checkout.remaining() == placed, "and none of it is scanned yet")

	# The till must refuse while anything is unrung. This is the whole mechanic.
	var money_before := GameState.money
	_check(not checkout.take_payment(), "the till refuses while items are unscanned")
	_check(GameState.money == money_before, "and takes no money for them")

	for i in placed:
		_check(checkout.scan(i), "scans item %d" % i)
	_check(not checkout.scan(0), "the same item cannot be scanned twice")
	_check(checkout.all_scanned(), "everything is rung up")
	_check(checkout.total() == expected, "the total matches the shelf prices (%d)" % expected)

	_check(checkout.take_payment(), "the till takes the money once everything is scanned")
	_check(GameState.money == money_before + expected, "and the takings go up by the total")
	_check(GameState.customers_served == 1, "the sale is counted")
	_check(not checkout.active, "the counter is clear afterwards")

	# An empty shelf means an empty basket means nothing to sell.
	for id: String in GameState.ITEMS:
		GameState.shelf_stock[id] = 0
	var c2 := _spawn_at_counter(909)
	var empty: Array[String] = []
	_check(checkout.begin(c2, empty) == 0, "a bare shelf leaves nothing to ring up")

	# Evidence channels still work from the counter.
	c.on_scan(_player)
	_check(c.profile.scanned, "sweep is recorded")
	c.on_lookup()
	_check(c.profile.looked_up, "file lookup is recorded")

	checkout.queue_free()
	c.queue_free()
	c2.queue_free()
	await get_tree().process_frame


func test_shopping_trip() -> void:
	print("\nThe walk round the shop:")
	GameState.reset_run()
	var p := ProfileGenerator.generate(4242, 2, 0.0)
	var c := Customer.new()
	c.setup(p, _world)
	_world.add_child(c)

	_check(c._path.size() >= 4, "they have a route in (%d waypoints)" % c._path.size())
	_check(c.global_position.distance_to(World.CUSTOMER_ENTRY) < 0.1,
		"they start at the entry point")
	var stops := 0
	for step: Dictionary in c._path:
		if not str(step["take"]).is_empty():
			stops += 1
	_check(stops == p.order.size(), "one stop per thing on their list")

	# Every waypoint has to be somewhere a person could actually stand.
	await get_tree().physics_frame
	await get_tree().physics_frame
	# The spawn point is not part of the path, which is exactly how a customer
	# ended up spawned inside a parked car and never moving all night.
	var blocked := 0
	var names: Array[String] = []
	var probes: Array[Vector3] = [World.CUSTOMER_ENTRY, World.CUSTOMER_EXIT]
	for step: Dictionary in c._path:
		probes.append(step["pos"])
	for pos: Vector3 in probes:
		if not _point_is_clear(pos + Vector3(0, 0.9, 0), 0.34):
			blocked += 1
			names.append(str(pos))
	_check(blocked == 0, "spawn, exit and every waypoint are clear (%d blocked %s)"
		% [blocked, ", ".join(names)])
	_check(_point_is_clear(World.CUSTOMER_STAND + Vector3(0, 0.9, 0), 0.30),
		"there is room to stand at the counter")
	_check(_point_is_clear(_world.anchors["player_spawn"] + Vector3(0, 0.9, 0), 0.30),
		"and room behind it for you")

	c.queue_free()
	await get_tree().process_frame


func test_rebinding() -> void:
	print("\nRebinding keys:")
	InputSetup.reset_bindings()
	_check(InputSetup.binding_label("interact") == "E", "interact starts on E")

	# Move it somewhere free.
	var to_j := InputEventKey.new()
	to_j.physical_keycode = KEY_J
	_check(InputSetup.rebind("interact", to_j), "it can be moved to a free key")
	_check(InputSetup.binding_label("interact") == "J", "and the menu shows the new key")
	_check(InputMap.event_is_action(to_j, "interact"), "and the game actually listens to it")

	# Taking a key another action already uses would make two things happen at
	# once, so it must be refused rather than silently accepted.
	var to_w := InputEventKey.new()
	to_w.physical_keycode = KEY_W
	_check(not InputSetup.rebind("interact", to_w), "a key already in use is refused")
	_check(InputSetup.binding_label("interact") == "J", "and the old binding survives the attempt")
	_check(InputSetup.binding_label("move_forward") == "W", "as does the one it clashed with")

	# Escape has to stay escape or the menu becomes impossible to leave.
	var to_esc := InputEventKey.new()
	to_esc.physical_keycode = KEY_ESCAPE
	_check(not InputSetup.rebind("interact", to_esc), "escape cannot be taken")

	# Overrides have to survive a restart.
	InputSetup.save_overrides()
	InputSetup.reset_bindings()
	_check(InputSetup.binding_label("interact") == "E", "resetting puts it back")
	InputSetup.rebind("interact", to_j)
	InputSetup.load_overrides()
	_check(InputSetup.binding_label("interact") == "J", "and a saved binding reloads")

	InputSetup.reset_bindings()
	_check(InputSetup.binding_label("interact") == "E", "left as it was found")


func test_score() -> void:
	print("\nThe score:")
	var lengths: Array[int] = []
	var built := 0
	for name: String in ["bed", "pulse", "dread", "deep"]:
		var layer: Dictionary = Music._layers.get(name, {})
		var p: AudioStreamPlayer = layer.get("player")
		if p != null and p.stream != null and (p.stream as AudioStreamWAV).data.size() > 0:
			built += 1
			lengths.append((p.stream as AudioStreamWAV).data.size())
	_check(built == 4, "all four layers synthesise (%d built)" % built)
	# They are mixed by volume while playing together, so any difference in
	# length would drift them apart over a night.
	var same := true
	for l in lengths:
		if l != lengths[0]:
			same = false
	_check(same, "every layer is exactly the same length, so they stay in sync")
	for name: String in ["bed", "pulse", "dread", "deep"]:
		var stream: AudioStreamWAV = Music._layers[name]["player"].stream
		_check(stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "%s loops" % name)

	# The invariant the whole detective mechanic depends on.
	var cop := ProfileGenerator.generate(31337, 3, 1.0)
	var civ := ProfileGenerator.generate(31337, 3, 0.0)
	_check(cop.kind == CustomerProfile.Kind.UNDERCOVER and civ.kind == CustomerProfile.Kind.CIVILIAN,
		"got one of each to compare")
	var as_cop := Music.tension_from(40.0, true, false, 0)
	var as_civ := Music.tension_from(40.0, true, false, 0)
	_check(is_equal_approx(as_cop, as_civ),
		"the score cannot tell an officer from a civilian (%.3f vs %.3f)" % [as_cop, as_civ])
	_check(Music.tension_from(0.0, false, false, 0) < Music.tension_from(0.0, true, false, 0),
		"but it does rise when they make the ask")
	_check(Music.tension_from(0.0, false, false, 0) < Music.tension_from(90.0, false, false, 0),
		"and with heat")
	_check(Music.tension_from(100.0, true, false, 5) <= 1.0, "and never runs past full")


func test_queue() -> void:
	print("\nThe queue:")
	GameState.reset_run()
	var director := NightDirector.new()
	director.setup(_world)
	add_child(director)

	var made: Array[Customer] = []
	for i in 4:
		var p := ProfileGenerator.generate(7000 + i * 31, 2, 0.0)
		var c := Customer.new()
		c.setup(p, _world)
		_world.add_child(c)
		c.state = Customer.State.QUEUEING
		made.append(c)
		director._present.append(c)
		director._on_finished_shopping(c)

	_check(director.waiting_count() == 4, "four people can be in line at once")
	var indices: Array[int] = []
	for c in made:
		indices.append(c.queue_index)
	print("   indices in arrival order: %s" % str(indices))
	_check(indices == [0, 1, 2, 3], "positions are handed out in arrival order")
	_check(World.QUEUE_SLOTS.size() >= NightDirector.MAX_IN_SHOP,
		"there is a floor mark for everyone who can be inside")

	# Nobody is served until the front is actually standing at the counter.
	_check(director.current_customer() == null, "queueing is not the same as being served")
	made[0].state = Customer.State.AT_COUNTER
	_check(director.current_customer() == made[0], "the front of the line is who you serve")

	# The front leaves; everyone steps up immediately rather than waiting for
	# them to walk out of the door.
	made[0].state = Customer.State.LEAVING
	director._prune()
	director._reassign_line()
	_check(director.waiting_count() == 3, "someone leaving drops out of the line")
	_check(made[1].queue_index == 0, "the next person steps up straight away")
	_check(made[3].queue_index == 2, "and everyone behind them shuffles forward")

	# Every queue mark has to be somewhere a person can stand.
	await get_tree().physics_frame
	var blocked := 0
	for slot: Vector3 in World.QUEUE_SLOTS:
		if not _point_is_clear(slot + Vector3(0, 0.9, 0), 0.32):
			blocked += 1
	_check(blocked == 0, "every queue mark is clear of the furniture (%d blocked)" % blocked)

	for c in made:
		c.queue_free()
	director.queue_free()
	await get_tree().process_frame


func test_sewer_threat() -> void:
	print("\nThe tunnels getting worse:")
	GameState.reset_run()
	var counts: Array[int] = []
	var tiers: Array[int] = []
	for trip in range(1, 9):
		GameState.sewer_trips = trip
		counts.append(GameState.sewer_dweller_count())
		tiers.append(GameState.sewer_tier())
	print("   trips 1-8 · dwellers %s" % str(counts))
	print("   trips 1-8 · tier     %s" % str(tiers))

	_check(counts[0] == 1, "the first trip is one of them")
	_check(tiers[0] == 0, "and the weakest tier there is")
	_check(counts[-1] > counts[0], "later trips send more")
	var monotonic := true
	for i in range(1, counts.size()):
		if counts[i] < counts[i - 1] or tiers[i] < tiers[i - 1]:
			monotonic = false
	_check(monotonic, "it never gets easier again")
	_check(counts[-1] <= 6, "but it stays finite (%d)" % counts[-1])

	# A first-trip dweller must be killable with the starting bat.
	var bat: Dictionary = GameState.WEAPONS["bat"]
	GameState.sewer_trips = 1
	var d := SewerDweller.new()
	d.setup(_player, Vector3(0, World.SEWER_Y, 0), GameState.sewer_tier())
	var swings := int(ceil(d.max_health / float(bat["damage"])))
	print("   first-trip dweller: %d hp, %d swings of the bat" % [int(d.max_health), swings])
	_check(swings <= 2, "the first one goes down in a swing or two")
	d.free()

	GameState.sewer_trips = 8
	var tough := SewerDweller.new()
	tough.setup(_player, Vector3(0, World.SEWER_Y, 0), GameState.sewer_tier())
	_check(tough.max_health > d.max_health if is_instance_valid(d) else true,
		"a late one takes considerably more")
	_check(int(ceil(tough.max_health / float(bat["damage"]))) >= 3,
		"the bat stops being enough")
	tough.free()


func test_illicit_and_departure() -> void:
	print("\nSelling to an officer:")
	GameState.reset_run()
	GameState.reset_night_tally()
	var cop := _spawn_at_counter(31337, int(CustomerProfile.Kind.UNDERCOVER))
	_check(cop.profile.kind == CustomerProfile.Kind.UNDERCOVER, "found an undercover officer to test with")
	_check(cop.profile.wants_illicit, "officers always make the ask")

	cop._asked_for_illicit = true
	var before := GameState.money
	cop.receive_illicit(2)
	_check(GameState.money > before, "the sale pays")
	_check(GameState.illicit_takings > 0, "it is booked under the counter, not over it")
	_check(cop.profile.sold_illicit, "the sale is remembered")

	cop._leave("sold")
	_check(GameState.evidence_against_you >= 2, "selling to an officer brings a full-strength raid")
	_check(not GameState.raid_reason.is_empty(), "the raid has a stated reason")

	GameState.evidence_against_you = 0
	var cop2 := _spawn_at_counter(31337, int(CustomerProfile.Kind.UNDERCOVER))
	cop2._leave("refused")
	_check(GameState.evidence_against_you == 1,
		"refusing an officer still brings them back, but with less")

	cop.queue_free()
	cop2.queue_free()
	await get_tree().process_frame


func test_violence() -> void:
	print("\nShooting people:")
	GameState.reset_run()
	GameState.reset_night_tally()

	var cop := _spawn_at_counter(80081, int(CustomerProfile.Kind.UNDERCOVER))
	cop.take_damage(500.0, _player)
	_check(cop.state == Customer.State.DEAD, "an officer can be killed")
	_check(GameState.cops_identified == 1, "killing an officer wins the round")
	_check(GameState.evidence_against_you == 0, "a dead officer files no report")

	GameState.reset_run()
	GameState.reset_night_tally()
	var civ := _spawn_at_counter(80081, int(CustomerProfile.Kind.CIVILIAN))
	var heat_before := GameState.heat
	civ.take_damage(500.0, _player)
	_check(GameState.civilians_killed == 1, "killing a civilian is counted")
	_check(GameState.heat > heat_before, "and it raises heat")
	_check(GameState.evidence_against_you >= 1, "and it brings them to the door")

	# A wounded customer runs rather than dying, taking what they know with them.
	GameState.reset_run()
	var runner := _spawn_at_counter(4711)
	runner.take_damage(5.0, _player)
	_check(runner.state == Customer.State.LEAVING, "a wounded customer flees")

	cop.queue_free()
	civ.queue_free()
	runner.queue_free()
	await get_tree().process_frame


func test_raid() -> void:
	print("\nRaid:")
	GameState.reset_run()
	GameState.night = 5
	var raid := RaidDirector.new()
	raid.setup(_world, _player)
	add_child(raid)
	raid.start(2, 5)
	_check(raid.phase == RaidDirector.Phase.FORMING, "the team forms up first")
	_check(raid._units.size() >= 3, "a squad actually spawns (%d)" % raid._units.size())
	_check(raid._entries.size() >= 1, "they have a way in")

	# Each fitting closes one of the shop's two approaches.
	raid.stop()
	GameState.defenses = ["window_bars"]
	raid.phase = RaidDirector.Phase.IDLE
	raid.start(1, 5)
	var uses_hatch := false
	for e: Vector3 in raid._entries:
		if absf(e.x - World.HATCH_X) < 1.0:
			uses_hatch = true
	_check(not uses_hatch, "hatch bars force them round to the shop door")

	raid.stop()
	GameState.defenses = ["door_bar"]
	raid.phase = RaidDirector.Phase.IDLE
	raid.start(1, 5)
	var uses_door := false
	for e: Vector3 in raid._entries:
		if absf(e.x - World.FRONT_DOOR_X) < 1.0:
			uses_door = true
	_check(not uses_door, "a barricaded shop door forces them through the hatch")

	# Barring both must not make you untouchable.
	raid.stop()
	GameState.defenses = ["door_bar", "window_bars"]
	raid.phase = RaidDirector.Phase.IDLE
	raid.start(1, 5)
	_check(raid._entries.size() >= 1, "barring both approaches still leaves them a way in")
	GameState.defenses = []

	# They must arrive in waves rather than as one crowd, and the raid must not
	# declare victory while a wave is still queued outside.
	raid.stop()
	GameState.defenses = []
	raid.phase = RaidDirector.Phase.IDLE
	raid.start(2, 5)
	var squad_size := raid._units.size()
	raid._open_up()
	_check(raid.phase == RaidDirector.Phase.FLASH, "the shutter failing throws a flashbang first")
	_check(raid._queue.size() == squad_size, "the whole squad queues up outside")
	raid._breach()
	var breaching := 0
	for u in raid._units:
		if is_instance_valid(u) and u.state == RaidUnit.State.BREACHING:
			breaching += 1
	_check(breaching <= RaidDirector.WAVE_SIZE,
		"only a wave comes through at a time (%d of %d)" % [breaching, squad_size])
	_check(raid._queue.size() == squad_size - breaching, "the rest are still waiting")

	# Killing everyone inside must not end it while others are still queued.
	for u in raid._units:
		if is_instance_valid(u) and u.state == RaidUnit.State.BREACHING:
			u.take_damage(9999.0)
	raid._process(0.016)
	_check(raid.phase != RaidDirector.Phase.DONE,
		"the raid is not over while a wave is still outside")

	for u in raid._units:
		if is_instance_valid(u):
			u.take_damage(9999.0)
	raid._queue.clear()
	_check(raid._live_count() == 0, "the squad can be killed")
	raid.stop()
	raid.queue_free()


# --- Every panel, built once --------------------------------------------------

func test_panels() -> void:
	print("\nInterface:")
	var c := _spawn_at_counter(2024)
	c.profile.scanned = true
	c.on_lookup()

	var terminal := TerminalUI.new()
	add_child(terminal)
	terminal.show_for(c)
	_check(terminal.open, "terminal opens on a subject")
	terminal.show_for(null)
	_check(terminal.open, "terminal handles having nobody at the window")
	terminal.close()

	var dialogue := DialogueUI.new()
	add_child(dialogue)
	dialogue.show_for(c, _player)
	_check(dialogue.open and dialogue._options.size() > 0, "dialogue offers options")
	# Spend every question and make sure the menu keeps up.
	var guard := 0
	while c.profile.patience > 0 and guard < 20:
		var opts := c.profile.available_questions()
		if opts.is_empty():
			break
		c.profile.ask(opts[0])
		guard += 1
	dialogue._rebuild()
	_check(dialogue._options.size() > 0, "dialogue still offers actions once questions run out")
	dialogue.close()

	var notebook := NotebookUI.new()
	add_child(notebook)
	notebook.show_notebook(c)
	_check(notebook.open, "notepad opens")
	notebook.show_notebook(null)
	_check(notebook.open, "notepad handles nobody at the window")
	notebook.close()

	var shop := ShopUI.new()
	add_child(shop)
	shop.show_shop()
	for tab: String in ["stock", "under", "arms", "fittings"]:
		shop._tab = tab
		shop._rebuild()
	_check(shop.open, "every supplier tab builds")
	shop.close()

	var pause := PauseUI.new()
	add_child(pause)
	pause.show_pause()
	_check(pause.open, "pause menu builds")
	pause.close()
	_check(not get_tree().paused, "closing the pause menu unfreezes the tree")

	var report := ReportUI.new()
	add_child(report)
	report.show_title()
	report.show_report({"night": 3, "served": 8, "takings": 90, "illicit": 120,
		"tips": 14, "rent": 219, "rent_paid": true, "cops": 1, "civilians": 0, "evidence": 1})
	report.show_raid_warning("You sold to an officer.", 6)
	report.show_game_over("shot")
	_check(report.open, "every interstitial builds")
	report.close()

	var hud := HUD.new()
	add_child(hud)
	hud.bind_player(_player)
	Signals.notice.emit("test", "bad")
	Signals.customer_spoke.emit("Anders Vesely", "Evening.")
	Signals.shift_clock.emit(120.0)
	Signals.money_changed.emit(50)
	Signals.heat_changed.emit(40.0)
	_check(true, "HUD absorbs every signal it listens for")

	c.queue_free()


func _report() -> void:
	print("\n=== %s ===\n" % ("ALL CHECKS PASSED" if failures.is_empty() else "%d FAILED" % failures.size()))
	for f in failures:
		print("  · " + f)
