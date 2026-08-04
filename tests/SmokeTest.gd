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
	print("\nA transaction:")
	GameState.reset_run()
	GameState.reset_night_tally()
	var c := _spawn_at_counter(555)
	var before := GameState.money

	var expected := 0
	for id: String in c.profile.order:
		expected += int(GameState.ITEMS[id]["price"])

	for id: String in c.profile.order:
		_check(c.receive_item(id), "customer accepts the %s they asked for" % id)
	_check(GameState.money >= before + expected, "shelf goods are paid for")
	_check(GameState.customers_served == 1, "the sale is counted")

	# They should not accept something they never asked for.
	var unwanted := ""
	for id: String in GameState.ITEMS:
		if not c.profile.order.has(id):
			unwanted = id
			break
	if not unwanted.is_empty():
		_check(not c.receive_item(unwanted), "customer refuses goods they didn't ask for")

	# The scanner and the terminal each open up their own channel of evidence.
	c.on_scan(_player)
	_check(c.profile.scanned, "sweep is recorded")
	c.on_lookup()
	_check(c.profile.looked_up, "file lookup is recorded")
	for id: String in c.profile.tells_on_channel(Tells.CHANNEL_SCANNER):
		_check(c.profile.tell_state(id)["discovered"], "sweeping reveals %s" % id)
	for id: String in c.profile.tells_on_channel(Tells.CHANNEL_TERMINAL):
		_check(c.profile.tell_state(id)["discovered"], "the file reveals %s" % id)

	c.queue_free()
	await get_tree().process_frame


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
		if e.z < 0.0:
			uses_hatch = true
	_check(not uses_hatch, "hatch bars force them round to the side door")

	raid.stop()
	GameState.defenses = ["door_bar"]
	raid.phase = RaidDirector.Phase.IDLE
	raid.start(1, 5)
	var uses_side := false
	for e: Vector3 in raid._entries:
		if e.x > World.SHOP_HALF_X - 1.5:
			uses_side = true
	_check(not uses_side, "a barricaded side door forces them through the hatch")

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
