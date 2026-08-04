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

var _screen_effect: ColorRect
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
	# Long enough for a customer to walk out of the fog and reach the hatch.
	for i in 260:
		await get_tree().process_frame

	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(path)
	if err != OK:
		printerr("[selftest] could not write %s (error %d)" % [path, err])
		get_tree().quit(1)
		return
	print("[selftest] wrote %s (%dx%d)" % [path, img.get_width(), img.get_height()])
	print("[selftest] night %d · money %d · customer at window: %s" % [
		GameState.night, GameState.money,
		"yes" if night_director.current_customer() != null else "no"])
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
	m.set_shader_parameter("vignette_strength", 0.95)
	m.set_shader_parameter("aberration", 0.5)
	m.set_shader_parameter("grain", 0.045)
	m.set_shader_parameter("posterize_steps", 40.0)
	m.set_shader_parameter("grade", Color(0.88, 0.93, 1.0))
	rect.material = m
	_screen_effect = rect
	layer.add_child(rect)


func _build_directors() -> void:
	night_director = NightDirector.new()
	night_director.setup(world)
	add_child(night_director)

	raid_director = RaidDirector.new()
	raid_director.setup(world, player)
	add_child(raid_director)


func _wire() -> void:
	player.wants_terminal.connect(_open_terminal)
	player.wants_shop.connect(_open_shop)
	player.wants_notebook.connect(_open_notebook)

	terminal.closed.connect(_on_panel_closed)
	dialogue.closed.connect(_on_panel_closed)
	notebook.closed.connect(_on_panel_closed)
	shop.closed.connect(_on_panel_closed)

	night_director.customer_ready.connect(_on_customer_ready)
	night_director.shift_finished.connect(_on_shift_finished)
	raid_director.raid_over.connect(_on_raid_over)

	pause.closed.connect(_on_panel_closed)
	pause.restart_requested.connect(_restart)
	Settings.changed.connect(_apply_settings)

	report.continued.connect(_on_report_continued)
	report.restart_requested.connect(_restart)
	report.quit_requested.connect(func() -> void: get_tree().quit())

	Signals.player_died.connect(_on_player_died)


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
	player.ui_locked = false
	player.health = player.max_health
	player.dead = false
	world.set_shutter_closed(false)
	world.anchors["shutter_is_closed"] = false
	night_director.start_night()


func _on_shift_finished(summary: Dictionary) -> void:
	phase = Phase.REPORT
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
			raid_director.start(int(_pending_summary.get("evidence", 0)), GameState.night)


func _on_raid_over(survived: bool) -> void:
	raid_director.stop()
	raid_director.phase = RaidDirector.Phase.IDLE
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


## Settings that live on a node rather than in a shader global have to be
## pushed out whenever they change.
func _apply_settings() -> void:
	if player != null and is_instance_valid(player) and player.camera != null:
		player.camera.fov = Settings.field_of_view
	if _screen_effect != null and is_instance_valid(_screen_effect):
		var m: ShaderMaterial = _screen_effect.material
		var k := Settings.crt_intensity
		m.set_shader_parameter("scanline_strength", 0.16 * k)
		m.set_shader_parameter("vignette_strength", 0.95 * k)
		m.set_shader_parameter("aberration", 0.5 * k)
		m.set_shader_parameter("grain", 0.045 * k)
		# Colour banding is the one part worth keeping a little of even at
		# zero, or the image looks flatly modern rather than merely clean.
		m.set_shader_parameter("posterize_steps", lerpf(0.0, 40.0, k))


# --- Atmosphere --------------------------------------------------------------

func _process(delta: float) -> void:
	_flicker(delta)


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
