extends Node
## Writes `locale/kiosk.csv`, the file a translator is handed.
##
## Two passes, because neither one alone is complete.
##
## The first reads the source. Every string that reaches a player is either
## handed to `Loc.t()`/`Loc.f()` at the point it is written, or passed straight
## into one of the five `UIKit` builders that translate on the player's behalf.
## Those are precise patterns, so a regular expression finds all of them without
## having to run anything, including lines that only appear on a night that goes
## badly wrong.
##
## The second reads the content tables — the tells, the hints, the achievements,
## the greetings, the shopping — as the real dictionaries they are, so a new
## tell is in the template the moment it is written and nobody has to remember
## to come back here.
##
## What guards the whole thing is neither pass. `SmokeTest` plays the game with
## `Loc.recording` on and fails if it is asked to translate a string this file
## did not produce, so a gap becomes a red test rather than an English sentence
## in the middle of somebody's German.
##
##     godot --headless --path . tools/MakeTemplate.tscn

const OUT_PATH := "res://locale/kiosk.csv"
const SCAN_ROOTS := ["res://scripts"]

## Where a literal is player-facing purely by virtue of where it sits. The
## capture group is the string; everything else is anchoring.
const PATTERNS := [
	# Explicitly marked, anywhere in the game.
	'Loc\\.t\\(\\s*"((?:[^"\\\\]|\\\\.)*)"',
	'Loc\\.f\\(\\s*"((?:[^"\\\\]|\\\\.)*)"',
	# Both arms of a plural. `Loc.f("%d reading." if n == 1 else "%d readings.")`
	# is two strings a translator has to write, and the patterns above only see
	# the first — which made the coverage test pass or fail depending on whether
	# anybody happened to sweep two things that run.
	'Loc\\.[tf]\\(\\s*"(?:[^"\\\\]|\\\\.)*"\\s+if\\b[\\s\\S]*?\\belse\\s+"((?:[^"\\\\]|\\\\.)*)"',
	# The panel builders translate what they are given, so a literal argument
	# here is a translatable string that needs no call of its own.
	'UIKit\\.label\\(\\s*"((?:[^"\\\\]|\\\\.)*)"',
	'UIKit\\.rich\\(\\s*"((?:[^"\\\\]|\\\\.)*)"',
	'UIKit\\.modal\\(\\s*"((?:[^"\\\\]|\\\\.)*)"',
	# field() and option_row() take their label first and their value second.
	'UIKit\\.field\\(\\s*"((?:[^"\\\\]|\\\\.)*)"',
	'UIKit\\.field\\(\\s*"(?:[^"\\\\]|\\\\.)*"\\s*,\\s*"((?:[^"\\\\]|\\\\.)*)"',
	'UIKit\\.option_row\\([^,()]*,\\s*"((?:[^"\\\\]|\\\\.)*)"',
]

var _found: Dictionary = {}


func _ready() -> void:
	Log.mute(true)
	_scan_sources()
	var from_source := _found.size()
	_walk_content()
	var total := _found.size()

	var written := _write()
	print("")
	print("locale template")
	print("  from the source   : %d" % from_source)
	print("  from the tables   : %d" % (total - from_source))
	print("  written           : %d lines -> %s" % [written, OUT_PATH])
	print("")
	get_tree().quit(0 if written > 0 else 1)


# --- Pass one: the source ------------------------------------------------

func _scan_sources() -> void:
	var compiled: Array[RegEx] = []
	for pattern: String in PATTERNS:
		var rx := RegEx.new()
		if rx.compile(pattern) != OK:
			push_error("locale: bad pattern %s" % pattern)
			continue
		compiled.append(rx)

	for root: String in SCAN_ROOTS:
		for path: String in _gd_files(root):
			var text := FileAccess.get_file_as_string(path)
			if text.is_empty():
				continue
			for rx: RegEx in compiled:
				for m: RegExMatch in rx.search_all(text):
					_add(_unescape(m.get_string(1)))


static func _gd_files(root: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(root)
	if dir == null:
		return out
	for name: String in dir.get_files():
		if name.ends_with(".gd"):
			out.append(root.path_join(name))
	for name: String in dir.get_directories():
		out.append_array(_gd_files(root.path_join(name)))
	out.sort()
	return out


## Turns the escapes back into the characters the game will actually ask for.
## `Loc.t()` is handed a runtime string, not the source text, so a line written
## with `\n` in it has to be recorded with a real newline or the lookup misses.
##
## `\uXXXX` is in here for the same reason and cost a red coverage test to
## learn: the speech bubble wraps what a customer says in typographic quotes,
## written as escapes because the source stays ASCII, and a template that
## carries the six literal characters is a template with no entry for the string
## the game actually looks up.
static func _unescape(raw: String) -> String:
	var out := raw.replace("\\n", "\n").replace("\\t", "\t") \
		.replace("\\\"", "\"")
	var rx := RegEx.new()
	if rx.compile("\\\\u([0-9a-fA-F]{4})") == OK:
		# Right to left, so replacing one does not shift the next one's offsets.
		var hits := rx.search_all(out)
		hits.reverse()
		for m: RegExMatch in hits:
			var code := ("0x" + m.get_string(1)).hex_to_int()
			out = out.left(m.get_start()) + String.chr(code) + out.substr(m.get_end())
	return out.replace("\\\\", "\\")


# --- Pass two: the content tables ----------------------------------------

## Read as the live dictionaries rather than as text, so anything added to them
## lands in the template without this file being touched.
func _walk_content() -> void:
	for entry: Dictionary in Tells.CATALOGUE.values():
		for field: String in ["label", "prompt", "innocent", "guilty",
				"cleared_note", "confirmed_note"]:
			_add(str(entry.get(field, "")))
	for entry: Dictionary in Tells.BASE_QUESTIONS.values():
		_add(str(entry.get("prompt", "")))
	_add_all(Tells.EVASIVE)
	_add(Tells.EVASIVE_NOTE)

	_add_all(Tutor.HINTS.values())

	for entry: Dictionary in Achievements.CATALOGUE.values():
		_add(str(entry.get("name", "")))
		_add(str(entry.get("desc", "")))

	for table: Dictionary in [GameState.ITEMS, GameState.WEAPONS, GameState.DEFENSES]:
		for entry: Dictionary in table.values():
			_add(str(entry.get("name", "")))
			_add(str(entry.get("desc", "")))

	_add_all(Customer.GRUMBLES_MILD)
	_add_all(Customer.GRUMBLES_SHARP)
	_add_all(Customer.PUSH_LINES)
	_add_all(Customer.PUSHED_BACK_LINES)
	_add_all(Customer.EMPTY_HANDED)

	_add_all(ProfileGenerator.GREETINGS)
	_add_all(ProfileGenerator.ILLICIT_LINES)
	_add_all(ProfileGenerator.STALE_SLANG_LINES)
	_add_all(ProfileGenerator.RECORD_POOL)
	_add_all(ProfileGenerator.CAR_COLOURS)
	_add_all(ProfileGenerator.MONTHS)
	_add_all(ProfileGenerator.UTILITIES_POOL)
	_add_all(ProfileGenerator.KIN_RELATIONS)
	for job: Dictionary in ProfileGenerator.JOBS:
		_add(str(job["occupation"]))

	# The names beside each key in the controls page.
	for entry: Array in InputSetup.REBINDABLE:
		_add(str(entry[1]))


func _add_all(values) -> void:
	for v in values:
		_add(str(v))


func _add(text: String) -> void:
	if text.is_empty():
		return
	# Numbers, brackets and separators are furniture, not language. Same rule
	# the recorder uses, so the two passes agree on what counts.
	var has_letter := false
	for i in text.length():
		var c := text[i]
		if c.to_upper() != c.to_lower():
			has_letter = true
			break
	if has_letter:
		_found[text] = true


# --- Writing -------------------------------------------------------------

## `key,en` and nothing else. A translator adds a column, names it with their
## locale code, and fills it in; anything they leave blank falls back to the
## English in the column beside it. Sorted, so the diff between two runs is the
## lines that actually changed rather than a reshuffle.
func _write() -> int:
	var keys := _found.keys()
	keys.sort()

	DirAccess.make_dir_recursive_absolute(OUT_PATH.get_base_dir())
	var file := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	if file == null:
		push_error("locale: cannot write %s (%d)" % [OUT_PATH, FileAccess.get_open_error()])
		return 0

	file.store_csv_line(PackedStringArray(["key", "en"]))
	for key: String in keys:
		file.store_csv_line(PackedStringArray([key, key]))
	file.close()
	return keys.size()
