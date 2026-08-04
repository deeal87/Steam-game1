class_name EasterEgg
extends Area3D
## The thing at the end of the road.
##
## It is a long way west, past the last working lamp, in an alcove between two
## dead buildings. You cannot see it from the kiosk and nothing points at it.
## Walking into it is the only way to find it, and doing so takes a screenshot
## by itself — the whole point is to have proof you got there.

signal found(screenshot_path: String)

const REVEAL_RANGE := 9.0

var _plaque: Label3D
var _lamp: OmniLight3D
var _triggered: bool = false


func _ready() -> void:
	name = "EasterEgg"
	monitoring = true
	monitorable = false
	# Only watch for the player's body layer.
	collision_layer = 0
	collision_mask = 0
	set_collision_mask_value(1, true)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, 3.0, 4.0)
	shape.shape = box
	add_child(shape)

	body_entered.connect(_on_body_entered)


func build_visuals(world: World) -> void:
	var name_text := PlayerIdentity.display_name().to_upper()

	# Label3D draws real text in 3D using the engine's built-in font, so the
	# plaque can carry a name that is only known at runtime without needing a
	# texture, a font file, or anything else on disk.
	# Label3D measures in font pixels and then scales by `pixel_size`, so the
	# world width is font_size * pixel_size * characters. Wrapping is set to the
	# board's own width in the same units, which is what keeps a long Steam name
	# on the board instead of halfway across the alley.
	const BOARD_W := 4.6
	const BOARD_H := 2.0
	const PIXEL_SIZE := 0.0012

	_plaque = Label3D.new()
	_plaque.text = "YOU ARE THE\nMASTER OF MASTER\n%s" % name_text
	_plaque.font_size = 64
	_plaque.outline_size = 14
	_plaque.modulate = Color(1.0, 0.86, 0.42)
	_plaque.outline_modulate = Color(0.05, 0.03, 0.0)
	_plaque.pixel_size = PIXEL_SIZE
	_plaque.width = (BOARD_W - 0.3) / PIXEL_SIZE
	_plaque.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_plaque.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_plaque.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_plaque.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	_plaque.shaded = false
	# Double-sided and stood proud of the board on the street side, so which way
	# Label3D happens to face by default cannot leave the sign blank.
	_plaque.double_sided = true
	_plaque.position = Vector3(0, 1.85, -0.10)
	_plaque.rotation_degrees = Vector3(0, 180, 0)
	add_child(_plaque)

	# The board it is screwed to. The text sits on the face pointing back down
	# the street, which is the side you arrive from.
	add_child(ProcMesh.box(Vector3(BOARD_W, BOARD_H, 0.12), Vector3(0, 1.85, 0),
		ProcMesh.mat(ProcTex.grime(Color(0.16, 0.13, 0.10), 0.4, 777), 1.0), "Board"))

	# It is not lit until you are almost on top of it. From any distance this
	# corner is simply the place where the street stops.
	_lamp = OmniLight3D.new()
	_lamp.position = Vector3(0, 2.4, 1.4)
	_lamp.light_color = Color(1.0, 0.80, 0.40)
	_lamp.light_energy = 0.0
	_lamp.omni_range = 7.0
	add_child(_lamp)


func _process(delta: float) -> void:
	if _lamp == null:
		return
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	var player: Node3D = players[0]
	var d := global_position.distance_to(player.global_position)
	# Fades up over the last few metres, so it emerges from the dark rather
	# than snapping on.
	var target: float = clampf(1.0 - (d / REVEAL_RANGE), 0.0, 1.0) * 2.6
	_lamp.light_energy = lerpf(_lamp.light_energy, target, delta * 3.0)


func _on_body_entered(body: Node3D) -> void:
	if _triggered or not body.is_in_group("player"):
		return
	_triggered = true
	GameState.found_easter_egg = true
	GameState.save_run()
	Audio.play("confirm", -6.0)
	# The capture itself is the game's job — it owns the viewport.
	found.emit("")
