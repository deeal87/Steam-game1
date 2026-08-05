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
	test_classes_resolve()
	test_achievements()
	test_audio()
	test_textures()
	test_icon()
	test_evidence()
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


## For assertions inside a loop, where printing a PASS line per iteration would
## bury the run. Silent unless it fails.
func _check_quiet(ok: bool, label: String) -> void:
	if not ok:
		print("  FAIL  %s" % label)
		failures.append(label)


## Every `class_name` in the project has to be in Godot's global class list.
##
## This exists because the failure it catches has now happened twice and is
## invisible both times. A script whose class is missing from the cache makes
## every file that names it fail to *parse* — so the node built from it comes
## out as a bare Node with none of its behaviour, no assertion necessarily
## fails, and the suite reports success. It cost a whole debugging session the
## first time (PauseUI) and would have shipped a game with no bodies in it the
## second (Body).
##
## Walking the source rather than listing names by hand means a new script is
## covered the moment it is written, which is exactly when this goes wrong.
func test_classes_resolve() -> void:
	print("Every class resolves:")
	var declared: Array[String] = []
	_collect_class_names("res://scripts", declared)
	declared.sort()

	var known := {}
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		known[str(entry["class"])] = true

	var missing: Array[String] = []
	for name: String in declared:
		if not known.has(name):
			missing.append(name)

	print("   %d classes declared under scripts/" % declared.size())
	_check(declared.size() > 20, "found the source tree (%d classes)" % declared.size())
	_check(missing.is_empty(),
		"every one is in the global class list%s" %
			("" if missing.is_empty() else " — missing: %s (reimport the project)" % ", ".join(missing)))


func _collect_class_names(dir_path: String, into: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			_collect_class_names(full, into)
		elif entry.ends_with(".gd"):
			var f := FileAccess.open(full, FileAccess.READ)
			if f != null:
				# Only the declaration, which is always the first non-comment
				# statement in the file when it is present at all.
				while not f.eof_reached():
					var line := f.get_line().strip_edges()
					if line.begins_with("class_name "):
						into.append(line.substr(11).split(" ")[0].strip_edges())
						break
					if line.begins_with("func ") or line.begins_with("var "):
						break
				f.close()
		entry = dir.get_next()
	dir.list_dir_end()


## Achievements have to work with no Steam at all, because that is every build
## this repository produces. The Steam calls are a mirror, never the source.
func test_achievements() -> void:
	print("\nAchievements:")
	Achievements.reset_all()
	var ids: Array = Achievements.CATALOGUE.keys()
	print("   %d in the catalogue · Steam connected: %s"
		% [ids.size(), "yes" if Achievements.steam_connected() else "no"])

	# API ids are what you type into Steamworks and are permanent once shipped.
	var bad_ids: Array[String] = []
	for id: String in ids:
		if id != id.to_upper() or id.contains(" "):
			bad_ids.append(id)
		var entry: Dictionary = Achievements.CATALOGUE[id]
		for key: String in ["name", "desc", "hidden"]:
			if not entry.has(key):
				bad_ids.append("%s.%s" % [id, key])
	_check(bad_ids.is_empty(), "every id is a valid Steamworks API name%s" %
		("" if bad_ids.is_empty() else " — %s" % ", ".join(bad_ids)))

	# Nothing rewards shooting people. The game charges for that everywhere else
	# and a trophy for it would undercut the lot.
	var rewards_violence := false
	for id: String in ids:
		var text := str(Achievements.CATALOGUE[id]["desc"]).to_lower()
		if text.contains("kill") or text.contains("shoot"):
			rewards_violence = true
	_check(not rewards_violence, "nothing pays you for shooting somebody")

	# Unlocking works, is idempotent, and survives a reload.
	_check(not Achievements.has("FIRST_NIGHT"), "starts locked")
	_check(Achievements.unlock("FIRST_NIGHT"), "unlocks once")
	_check(not Achievements.unlock("FIRST_NIGHT"), "and not twice")
	_check(Achievements.has("FIRST_NIGHT"), "and stays unlocked")
	_check(not Achievements.unlock("NOT_A_REAL_ID"), "an unknown id does nothing")

	Achievements._earned.clear()
	Achievements.load_progress()
	_check(Achievements.has("FIRST_NIGHT"), "and it survives a reload")

	# Hidden ones keep their description back until earned, or the list is a
	# walkthrough for the one thing in the game worth finding yourself.
	var hidden_before := ""
	for a: Dictionary in Achievements.listing():
		if str(a["id"]) == "MASTER":
			hidden_before = str(a["name"])
	_check(hidden_before == "???", "a hidden one does not name itself first")
	Achievements.unlock("MASTER")
	var hidden_after := ""
	for a: Dictionary in Achievements.listing():
		if str(a["id"]) == "MASTER":
			hidden_after = str(a["name"])
	_check(hidden_after != "???", "and does once you have found it")

	# The conditions, driven the way the game drives them.
	Achievements.reset_all()
	GameState.reset_run()
	Achievements.check_night_end({
		"rent_paid": true, "illicit": 0, "served": 6,
		"bill": {"dismissed_count": 0, "killed_count": 0},
		"bodies": {}, "reputation": 100.0,
	})
	_check(Achievements.has("FIRST_NIGHT"), "surviving a shift pays out")
	_check(Achievements.has("MADE_THE_RENT"), "so does making rent on shelf trade alone")
	_check(Achievements.has("CLEAN_READ"), "and a night with nobody wronged")
	_check(Achievements.has("SPOTLESS"), "and one with your name untouched")

	Achievements.reset_all()
	Achievements.check_night_end({
		"rent_paid": true, "illicit": 220, "served": 6,
		"bill": {"dismissed_count": 1, "killed_count": 0},
		"bodies": {}, "reputation": 93.0,
	})
	_check(not Achievements.has("MADE_THE_RENT"), "selling under the counter does not count")
	_check(not Achievements.has("CLEAN_READ"), "and throwing somebody out is not clean")
	_check(not Achievements.has("SPOTLESS"), "and a dented name is not spotless")

	# A body left on the floor is not a clean night either.
	Achievements.reset_all()
	Achievements.check_night_end({
		"rent_paid": true, "illicit": 0, "served": 6,
		"bill": {"dismissed_count": 0, "killed_count": 0},
		"bodies": {"civilians": 1, "officers": 0}, "reputation": 100.0,
	})
	_check(not Achievements.has("CLEAN_READ"),
		"leaving one on the floor is not a clean night")

	# Running for it is not surviving it.
	Achievements.reset_all()
	Achievements.check_raid_survived(true)
	_check(not Achievements.has("SURVIVED_RAID"), "going down the ladder is not surviving")
	Achievements.check_raid_survived(false)
	_check(Achievements.has("SURVIVED_RAID"), "standing there is")

	Achievements.reset_all()
	Achievements.check_body_disposed(true)
	_check(not Achievements.has("NO_WITNESSES"), "somebody saw it, so it does not count")
	Achievements.check_body_disposed(false)
	_check(Achievements.has("NO_WITNESSES"), "nobody saw it, so it does")

	# With no Steam the push is a no-op that reports honestly rather than
	# throwing. This is the normal case, not the edge case.
	_check(not Achievements._push_to_steam("FIRST_NIGHT"),
		"pushing to a Steam that is not there fails quietly")
	_check(not Achievements.steam_connected(), "and the interface can say so")

	Achievements.reset_all()
	GameState.reset_run()


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


## The icon is the one generated asset that has to exist as a file on disk
## before a build runs, which means it can go stale without anything noticing.
## These checks are mostly here to catch that.
func test_icon() -> void:
	print("\nThe icon:")
	for size: int in [16, 32, 256]:
		var img := ProcIcon.build(size)
		_check(img != null and img.get_width() == size and img.get_height() == size,
			"draws at %d×%d" % [size, size])

	# It has to be a lit window in the dark at *every* size, not just the big
	# one. If the figure or the frame ever grows enough to swallow the light,
	# the small icons go black and this is the only thing that would say so.
	for size: int in [16, 24, 32, 48, 64, 128, 256]:
		var img := ProcIcon.build(size)
		var hatch := img.get_pixel(int(size * 0.26), int(size * 0.36))
		var corner := img.get_pixel(int(size * 0.03), int(size * 0.03))
		_check_quiet(hatch.get_luminance() > corner.get_luminance() + 0.25,
			"at %dpx the hatch is not clearly brighter than the corner (%.2f vs %.2f)"
				% [size, hatch.get_luminance(), corner.get_luminance()])
	_check(true, "the hatch reads brighter than the night at every size")

	# And the committed files have to match what the generator produces now,
	# or the shipped build carries an icon nobody has looked at.
	var on_disk := Image.new()
	var err := on_disk.load("res://icon.png")
	_check(err == OK, "icon.png is present in the project")
	if err == OK:
		var fresh := ProcIcon.build(on_disk.get_width())
		_check(on_disk.get_size() == fresh.get_size(),
			"and is the size the generator makes (%v)" % on_disk.get_size())
		_check(_images_match(on_disk, fresh),
			"and is up to date — rerun tools/MakeIcon.tscn if this fails")


## There are nine keys. If the menu ever lists more than nine things, the ones
## past the ninth cannot be chosen at all — and because the actions are laid out
## last, the option that silently disappears is "tell them to move on". Which is
## a decision the whole game is about.
##
## This is checked against the worst person the generator can produce, not
## against a typical one: every tell discovered, everything on offer at once.
func _test_dialogue_fits() -> void:
	var dialogue := DialogueUI.new()
	add_child(dialogue)

	var worst := 0
	var worst_actions := 0
	var missing_action := 0
	for i in 400:
		var p := ProfileGenerator.generate(i * 7 + 3, 9, 0.5)
		for id: String in p.tells:
			p.discover(id)
		var c := Customer.new()
		c.setup(p, _world)
		add_child(c)
		# The state that puts the most on screen at once: they have asked, you
		# are holding stock, so both the sell and the refuse rows are live.
		c._asked_for_illicit = true
		_player.held_illicit = 2

		dialogue.show_for(c, _player)
		worst = maxi(worst, dialogue._options.size())
		var actions := 0
		var can_dismiss := false
		for o: Dictionary in dialogue._options:
			var t := str(o["data"]["type"])
			if t != "ask" and t != "page":
				actions += 1
			if t == "dismiss":
				can_dismiss = true
		worst_actions = maxi(worst_actions, actions)
		if not can_dismiss:
			missing_action += 1
		dialogue.close()
		c.queue_free()

	_player.held_illicit = 0
	print("   worst case: %d rows, %d of them actions, on %d keys" %
		[worst, worst_actions, DialogueUI.MAX_OPTIONS])
	_check(worst <= DialogueUI.MAX_OPTIONS,
		"the menu never lists more options than there are keys (%d)" % worst)
	_check(missing_action == 0,
		"and telling somebody to move on is always reachable (%d without it)" % missing_action)

	# Paging has to actually reach the questions it hid, or it is just a
	# prettier way of losing them.
	var busy := ProfileGenerator.generate(31337, 9, 1.0)
	for id: String in busy.tells:
		busy.discover(id)
	var cust := Customer.new()
	cust.setup(busy, _world)
	add_child(cust)
	cust._asked_for_illicit = true
	_player.held_illicit = 2
	dialogue.show_for(cust, _player)

	var wanted := busy.available_questions().size()
	var seen := {}
	for turn in 12:
		for o: Dictionary in dialogue._options:
			if str(o["data"]["type"]) == "ask":
				seen[str(o["data"]["entry"]["id"])] = true
		var pager: Dictionary = {}
		for o: Dictionary in dialogue._options:
			if str(o["data"]["type"]) == "page":
				pager = o
		if pager.is_empty():
			break
		dialogue._choose(pager)
	print("   a full menu offers %d questions; paging reached %d" % [wanted, seen.size()])
	_check(seen.size() == wanted, "every question is reachable by paging (%d of %d)"
		% [seen.size(), wanted])

	_player.held_illicit = 0
	dialogue.close()
	cust.queue_free()
	dialogue.queue_free()


## The evidence database is the content of the game, and almost all of it is
## text that nothing else would ever notice was wrong. A tell missing a field,
## two tells sharing a question id, or a standing question with no answer
## written for it would all show up in play as a blank line and nowhere else.
func test_evidence() -> void:
	print("\nThe evidence:")
	var ids := Tells.all_ids()
	print("   %d tells · %d standing questions" % [ids.size(), Tells.BASE_QUESTIONS.size()])

	var required := ["channel", "label", "weight", "question", "prompt",
		"innocent", "guilty", "cleared_note", "confirmed_note"]
	var incomplete: Array[String] = []
	for id: String in ids:
		var t := Tells.get_tell(id)
		for key: String in required:
			if not t.has(key) or str(t[key]).is_empty():
				incomplete.append("%s.%s" % [id, key])
	_check(incomplete.is_empty(), "every tell is complete%s" %
		("" if incomplete.is_empty() else " — missing %s" % ", ".join(incomplete)))

	# A shared question id would make one tell's question resolve the other.
	var seen := {}
	var clashes: Array[String] = []
	for id: String in ids:
		var q: String = Tells.get_tell(id)["question"]
		if seen.has(q):
			clashes.append("%s and %s both use %s" % [seen[q], id, q])
		seen[q] = id
		if Tells.BASE_QUESTIONS.has(q):
			clashes.append("%s collides with a standing question (%s)" % [id, q])
	_check(clashes.is_empty(), "no two questions share an id%s" %
		("" if clashes.is_empty() else " — %s" % "; ".join(clashes)))

	# Weights have to mean something. A tell at 3 is close to conclusive, so
	# nothing may sit above that, and nothing may be worth nothing.
	var bad_weight: Array[String] = []
	for id: String in ids:
		var w := int(Tells.get_tell(id)["weight"])
		if w < 1 or w > 3:
			bad_weight.append("%s (%d)" % [id, w])
	_check(bad_weight.is_empty(), "every weight is in range%s" %
		("" if bad_weight.is_empty() else " — %s" % ", ".join(bad_weight)))

	# Every channel has to carry enough that a player who works one of them
	# still meets people they have not read before.
	for channel: String in [Tells.CHANNEL_SCANNER, Tells.CHANNEL_TERMINAL,
			Tells.CHANNEL_BEHAVIOUR]:
		var n := Tells.ids_for_channel(channel).size()
		_check(n >= 10, "%s carries %d tells" % [channel, n])

	# Standing questions need an answer written for them. A question id with no
	# arm in _write_base_answers stores an empty string and says nothing at all.
	var silent: Array[String] = []
	var mismatched: Array[String] = []
	for i in 300:
		var p := ProfileGenerator.generate(i * 41 + 11, 3, 0.5)
		for qid: String in Tells.BASE_QUESTIONS:
			var ans: Dictionary = p.base_answers.get(qid, {})
			if ans.is_empty() or str(ans.get("text", "")).is_empty():
				if not silent.has(qid):
					silent.append(qid)
			# The field named by the question has to exist on the profile, or
			# the answer is being checked against nothing.
			var field: String = Tells.BASE_QUESTIONS[qid]["field"]
			if p.get(field) == null and not mismatched.has(qid):
				mismatched.append(qid)
	_check(silent.is_empty(), "every standing question gets an answer%s" %
		("" if silent.is_empty() else " — silent: %s" % ", ".join(silent)))
	_check(mismatched.is_empty(), "and reads a field that exists%s" %
		("" if mismatched.is_empty() else " — missing: %s" % ", ".join(mismatched)))

	_test_file_consistency()


## The terminal must never claim something the file does not show. If a tell's
## innocent explanation cites a line in the record, and the record has been
## emptied by another tell, the honest answer reads as a lie and the player is
## being punished for checking.
func _test_file_consistency() -> void:
	var coexisting: Array[String] = []
	var scrubbed_with_record := 0
	var scrubbed := 0
	for i in 4000:
		var p := ProfileGenerator.generate(i * 13 + 7, 5, 0.5)
		for pair: Array in ProfileGenerator.CONFLICTING_TELLS:
			if p.has_tell(pair[0]) and p.has_tell(pair[1]):
				var label := "%s + %s" % [pair[0], pair[1]]
				if not coexisting.has(label):
					coexisting.append(label)
		if p.has_tell("record_scrubbed"):
			scrubbed += 1
			if not p.record.is_empty():
				scrubbed_with_record += 1
	_check(coexisting.is_empty(), "tells that contradict each other never coexist%s" %
		("" if coexisting.is_empty() else " — %s" % ", ".join(coexisting)))
	_check(scrubbed > 0, "the sample contained scrubbed records to check (%d)" % scrubbed)
	_check(scrubbed_with_record == 0,
		"a scrubbed record really is empty (%d of %d had entries)"
			% [scrubbed_with_record, scrubbed])


## Compares two images on a coarse grid rather than pixel by pixel: PNG round
## trips are lossless but the imported copy can come back in a different format,
## and a handful of sample points is enough to catch a stale icon.
func _images_match(a: Image, b: Image) -> bool:
	if a.get_size() != b.get_size():
		return false
	var step: int = maxi(1, a.get_width() / 24)
	for y in range(0, a.get_height(), step):
		for x in range(0, a.get_width(), step):
			var pa := a.get_pixel(x, y)
			var pb := b.get_pixel(x, y)
			if absf(pa.r - pb.r) > 0.02 or absf(pa.g - pb.g) > 0.02 or absf(pa.b - pb.b) > 0.02:
				return false
	return true


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

	# Every branch, end to end. A junction that looks fine in the code and is
	# bricked up in the world is the failure mode this whole test exists for —
	# the tunnels were a sealed box once already.
	var mid_bottom: Vector3 = _world.anchors["sewer_mid_bottom"]
	_check(_point_is_clear(mid_bottom + Vector3(0, 0.9, 0), 0.30),
		"the middle ladder does not drop you inside a wall")

	for branch: Array in [
		["the dogleg to the far exit", World.SEWER_EXIT.x, World.SEWER_EXIT.z, -1.0],
		["the dogleg to the middle ladder", World.SEWER_MID_EXIT.x, World.SEWER_MID_EXIT.z, -1.0],
		["the spur off the north side", World.SEWER_SPUR_X, World.SEWER_SPUR_END_Z, 1.0],
	]:
		var at_x: float = branch[1]
		var to_z: float = branch[2]
		var step: float = branch[3]
		var leg_blocked := 0
		var probed := 0
		var z: float = World.MANHOLE.z
		while (z > to_z) if step < 0.0 else (z < to_z):
			probed += 1
			if not _point_is_clear(Vector3(at_x, bottom.y + 0.9, z), 0.28):
				leg_blocked += 1
			z += step
		_check(leg_blocked == 0, "%s is clear (%d of %d blocked)"
			% [str(branch[0]), leg_blocked, probed])

	# The crate has to be reachable, or the reward for walking a dead end is a
	# wall with a light on it.
	var cache: Vector3 = _world.anchors["sewer_cache"]
	_check(_point_is_clear(cache + Vector3(0, 0.9, -1.6), 0.30),
		"there is somewhere to stand at the crate")

	# You must also be able to stand up in it.
	_check(_point_is_clear(bottom + Vector3(0, 1.5, 0), 0.25), "there is headroom down there")

	# Each junction has to be open in both directions, not just along whichever
	# axis the probe happened to walk.
	var junctions: Array = _world.anchors.get("sewer_junctions", [])
	var sealed := 0
	for j: Vector3 in junctions:
		if not _point_is_clear(j + Vector3(0, 0.9, 0), 0.30):
			sealed += 1
	_check(junctions.size() == 3, "all three junctions are registered (%d)" % junctions.size())
	_check(sealed == 0, "and every one of them is open (%d bricked up)" % sealed)


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
	var names: Array = Music.BASE.keys()
	var lengths: Array[int] = []
	var built := 0
	for name: String in names:
		var layer: Dictionary = Music._layers.get(name, {})
		var p: AudioStreamPlayer = layer.get("player")
		if p != null and p.stream != null and (p.stream as AudioStreamWAV).data.size() > 0:
			built += 1
			lengths.append((p.stream as AudioStreamWAV).data.size())
	_check(built == names.size(), "all %d layers synthesise (%d built)" % [names.size(), built])
	# They are mixed by volume while playing together, so any difference in
	# length would drift them apart over a night.
	var same := true
	for l in lengths:
		if l != lengths[0]:
			same = false
	_check(same, "every layer is exactly the same length, so they stay in sync")
	for name: String in names:
		var stream: AudioStreamWAV = Music._layers[name]["player"].stream
		_check(stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "%s loops" % name)

	# Every layer a section asks for has to actually exist, or that section
	# silently plays less than it was written to.
	var missing: Array[String] = []
	for section: Dictionary in Music.SECTIONS:
		for name: String in section:
			if not Music.BASE.has(name):
				missing.append(name)
	_check(missing.is_empty(), "every section names layers that exist%s" %
		("" if missing.is_empty() else " (missing %s)" % ", ".join(missing)))
	_check(int(Music.SECTIONS[0].size()) < int(Music.SECTIONS[-1].size()),
		"the arrangement is thicker at the top than the bottom (%d layers vs %d)" %
			[int(Music.SECTIONS[0].size()), int(Music.SECTIONS[-1].size())])

	_test_sections()

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


## The arrangement has to walk, not jump, and it has to be willing to come back
## down. Both of those are what separate a score that develops from a score that
## is four faders being pushed around.
func _test_sections() -> void:
	var top: int = Music.SECTIONS.size() - 1

	# Climbing: hold the tension at full and count how many bars it takes to
	# arrive. One step per bar means the number of steps is the number of bars.
	var s := 0
	var steps := 0
	for bar in 20:
		var next: int = Music.wanted_section(s, 1.0)
		if next == s:
			break
		_check_quiet(absi(next - s) == 1, "the arrangement only ever moves one step")
		s = next
		steps += 1
	_check(s == top, "full tension eventually reaches the top section (%d)" % s)
	_check(steps == top, "and takes %d bars to get there rather than jumping" % top)

	# Falling: drop the tension to nothing and it has to come all the way back.
	steps = 0
	for bar in 20:
		var next: int = Music.wanted_section(s, 0.0)
		if next == s:
			break
		s = next
		steps += 1
	_check(s == 0, "and it unwinds back to quiet when the night calms down")
	_check(steps == top, "one step at a time on the way down too")

	# Hysteresis: a tension that is enough to *stay* in a section must not be
	# enough to have *entered* it, or the score flaps on the boundary.
	var flaps := 0
	for i in Music.CLIMB.size():
		if float(Music.FALL[i]) >= float(Music.CLIMB[i]):
			flaps += 1
	_check(flaps == 0, "climbing costs more tension than staying does")
	var edge := (float(Music.CLIMB[0]) + float(Music.FALL[0])) * 0.5
	_check(Music.wanted_section(0, edge) == 0 and Music.wanted_section(1, edge) == 1,
		"so a tension between the two thresholds leaves the section where it is")

	# The night bias. Same tension, later night, higher floor.
	Music.set_night(1)
	var early := Music._night_bias
	Music.set_night(10)
	var late := Music._night_bias
	_check(late > early, "later nights bias the arrangement upward (%.2f vs %.2f)" % [late, early])
	_check(Music.wanted_section(0, 0.10 + late) > Music.wanted_section(0, 0.10 + early),
		"a quiet moment on night 10 is not as quiet as one on night 1")
	Music.set_night(1)

	# The hour of the night thins the pad and lifts the sub. Checked as a trim
	# rather than by ear, but it is the only part that changes without tension.
	Music.set_progress(0.0)
	var pad_open := Music._hour_trim("bed")
	var sub_open := Music._hour_trim("deep")
	Music.set_progress(1.0)
	_check(Music._hour_trim("bed") < pad_open, "the pad recedes as it gets late")
	_check(Music._hour_trim("deep") > sub_open, "and the sub comes up under it")
	Music.set_progress(0.0)

	# Layers must never be stopped while a scene is running. A stopped stream
	# restarts at zero, and one layer a bar out of phase with the rest is the
	# one failure here that would be obvious to every player and invisible in a
	# volume check.
	Music.play_shift()
	Music.set_tension(1.0)
	for bar in 6:
		Music._process(Music.bar_seconds())
	var stopped: Array[String] = []
	for name: String in Music.BASE:
		if not (Music._layers[name]["player"] as AudioStreamPlayer).playing:
			stopped.append(name)
	_check(stopped.is_empty(), "no layer is ever stopped mid-shift%s" %
		("" if stopped.is_empty() else " (stopped: %s)" % ", ".join(stopped)))
	_check(Music.section() > 0, "and six bars of full tension has moved the arrangement (%d)"
		% Music.section())

	# But the end of the night does have to release them, or they keep mixing
	# into a scene that is over.
	Music.stop_all()
	for i in 40:
		Music._process(0.25)
	var still_going: Array[String] = []
	for name: String in Music.BASE:
		if (Music._layers[name]["player"] as AudioStreamPlayer).playing:
			still_going.append(name)
	_check(still_going.is_empty(), "and every layer lets go once the night ends%s" %
		("" if still_going.is_empty() else " (still playing: %s)" % ", ".join(still_going)))


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
	await test_pushing_in()


## Somebody impatient enough will step in front of the person ahead of them.
##
## The rule that matters most here is the last one: how pushy somebody is must
## have nothing to do with whether they are police. A queue-jumper who turned
## out to be an officer more often than not would answer the only question the
## game asks, for free, through a behaviour nobody can avoid noticing.
func test_pushing_in() -> void:
	print("\nPushing in:")
	GameState.reset_run()
	var director := NightDirector.new()
	director.setup(_world)
	add_child(director)

	var made: Array[Customer] = []
	for i in 4:
		var p := ProfileGenerator.generate(7000 + i * 31, 2, 0.0)
		# Everyone waits their turn except the person at the back.
		p.pushiness = 1.0 if i == 3 else 0.0
		var c := Customer.new()
		c.setup(p, _world)
		_world.add_child(c)
		c.state = Customer.State.QUEUEING
		made.append(c)
		director._present.append(c)
		director._on_finished_shopping(c)

	# Nobody has been standing there yet, so nobody has a grievance.
	director._consider_pushing()
	director._reassign_line()
	_check(made[3].queue_index == 3, "nobody pushes in the moment they join the line")

	# Let the one at the back stew.
	for tick in 400:
		made[3]._wait_behaviour(0.1)
	director._consider_pushing()
	director._reassign_line()
	_check(made[3].queue_index == 2, "somebody impatient enough steps forward one place")
	_check(made[2].queue_index == 3, "and the person they stepped in front of drops back")
	_check(made[0].queue_index == 0, "the person being served is never stepped in front of")

	# One swap per tick, so a line can shuffle but never invert at once.
	for tick in 400:
		made[3]._wait_behaviour(0.1)
	director._consider_pushing()
	director._reassign_line()
	_check(made[3].queue_index == 1, "and only one place at a time")

	# Patient people never do it, however long they stand there.
	var patient := made[0]
	patient.state = Customer.State.QUEUEING
	patient.profile.pushiness = 0.0
	for tick in 2000:
		patient._wait_behaviour(0.1)
	_check(not patient.ready_to_push(made[1]),
		"somebody easy-going waits all night without trying it")

	# Being pushed past costs the person in front patience, which is what makes
	# a busy queue something you have to actually manage.
	var before := made[2]._time_queued
	made[2].on_pushed_past(made[3])
	_check(made[2]._time_queued > before, "being stepped in front of burns their patience")

	for c in made:
		c.queue_free()
	director.queue_free()
	await get_tree().process_frame

	# The invariant.
	#
	# Judged in standard errors, not in raw difference. A flat tolerance is
	# useless here: uniform draws over three thousand profiles have a standard
	# error near 0.008, so "within 0.05" would wave through a bias six times
	# larger than anything sampling noise could produce. Two standard errors is
	# the line where a difference stops looking like chance.
	# Checked for every trait a player perceives without investigating, not just
	# for pushiness. These are all things you cannot help noticing — how big
	# somebody is, how they behave in a queue — so any of them drifting with
	# `kind` would be a free answer. `cover_strength` and `patience_max` are
	# excluded on purpose: those *are* meant to differ, and neither is visible.
	#
	# Two standard errors would normally be a flaky threshold to hold four
	# measurements to. It is not, here, because every one of these comes off a
	# hashed per-person stream: the same seeds give the same numbers on every
	# run, so this is a fixed measurement rather than a sample. A trait drawn
	# from the main stream would move around between runs and eventually trip
	# this — which is exactly how `nerves` was caught.
	var stats := {}
	for field: String in ["height_scale", "bulk_scale", "pushiness", "nerves"]:
		stats[field] = {"cop": 0.0, "civ": 0.0, "cop_sq": 0.0, "civ_sq": 0.0}
	var cop_n := 0
	var civ_n := 0
	for i in 3000:
		var p := ProfileGenerator.generate(i * 29 + 3, 4, 0.5)
		var side := "cop" if p.kind == CustomerProfile.Kind.UNDERCOVER else "civ"
		if side == "cop":
			cop_n += 1
		else:
			civ_n += 1
		for field: String in stats:
			var v: float = p.get(field)
			stats[field][side] += v
			stats[field][side + "_sq"] += v * v

	var leaked: Array[String] = []
	for field: String in stats:
		var s: Dictionary = stats[field]
		var ca: float = float(s["cop"]) / maxf(1.0, float(cop_n))
		var va: float = float(s["civ"]) / maxf(1.0, float(civ_n))
		var cvar: float = maxf(float(s["cop_sq"]) / maxf(1.0, float(cop_n)) - ca * ca, 0.0)
		var vvar: float = maxf(float(s["civ_sq"]) / maxf(1.0, float(civ_n)) - va * va, 0.0)
		# Standard error of the difference of two means. Judged in standard
		# errors rather than as a flat tolerance: these traits have wildly
		# different scales, and a fixed threshold would be far too strict for one
		# and useless for another.
		var sem: float = sqrt(cvar / maxf(1.0, float(cop_n)) + vvar / maxf(1.0, float(civ_n)))
		var sigmas: float = absf(ca - va) / maxf(sem, 0.0000001)
		print("   %-13s officers %.4f · civilians %.4f · %.1f sigma apart" %
			[field, ca, va, sigmas])
		# Two standard errors is where a difference stops looking like chance.
		if sigmas >= 2.0:
			leaked.append("%s (%.1f sigma)" % [field, sigmas])
	_check(leaked.is_empty(), "nothing a player can see says whether they are police%s" %
		("" if leaked.is_empty() else " — leaking: %s" % ", ".join(leaked)))

	# And someone who gives up waiting costs you a little of your name, but far
	# less than being wrong about somebody does.
	GameState.reset_run()
	GameState.note_gave_up_waiting()
	_check(GameState.customers_gave_up == 1, "giving up waiting is counted")
	_check(GameState.reputation < 100.0, "and costs you a little of your name")
	_check(int(GameState.mistake_bill()["total"]) == 0,
		"but is not billed — being slow is not the same as being wrong")
	_check(GameState.ABANDON_REPUTATION < GameState.CLEAN_NIGHT_RECOVERY,
		"and an otherwise clean night still comes out ahead of one of them")
	GameState.reset_run()


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

	# The dead end has to be guarded, or the crate is a free hundred for anyone
	# who knows where it is.
	GameState.reset_run()
	var director := SewerDirector.new()
	director.setup(_world, _player)
	add_child(director)
	_player.global_position = _world.anchors["sewer_shaft_bottom"]

	GameState.sewer_trips = 3
	director._spawn(GameState.sewer_dweller_count(), GameState.sewer_tier())
	var on_spur := 0
	for d2 in director._dwellers:
		if absf(d2.global_position.x - World.SEWER_SPUR_X) < 2.0 \
				and d2.global_position.z > World.MANHOLE.z + 2.0:
			on_spur += 1
	print("   trip 3: %d of %d are waiting down the spur" % [on_spur, director._dwellers.size()])
	_check(director._dwellers.size() > 1, "a later trip sends more than one")
	_check(on_spur >= 1, "and one of them is between you and the crate")
	director._despawn()

	# One dweller and there is nothing on the spur — the whole tunnel is the
	# threat on an early trip, and the crate is the reward for going early.
	GameState.sewer_trips = 1
	director._spawn(GameState.sewer_dweller_count(), GameState.sewer_tier())
	var early_spur := 0
	for d3 in director._dwellers:
		if absf(d3.global_position.x - World.SEWER_SPUR_X) < 2.0 \
				and d3.global_position.z > World.MANHOLE.z + 2.0:
			early_spur += 1
	_check(early_spur == 0, "the first trip leaves the spur clear")
	director._despawn()
	director.queue_free()

	# The crate itself: worth going for, and there exactly once.
	GameState.reset_run()
	var before := GameState.money
	var first := GameState.open_sewer_cache()
	print("   the crate paid %d (a night 1 rent is %d)" % [first, GameState.rent_due()])
	_check(first > 0, "the crate has something in it")
	_check(GameState.money == before + first, "and it reaches your pocket")
	_check(first >= int(float(GameState.rent_due()) * 0.6),
		"worth enough to be an alternative to a risky sale")
	_check(GameState.open_sewer_cache() == 0, "and it is empty the second time")
	_check(GameState.money == before + first, "so the tunnels are not a money printer")
	GameState.reset_run()
	_check(not GameState.sewer_cache_taken, "a fresh run restocks it")


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
	await test_bodies()


## Shooting somebody used to cost a mouse click and an automatic bag. The whole
## point of this system is that it now costs work, done under time pressure,
## with the queue still coming in.
func test_bodies() -> void:
	print("\nWhat you do with the body:")
	GameState.reset_run()
	var director := BodyDirector.new()
	director.setup(_world)
	add_child(director)

	# Shooting somebody leaves them there. No automatic bag, no vanishing.
	var victim := _spawn_at_counter(90210, int(CustomerProfile.Kind.CIVILIAN))
	var bags_before := GameState.body_bags
	victim.take_damage(500.0, _player)
	await get_tree().process_frame
	_check(director.count() == 1, "shooting somebody leaves a body on the floor")
	_check(GameState.body_bags == bags_before, "and does not silently spend a bag")

	var corpse := director.nearest_to(victim.global_position, 3.0)
	_check(corpse != null, "and it is there to be picked up")
	if corpse == null:
		director.queue_free()
		return
	_check(not corpse.bagged, "it starts unbagged, which is the problem")

	# An unbagged body empties your shop.
	var witness := _spawn_at_counter(5150)
	witness.global_position = corpse.global_position + Vector3(1.0, 0, 0)
	var heat_before := GameState.heat
	var rep_before := GameState.reputation
	director._check_timer = 0.0
	director._process(1.0)
	_check(witness.state == Customer.State.LEAVING, "anyone who walks in on one leaves")
	_check(GameState.heat > heat_before, "it raises heat")
	_check(GameState.reputation < rep_before, "and takes your name down")

	# Only once each, or standing next to one would drain you at the frame rate.
	var heat_after := GameState.heat
	director._check_timer = 0.0
	director._process(1.0)
	_check(is_equal_approx(GameState.heat, heat_after),
		"but each of them only reacts once")

	# Bagging costs a bag, and you cannot do it without one.
	GameState.body_bags = 0
	_check(not corpse.bag(), "with no bags left you cannot bag them")
	GameState.body_bags = 2
	_check(corpse.bag(), "with a bag you can")
	_check(GameState.body_bags == 1, "and it costs one (%d left)" % GameState.body_bags)

	# A bagged one is no longer the thing people scream at.
	var calm := _spawn_at_counter(6006)
	calm.global_position = corpse.global_position + Vector3(0.8, 0, 0)
	director._check_timer = 0.0
	director._process(1.0)
	_check(calm.state != Customer.State.LEAVING, "nobody panics at a bagged one")

	# Carrying fills your hands and slows you down.
	_player.held_illicit = 2
	_player.equipped = "bat"
	_check(corpse.take_up(), "a bagged body can be picked up")
	_player.carried_body = corpse
	_player.clear_hands()
	_player.equipped = ""
	_check(_player.held_illicit == 0 and _player.equipped.is_empty(),
		"which empties your hands — no serving, no shooting")
	_check(Player.CARRY_SPEED < Player.SPEED, "and slows you to a walk (%.1f vs %.1f)"
		% [Player.CARRY_SPEED, Player.SPEED])

	# The manhole is the only way one leaves the building.
	var heat_at_disposal := GameState.heat
	corpse.dispose()
	await get_tree().process_frame
	_check(director.count() == 0, "the manhole is where they go")
	_check(GameState.heat < heat_at_disposal, "and getting rid of one takes the edge off")
	_player.carried_body = null

	# Anything still there at five is evidence, and a dead customer is worse
	# than a dead officer because there is nobody to explain it.
	GameState.reset_run()
	var left := Body.new()
	left.setup(Vector3.ZERO, true, "Someone", 1)
	director.adopt(left)
	var officer := Body.new()
	officer.setup(Vector3(2, 0, 0), false, "Someone", 2)
	director.adopt(officer)
	var settled := director.settle_night()
	print("   closing up with 2 on the floor: +%d heat" % int(settled["heat"]))
	_check(int(settled["civilians"]) == 1 and int(settled["officers"]) == 1,
		"the reckoning counts both kinds")
	_check(GameState.evidence_against_you >= 2, "and every one of them is evidence")
	_check(BodyDirector.LEFTOVER_HEAT_CIVILIAN > BodyDirector.LEFTOVER_HEAT_OFFICER,
		"a dead customer costs more than a dead officer (%d vs %d)"
			% [BodyDirector.LEFTOVER_HEAT_CIVILIAN, BodyDirector.LEFTOVER_HEAT_OFFICER])
	_check(not GameState.raid_reason.is_empty(), "and it gives them a reason to come")

	director.clear()
	director.queue_free()
	victim.queue_free()
	witness.queue_free()
	calm.queue_free()
	GameState.reset_run()
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
	await test_squad_works_together()


## The difference between eight people in a room and a door team.
func test_squad_works_together() -> void:
	print("\nThe squad working together:")
	GameState.reset_run()
	GameState.defenses = []
	var raid := RaidDirector.new()
	raid.setup(_world, _player)
	add_child(raid)
	raid.start(2, 5)
	raid._open_up()
	raid._breach()

	# A wave is a point and a cover, not two of the same thing.
	var point: RaidUnit = null
	var cover: RaidUnit = null
	for u in raid._units:
		if u.state != RaidUnit.State.BREACHING:
			continue
		if u.role == RaidUnit.Role.POINT and point == null:
			point = u
		elif u.role == RaidUnit.Role.COVER and cover == null:
			cover = u
	_check(point != null, "somebody takes point")
	_check(cover != null, "and somebody covers him")
	if point != null and cover != null:
		_check(cover.accuracy > point.accuracy,
			"the man holding still shoots better than the man moving (%.2f vs %.2f)"
				% [cover.accuracy, point.accuracy])
		_check(point._has_flank,
			"the point man goes round the counter rather than up the middle")

	# Two ways in means one each. That is what closing one of them buys you.
	var entries: Array[float] = []
	for u in [point, cover]:
		if u != null:
			entries.append(u.entry_used.x)
	_check(raid._entries.size() == 2, "both approaches are open in this test")
	_check(entries.size() == 2 and absf(entries[0] - entries[1]) > 1.0,
		"with two doors open the pair splits between them")

	# Shared contact: one of them seeing you tells the rest.
	var seen_at := Vector3(1.5, 0.0, 2.0)
	raid.report_contact(seen_at)
	var intel := raid.shared_intel()
	_check(not intel.is_empty() and intel["at"] == seen_at, "a sighting is called in")
	if cover != null:
		cover._squad = raid
		cover._last_known = Vector3(-99, 0, -99)
		_check(cover._search_goal() == seen_at,
			"and somebody who never saw you goes to where he was told, not where he guessed")

	# But intel goes stale, or you could never shake them.
	raid.squad_contact_age = RaidDirector.INTEL_LIFETIME + 1.0
	_check(raid.shared_intel().is_empty(), "an old sighting stops being worth walking to")
	if cover != null:
		_check(cover._search_goal() == cover._last_known,
			"and they fall back on what they saw themselves")

	# A cover man holds his angle instead of wandering off looking.
	if cover != null:
		cover.state = RaidUnit.State.SEARCHING
		var held := cover.global_position
		for i in 20:
			cover._physics_process(0.05)
		_check(cover.global_position.distance_to(held) < 0.5,
			"the cover man does not leave the door to go searching")

	# Kill the point and his cover has to come on, or shooting one man per wave
	# would clear the room.
	if point != null and cover != null:
		point.take_damage(9999.0)
		raid._promote_cover()
		_check(cover.role == RaidUnit.Role.POINT,
			"killing the point man moves his cover up")
		_check(cover.state == RaidUnit.State.BREACHING, "and puts him back in motion")

	raid.stop()
	raid.queue_free()
	GameState.reset_run()
	await get_tree().process_frame


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
	_test_dialogue_fits()
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
