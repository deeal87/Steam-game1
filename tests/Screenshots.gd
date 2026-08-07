extends Node
## Drives the real game under a real renderer and saves frames to disk.
##
##   xvfb-run -a godot --path . res://tests/Screenshots.tscn -- --shots=<dir>
##
## Headless tests prove the logic runs. They cannot tell you the kiosk looks
## like a kiosk, that the affine texture warping is visible, or that the strip
## light is doing anything. This does.

const BOOT := preload("res://scenes/Boot.tscn")

var out_dir: String = "res://.shots"
var game: Node


func _ready() -> void:
	# PauseUI freezes the tree, so this harness has to keep running through it.
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			out_dir = arg.substr(8)
	DirAccess.make_dir_recursive_absolute(out_dir)

	game = BOOT.instantiate()
	add_child(game)

	await _settle(70)
	await _shot("01_title")

	# Open up.
	await _tap("interact")
	await _settle(40)
	await _shot("02_counter_empty")

	# Wait for the first customer to walk in, shop, and reach the counter.
	var director: NightDirector = game.night_director
	var waited := 0
	while waited < 1800:
		var c: Customer = director.current_customer()
		# Hold out for someone served AND someone else waiting, so the shot
		# shows the queue rather than a single customer.
		if c != null and c.state == Customer.State.AT_COUNTER and director.waiting_count() >= 2:
			break
		await get_tree().process_frame
		waited += 1
	print("  [diag] in shop=%d  in line=%d  served=%s" % [
		director.present_count(), director.waiting_count(),
		str(director.current_customer() != null)])
	await _settle(30)
	await _shot("03_customer_at_hatch")

	var customer: Customer = director.current_customer()
	if customer != null:
		print("  [diag] customer at %s  state=%d  visible=%s  basket=%s" % [
			str(customer.global_position), customer.state,
			str(customer.visible), str(customer.basket)])
		print("  [diag] player at %s  stand anchor %s" % [
			str(game.player.global_position), str(World.CUSTOMER_STAND)])
		# Side-on, where a person is unmistakable.
		await _look_from(Vector3(2.6, 0.1, World.CUSTOMER_STAND.z), 1.57, "03b_customer_side")
		# Sweep them, pull the file, then look at the terminal.
		customer.on_scan(game.player)
		await _settle(10)
		await _shot("04_after_sweep")

		game.terminal.show_for(customer)
		await _settle(40)
		await _shot("05_terminal")
		game.terminal.close()
		await _settle(10)

		game.dialogue.show_for(customer, game.player)
		await _settle(20)
		await _shot("06_dialogue")

		# Spend a question so the answer panel is populated.
		var opts := customer.profile.available_questions()
		if not opts.is_empty():
			game.dialogue._choose(game.dialogue._options[0])
			await _settle(20)
			await _shot("07_dialogue_answer")
		game.dialogue.close()
		await _settle(10)

		game.notebook.show_notebook(customer)
		await _settle(20)
		await _shot("08_notepad")
		game.notebook.close()
		await _settle(10)

	game.shop.show_shop()
	await _settle(20)
	await _shot("09_supplier")
	game.shop.close()
	await _settle(10)

	# Turn round and look at the back of the shop.
	game.player.rotation.y = PI
	await _settle(20)
	await _shot("10_back_of_kiosk")

	# The pause menu, and proof the accessibility toggles actually do something.
	game.player.rotation.y = 0.0
	await _settle(20)
	game.pause.show_pause()
	await _settle(20)
	await _shot("11_pause_settings")
	game.pause._page = "keys"
	game.pause._rebuild()
	await _settle(20)
	await _shot("11b_pause_controls")
	game.pause._page = "settings"
	game.pause.close()
	await _settle(10)

	Settings.retro_intensity = 0.0
	Settings.crt_intensity = 0.0
	Settings.apply()
	await _settle(25)
	await _shot("12_effects_disabled")
	Settings.reset()
	await _settle(15)

	# --- A tour of the places that did not exist before ---------------------
	await _look_from(Vector3(-0.6, 0.1, 3.4), 0.0, "13_shop_floor")
	await _look_from(Vector3(-3.0, 0.1, 3.2), 0.0, "14_through_to_stockroom")
	await _look_from(Vector3(-2.6, 0.1, 5.4), 3.6, "15_stockroom")
	await _look_from(World.MANHOLE + Vector3(0, 0.1, -1.5), 3.14, "16_manhole", -0.55)

	# Outside, through the side door, then a long look west down the street.
	await _look_from(Vector3(World.FRONT_DOOR_X, 0.3, -World.SHOP_HALF_Z - 2.6), PI, "17_outside_shop_door")
	await _look_from(Vector3(-8.0, 0.3, -2.0), 1.57, "18_street_looking_west")

	# Standing on top of the tunnels, looking at your feet. The road is solid
	# here and it has to read as solid: this is the shot that says whether the
	# sewer is showing through the ground, which it did for a long time and
	# which no amount of walking around at eye height ever revealed.
	await _look_from(Vector3(-24.0, 0.3, World.MANHOLE.z), PI, "18b_road_over_tunnel", -1.35)

	# Down the ladder.
	game.player.toggle_torch()
	await _look_from(Vector3(World.MANHOLE.x - 1.0, World.SEWER_Y + 0.2, World.MANHOLE.z), 1.57, "19_sewer")

	# Populate the tunnel the way going down the ladder would, so the shots
	# show what is actually waiting rather than an empty corridor.
	GameState.sewer_trips = 4
	game.sewer_director.active = false
	game.sewer_director.enter()
	await _settle(40)
	# Seven metres east of whoever is down there, looking west at them — but on
	# the main run, not wherever they happen to be standing. Half the dwellers
	# spawn on the spur, and "their position plus seven metres of x" is a point
	# inside solid ground with the lights on the other side of a wall: this shot
	# has been a black rectangle for as long as it has existed.
	var lurker := _nearest_dweller(game)
	var down_the_tunnel := Vector3(-30.0, World.SEWER_Y + 0.2, World.MANHOLE.z)
	if lurker != null:
		down_the_tunnel.x = clampf(lurker.global_position.x + 7.0,
			World.SEWER_EXIT.x + 2.0, World.MANHOLE.x - 2.0)
	await _look_from(down_the_tunnel, 1.57, "20_sewer_tunnel")
	game.sewer_director.leave()

	# The far end. Approach it the way a player would, from down the street.
	await _look_from(Vector3(World.STREET_END + 7.0, 0.3, 0.5), 2.2, "21_far_end_approach")
	await _look_from(Vector3(World.STREET_END, 0.3, 3.4), 3.14, "22_easter_egg")
	game.player.toggle_torch()

	# And the raid, watched from behind the counter looking at the front of the
	# shop — which is where a player is standing when one starts, and is not
	# where this used to stand. Thirty-five centimetres in front of the island
	# rack, facing it, is a screenful of shelf and a prompt to take a pot of
	# noodles; both raid shots have been that for as long as they have existed.
	game.player.global_position = game.world.anchors["player_spawn"]
	game.player.rotation.y = 0.0
	game.player.camera.rotation.x = 0.0
	await _settle(20)
	GameState.night = 4
	game.raid_director.start(2, 4)
	await _settle(120)
	await _shot("23_raid_forming")
	await _settle(300)
	await _shot("24_raid_breach")

	# And one of them close enough to see what they are wearing. The breach shot
	# is about what it feels like from behind the counter; this one is the only
	# way to check the kit actually went on.
	var officer := _nearest_unit(game)
	if officer != null:
		# Three-quarter and far enough back to see a whole person, with the torch
		# on — a unit standing in an unlit part of the street is a black
		# rectangle, which is the intended effect in play and useless here.
		game.player.toggle_torch()
		var target: Vector3 = officer.global_position
		var at := target + Vector3(1.9, 0.1, 3.2)
		await _look_from(at, atan2(at.x - target.x, at.z - target.z), "25_raid_close", -0.08)
		game.player.toggle_torch()

	print("Screenshots written to %s" % out_dir)
	get_tree().quit()


## `Input.action_press` only sets the polled state; it never produces an event,
## so anything listening in `_unhandled_input` would never hear it. Feeding a
## real InputEventAction through the input system does reach those handlers.
func _tap(action: String) -> void:
	for pressed: bool in [true, false]:
		var ev := InputEventAction.new()
		ev.action = action
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await get_tree().process_frame


## Puts the player somewhere, points them, waits for the world to catch up and
## takes the picture. Physics needs a couple of frames after a teleport before
## lights and triggers have settled.
func _nearest_unit(g: Node) -> RaidUnit:
	for child in g.world.get_children():
		if child is RaidUnit:
			return child
	return null


func _nearest_dweller(g: Node) -> SewerDweller:
	for child in g.world.get_children():
		if child is SewerDweller:
			return child
	return null


func _look_from(pos: Vector3, yaw: float, name: String, pitch: float = 0.0) -> void:
	game.player.velocity = Vector3.ZERO
	game.player.global_position = pos
	game.player.rotation.y = yaw
	game.player.camera.rotation.x = pitch
	await _settle(24)
	await _shot(name)


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [out_dir, name]
	img.save_png(path)
	print("  shot %s  (%dx%d)" % [name, img.get_width(), img.get_height()])
