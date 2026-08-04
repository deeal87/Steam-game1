class_name World
extends Node3D
## Builds the kiosk and the street it stands on.
##
## The kiosk is a sealed box roughly 4.5 m by 3.5 m and you never leave it.
## Customers come out of the dark to a hatch in the front wall. That geometry
## is the whole premise: everything dangerous is on the other side of a pane of
## glass and a counter, right up until it isn't.

# Interior extents. Everything else is positioned relative to these.
const HALF_X := 2.25
const HALF_Z := 1.75
const CEILING := 2.60

const HATCH_WIDTH := 1.70
const HATCH_BOTTOM := 1.00
const HATCH_TOP := 1.95
const COUNTER_Y := 1.00

## Where a customer stands to be served, and where they walk in from.
## Close enough to the hatch that they fill it. Any further out and they are a
## silhouette in the fog, which looks atmospheric and makes the game unplayable.
const CUSTOMER_STAND := Vector3(0, 0, -HALF_Z - 0.52)
const CUSTOMER_ENTRY := Vector3(7.5, 0, -6.0)
const CUSTOMER_EXIT := Vector3(-8.5, 0, -7.0)

var anchors: Dictionary = {}
var shelf_slots: Dictionary = {}      ## item_id -> Array[MeshInstance3D]
var cash_pickups: Array[Node3D] = []
var strip_light: OmniLight3D
var sign_light: OmniLight3D
var _breach_points: Array[Vector3] = []

var _mats: Dictionary = {}


func _ready() -> void:
	name = "World"
	_build_materials()
	_build_environment()
	_build_street()
	_build_kiosk_shell()
	_build_counter()
	_build_fittings()
	_build_shelving()
	refresh_shelves()


# --- Materials ---------------------------------------------------------------

func _build_materials() -> void:
	_mats["asphalt"] = ProcMesh.mat(ProcTex.asphalt(7), 6.0)
	_mats["pavement"] = ProcMesh.mat(ProcTex.grime(Color(0.20, 0.20, 0.21), 0.5, 12), 4.0)
	_mats["brick"] = ProcMesh.mat(ProcTex.brick(21), 3.0)
	_mats["brick_far"] = ProcMesh.mat(ProcTex.brick(33), 6.0, Color.BLACK, 0.0, Color(0.55, 0.55, 0.6))
	_mats["floor"] = ProcMesh.mat(ProcTex.tiles(41), 3.0)
	_mats["wall"] = ProcMesh.mat(ProcTex.grime(Color(0.38, 0.37, 0.33), 0.45, 55), 2.0)
	_mats["ceiling"] = ProcMesh.mat(ProcTex.grime(Color(0.26, 0.26, 0.25), 0.5, 61), 2.0)
	_mats["counter"] = ProcMesh.mat(ProcTex.grime(Color(0.30, 0.24, 0.18), 0.4, 71), 2.0)
	_mats["steel"] = ProcMesh.mat(ProcTex.metal(Color(0.30, 0.31, 0.33), 81))
	_mats["dark_steel"] = ProcMesh.mat(ProcTex.metal(Color(0.14, 0.14, 0.16), 83))
	_mats["shutter"] = ProcMesh.mat(ProcTex.corrugated(Color(0.26, 0.26, 0.28), 91), 2.0)
	_mats["glass"] = ProcMesh.mat(ProcTex.flat(Color(0.30, 0.35, 0.38)), 1.0, Color(0.4, 0.5, 0.55), 0.06)
	_mats["screen"] = ProcMesh.mat(ProcTex.flat(Color(0.10, 0.35, 0.16)), 1.0, Color(0.20, 0.85, 0.35), 1.3)
	_mats["neon"] = ProcMesh.mat(ProcTex.neon_sign(Color(1.0, 0.25, 0.45), 5), 1.0, Color(1.0, 0.25, 0.45), 2.2)
	_mats["lamp"] = ProcMesh.mat(ProcTex.flat(Color(1.0, 0.92, 0.72)), 1.0, Color(1.0, 0.90, 0.66), 2.0)
	_mats["cash"] = ProcMesh.mat(ProcTex.flat(Color(0.55, 0.62, 0.42)), 1.0, Color(0.4, 0.5, 0.3), 0.25)


func mat(id: String) -> Material:
	return _mats.get(id, _mats["wall"])


# --- Environment -------------------------------------------------------------

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.012, 0.013, 0.020)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.10, 0.11, 0.16)
	env.ambient_light_energy = 0.34

	# Fog does the heavy lifting: the street does not end, it simply stops
	# being visible about twelve metres out.
	env.fog_enabled = true
	env.fog_light_color = Color(0.035, 0.038, 0.050)
	env.fog_density = 0.055
	env.fog_sky_affect = 0.0

	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)


# --- Street ------------------------------------------------------------------

func _build_street() -> void:
	var street := Node3D.new()
	street.name = "Street"
	add_child(street)

	street.add_child(ProcMesh.solid_box(Vector3(40, 0.4, 40), Vector3(0, -0.2, -12), mat("asphalt"), "Road"))
	street.add_child(ProcMesh.box(Vector3(14, 0.22, 5), Vector3(0, 0.02, -2.2), mat("pavement"), "Pavement"))

	# A terrace of dead buildings on the far side, just close enough to read as
	# a street and far enough to be almost entirely fog.
	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	for i in 9:
		var w := rng.randf_range(3.0, 6.0)
		var h := rng.randf_range(6.0, 13.0)
		var x := -18.0 + float(i) * 4.4 + rng.randf_range(-0.6, 0.6)
		street.add_child(ProcMesh.box(Vector3(w, h, 6.0), Vector3(x, h * 0.5, -16.0), mat("brick_far"), "Block%d" % i))
	for i in 4:
		var h2 := rng.randf_range(5.0, 9.0)
		street.add_child(ProcMesh.box(Vector3(5.0, h2, 5.0),
			Vector3(-13.0 - float(i) * 5.0, h2 * 0.5, -1.0), mat("brick_far"), "Left%d" % i))
		street.add_child(ProcMesh.box(Vector3(5.0, h2 * 1.2, 5.0),
			Vector3(13.0 + float(i) * 5.0, h2 * 0.6, -1.0), mat("brick_far"), "Right%d" % i))

	# Three lamp posts. Two of them are dead, which is why the kiosk's own sign
	# is the brightest thing for a hundred metres.
	_lamp_post(street, Vector3(-6.5, 0, -4.2), false)
	_lamp_post(street, Vector3(4.8, 0, -5.0), true)
	_lamp_post(street, Vector3(12.0, 0, -4.0), false)

	# Litter, a bin, a dead car. Something for the eye to land on.
	street.add_child(ProcMesh.box(Vector3(0.6, 1.0, 0.6), Vector3(-3.4, 0.5, -2.6), mat("dark_steel"), "Bin"))
	street.add_child(ProcMesh.box(Vector3(1.9, 0.7, 4.2), Vector3(8.5, 0.45, -7.5), mat("dark_steel"), "DeadCarBody"))
	street.add_child(ProcMesh.box(Vector3(1.7, 0.55, 2.0), Vector3(8.5, 1.05, -7.8), mat("glass"), "DeadCarCab"))
	for i in 16:
		var lx := rng.randf_range(-11.0, 11.0)
		var lz := rng.randf_range(-9.0, -1.5)
		street.add_child(ProcMesh.box(Vector3(0.18, 0.02, 0.24), Vector3(lx, 0.14, lz),
			mat("pavement"), "Litter%d" % i))

	_breach_points = [
		Vector3(3.2, 0, -4.0),
		Vector3(-3.6, 0, -4.4),
		Vector3(0.0, 0, -6.5),
	]


func _lamp_post(parent: Node3D, pos: Vector3, working: bool) -> void:
	parent.add_child(ProcMesh.cylinder(0.09, 5.0, pos + Vector3(0, 2.5, 0), mat("dark_steel"), 6))
	parent.add_child(ProcMesh.box(Vector3(0.9, 0.10, 0.30), pos + Vector3(0.4, 4.95, 0), mat("dark_steel"), "Arm"))
	var head := ProcMesh.box(Vector3(0.5, 0.14, 0.28), pos + Vector3(0.78, 4.86, 0),
		mat("lamp") if working else mat("dark_steel"), "Head")
	parent.add_child(head)
	if working:
		var l := OmniLight3D.new()
		l.position = pos + Vector3(0.78, 4.7, 0)
		l.light_color = Color(1.0, 0.86, 0.60)
		l.light_energy = 2.6
		l.omni_range = 9.0
		l.omni_attenuation = 1.6
		parent.add_child(l)


# --- Kiosk shell -------------------------------------------------------------

func _build_kiosk_shell() -> void:
	var kiosk := Node3D.new()
	kiosk.name = "Kiosk"
	add_child(kiosk)

	kiosk.add_child(ProcMesh.solid_box(Vector3(HALF_X * 2, 0.2, HALF_Z * 2), Vector3(0, -0.1, 0), mat("floor"), "Floor"))
	kiosk.add_child(ProcMesh.solid_box(Vector3(HALF_X * 2 + 0.4, 0.2, HALF_Z * 2 + 0.4),
		Vector3(0, CEILING + 0.1, 0), mat("ceiling"), "Ceiling"))

	# Back and side walls are solid. Only the front has an opening.
	kiosk.add_child(ProcMesh.solid_box(Vector3(HALF_X * 2 + 0.4, CEILING, 0.2),
		Vector3(0, CEILING * 0.5, HALF_Z + 0.1), mat("wall"), "BackWall"))
	kiosk.add_child(ProcMesh.solid_box(Vector3(0.2, CEILING, HALF_Z * 2),
		Vector3(-HALF_X - 0.1, CEILING * 0.5, 0), mat("wall"), "WallL"))
	kiosk.add_child(ProcMesh.solid_box(Vector3(0.2, CEILING, HALF_Z * 2),
		Vector3(HALF_X + 0.1, CEILING * 0.5, 0), mat("wall"), "WallR"))

	# Front wall, built around the hatch. The pieces overlap by a few
	# centimetres: vertex snapping quantises screen positions, which can pull a
	# shared edge apart by a pixel and open a seam you can see the street
	# through. Overlapping costs nothing and closes them for good.
	const SEAM := 0.06
	var side_w := (HALF_X * 2 - HATCH_WIDTH) * 0.5 + SEAM
	for side: int in [-1, 1]:
		var cx := side * (HATCH_WIDTH * 0.5 + side_w * 0.5 - SEAM * 0.5)
		kiosk.add_child(ProcMesh.solid_box(Vector3(side_w, CEILING, 0.2),
			Vector3(cx, CEILING * 0.5, -HALF_Z - 0.1), mat("wall"), "FrontWall%d" % side))
	kiosk.add_child(ProcMesh.solid_box(Vector3(HATCH_WIDTH, HATCH_BOTTOM, 0.2),
		Vector3(0, HATCH_BOTTOM * 0.5, -HALF_Z - 0.1), mat("wall"), "HatchSill"))
	kiosk.add_child(ProcMesh.solid_box(Vector3(HATCH_WIDTH, CEILING - HATCH_TOP, 0.2),
		Vector3(0, (CEILING + HATCH_TOP) * 0.5, -HALF_Z - 0.1), mat("wall"), "HatchHead"))

	# Glass either side of the serving gap, so the hatch reads as a window with
	# a hole in it rather than a doorway.
	for side: int in [-1, 1]:
		kiosk.add_child(ProcMesh.box(Vector3(0.28, HATCH_TOP - HATCH_BOTTOM, 0.04),
			Vector3(side * (HATCH_WIDTH * 0.5 - 0.14), (HATCH_TOP + HATCH_BOTTOM) * 0.5, -HALF_Z - 0.1),
			mat("glass"), "Pane%d" % side))

	# The roller shutter. Parked in its housing just under the awning when open,
	# rather than sticking up through the roof.
	var shutter_h := HATCH_TOP - HATCH_BOTTOM
	var shutter := ProcMesh.box(Vector3(HATCH_WIDTH + 0.2, shutter_h, 0.06),
		Vector3(0, CEILING - shutter_h * 0.5 + 0.02, -HALF_Z - 0.16), mat("shutter"), "Shutter")
	kiosk.add_child(shutter)
	anchors["shutter"] = shutter
	anchors["shutter_open_y"] = shutter.position.y
	anchors["shutter_closed_y"] = (HATCH_TOP + HATCH_BOTTOM) * 0.5 - 0.05

	# Exterior dressing. The sign sits above the awning, clear of the hatch, so
	# it lights the pavement without hanging in the middle of the window.
	var sign := ProcMesh.box(Vector3(3.4, 0.55, 0.12), Vector3(0, 3.05, -HALF_Z - 0.62), mat("neon"), "Sign")
	kiosk.add_child(sign)
	sign_light = OmniLight3D.new()
	sign_light.position = Vector3(0, 2.75, -HALF_Z - 1.1)
	sign_light.light_color = Color(1.0, 0.32, 0.50)
	sign_light.light_energy = 2.6
	sign_light.omni_range = 8.0
	add_child(sign_light)

	kiosk.add_child(ProcMesh.box(Vector3(HALF_X * 2 + 1.2, 0.12, 1.1),
		Vector3(0, 2.72, -HALF_Z - 0.5), mat("dark_steel"), "Awning"))

	# A little warm spill under the awning. Without it a customer is a
	# silhouette, and the whole game is about reading their face.
	var hatch_light := OmniLight3D.new()
	hatch_light.position = Vector3(0, 2.20, -HALF_Z - 0.75)
	hatch_light.light_color = Color(1.0, 0.90, 0.74)
	hatch_light.light_energy = 2.8
	hatch_light.omni_range = 3.6
	hatch_light.omni_attenuation = 1.5
	add_child(hatch_light)
	kiosk.add_child(ProcMesh.box(Vector3(HALF_X * 2 + 0.6, 0.3, HALF_Z * 2 + 0.6),
		Vector3(0, CEILING + 0.30, 0), mat("shutter"), "Roof"))

	# One strip light, and it is not well.
	strip_light = OmniLight3D.new()
	strip_light.position = Vector3(0, CEILING - 0.35, 0.1)
	strip_light.light_color = Color(0.85, 0.92, 1.0)
	strip_light.light_energy = 2.3
	strip_light.omni_range = 7.5
	strip_light.omni_attenuation = 1.1
	add_child(strip_light)
	kiosk.add_child(ProcMesh.box(Vector3(1.6, 0.08, 0.22), Vector3(0, CEILING - 0.12, 0.1),
		ProcMesh.mat(ProcTex.flat(Color(0.9, 0.95, 1.0)), 1.0, Color(0.85, 0.92, 1.0), 1.6), "StripTube"))

	anchors["customer_stand"] = CUSTOMER_STAND
	anchors["customer_entry"] = CUSTOMER_ENTRY
	anchors["customer_exit"] = CUSTOMER_EXIT
	anchors["player_spawn"] = Vector3(0, 0.1, 0.40)


# --- Counter and the things on it --------------------------------------------

func _build_counter() -> void:
	var counter := Node3D.new()
	counter.name = "Counter"
	add_child(counter)

	# The serving ledge, sitting just inside the hatch.
	counter.add_child(ProcMesh.solid_box(Vector3(HALF_X * 2, 0.10, 0.62),
		Vector3(0, COUNTER_Y, -HALF_Z + 0.31), mat("counter"), "Ledge"))
	counter.add_child(ProcMesh.solid_box(Vector3(HALF_X * 2, COUNTER_Y - 0.05, 0.50),
		Vector3(0, (COUNTER_Y - 0.05) * 0.5, -HALF_Z + 0.25), mat("counter"), "Kickboard"))
	# A lip on the far side so goods do not slide out into the street.
	counter.add_child(ProcMesh.box(Vector3(HALF_X * 2, 0.10, 0.06),
		Vector3(0, COUNTER_Y + 0.10, -HALF_Z + 0.02), mat("counter"), "Lip"))

	_interactable(counter, "till", "Till", Vector3(0.42, 0.34, 0.44),
		Vector3(1.35, COUNTER_Y + 0.22, -HALF_Z + 0.36), mat("steel"))
	_interactable(counter, "terminal", "Terminal", Vector3(0.60, 0.50, 0.46),
		Vector3(-1.42, COUNTER_Y + 0.30, -HALF_Z + 0.38), mat("dark_steel"))

	# The monitor face, angled back toward the player.
	var screen := ProcMesh.quad(Vector2(0.50, 0.38), Vector3(-1.42, COUNTER_Y + 0.34, -HALF_Z + 0.61), mat("screen"))
	screen.rotation_degrees = Vector3(-8, 180, 0)
	counter.add_child(screen)
	var glow := OmniLight3D.new()
	glow.position = Vector3(-1.42, COUNTER_Y + 0.40, -HALF_Z + 0.85)
	glow.light_color = Color(0.35, 1.0, 0.45)
	glow.light_energy = 0.85
	glow.omni_range = 2.4
	counter.add_child(glow)
	anchors["terminal_glow"] = glow

	# Under the counter: the part of the business that is not on the shelves.
	_interactable(counter, "stash", "Stash", Vector3(0.50, 0.34, 0.42),
		Vector3(0.55, 0.30, -HALF_Z + 0.30), mat("dark_steel"))

	# The scanner sits in a cradle until you pick it up.
	_interactable(counter, "scanner", "Scanner", Vector3(0.16, 0.10, 0.30),
		Vector3(0.78, COUNTER_Y + 0.10, -HALF_Z + 0.40), mat("steel"))

	anchors["counter_y"] = COUNTER_Y
	anchors["handover"] = Vector3(0, COUNTER_Y + 0.12, -HALF_Z + 0.15)


func _build_fittings() -> void:
	var fit := Node3D.new()
	fit.name = "Fittings"
	add_child(fit)

	# Back-room hatch. In a building this size the "stockroom" is a cupboard,
	# which is why restocking means crouching and rummaging rather than walking.
	_interactable(fit, "crates", "Crates", Vector3(1.30, 0.75, 0.55),
		Vector3(-1.30, 0.38, HALF_Z - 0.32), mat("counter"))
	_interactable(fit, "shop", "Supplier Phone", Vector3(0.20, 0.34, 0.12),
		Vector3(HALF_X - 0.14, 1.45, 0.55), mat("dark_steel"))
	_interactable(fit, "shutter_control", "Shutter Control", Vector3(0.16, 0.24, 0.10),
		Vector3(-HALF_X + 0.14, 1.40, -HALF_Z + 0.60), mat("steel"))

	# The camera the nervier customers keep looking at.
	fit.add_child(ProcMesh.box(Vector3(0.16, 0.12, 0.26), Vector3(HALF_X - 0.30, CEILING - 0.30, -HALF_Z + 0.40),
		mat("dark_steel"), "Camera"))

	# The back door. Nothing comes through it during trade. During a raid it is
	# the first thing that fails.
	var door := ProcMesh.solid_box(Vector3(0.95, 2.05, 0.10), Vector3(1.30, 1.02, HALF_Z + 0.06),
		mat("dark_steel"), "BackDoor")
	fit.add_child(door)
	anchors["back_door"] = door

	# A stool, a kettle, a radio. Somebody works here.
	fit.add_child(ProcMesh.cylinder(0.16, 0.62, Vector3(0.2, 0.31, 0.55), mat("dark_steel"), 6))
	fit.add_child(ProcMesh.box(Vector3(0.16, 0.22, 0.16), Vector3(-2.0, 0.85, 1.2), mat("steel"), "Kettle"))
	fit.add_child(ProcMesh.box(Vector3(0.34, 0.16, 0.16), Vector3(-1.9, 1.62, HALF_Z - 0.25), mat("dark_steel"), "Radio"))


# --- Shelving ----------------------------------------------------------------

const SHELF_TINTS := {
	"smokes": Color(0.72, 0.20, 0.18),
	"soda": Color(0.20, 0.32, 0.72),
	"crisps": Color(0.78, 0.60, 0.16),
	"beer": Color(0.30, 0.52, 0.24),
	"noodles": Color(0.76, 0.42, 0.14),
	"batteries": Color(0.20, 0.20, 0.24),
	"lighter": Color(0.66, 0.24, 0.52),
	"coffee": Color(0.36, 0.24, 0.16),
}

## Three racks: one on each side wall and one across the back. Each product has
## a run of eight box slots, and stock level just shows or hides them, so the
## shelves visibly empty out as the night goes on.
func _build_shelving() -> void:
	var racks := Node3D.new()
	racks.name = "Shelving"
	add_child(racks)

	var layout := {
		0: {"origin": Vector3(-HALF_X + 0.22, 0, -0.2), "dir": Vector3(0, 0, 1), "rot": 90.0},
		1: {"origin": Vector3(HALF_X - 0.22, 0, -0.2), "dir": Vector3(0, 0, 1), "rot": -90.0},
		2: {"origin": Vector3(-1.1, 0, HALF_Z - 0.22), "dir": Vector3(1, 0, 0), "rot": 0.0},
	}

	# Group products by which rack they live on.
	var by_rack := {0: [], 1: [], 2: []}
	for id: String in GameState.ITEMS:
		var r: int = int(GameState.ITEMS[id]["shelf"])
		by_rack[r].append(id)

	for rack_id: int in layout:
		var conf: Dictionary = layout[rack_id]
		var origin: Vector3 = conf["origin"]
		var dir: Vector3 = conf["dir"]
		var items: Array = by_rack[rack_id]

		# The rack carcass.
		var span := 1.9
		var centre: Vector3 = origin + dir * (span * 0.5)
		var carcass_size: Vector3 = Vector3(0.34, 1.55, span) if dir.z > 0.5 else Vector3(span, 1.55, 0.34)
		racks.add_child(ProcMesh.solid_box(carcass_size, centre + Vector3(0, 0.775, 0),
			mat("dark_steel"), "Rack%d" % rack_id))

		for i in items.size():
			var item_id: String = items[i]
			var level_y := 0.85 + float(i) * 0.42
			var slots: Array[MeshInstance3D] = []
			var tint: Color = SHELF_TINTS.get(item_id, Color(0.5, 0.5, 0.5))
			var box_mat := ProcMesh.mat(ProcTex.product(tint, hash(item_id)))
			for s in 8:
				var along := 0.16 + float(s) * 0.23
				var pos: Vector3 = origin + dir * along + Vector3(0, level_y, 0)
				var box := ProcMesh.box(Vector3(0.17, 0.22, 0.17), pos, box_mat, "%s_%d" % [item_id, s])
				box.rotation_degrees = Vector3(0, conf["rot"], 0)
				racks.add_child(box)
				slots.append(box)
			shelf_slots[item_id] = slots

			# Each product run is its own interactable, so you take stock from
			# the shelf the customer can see rather than from an abstract pool.
			var mid: Vector3 = origin + dir * (span * 0.5) + Vector3(0, level_y, 0)
			var zone_size: Vector3 = Vector3(0.30, 0.36, span) if dir.z > 0.5 else Vector3(span, 0.36, 0.30)
			_interact_zone(racks, "shelf:" + item_id, mid, zone_size)


func refresh_shelves() -> void:
	for item_id: String in shelf_slots:
		var units := GameState.shelf_units(item_id)
		var slots: Array = shelf_slots[item_id]
		for i in slots.size():
			(slots[i] as MeshInstance3D).visible = i < units


# --- Cash lying about --------------------------------------------------------

## Scatters a few notes and coins around the kiosk at the start of each shift:
## takings that missed the till, change dropped behind the fridge. Finding them
## is a small reason to actually look at the room you are standing in.
func scatter_cash(rng: RandomNumberGenerator) -> void:
	for node: Node3D in cash_pickups:
		if is_instance_valid(node):
			node.queue_free()
	cash_pickups.clear()

	var spots := [
		Vector3(-1.95, 0.06, 1.35), Vector3(1.90, 0.06, 1.10), Vector3(-0.60, 0.06, 1.55),
		Vector3(2.05, 0.06, -1.05), Vector3(-2.05, 0.06, -0.95), Vector3(0.95, 0.06, 1.48),
		Vector3(-1.20, 1.16, -HALF_Z + 0.42), Vector3(1.75, 0.06, 0.30),
	]
	spots.shuffle()
	var count := rng.randi_range(2, 4)
	for i in mini(count, spots.size()):
		var value := rng.randi_range(3, 18)
		var body := _interact_zone(self, "cash", spots[i], Vector3(0.30, 0.24, 0.30))
		body.set_meta("value", value)
		var note := ProcMesh.box(Vector3(0.16, 0.012, 0.09), Vector3.ZERO, mat("cash"), "Note")
		note.rotation_degrees = Vector3(0, rng.randf_range(0, 180), 0)
		body.add_child(note)
		body.position = spots[i]
		cash_pickups.append(body)


# --- Helpers -----------------------------------------------------------------

## Interaction targets live on physics layer 2 so the player's look-ray can
## pick them out without also hitting walls.
func _interactable(parent: Node3D, id: String, node_name: String, size: Vector3,
		pos: Vector3, material: Material) -> StaticBody3D:
	var body := ProcMesh.solid_box(size, pos, material, node_name)
	body.set_collision_layer_value(1, true)
	body.set_collision_layer_value(2, true)
	body.set_meta("interact", id)
	parent.add_child(body)
	return body


## A trigger volume with no visible body and no collision against the player,
## used for shelf runs and dropped cash.
func _interact_zone(parent: Node3D, id: String, pos: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Zone_" + id
	body.position = pos
	body.set_collision_layer_value(1, false)
	body.set_collision_layer_value(2, true)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	body.add_child(cs)
	body.set_meta("interact", id)
	parent.add_child(body)
	return body


func breach_points() -> Array[Vector3]:
	return _breach_points


func set_shutter_closed(closed: bool) -> void:
	var shutter: Node3D = anchors.get("shutter")
	if shutter == null:
		return
	var target: float = anchors["shutter_closed_y"] if closed else anchors["shutter_open_y"]
	var tw := create_tween()
	tw.tween_property(shutter, "position:y", target, 1.4).set_trans(Tween.TRANS_SINE)
