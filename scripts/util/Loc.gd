class_name Loc
extends RefCounted
## Every word the player reads passes through here.
##
## The game is written in English and ships in English. That is not the same as
## being *stuck* in English, and the difference is entirely down to whether the
## strings are reachable. So the rule is: the English text stays where it is,
## written inline next to the code that decides to show it, because that is
## where it is readable and where it gets edited. What changes is that nothing
## reaches a label without being handed to `t()` or `f()` first.
##
## The source English string is its own key. There is no `MENU_TITLE_02` layer
## to keep in sync, nothing to look up while writing a line, and a missing
## translation degrades to the English original rather than to a shouty
## identifier. `tools/MakeTemplate.gd` walks the code and the content tables and
## writes `locale/kiosk.csv`, which is the file a translator is handed; a test
## records every string the running game actually asks for and fails if one of
## them is not in that file, so the template cannot quietly rot.
##
## Translations are plain CSV read at runtime, not imported resources. That
## means somebody can drop a file into `user://locale/` and play the game in
## their own language without a rebuild, and it means the whole system is one
## file with no import step behind it.

## Shipped translations. One CSV, one column per language.
const BUILTIN_DIR := "res://locale"
## Anything a player drops in here wins over the shipped file, so a community
## translation can be installed and corrected without touching the game.
const PLAYER_DIR := "user://locale"

## The language the game is written in. Its column exists in the template so a
## translator has the source text beside their own, but it is never looked up —
## English is what `t()` returns when it finds nothing.
const SOURCE_LOCALE := "en"

## locale code -> { source string: translated string }
static var _tables: Dictionary = {}
static var _locale: String = SOURCE_LOCALE
static var _loaded: bool = false

## Turned on by the template tool and by the coverage test. Off in the game,
## where it would be a dictionary insert per label per frame.
static var recording: bool = false
static var _seen: Dictionary = {}
## Strings `f()` has already built. A composed line — "Night 3. Rent is 240 by
## five." — reaches the same labels as a written one, and without this it would
## be recorded as if a translator had to handle it. Only populated while
## recording, and thrown away with the rest of it.
static var _composed: Dictionary = {}


# --- Translating ---------------------------------------------------------

## The whole interface goes through this. Returns `text` unchanged when there
## is no translation for it, which is the normal case and the English case.
static func t(text: String) -> String:
	if recording and _has_letters(text) and not _composed.has(text):
		_seen[text] = true
	if not _loaded:
		load_tables()
	if _locale == SOURCE_LOCALE:
		return text
	var table: Dictionary = _tables.get(_locale, {})
	var hit: Variant = table.get(text)
	if hit == null:
		return text
	return String(hit)


## Translate first, then format. The format string is what gets translated —
## composing English and then looking up the result would mean asking for
## "Night 3. Rent is 240 by five." and never finding it.
##
## A translation that has lost or gained a placeholder would crash the `%`, so
## one that does not match the original is refused and the English is used.
## That matters because these files are meant to be editable by players.
static func f(text: String, args: Array) -> String:
	var pattern := t(text)
	if pattern != text and _specifiers(pattern) != _specifiers(text):
		pattern = text
	var built: String = pattern % args
	if recording:
		_composed[built] = true
	return built


## Marks a string that is already in the player's language — a paragraph
## assembled line by line, a registry field built out of translated parts — so
## the label it eventually lands in does not record the whole assembled thing
## as one more line for a translator to write. Returns it unchanged.
static func done(text: String) -> String:
	if recording:
		_composed[text] = true
	return text


## Whether a string is a *sentence* or a piece of furniture. The interface is
## full of strings that pass through the same labels as prose — "[3]", ">",
## "04:12", "%d/%d" — and putting those in front of a translator is asking them
## to check a hundred rows that can never change. Only checked while recording;
## the lookup itself does not care, because a miss costs nothing.
static func _has_letters(text: String) -> bool:
	for i in text.length():
		var c := text[i]
		if c.to_upper() != c.to_lower():
			return true
	return false


## Counts real `%` conversions, ignoring the `%%` escape. Used only to decide
## whether a translation is safe to format with.
static func _specifiers(text: String) -> int:
	var count := 0
	var i := 0
	while i < text.length():
		if text[i] != "%":
			i += 1
			continue
		if i + 1 < text.length() and text[i + 1] == "%":
			i += 2
			continue
		count += 1
		i += 1
	return count


# --- Which language ------------------------------------------------------

static func locale() -> String:
	if not _loaded:
		load_tables()
	return _locale


## Silently ignores a language there is no table for, so a settings file
## carried over from a build that had one more translation than this one does
## not leave the player staring at an empty menu.
static func set_locale(code: String) -> void:
	if not _loaded:
		load_tables()
	if code == SOURCE_LOCALE or _tables.has(code):
		_locale = code


## English first, then whatever else was found, in a stable order so the menu
## does not reshuffle itself between runs.
static func locales() -> PackedStringArray:
	if not _loaded:
		load_tables()
	var out := PackedStringArray([SOURCE_LOCALE])
	var rest := _tables.keys()
	rest.sort()
	for code: String in rest:
		if code != SOURCE_LOCALE:
			out.append(code)
	return out


## What to put in the menu. `TranslationServer` knows the endonyms, so there is
## no table of language names here to fall out of date.
static func locale_name(code: String) -> String:
	var named := TranslationServer.get_locale_name(code)
	if named.is_empty():
		return code
	return named


## The language to start in when the player has never chosen one: theirs, if
## the game has it, and English otherwise.
static func detect() -> String:
	if not _loaded:
		load_tables()
	var want := OS.get_locale_language()
	if _tables.has(want):
		return want
	return SOURCE_LOCALE


# --- Loading -------------------------------------------------------------

## Shipped tables first, then the player's directory over the top, so a
## community fix to one line replaces that line and leaves the rest alone.
static func load_tables() -> void:
	_loaded = true
	_tables.clear()
	_read_dir(BUILTIN_DIR)
	_read_dir(PLAYER_DIR)


## Re-reads everything and keeps the current language if it survived. For the
## tests, and for anyone editing a translation with the game still open.
static func reload() -> void:
	var was := _locale
	load_tables()
	_locale = SOURCE_LOCALE
	set_locale(was)


static func _read_dir(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var names := DirAccess.get_files_at(path)
	names.sort()
	for name: String in names:
		# Exported CSVs keep their name; a stray `.import` sidecar must not be
		# mistaken for a table.
		if not name.to_lower().ends_with(".csv"):
			continue
		_read_file(path.path_join(name))


## Reads one table. The first row names the columns: `key` and then one code
## per language. A row with fewer cells than the header is short rather than
## broken — the missing languages simply have nothing for that line.
static func _read_file(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		Log.warn("locale: cannot read %s (%d)" % [path, FileAccess.get_open_error()])
		return

	var header := file.get_csv_line()
	if header.size() < 2 or header[0].strip_edges().to_lower() != "key":
		Log.warn("locale: %s has no key column, ignoring" % path)
		return

	var codes := PackedStringArray()
	for i in range(1, header.size()):
		codes.append(header[i].strip_edges())

	var rows := 0
	while not file.eof_reached():
		var line := file.get_csv_line()
		if line.is_empty():
			continue
		var key := line[0]
		if key.is_empty():
			continue
		for i in range(1, line.size()):
			var code: String = codes[i - 1] if i - 1 < codes.size() else ""
			# The English column is the source text repeated for the
			# translator's benefit. Storing it would only cost memory.
			if code.is_empty() or code == SOURCE_LOCALE:
				continue
			var value := line[i]
			if value.is_empty():
				continue
			if not _tables.has(code):
				_tables[code] = {}
			(_tables[code] as Dictionary)[key] = value
		rows += 1
	Log.info("locale: %s — %d lines, %s" % [path.get_file(), rows, ", ".join(codes)])


# --- For the template tool and the coverage test -------------------------

## Every distinct string the game has asked to translate since recording began.
static func seen() -> PackedStringArray:
	var out := PackedStringArray()
	for key: String in _seen:
		out.append(key)
	out.sort()
	return out


static func forget() -> void:
	_seen.clear()
	_composed.clear()


## What the shipped template contains, as a set. Used by the coverage test to
## check nothing the game says is missing from it.
static func template_keys(path: String = BUILTIN_DIR.path_join("kiosk.csv")) -> Dictionary:
	var out: Dictionary = {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return out
	var header := file.get_csv_line()
	if header.size() < 1:
		return out
	while not file.eof_reached():
		var line := file.get_csv_line()
		if line.is_empty() or line[0].is_empty():
			continue
		out[line[0]] = true
	return out
