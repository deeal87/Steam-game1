extends Node
## Player settings, persisted to disk.
##
## The retro presentation is the one thing here that is genuinely an
## accessibility question rather than a taste question. Scanlines, film grain
## and chromatic aberration cause real eye strain for some people, and the
## vertex jitter that sells the era is motion instability by another name. Both
## are adjustable down to nothing, and turning them off costs you nothing but
## the look.

const PATH := "user://settings.cfg"

signal changed

var master_volume: float = 0.8      ## 0-1
var music_volume: float = 0.55
## Effects had no volume of their own — they played straight onto Master, so the
## only way to quieten a gunshot was to quieten the whole game.
var sfx_volume: float = 0.85
var mouse_sensitivity: float = 1.0  ## multiplier on the base look speed
var field_of_view: float = 68.0
var crt_intensity: float = 1.0      ## scanlines, grain, aberration, vignette
var retro_intensity: float = 1.0    ## vertex snapping and affine warping
var subtitles: bool = true

# --- Display ---
#
# A Steam build has to let people choose these. Shipping locked to a 1280x720
# window is fine for development and unacceptable on a store page: players run
# 1440p, ultrawides, 144Hz panels and handhelds, and a game that ignores all of
# that reads as unfinished before anybody has played a minute of it.
enum WindowMode { WINDOWED, BORDERLESS, FULLSCREEN }

var window_mode: int = WindowMode.WINDOWED
## Index into RESOLUTIONS. Only meaningful in windowed mode — the other two take
## the size of the display they are on.
var resolution_index: int = 0
var vsync: bool = true
## 0 means "no cap", which is the right default with vsync on.
var fps_cap: int = 0

## Window sizes offered in the menu. All 16:9, because the interface is laid out
## in a 1280x720 design space and scaled; ultrawide and other ratios are handled
## by the stretch mode rather than by a bigger list here.
const RESOLUTIONS := [
	Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080),
	Vector2i(2560, 1440), Vector2i(3840, 2160),
]

const FPS_CAPS := [0, 30, 60, 90, 120, 144, 240]
## Overrides whatever Steam or the OS reports. Empty means "work it out".
var player_name: String = ""


func _ready() -> void:
	load_settings()
	apply()


func apply() -> void:
	apply_display()
	AudioServer.set_bus_volume_db(0, linear_to_db(clampf(master_volume, 0.0001, 1.0)))
	AudioServer.set_bus_mute(0, master_volume <= 0.001)
	Music.set_volume(music_volume)
	Audio.set_volume(sfx_volume)

	# The PS1 vertex and texture effects are driven by global shader
	# parameters, so one write here reaches every material in the world
	# without walking the scene tree.
	RenderingServer.global_shader_parameter_set("ps1_snap", retro_intensity)
	RenderingServer.global_shader_parameter_set("ps1_affine", retro_intensity)

	changed.emit()


## Window mode, size, vsync and frame cap.
##
## Separated from the rest of `apply()` so the display can be changed without
## re-writing audio buses and shader globals, and skipped entirely under the
## headless server where there is no window to talk to.
func apply_display() -> void:
	if DisplayServer.get_name() == "headless":
		return

	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = maxi(0, fps_cap)

	match window_mode:
		WindowMode.FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
		WindowMode.BORDERLESS:
			# Borderless at the size of the screen it is on, which is what most
			# players mean by "fullscreen" and what alt-tabs cleanly.
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
			var screen := DisplayServer.window_get_current_screen()
			DisplayServer.window_set_size(DisplayServer.screen_get_size(screen))
			DisplayServer.window_set_position(DisplayServer.screen_get_position(screen))
		_:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			var size: Vector2i = RESOLUTIONS[clampi(resolution_index, 0, RESOLUTIONS.size() - 1)]
			# Never open a window bigger than the screen it has to fit on — a
			# handheld reporting 1280x800 must not be handed a 4K window.
			var usable := DisplayServer.screen_get_usable_rect(
				DisplayServer.window_get_current_screen())
			size.x = mini(size.x, usable.size.x)
			size.y = mini(size.y, usable.size.y)
			DisplayServer.window_set_size(size)
			DisplayServer.window_set_position(
				usable.position + (usable.size - size) / 2)


## The largest listed resolution that actually fits on this screen, used to pick
## a sensible default the first time the game runs.
func default_resolution_index() -> int:
	if DisplayServer.get_name() == "headless":
		return 0
	var usable := DisplayServer.screen_get_usable_rect(
		DisplayServer.window_get_current_screen()).size
	var best := 0
	for i in RESOLUTIONS.size():
		var r: Vector2i = RESOLUTIONS[i]
		if r.x <= usable.x and r.y <= usable.y:
			best = i
	return best


func reset() -> void:
	window_mode = WindowMode.WINDOWED
	resolution_index = default_resolution_index()
	vsync = true
	fps_cap = 0
	master_volume = 0.8
	music_volume = 0.55
	sfx_volume = 0.85
	mouse_sensitivity = 1.0
	field_of_view = 68.0
	crt_intensity = 1.0
	retro_intensity = 1.0
	subtitles = true
	player_name = ""
	apply()
	save_settings()


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("input", "sensitivity", mouse_sensitivity)
	cfg.set_value("video", "fov", field_of_view)
	cfg.set_value("video", "crt", crt_intensity)
	cfg.set_value("video", "retro", retro_intensity)
	cfg.set_value("ui", "subtitles", subtitles)
	cfg.set_value("ui", "player_name", player_name)
	cfg.set_value("video", "window_mode", window_mode)
	cfg.set_value("video", "resolution", resolution_index)
	cfg.set_value("video", "vsync", vsync)
	cfg.set_value("video", "fps_cap", fps_cap)
	Persist.write(cfg, PATH, "settings")


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if not Persist.read(cfg, PATH, "settings"):
		# First run. Open at the biggest listed size this screen can hold rather
		# than at a hardcoded 720p, so a 1440p monitor does not get a small
		# window in the corner and a handheld does not get one it cannot fit.
		resolution_index = default_resolution_index()
		return
	master_volume = cfg.get_value("audio", "master", master_volume)
	music_volume = cfg.get_value("audio", "music", music_volume)
	sfx_volume = cfg.get_value("audio", "sfx", sfx_volume)
	mouse_sensitivity = cfg.get_value("input", "sensitivity", mouse_sensitivity)
	field_of_view = cfg.get_value("video", "fov", field_of_view)
	crt_intensity = cfg.get_value("video", "crt", crt_intensity)
	retro_intensity = cfg.get_value("video", "retro", retro_intensity)
	subtitles = cfg.get_value("ui", "subtitles", subtitles)
	player_name = cfg.get_value("ui", "player_name", player_name)
	window_mode = cfg.get_value("video", "window_mode", window_mode)
	resolution_index = cfg.get_value("video", "resolution", default_resolution_index())
	vsync = cfg.get_value("video", "vsync", vsync)
	fps_cap = cfg.get_value("video", "fps_cap", fps_cap)
