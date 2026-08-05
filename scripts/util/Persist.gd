class_name Persist
extends RefCounted
## Writing things to disk, and noticing when that does not work.
##
## Every `ConfigFile.save()` in this project used to be called for its side
## effect and its return value thrown away. That is fine right up until it
## isn't: a full disk, a read-only profile directory, a Steam Cloud conflict
## mid-write, or an antivirus holding the file open all make the call fail, and
## all of them used to fail *silently*. The player finds out when they relaunch
## and their run is gone.
##
## So: one place that writes config files, logs what happened, and — when the
## thing being written is something the player would grieve — tells them on
## screen while they can still do something about it.

## Config paths in `user://`, so they sit together and Steam Cloud can be pointed
## at one directory rather than five scattered names.
static func write(cfg: ConfigFile, path: String, what: String,
		tell_player: bool = false) -> bool:
	var err := cfg.save(path)
	if err == OK:
		return true

	Log.error("could not write %s to %s (error %d: %s)"
		% [what, path, err, error_string(err)])
	if tell_player:
		# Worth interrupting for. Losing a night's takings to a disk that
		# silently refused the write is the worst outcome this game has, and it
		# is the one thing the player can still act on — quit, free some space,
		# and the run is still in memory.
		Signals.notice.emit(
			"Could not save your %s. Check disk space before you quit." % what, "bad")
	return false


## Reads a config, distinguishing "not there yet" from "there and broken".
##
## The difference matters. A missing file on first run is normal and silent; a
## file that exists and will not parse means something corrupted it, and that is
## worth a line in the log even though the game recovers by using defaults.
static func read(cfg: ConfigFile, path: String, what: String) -> bool:
	var err := cfg.load(path)
	if err == OK:
		return true
	if err == ERR_FILE_NOT_FOUND:
		return false
	Log.warn("%s at %s could not be read (error %d: %s) — using defaults"
		% [what, path, err, error_string(err)])
	return false
