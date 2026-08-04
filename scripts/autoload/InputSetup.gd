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


func _ensure_action(action: String) -> void:
	if InputMap.has_action(action):
		InputMap.action_erase_events(action)
	else:
		InputMap.add_action(action)


## Returns the 1-based choice index pressed this frame, or -1.
static func choice_pressed() -> int:
	for i in CHOICE_KEYS.size():
		if Input.is_action_just_pressed("choice_%d" % (i + 1)):
			return i + 1
	return -1
