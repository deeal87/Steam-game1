class_name PlayerIdentity
extends RefCounted
## Works out what to call the player.
##
## Order of preference:
##
##   1. A name they typed into the settings menu.
##   2. Their Steam persona name, if GodotSteam is present. The plugin is not
##      bundled — it is a per-platform binary and this repository deliberately
##      ships no binaries — but the call is written so that dropping GodotSteam
##      in and initialising it is all that is needed. No code change here.
##   3. The operating system account name.
##   4. A shrug.

const FALLBACK := "STRANGER"


static func display_name() -> String:
	var override := Settings.player_name.strip_edges()
	if not override.is_empty():
		return override

	var steam := steam_name()
	if not steam.is_empty():
		return steam

	var os_name := os_account_name()
	if not os_name.is_empty():
		return os_name

	return FALLBACK


## Returns the Steam persona name, or "" when Steam is not available.
##
## Guarded on every step: the singleton may be absent, may be present but not
## initialised, and may return an empty string or the placeholder Steam hands
## back before the user's profile has loaded.
static func steam_name() -> String:
	if not Engine.has_singleton("Steam"):
		return ""
	var steam := Engine.get_singleton("Steam")
	if not steam.has_method("getPersonaName"):
		return ""
	var name := ""
	if steam.has_method("isSteamRunning") and not steam.call("isSteamRunning"):
		return ""
	name = str(steam.call("getPersonaName")).strip_edges()
	if name.is_empty() or name == "[unknown]":
		return ""
	return name


static func os_account_name() -> String:
	for key: String in ["USERNAME", "USER", "LOGNAME"]:
		var value := OS.get_environment(key).strip_edges()
		if not value.is_empty():
			return value
	return ""


## True when the name came from Steam, so the game can say so honestly rather
## than implying a Steam connection it does not have.
static func is_steam_name() -> bool:
	return Settings.player_name.strip_edges().is_empty() and not steam_name().is_empty()
