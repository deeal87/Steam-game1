extends Node3D
## Top level. Owns the world, the player, every panel, and the order the night
## happens in.

enum Phase { TITLE, SHIFT, REPORT, RAID_WARNING, RAID, OVER }

## How much smaller than the window the 3D view renders. At 720p this puts the
## world at roughly 426x240 — squarely in the right era.
const RENDER_SHRINK := 3

var phase: Phase = Phase.TITLE

var viewport_3d: SubViewport
var viewport_container: SubViewportContainer
var world: World
var player: Player
var hud: HUD
var terminal: TerminalUI
var dialogue: DialogueUI
var notebook: NotebookUI
var shop: ShopUI
var report: ReportUI
var pause: PauseUI
var night_director: NightDirector
var raid_director: RaidDirector
var sewer_director: SewerDirector
var checkout: Checkout

var _screen_effect: ColorRect
var _flash_rect: ColorRect
var _fade_rect: ColorRect
var _travelling: bool = false
var _flicker_timer: float = 0.0
var _flicker_energy: float = 2.3
var _pending_summary: Dictionary = {}


func _ready() -> void:
	randomize()
	_build_world()
	_build_ui()
	_build_directors()
	_wire()

	_apply_settings()

	report.show_title()
	player.ui_locked = true

	_maybe_self_test()


## `--selftest` opens the kiosk, renders a few seconds of the real game, writes
## a frame to disk and quits.
##
## This ships in the release binary on purpose. It is the only way to confirm
## that an exported build actually renders on a machine you cannot look at —
## a headless test proves the logic runs, and "it didn't crash" proves very
## little. Pass `--selftest=/some/path.png` to choose where the frame goes.
func _maybe_self_test() -> void:
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	var path := ""
	var wanted := false
	for arg: String in args:
		if arg == "--selftest":
			wanted = true
		elif arg.begins_with("--selftest="):
			wanted = true
			path = arg.substr(11)
	if not wanted:
		return
	if path.is_empty():
		path = "user://selftest.png"
	_run_self_test(path)


func _run_self_test(path: String) -> void:
	print("[selftest] opening up")
	for i in 40:
		await get_tree().process_frame
	# Go through the title screen the way a player does, rather than calling
	# _start_shift directly — otherwise the title stays on top of the shift and
	# the frame proves nothing about the transition.
	report._continue()
	# Wait for someone to come off the street, do their shopping and reach the
	# till, rather than for a fixed number of frames — the walk takes as long as
	# it takes, and on a slow machine a fixed budget just reports "nobody yet".
	# Capped so the check can never hang a build server.
	var waited := 0
	while waited < 2400:
		if night_director.current_customer() != null:
			break
		await get_tree().process_frame
		waited += 1
	for i in 20:
		await get_tree().process_frame

	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(path)
	if err != OK:
		printerr("[selftest] could not write %s (error %d)" % [path, err])
		get_tree().quit(1)
		return
	print("[selftest] wrote %s (%dx%d)" % [path, img.get_width(), img.get_height()])
	print("[selftest] night %d · money %d · in shop %d · in line %d · at the till: %s" % [
		GameState.night, GameState.money,
		night_director.present_count(), night_director.waiting_count(),
		"yes" if night_director.current_customer() != null else "no"])
	# The score is the one system a screenshot cannot vouch for, so it reports
	# itself: which section the arrangement is in, and what is audible.
	var audible: Array[String] = []
	for name: String in Music.BASE:
		var p: AudioStreamPlayer = Music._layers[name]["player"]
		if p.playing and p.volume_db > -50.0:
			audible.append(name)
	print("[selftest] score section %d · playing: %s" % [
		Music.section(), ", ".join(audible) if not audible.is_empty() else "nothing"])
	get_tree().quit(0)


# --- Construction ------------------------------------------------------------

## The 3D world lives in its own SubViewport, rendered at a third of the window
## resolution and scaled back up with nearest-neighbour filtering. That is what
## produces the chunky pixels and the crawling edges; the interface is drawn
## afterwards at full resolution and stays legible.
func _build_world() -> void:
	var layer := CanvasLayer.new()
	layer.layer = -1
	add_child(layer)

	viewport_container = SubViewportContainer.new()
	viewport_container.stretch = true
	viewport_container.stretch_shrink = RENDER_SHRINK
	viewport_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	viewport_container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	layer.add_child(viewport_container)

	viewport_3d = SubViewport.new()
	viewport_3d.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport_3d.handle_input_locally = false
	viewport_3d.msaa_3d = Viewport.MSAA_DISABLED
	viewport_3d.positional_shadow_atlas_size = 1024
	viewport_container.add_child(viewport_3d)

	world = World.new()
	viewport_3d.add_child(world)

	player = Player.new()
	player.world = world
	viewport_3d.add_child(player)
	player.global_position = world.anchors["player_spawn"]
	# Face the hatch, which is at -Z. Godot's forward is already -Z, so this
	# wants to stay at zero — rotating by PI puts your back to the window.
	player.rotation.y = 0.0


func _build_ui() -> void:
	hud = HUD.new()
	add_child(hud)
	hud.bind_player(player)

	terminal = TerminalUI.new()
	add_child(terminal)

	dialogue = DialogueUI.new()
	add_child(dialogue)

	notebook = NotebookUI.new()
	add_child(notebook)

	shop = ShopUI.new()
	add_child(shop)

	report = ReportUI.new()
	add_child(report)

	pause = PauseUI.new()
	add_child(pause)

	_build_screen_effect()


## The whole game is drawn through one grubby pass: scanlines, a little
## channel separation, and a vignette that keeps the corners of the room dark.
func _build_screen_effect() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)

	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/crt.gdshader")
	m.set_shader_parameter("scanline_strength", 0.16)
	m.set_shader_parameter("scanline_count", 270.0)
	m.set_shader_parameter("vignette_strength", 0.72)
	m.set_shader_parameter("aberration", 0.5)
	m.set_shader_parameter("grain", 0.045)
	m.set_shader_parameter("posterize_steps", 40.0)
	m.set_shader_parameter("grade", Color(0.88, 0.93, 1.0))
	rect.material = m
	_screen_effect = rect
	layer.add_child(rect)

	# Sits above the CRT pass so the flashbang whites out the grade as well as
	# the picture. Ignores mouse input and starts fully transparent.
	var flash_layer := CanvasLayer.new()
	flash_layer.layer = 21
	add_child(flash_layer)
	_flash_rect = ColorRect.new()
	_flash_rect.color = Color(1, 1, 1, 0)
	_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash_layer.add_child(_flash_rect)

	# Black, above everything, for the ladder transitions.
	var fade_layer := CanvasLayer.new()
	fade_layer.layer = 22
	add_child(fade_layer)
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0, 0, 0, 0)
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_layer.add_child(_fade_rect)


func _build_directors() -> void:
	night_director = NightDirector.new()
	night_director.setup(world)
	add_child(night_director)

	raid_director = RaidDirector.new()
	raid_director.setup(world, player)
	add_child(raid_director)

	sewer_director = SewerDirector.new()
	sewer_director.setup(world, player)
	add_child(sewer_director)

	checkout = Checkout.new()
	checkout.setup(world)
	add_child(checkout)
	player.checkout = checkout


func _wire() -> void:
	player.wants_terminal.connect(_open_terminal)
	player.wants_shop.connect(_open_shop)
	player.wants_notebook.connect(_open_notebook)

	terminal.closed.connect(_on_panel_closed)
	dialogue.closed.connect(_on_panel_closed)
	notebook.closed.connect(_on_panel_closed)
	shop.closed.connect(_on_panel_closed)

	night_director.customer_ready.connect(_on_customer_ready)
	Signals.customer_arrived.connect(_on_customer_arrived)
	Signals.customer_departed.connect(_on_customer_departed)
	checkout.completed.connect(_on_checkout_completed)
	checkout.changed.connect(_on_checkout_changed)
	night_director.shift_finished.connect(_on_shift_finished)
	raid_director.raid_over.connect(_on_raid_over)

	pause.closed.connect(_on_panel_closed)
	pause.restart_requested.connect(_restart)
	Settings.changed.connect(_apply_settings)

	report.continued.connect(_on_report_continued)
	report.restart_requested.connect(_restart)
	report.quit_requested.connect(func() -> void: get_tree().quit())

	Signals.player_died.connect(_on_player_died)
	Signals.flashbang.connect(_on_flashbang)
	Signals.travel_requested.connect(_on_travel_requested)

	var egg: EasterEgg = world.anchors.get("easter_egg")
	if egg != null:
		egg.found.connect(_on_easter_egg_found)


# --- Panels ------------------------------------------------------------------

func _any_panel_open() -> bool:
	return terminal.open or dialogue.open or notebook.open or shop.open \
		or report.open or pause.open


func _open_terminal() -> void:
	if _any_panel_open():
		return
	terminal.show_for(night_director.current_customer())
	player.ui_locked = true


func _open_shop() -> void:
	if _any_panel_open():
		return
	shop.show_shop()
	player.ui_locked = true


func _open_notebook() -> void:
	if _any_panel_open():
		return
	notebook.show_notebook(night_director.current_customer())
	player.ui_locked = true


func _on_customer_ready(customer: Customer) -> void:
	customer.wants_conversation.connect(_open_dialogue)


## They reach the counter and put their shopping down. If the shelves were bare
## there is nothing to ring up and they say so.
func _on_customer_arrived(customer: Customer) -> void:
	if checkout.active and checkout.customer != null and is_instance_valid(checkout.customer) \
			and checkout.customer != customer:
		# Someone is still being rung up. The new arrival waits their turn.
		return
	var basket: Array[String] = customer.basket
	var placed := checkout.begin(customer, basket)
	if placed <= 0:
		Signals.notice.emit("They came to the counter with nothing. Fill the shelves.", "warn")
	else:
		Signals.notice.emit("%d item%s on the counter. Scan them." %
			[placed, "" if placed == 1 else "s"], "info")


## If the person being rung up walks off — refused, dismissed, shot, or simply
## fed up — their shopping cannot stay sitting on the counter for the next one.
func _on_customer_departed(customer: Customer, _outcome: String) -> void:
	if checkout.active and checkout.customer == customer:
		if checkout.remaining() > 0:
			Signals.notice.emit("They left their shopping on the counter.", "warn")
		checkout.clear()
	# Whoever is at the front now gets the counter.
	var next := night_director.current_customer()
	if next != null and not checkout.active:
		_on_customer_arrived(next)


func _on_checkout_completed(total: int) -> void:
	# The checkout knows who it was serving; the front of the queue may already
	# have changed by the time the till closes.
	var customer := checkout.customer
	if customer == null or not is_instance_valid(customer):
		customer = night_director.current_customer()
	if customer != null:
		customer.on_paid(total)


func _on_checkout_changed() -> void:
	Signals.checkout_changed.emit(checkout.scanned_count(), checkout.item_count(), checkout.total())


func _open_dialogue(customer: Customer) -> void:
	if _any_panel_open():
		return
	dialogue.show_for(customer, player)
	player.ui_locked = true


func _on_panel_closed() -> void:
	if _any_panel_open():
		return
	player.ui_locked = false
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# --- Night cycle -------------------------------------------------------------

func _start_shift() -> void:
	phase = Phase.SHIFT
	checkout.clear()
	Music.set_night(GameState.night)
	Music.set_progress(0.0)
	Music.play_shift()
	player.ui_locked = false
	player.health = player.max_health
	player.dead = false
	world.set_shutter_closed(false)
	world.anchors["shutter_is_closed"] = false
	night_director.start_night()


func _on_shift_finished(summary: Dictionary) -> void:
	phase = Phase.REPORT
	Music.stop_all()
	_pending_summary = summary
	player.ui_locked = true
	GameState.nights_survived += 1
	GameState.save_run()
	report.show_report(summary)


func _on_report_continued() -> void:
	match phase:
		Phase.TITLE:
			_start_shift()
		Phase.REPORT:
			var evidence := int(_pending_summary.get("evidence", 0))
			if evidence > 0:
				phase = Phase.RAID_WARNING
				var reason: String = str(_pending_summary.get("raid_reason", ""))
				if reason.is_empty():
					reason = "Someone reported the kiosk."
				report.show_raid_warning(reason, GameState.raid_squad_size() + evidence - 1)
			else:
				_advance_night()
		Phase.RAID_WARNING:
			phase = Phase.RAID
			player.ui_locked = false
			player.health = player.max_health
			# You are not going to win a firefight with your hands empty.
			if player.equipped.is_empty():
				player.equipped = GameState.best_weapon()
				player._show_in_hand("weapon")
				Signals.notice.emit("%s in your hands." %
					GameState.WEAPONS[player.equipped]["name"], "info")
			Music.play_raid()
			raid_director.start(int(_pending_summary.get("evidence", 0)), GameState.night)


func _on_raid_over(survived: bool) -> void:
	raid_director.stop()
	raid_director.phase = RaidDirector.Phase.IDLE
	Music.stop_all()
	if survived:
		_advance_night()


func _advance_night() -> void:
	GameState.night += 1
	GameState.evidence_against_you = 0
	GameState.raid_reason = ""
	GameState.save_run()
	_start_shift()


func _on_player_died(cause: String) -> void:
	if phase == Phase.OVER:
		return
	phase = Phase.OVER
	night_director.stop()
	raid_director.stop()
	sewer_director.stop()
	checkout.clear()
	Music.stop_all()
	Audio.stop_ambience()
	var text := "They came through the door and you were still holding a bag of crisps."
	if cause != "shot":
		text = cause
	await get_tree().create_timer(2.2).timeout
	report.show_game_over(text)


func _restart() -> void:
	GameState.clear_save()
	GameState.reset_run()
	get_tree().reload_current_scene()


## Ladder and manhole transitions: fade out, move, fade back in.
func _on_travel_requested(destination: Vector3, label: String, is_escape: bool) -> void:
	if _travelling or player == null or player.dead:
		return
	_travelling = true
	player.ui_locked = true

	var tw := create_tween()
	tw.tween_property(_fade_rect, "color:a", 1.0, 0.45)
	await tw.finished

	player.velocity = Vector3.ZERO
	player.global_position = destination
	Signals.notice.emit(label, "info")

	# Below ground or back above it. Going down counts as a trip and populates
	# the tunnels; coming up clears them.
	if destination.y < World.SEWER_Y + 2.0:
		sewer_director.enter()
		Music.play_sewer()
	else:
		sewer_director.leave()
		if phase == Phase.RAID:
			Music.play_raid()
		elif phase == Phase.SHIFT:
			Music.play_shift()

	# Climbing down out of the kiosk while they are coming through the door is
	# the escape, and it is the only place the sewer changes the run.
	if is_escape and phase == Phase.RAID and raid_director.phase != RaidDirector.Phase.DONE:
		_flee_raid()

	var back := create_tween()
	back.tween_interval(0.25)
	back.tween_property(_fade_rect, "color:a", 0.0, 0.6)
	await back.finished

	_travelling = false
	if not _any_panel_open():
		player.ui_locked = false


func _flee_raid() -> void:
	var lost := GameState.flee_through_sewer()
	raid_director.stop()
	raid_director.phase = RaidDirector.Phase.IDLE
	Audio.stop_ambience()
	Signals.notice.emit("You get the cover back over your head. Above you, they are taking the place apart.", "warn")
	Signals.notice.emit("Gone: %d in cash, %d units." % [int(lost["cash"]), int(lost["stash"])], "bad")
	_advance_night()


## Walking into the thing at the end of the road takes a picture by itself.
## The whole point of it is having proof you got there, and asking the player to
## remember to press a screenshot key at that moment would defeat it.
func _on_easter_egg_found(_unused: String) -> void:
	var path := await _capture_screenshot("kiosk_master")
	Signals.notice.emit("YOU ARE THE MASTER OF MASTER %s" % PlayerIdentity.display_name().to_upper(), "good")
	if path.is_empty():
		Signals.notice.emit("(Screenshot failed to save.)", "bad")
	else:
		Signals.notice.emit("Screenshot saved: %s" % path, "info")


## Writes a PNG next to the save file. Returns the absolute path, or "".
func _capture_screenshot(prefix: String) -> String:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		return ""
	var dir := "user://screenshots"
	DirAccess.make_dir_recursive_absolute(dir)
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var path := "%s/%s_%s.png" % [dir, prefix, stamp]
	if img.save_png(path) != OK:
		return ""
	return ProjectSettings.globalize_path(path)


## They throw something through the hatch before they follow it. The white-out
## is short but total, and it is the reason the breach has a rhythm you can
## brace for rather than simply losing to.
func _on_flashbang() -> void:
	if _flash_rect == null or not is_instance_valid(_flash_rect):
		return
	_flash_rect.color = Color(1, 1, 1, 0.95)
	var tw := create_tween()
	tw.tween_property(_flash_rect, "color:a", 0.0, 1.7).set_trans(Tween.TRANS_EXPO)
	Audio.play("breach", -4.0, 1.6)


## Settings that live on a node rather than in a shader global have to be
## pushed out whenever they change.
func _apply_settings() -> void:
	if player != null and is_instance_valid(player) and player.camera != null:
		player.camera.fov = Settings.field_of_view
	if _screen_effect != null and is_instance_valid(_screen_effect):
		var m: ShaderMaterial = _screen_effect.material
		var k := Settings.crt_intensity
		m.set_shader_parameter("scanline_strength", 0.16 * k)
		m.set_shader_parameter("vignette_strength", 0.72 * k)
		m.set_shader_parameter("aberration", 0.5 * k)
		m.set_shader_parameter("grain", 0.045 * k)
		# Colour banding is the one part worth keeping a little of even at
		# zero, or the image looks flatly modern rather than merely clean.
		m.set_shader_parameter("posterize_steps", lerpf(0.0, 40.0, k))


# --- Atmosphere --------------------------------------------------------------

func _process(delta: float) -> void:
	_flicker(delta)
	_score(delta)


var _score_timer: float = 0.0

## Feeds the score.
##
## Only two inputs, and both are things the player is already looking at: the
## heat meter, and whether the person at the counter has made the ask. Wiring
## this to whether they are actually police would give the game away — the
## music would answer the only question that matters.
func _score(delta: float) -> void:
	if phase != Phase.SHIFT:
		return
	_score_timer -= delta
	if _score_timer > 0.0:
		return
	_score_timer = 0.35

	var customer := night_director.current_customer()
	var asked := customer != null and customer._asked_for_illicit
	var sold := customer != null and customer.profile.sold_illicit
	Music.set_tension(Music.tension_from(
		GameState.heat, asked, sold, GameState.evidence_against_you))
	# How late it is. Also on screen, so the score is not telling tales.
	Music.set_progress(1.0 - night_director.minutes_left / NightDirector.SHIFT_MINUTES)


## The strip light is failing. It mostly holds, then drops out for a frame or
## two, which is enough to make you look up.
func _flicker(delta: float) -> void:
	if world == null or world.strip_light == null:
		return
	_flicker_timer -= delta
	if _flicker_timer <= 0.0:
		if randf() < 0.16:
			_flicker_energy = randf_range(0.25, 1.1)
			_flicker_timer = randf_range(0.03, 0.13)
			Audio.play("beep_low", -40.0, 0.4)
		else:
			_flicker_energy = randf_range(2.05, 2.45)
			_flicker_timer = randf_range(0.5, 3.2)
	world.strip_light.light_energy = lerpf(world.strip_light.light_energy, _flicker_energy, delta * 22.0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cancel") and not _any_panel_open():
		pause.show_pause()
		get_viewport().set_input_as_handled()
