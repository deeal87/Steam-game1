extends Node
## Registers the input map in code.
##
## Godot normally stores bindings inside project.godot as serialised event
## objects, which are painful to read or review in a diff. Building the map at
## boot keeps every binding in one legible place.

const BINDINGS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"sprint": [KEY_SHIFT],
	"crouch": [KEY_CTRL],
	"jump": [KEY_SPACE],
	"interact": [KEY_E],
	"scanner": [KEY_F],
	"holster": [KEY_X],
	"reload": [KEY_R],
	"notebook": [KEY_TAB],
	"cancel": [KEY_ESCAPE],
	"restock": [KEY_Q],
	"torch": [KEY_T],
}

const MOUSE_BINDINGS := {
	"fire": MOUSE_BUTTON_LEFT,
	"aim": MOUSE_BUTTON_RIGHT,
}

## What each action is called in the rebinding menu, and the order they appear
## in. Anything not listed here is not rebindable — the number keys pick
## dialogue options and are needed to navigate the menu itself.
const REBINDABLE := [
	["move_forward", "Forward"],
	["move_back", "Back"],
	["move_left", "Left"],
	["move_right", "Right"],
	["sprint", "Run"],
	["crouch", "Crouch"],
	["jump", "Jump"],
	["interact", "Use / scan / talk"],
	["restock", "Refill shelf"],
	["scanner", "Sweep with scanner"],
	["torch", "Torch"],
	["notebook", "Notepad"],
	["holster", "Change hands"],
	["reload", "Reload"],
]

const OVERRIDE_PATH := "user://keybinds.cfg"


## Number keys pick dialogue options and shop rows.
const CHOICE_KEYS := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9]


func _ready() -> void:
	for action: String in BINDINGS:
		_ensure_action(action)
		for code: int in BINDINGS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = code
			InputMap.action_add_event(action, ev)

	for action: String in MOUSE_BINDINGS:
		_ensure_action(action)
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BINDINGS[action]
		InputMap.action_add_event(action, ev)

	for i in CHOICE_KEYS.size():
		var action := "choice_%d" % (i + 1)
		_ensure_action(action)
		var ev := InputEventKey.new()
		ev.physical_keycode = CHOICE_KEYS[i]
		InputMap.action_add_event(action, ev)

	load_overrides()


func _ensure_action(action: String) -> void:
	if InputMap.has_action(action):
		InputMap.action_erase_events(action)
	else:
		InputMap.add_action(action)


## Replaces every binding on an action with a single event.
##
## Bindings are stored as *physical* keycodes, which is why nothing here has to
## care that the player is on QWERTZ or AZERTY: W is the key where W is, not the
## letter printed on it. Rebinding is still needed — physical layout does not
## help someone playing left-handed or with one hand.
func rebind(action: String, event: InputEvent) -> bool:
	if not InputMap.has_action(action):
		return false
	# Refuse a key already doing another job, rather than silently making two
	# things happen at once.
	for other: Array in REBINDABLE:
		if other[0] == action:
			continue
		for existing: InputEvent in InputMap.action_get_events(other[0]):
			if _same_key(existing, event):
				return false
	if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
		return false

	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, event)
	save_overrides()
	return true


static func _same_key(a: InputEvent, b: InputEvent) -> bool:
	if a is InputEventKey and b is InputEventKey:
		return (a as InputEventKey).physical_keycode == (b as InputEventKey).physical_keycode
	if a is InputEventMouseButton and b is InputEventMouseButton:
		return (a as InputEventMouseButton).button_index == (b as InputEventMouseButton).button_index
	return false


## Human-readable name of whatever is currently bound to an action.
static func binding_label(action: String) -> String:
	if not InputMap.has_action(action):
		return "—"
	for ev: InputEvent in InputMap.action_get_events(action):
		if ev is InputEventKey:
			return OS.get_keycode_string((ev as InputEventKey).physical_keycode)
		if ev is InputEventMouseButton:
			return "Mouse %d" % (ev as InputEventMouseButton).button_index
	return "—"


func save_overrides() -> void:
	var cfg := ConfigFile.new()
	for entry: Array in REBINDABLE:
		var action: String = entry[0]
		for ev: InputEvent in InputMap.action_get_events(action):
			if ev is InputEventKey:
				cfg.set_value("keys", action, (ev as InputEventKey).physical_keycode)
				break
	cfg.save(OVERRIDE_PATH)


func load_overrides() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(OVERRIDE_PATH) != OK:
		return
	for entry: Array in REBINDABLE:
		var action: String = entry[0]
		var code: int = cfg.get_value("keys", action, 0)
		if code == 0 or not InputMap.has_action(action):
			continue
		var ev := InputEventKey.new()
		ev.physical_keycode = code
		InputMap.action_erase_events(action)
		InputMap.action_add_event(action, ev)


## Puts every binding back to the built-in default.
func reset_bindings() -> void:
	for entry: Array in REBINDABLE:
		var action: String = entry[0]
		if not BINDINGS.has(action):
			continue
		_ensure_action(action)
		for code: int in BINDINGS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = code
			InputMap.action_add_event(action, ev)
	if FileAccess.file_exists(OVERRIDE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(OVERRIDE_PATH))


## Returns the 1-based choice index pressed this frame, or -1.
static func choice_pressed() -> int:
	for i in CHOICE_KEYS.size():
		if Input.is_action_just_pressed("choice_%d" % (i + 1)):
			return i + 1
	return -1
