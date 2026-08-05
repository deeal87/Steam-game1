extends Node
## The log a player can send you when something goes wrong.
##
## Until now the game wrote nothing anywhere. A bug report from a stranger would
## have been "it crashed" and nothing else — no platform, no renderer, no idea
## which night they were on or what the game was doing at the time. That is the
## difference between a fixable report and an unfixable one.
##
## Two files, both in `user://` next to the saves so Steam Cloud picks them up:
## the current run's log, and the previous run's. The previous one is the
## important half — a crash means the player relaunches to tell you about it, and
## a single log file would already have been overwritten by the time they did.
##
## Everything also goes to stdout, so `--verbose` and an attached console show
## the same thing, and errors additionally go through `push_error` so Godot's own
## reporting sees them.

const PATH := "user://kiosk.log"
const PREVIOUS := "user://kiosk.previous.log"
## Past this the file is truncated rather than left to grow without limit. A
## player who leaves the game running for a week should not find a gigabyte of
## text in their profile.
const MAX_BYTES := 512 * 1024

var _file: FileAccess = null
var _written: int = 0
var _muted: bool = false


func _ready() -> void:
	_rotate()
	_file = FileAccess.open(PATH, FileAccess.WRITE)
	if _file == null:
		# Nowhere to write. Not fatal — the game runs fine without a log — but
		# say so once on stdout rather than failing silently every call.
		printerr("[log] could not open %s (error %d); logging to stdout only"
			% [PATH, FileAccess.get_open_error()])
		return
	_header()


## Keeps exactly one previous run, because that is the one that has the crash in
## it. Any further history is somebody else's problem.
func _rotate() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var previous := ProjectSettings.globalize_path(PREVIOUS)
	if FileAccess.file_exists(PREVIOUS):
		DirAccess.remove_absolute(previous)
	DirAccess.rename_absolute(ProjectSettings.globalize_path(PATH), previous)


## What a bug report needs before the first line of gameplay: which build, which
## machine, which renderer, which screen. Nearly every "cannot reproduce" comes
## down to one of these being different from the reporter's.
func _header() -> void:
	var v := Engine.get_version_info()
	info("Kiosk At Midnight %s — %s" % [
		ProjectSettings.get_setting("application/config/version", "unversioned"),
		Time.get_datetime_string_from_system(true, true)])
	info("godot %s.%s.%s %s · %s %s" % [v["major"], v["minor"], v["patch"], v["status"],
		OS.get_name(), OS.get_distribution_name()])
	info("renderer: %s · display: %s" % [
		RenderingServer.get_video_adapter_name() if DisplayServer.get_name() != "headless" else "headless",
		DisplayServer.get_name()])
	if DisplayServer.get_name() != "headless":
		var screen := DisplayServer.window_get_current_screen()
		var size := DisplayServer.screen_get_size(screen)
		# Refresh rate comes back as -1 when the platform will not say — a
		# virtual display, some Wayland setups, some remote sessions. Printed as
		# "unknown" rather than run through int(), which turns it into a
		# nine-quintillion-hertz monitor and makes the whole log look wrong.
		var hz := DisplayServer.screen_get_refresh_rate(screen)
		var hz_text := "%d Hz" % int(round(hz)) if hz > 0.0 else "refresh rate unknown"
		info("screen %d: %d x %d, %s · %d screens attached"
			% [screen, size.x, size.y, hz_text, DisplayServer.get_screen_count()])
	info("cpu: %s (%d threads) · memory: %d MB" % [
		OS.get_processor_name(), OS.get_processor_count(),
		int(OS.get_memory_info().get("physical", 0)) / 1048576])
	info("---")


func info(message: String) -> void:
	_write("INFO", message)


func warn(message: String) -> void:
	_write("WARN", message)
	push_warning(message)


func error(message: String) -> void:
	_write("ERROR", message)
	# Through Godot's own channel as well, so it lands in the editor's error
	# panel and in whatever crash reporting is attached to a release build.
	push_error(message)


## Silences the file during tests, which run thousands of operations and have no
## use for a log of them.
func mute(quiet: bool) -> void:
	_muted = quiet


func _write(level: String, message: String) -> void:
	if _muted:
		return
	var line := "%7.2f  %-5s  %s" % [
		float(Time.get_ticks_msec()) / 1000.0, level, message]
	print(line)
	if _file == null or _written > MAX_BYTES:
		return
	_file.store_line(line)
	_written += line.length() + 1
	# Flushed every line rather than on close: a log that is still in a buffer
	# when the process dies is a log of everything except the interesting part.
	_file.flush()
