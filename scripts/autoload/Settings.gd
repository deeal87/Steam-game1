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
var mouse_sensitivity: float = 1.0  ## multiplier on the base look speed
var field_of_view: float = 68.0
var crt_intensity: float = 1.0      ## scanlines, grain, aberration, vignette
var retro_intensity: float = 1.0    ## vertex snapping and affine warping
var subtitles: bool = true
## Overrides whatever Steam or the OS reports. Empty means "work it out".
var player_name: String = ""


func _ready() -> void:
	load_settings()
	apply()


func apply() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(clampf(master_volume, 0.0001, 1.0)))
	AudioServer.set_bus_mute(0, master_volume <= 0.001)
	Music.set_volume(music_volume)

	# The PS1 vertex and texture effects are driven by global shader
	# parameters, so one write here reaches every material in the world
	# without walking the scene tree.
	RenderingServer.global_shader_parameter_set("ps1_snap", retro_intensity)
	RenderingServer.global_shader_parameter_set("ps1_affine", retro_intensity)

	changed.emit()


func reset() -> void:
	master_volume = 0.8
	music_volume = 0.55
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
	cfg.set_value("input", "sensitivity", mouse_sensitivity)
	cfg.set_value("video", "fov", field_of_view)
	cfg.set_value("video", "crt", crt_intensity)
	cfg.set_value("video", "retro", retro_intensity)
	cfg.set_value("ui", "subtitles", subtitles)
	cfg.set_value("ui", "player_name", player_name)
	cfg.save(PATH)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	master_volume = cfg.get_value("audio", "master", master_volume)
	music_volume = cfg.get_value("audio", "music", music_volume)
	mouse_sensitivity = cfg.get_value("input", "sensitivity", mouse_sensitivity)
	field_of_view = cfg.get_value("video", "fov", field_of_view)
	crt_intensity = cfg.get_value("video", "crt", crt_intensity)
	retro_intensity = cfg.get_value("video", "retro", retro_intensity)
	subtitles = cfg.get_value("ui", "subtitles", subtitles)
	player_name = cfg.get_value("ui", "player_name", player_name)
