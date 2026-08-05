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

## Gamepad, laid out the way a first-person game on a pad is expected to be.
##
## Not an afterthought: this game is a strong fit for a handheld — it is a
## seated, slow, reading-heavy game in a small room — and without a pad it
## simply cannot be played on a Steam Deck at all. The face buttons follow the
## platform convention (south confirms, east cancels) so nobody has to learn
## them, and the two triggers do what triggers do.
const PAD_BINDINGS := {
	"interact": [JOY_BUTTON_A],
	"cancel": [JOY_BUTTON_B, JOY_BUTTON_START],
	"restock": [JOY_BUTTON_X],
	"torch": [JOY_BUTTON_Y],
	"notebook": [JOY_BUTTON_BACK],
	"crouch": [JOY_BUTTON_LEFT_STICK],
	"sprint": [JOY_BUTTON_LEFT_SHOULDER],
	"scanner": [JOY_BUTTON_RIGHT_SHOULDER],
	"holster": [JOY_BUTTON_DPAD_UP],
	"reload": [JOY_BUTTON_DPAD_DOWN],
	"jump": [JOY_BUTTON_DPAD_LEFT],
}

## Triggers are axes, not buttons, so they bind separately.
const PAD_TRIGGERS := {
	"fire": JOY_AXIS_TRIGGER_RIGHT,
	"aim": JOY_AXIS_TRIGGER_LEFT,
}

## The left stick walks, the right stick looks. Each entry is [axis, direction].
const PAD_MOVEMENT := {
	"move_left": [JOY_AXIS_LEFT_X, -1.0],
	"move_right": [JOY_AXIS_LEFT_X, 1.0],
	"move_forward": [JOY_AXIS_LEFT_Y, -1.0],
	"move_back": [JOY_AXIS_LEFT_Y, 1.0],
	"look_left": [JOY_AXIS_RIGHT_X, -1.0],
	"look_right": [JOY_AXIS_RIGHT_X, 1.0],
	"look_up": [JOY_AXIS_RIGHT_Y, -1.0],
	"look_down": [JOY_AXIS_RIGHT_Y, 1.0],
}

## Numbered choices — dialogue options, shop rows — are picked with the number
## keys on a keyboard, which a pad does not have. So the pad gets a cursor: the
## d-pad steps it and the south button takes whatever is highlighted. The panels
## draw the highlight; these are just the stepping.
const PAD_UI := {
	"choice_next": [JOY_BUTTON_DPAD_DOWN],
	"choice_prev": [JOY_BUTTON_DPAD_UP],
	"choice_take": [JOY_BUTTON_A],
}

## Below this the right stick is treated as noise rather than as looking around.
const STICK_DEADZONE := 0.18

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

	_bind_gamepad()
	load_overrides()


## Adds the pad on top of the keyboard rather than instead of it, so both are
## live at once and a player can put the pad down mid-shift and keep going.
func _bind_gamepad() -> void:
	for action: String in PAD_BINDINGS:
		_ensure_action_exists(action)
		for button: int in PAD_BINDINGS[action]:
			var ev := InputEventJoypadButton.new()
			ev.button_index = button
			InputMap.action_add_event(action, ev)

	for action: String in PAD_TRIGGERS:
		_ensure_action_exists(action)
		var ev := InputEventJoypadMotion.new()
		ev.axis = PAD_TRIGGERS[action]
		ev.axis_value = 1.0
		InputMap.action_add_event(action, ev)

	for action: String in PAD_MOVEMENT:
		_ensure_action_exists(action)
		var conf: Array = PAD_MOVEMENT[action]
		var ev := InputEventJoypadMotion.new()
		ev.axis = conf[0]
		ev.axis_value = conf[1]
		InputMap.action_add_event(action, ev)

	for action: String in PAD_UI:
		_ensure_action_exists(action)
		for button: int in PAD_UI[action]:
			var ev := InputEventJoypadButton.new()
			ev.button_index = button
			InputMap.action_add_event(action, ev)

	# Deadzones on the sticks, so a worn thumbstick does not walk you into the
	# street while you are reading somebody's file.
	for action: String in PAD_MOVEMENT:
		InputMap.action_set_deadzone(action, STICK_DEADZONE)


## Like `_ensure_action` but never wipes what is already bound — the gamepad is
## added alongside the keyboard, not in place of it.
func _ensure_action_exists(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)


func _ensure_action(action: String) -> void:
	if InputMap.has_action(action):
		InputMap.action_erase_events(action)
	else:
		InputMap.add_action(action)


## Clears the keyboard and mouse events on an action and leaves the gamepad
## alone.
##
## Rebinding used to call `action_erase_events`, which was right when a key was
## the only thing an action could carry. Now that every action also has a pad
## button, wiping the lot means changing one key silently unbinds the whole
## controller — and so did loading saved overrides at boot, and so did pressing
## "reset to defaults". A player on a Deck who ever touched the controls menu
## would have found the pad simply stopped working, with nothing to explain it.
static func _erase_manual_events(action: String) -> void:
	if not InputMap.has_action(action):
		return
	for ev: InputEvent in InputMap.action_get_events(action):
		if ev is InputEventKey or ev is InputEventMouseButton:
			InputMap.action_erase_event(action, ev)


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

	_erase_manual_events(action)
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
	Persist.write(cfg, OVERRIDE_PATH, "key bindings")


func load_overrides() -> void:
	var cfg := ConfigFile.new()
	if not Persist.read(cfg, OVERRIDE_PATH, "key bindings"):
		return
	for entry: Array in REBINDABLE:
		var action: String = entry[0]
		var code: int = cfg.get_value("keys", action, 0)
		if code == 0 or not InputMap.has_action(action):
			continue
		var ev := InputEventKey.new()
		ev.physical_keycode = code
		_erase_manual_events(action)
		InputMap.action_add_event(action, ev)


## Puts every binding back to the built-in default.
func reset_bindings() -> void:
	for entry: Array in REBINDABLE:
		var action: String = entry[0]
		if not BINDINGS.has(action):
			continue
		_erase_manual_events(action)
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
