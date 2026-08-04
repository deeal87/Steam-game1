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

	# Wait for the first customer to walk out of the fog and reach the hatch.
	var director: NightDirector = game.night_director
	var waited := 0
	while waited < 900:
		var c: Customer = director.current_customer()
		if c != null and c.state == Customer.State.AT_COUNTER:
			break
		await get_tree().process_frame
		waited += 1
	await _settle(30)
	await _shot("03_customer_at_hatch")

	var customer: Customer = director.current_customer()
	if customer != null:
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

	# And the raid.
	game.player.rotation.y = 0.0
	GameState.night = 4
	game.raid_director.start(2, 4)
	await _settle(150)
	await _shot("11_raid_forming")
	await _settle(360)
	await _shot("12_raid_breach")

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


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [out_dir, name]
	img.save_png(path)
	print("  shot %s  (%dx%d)" % [name, img.get_width(), img.get_height()])
