class_name World
extends Node3D
## Builds the kiosk, the street it stands on, and the tunnels underneath it.
##
## The kiosk is no longer a single sealed box. It is a shop floor with a hatch
## onto the street, a stockroom behind it holding everything you have not put
## out yet, a side door you can actually walk out of, and a manhole in the
## stockroom floor that goes somewhere.
##
## Layout, looking down (-Z is the street side, where customers come from):
##
##                        [ hatch ]
##      +-------------------[==]-------------------+   z = -SHOP_HALF_Z
##      |                SHOP FLOOR                |
##      |  [racks]                       [racks]   |
##      |                                  [door] -+-> street        x = +SHOP_HALF_X
##      +--------[doorway]-------------------------+   z = +SHOP_HALF_Z
##               |      |
##      +--------+      +------------+
##      |         STOCKROOM          |
##      |  [pallet racks]   (O)      |   (O) = manhole to the sewer
##      +----------------------------+       z = STOCK_MAX_Z

# --- Shop floor --------------------------------------------------------------
const SHOP_HALF_X := 3.50
const SHOP_HALF_Z := 2.50
const CEILING := 2.80

const HATCH_WIDTH := 1.90
const HATCH_BOTTOM := 1.00
const HATCH_TOP := 1.95
const COUNTER_Y := 1.00

## Opening in the back wall through to the stockroom.
const BACK_DOOR_X := -2.20
const BACK_DOOR_W := 1.30
## Opening in the right-hand wall, out onto the pavement.
const SIDE_DOOR_Z := 1.55
const SIDE_DOOR_W := 1.10
const DOOR_H := 2.10

# --- Stockroom ---------------------------------------------------------------
const STOCK_MIN_X := -4.80
const STOCK_MAX_X := 1.40
const STOCK_MIN_Z := SHOP_HALF_Z
const STOCK_MAX_Z := 7.20
const STOCK_CEILING := 2.60

## Manhole down to the sewer, in the stockroom floor.
const MANHOLE := Vector3(-3.40, 0.0, 6.10)

# --- Sewer -------------------------------------------------------------------
const SEWER_Y := -4.50
const SEWER_HALF_W := 1.30
## Where the tunnel comes back up: a dark alley at the far west end of the
## street, which is also roughly where the thing at the end of the road is.
const SEWER_EXIT := Vector3(-55.0, 0.0, 1.60)

# --- Street ------------------------------------------------------------------
const STREET_WEST := -72.0
const STREET_EAST := 30.0
## The far end. Unlit, and far enough that the fog hides it from the kiosk.
const STREET_END := -60.0

## Where a customer stands to be served, and where they walk in from.
const CUSTOMER_STAND := Vector3(0, 0, -SHOP_HALF_Z - 0.52)
const CUSTOMER_ENTRY := Vector3(9.0, 0, -7.0)
const CUSTOMER_EXIT := Vector3(-11.0, 0, -8.0)

var anchors: Dictionary = {}
var shelf_slots: Dictionary = {}      ## item_id -> Array[MeshInstance3D]
var cash_pickups: Array[Node3D] = []
var strip_light: OmniLight3D
var stock_light: OmniLight3D
var sign_light: OmniLight3D
var _breach_points: Array[Vector3] = []
var _mats: Dictionary = {}


func _ready() -> void:
	name = "World"
	_build_materials()
	_build_environment()
	StreetBuilder.build(self)
	_build_shop_shell()
	_build_counter()
	_build_fittings()
	_build_shelving()
	_build_stockroom()
	SewerBuilder.build(self)
	refresh_shelves()


# --- Materials ---------------------------------------------------------------

func _build_materials() -> void:
	_mats["asphalt"] = ProcMesh.mat(ProcTex.asphalt(7), 14.0)
	_mats["pavement"] = ProcMesh.mat(ProcTex.grime(Color(0.20, 0.20, 0.21), 0.5, 12), 10.0)
	_mats["brick"] = ProcMesh.mat(ProcTex.brick(21), 3.0)
	_mats["brick_far"] = ProcMesh.mat(ProcTex.brick(33), 6.0, Color.BLACK, 0.0, Color(0.55, 0.55, 0.6))
	_mats["floor"] = ProcMesh.mat(ProcTex.tiles(41), 4.0)
	_mats["wall"] = ProcMesh.mat(ProcTex.grime(Color(0.38, 0.37, 0.33), 0.45, 55), 3.0)
	_mats["ceiling"] = ProcMesh.mat(ProcTex.grime(Color(0.26, 0.26, 0.25), 0.5, 61), 3.0)
	_mats["counter"] = ProcMesh.mat(ProcTex.grime(Color(0.30, 0.24, 0.18), 0.4, 71), 2.0)
	_mats["steel"] = ProcMesh.mat(ProcTex.metal(Color(0.30, 0.31, 0.33), 81))
	_mats["dark_steel"] = ProcMesh.mat(ProcTex.metal(Color(0.14, 0.14, 0.16), 83))
	_mats["shutter"] = ProcMesh.mat(ProcTex.corrugated(Color(0.26, 0.26, 0.28), 91), 2.0)
	_mats["glass"] = ProcMesh.mat(ProcTex.flat(Color(0.30, 0.35, 0.38)), 1.0, Color(0.4, 0.5, 0.55), 0.06)
	_mats["screen"] = ProcMesh.mat(ProcTex.flat(Color(0.10, 0.35, 0.16)), 1.0, Color(0.20, 0.85, 0.35), 1.3)
	_mats["neon"] = ProcMesh.mat(ProcTex.neon_sign(Color(1.0, 0.25, 0.45), 5), 1.0, Color(1.0, 0.25, 0.45), 2.2)
	_mats["lamp"] = ProcMesh.mat(ProcTex.flat(Color(1.0, 0.92, 0.72)), 1.0, Color(1.0, 0.90, 0.66), 2.0)
	_mats["cash"] = ProcMesh.mat(ProcTex.flat(Color(0.55, 0.62, 0.42)), 1.0, Color(0.4, 0.5, 0.3), 0.25)
	# Bare concrete for the stockroom, and wet brick below ground.
	_mats["concrete"] = ProcMesh.mat(ProcTex.grime(Color(0.40, 0.40, 0.38), 0.45, 131), 3.0)
	_mats["sewer_brick"] = ProcMesh.mat(ProcTex.brick(137), 5.0, Color.BLACK, 0.0, Color(0.72, 0.78, 0.74))
	_mats["water"] = ProcMesh.mat(ProcTex.grime(Color(0.10, 0.13, 0.12), 0.4, 141), 8.0,
		Color(0.06, 0.10, 0.09), 0.15)
	_mats["cardboard"] = ProcMesh.mat(ProcTex.grime(Color(0.44, 0.33, 0.21), 0.35, 151), 1.0)


func mat(id: String) -> Material:
	return _mats.get(id, _mats["wall"])


# --- Environment -------------------------------------------------------------

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.012, 0.013, 0.020)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.15, 0.16, 0.22)
	env.ambient_light_energy = 0.55

	# Thinner than before, because the street is now long enough that you need
	# to see a little way down it — but still thick enough that the far end is
	# a rumour rather than a destination.
	env.fog_enabled = true
	env.fog_light_color = Color(0.035, 0.038, 0.050)
	env.fog_density = 0.018
	env.fog_sky_affect = 0.0

	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)


# --- Shop floor --------------------------------------------------------------

func _build_shop_shell() -> void:
	var kiosk := Node3D.new()
	kiosk.name = "Kiosk"
	add_child(kiosk)

	kiosk.add_child(ProcMesh.solid_box(Vector3(SHOP_HALF_X * 2, 0.2, SHOP_HALF_Z * 2),
		Vector3(0, -0.1, 0), mat("floor"), "Floor"))
	kiosk.add_child(ProcMesh.solid_box(Vector3(SHOP_HALF_X * 2 + 0.4, 0.2, SHOP_HALF_Z * 2 + 0.4),
		Vector3(0, CEILING + 0.1, 0), mat("ceiling"), "Ceiling"))

	# Left wall is solid.
	kiosk.add_child(ProcMesh.solid_box(Vector3(0.2, CEILING, SHOP_HALF_Z * 2),
		Vector3(-SHOP_HALF_X - 0.1, CEILING * 0.5, 0), mat("wall"), "WallL"))

	# Right wall, with a doorway out onto the pavement.
	_wall_with_gap(kiosk, "WallR", Vector3(SHOP_HALF_X + 0.1, 0, 0), false,
		SHOP_HALF_Z * 2, CEILING, SIDE_DOOR_Z, SIDE_DOOR_W, DOOR_H)

	# Back wall, with a doorway through to the stockroom.
	_wall_with_gap(kiosk, "BackWall", Vector3(0, 0, SHOP_HALF_Z + 0.1), true,
		SHOP_HALF_X * 2 + 0.4, CEILING, BACK_DOOR_X, BACK_DOOR_W, DOOR_H)

	# Front wall, built around the serving hatch. Pieces overlap slightly:
	# vertex snapping can pull a shared edge apart by a pixel and open a seam.
	const SEAM := 0.06
	var side_w := (SHOP_HALF_X * 2 - HATCH_WIDTH) * 0.5 + SEAM
	for side: int in [-1, 1]:
		var cx := side * (HATCH_WIDTH * 0.5 + side_w * 0.5 - SEAM * 0.5)
		kiosk.add_child(ProcMesh.solid_box(Vector3(side_w, CEILING, 0.2),
			Vector3(cx, CEILING * 0.5, -SHOP_HALF_Z - 0.1), mat("wall"), "FrontWall%d" % side))
	kiosk.add_child(ProcMesh.solid_box(Vector3(HATCH_WIDTH, HATCH_BOTTOM, 0.2),
		Vector3(0, HATCH_BOTTOM * 0.5, -SHOP_HALF_Z - 0.1), mat("wall"), "HatchSill"))
	kiosk.add_child(ProcMesh.solid_box(Vector3(HATCH_WIDTH, CEILING - HATCH_TOP, 0.2),
		Vector3(0, (CEILING + HATCH_TOP) * 0.5, -SHOP_HALF_Z - 0.1), mat("wall"), "HatchHead"))

	for side: int in [-1, 1]:
		kiosk.add_child(ProcMesh.box(Vector3(0.28, HATCH_TOP - HATCH_BOTTOM, 0.04),
			Vector3(side * (HATCH_WIDTH * 0.5 - 0.14), (HATCH_TOP + HATCH_BOTTOM) * 0.5, -SHOP_HALF_Z - 0.1),
			mat("glass"), "Pane%d" % side))

	var shutter_h := HATCH_TOP - HATCH_BOTTOM
	var shutter := ProcMesh.box(Vector3(HATCH_WIDTH + 0.2, shutter_h, 0.06),
		Vector3(0, CEILING - shutter_h * 0.5 + 0.02, -SHOP_HALF_Z - 0.16), mat("shutter"), "Shutter")
	kiosk.add_child(shutter)
	anchors["shutter"] = shutter
	anchors["shutter_open_y"] = shutter.position.y
	anchors["shutter_closed_y"] = (HATCH_TOP + HATCH_BOTTOM) * 0.5 - 0.05

	# Exterior dressing.
	var sign := ProcMesh.box(Vector3(3.8, 0.55, 0.12), Vector3(0, 3.25, -SHOP_HALF_Z - 0.62),
		mat("neon"), "Sign")
	kiosk.add_child(sign)
	sign_light = OmniLight3D.new()
	sign_light.position = Vector3(0, 2.95, -SHOP_HALF_Z - 1.1)
	sign_light.light_color = Color(1.0, 0.32, 0.50)
	sign_light.light_energy = 2.6
	sign_light.omni_range = 9.0
	add_child(sign_light)

	kiosk.add_child(ProcMesh.box(Vector3(SHOP_HALF_X * 2 + 1.2, 0.12, 1.1),
		Vector3(0, 2.92, -SHOP_HALF_Z - 0.5), mat("dark_steel"), "Awning"))
	kiosk.add_child(ProcMesh.box(Vector3(SHOP_HALF_X * 2 + 0.6, 0.3, SHOP_HALF_Z * 2 + 0.6),
		Vector3(0, CEILING + 0.30, 0), mat("shutter"), "Roof"))

	var hatch_light := OmniLight3D.new()
	hatch_light.position = Vector3(0, 2.20, -SHOP_HALF_Z - 0.75)
	hatch_light.light_color = Color(1.0, 0.90, 0.74)
	hatch_light.light_energy = 2.8
	hatch_light.omni_range = 3.8
	hatch_light.omni_attenuation = 1.5
	add_child(hatch_light)

	strip_light = OmniLight3D.new()
	strip_light.position = Vector3(0, CEILING - 0.35, 0.1)
	strip_light.light_color = Color(0.85, 0.92, 1.0)
	strip_light.light_energy = 2.3
	strip_light.omni_range = 9.0
	strip_light.omni_attenuation = 1.1
	add_child(strip_light)
	kiosk.add_child(ProcMesh.box(Vector3(2.2, 0.08, 0.22), Vector3(0, CEILING - 0.12, 0.1),
		ProcMesh.mat(ProcTex.flat(Color(0.9, 0.95, 1.0)), 1.0, Color(0.85, 0.92, 1.0), 1.6), "StripTube"))

	anchors["customer_stand"] = CUSTOMER_STAND
	anchors["customer_entry"] = CUSTOMER_ENTRY
	anchors["customer_exit"] = CUSTOMER_EXIT
	anchors["player_spawn"] = Vector3(0, 0.1, -1.35)


## Builds a wall with a rectangular doorway cut into it, as three solid pieces.
## `along_x` picks whether the wall runs across X or across Z.
func _wall_with_gap(parent: Node3D, node_name: String, centre: Vector3, along_x: bool,
		length: float, height: float, gap_centre: float, gap_width: float, gap_height: float) -> void:
	var half := length * 0.5
	var left_len := (gap_centre - gap_width * 0.5) - (-half)
	var right_len := half - (gap_centre + gap_width * 0.5)

	for piece: Array in [[left_len, -half + left_len * 0.5], [right_len, half - right_len * 0.5]]:
		var seg_len: float = piece[0]
		if seg_len <= 0.02:
			continue
		var offset: float = piece[1]
		var size := Vector3(seg_len, height, 0.2) if along_x else Vector3(0.2, height, seg_len)
		var pos := centre + (Vector3(offset, height * 0.5, 0) if along_x else Vector3(0, height * 0.5, offset))
		parent.add_child(ProcMesh.solid_box(size, pos, mat("wall"), node_name + "Seg"))

	# The lintel above the opening.
	var head := height - gap_height
	if head > 0.02:
		var size := Vector3(gap_width, head, 0.2) if along_x else Vector3(0.2, head, gap_width)
		var pos := centre + (Vector3(gap_centre, gap_height + head * 0.5, 0) if along_x
			else Vector3(0, gap_height + head * 0.5, gap_centre))
		parent.add_child(ProcMesh.solid_box(size, pos, mat("wall"), node_name + "Head"))


# --- Counter -----------------------------------------------------------------

func _build_counter() -> void:
	var counter := Node3D.new()
	counter.name = "Counter"
	add_child(counter)

	counter.add_child(ProcMesh.solid_box(Vector3(SHOP_HALF_X * 2, 0.10, 0.65),
		Vector3(0, COUNTER_Y, -SHOP_HALF_Z + 0.33), mat("counter"), "Ledge"))
	counter.add_child(ProcMesh.solid_box(Vector3(SHOP_HALF_X * 2, COUNTER_Y - 0.05, 0.52),
		Vector3(0, (COUNTER_Y - 0.05) * 0.5, -SHOP_HALF_Z + 0.26), mat("counter"), "Kickboard"))
	counter.add_child(ProcMesh.box(Vector3(SHOP_HALF_X * 2, 0.10, 0.06),
		Vector3(0, COUNTER_Y + 0.10, -SHOP_HALF_Z + 0.02), mat("counter"), "Lip"))

	_interactable(counter, "till", "Till", Vector3(0.42, 0.34, 0.44),
		Vector3(1.45, COUNTER_Y + 0.22, -SHOP_HALF_Z + 0.38), mat("steel"))
	_interactable(counter, "terminal", "Terminal", Vector3(0.60, 0.50, 0.46),
		Vector3(-1.52, COUNTER_Y + 0.30, -SHOP_HALF_Z + 0.40), mat("dark_steel"))

	var screen := ProcMesh.quad(Vector2(0.50, 0.38),
		Vector3(-1.52, COUNTER_Y + 0.34, -SHOP_HALF_Z + 0.63), mat("screen"))
	screen.rotation_degrees = Vector3(-8, 180, 0)
	counter.add_child(screen)
	var glow := OmniLight3D.new()
	glow.position = Vector3(-1.52, COUNTER_Y + 0.40, -SHOP_HALF_Z + 0.87)
	glow.light_color = Color(0.35, 1.0, 0.45)
	glow.light_energy = 0.85
	glow.omni_range = 2.6
	counter.add_child(glow)
	anchors["terminal_glow"] = glow

	_interactable(counter, "stash", "Stash", Vector3(0.50, 0.34, 0.42),
		Vector3(0.60, 0.30, -SHOP_HALF_Z + 0.32), mat("dark_steel"))
	_interactable(counter, "scanner", "Scanner", Vector3(0.16, 0.10, 0.30),
		Vector3(0.85, COUNTER_Y + 0.10, -SHOP_HALF_Z + 0.42), mat("steel"))

	anchors["counter_y"] = COUNTER_Y
	anchors["handover"] = Vector3(0, COUNTER_Y + 0.12, -SHOP_HALF_Z + 0.15)


func _build_fittings() -> void:
	var fit := Node3D.new()
	fit.name = "Fittings"
	add_child(fit)

	_interactable(fit, "shop", "Supplier Phone", Vector3(0.20, 0.34, 0.12),
		Vector3(SHOP_HALF_X - 0.14, 1.45, -0.60), mat("dark_steel"))
	_interactable(fit, "shutter_control", "Shutter Control", Vector3(0.16, 0.24, 0.10),
		Vector3(-SHOP_HALF_X + 0.14, 1.40, -SHOP_HALF_Z + 0.60), mat("steel"))

	fit.add_child(ProcMesh.box(Vector3(0.16, 0.12, 0.26),
		Vector3(SHOP_HALF_X - 0.30, CEILING - 0.30, -SHOP_HALF_Z + 0.40), mat("dark_steel"), "Camera"))

	fit.add_child(ProcMesh.cylinder(0.16, 0.62, Vector3(0.2, 0.31, -1.6), mat("dark_steel"), 6))
	fit.add_child(ProcMesh.box(Vector3(0.16, 0.22, 0.16), Vector3(-3.1, 0.85, -0.4), mat("steel"), "Kettle"))
	fit.add_child(ProcMesh.box(Vector3(0.34, 0.16, 0.16),
		Vector3(-3.0, 1.62, SHOP_HALF_Z - 0.25), mat("dark_steel"), "Radio"))

	# The raid still forces the shop's two openings, so it needs the old anchor.
	anchors["back_door"] = Vector3(BACK_DOOR_X, 0, SHOP_HALF_Z)


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

## Three racks around the shop floor, each carrying a few products on separate
## levels. Stock level just shows or hides boxes, so the shelves visibly empty
## out over the night.
func _build_shelving() -> void:
	var racks := Node3D.new()
	racks.name = "Shelving"
	add_child(racks)

	var layout := {
		0: {"origin": Vector3(-SHOP_HALF_X + 0.24, 0, -1.1), "dir": Vector3(0, 0, 1), "rot": 90.0, "span": 3.0},
		1: {"origin": Vector3(SHOP_HALF_X - 0.24, 0, -1.3), "dir": Vector3(0, 0, 1), "rot": -90.0, "span": 2.2},
		2: {"origin": Vector3(-0.9, 0, SHOP_HALF_Z - 0.24), "dir": Vector3(1, 0, 0), "rot": 0.0, "span": 3.4},
	}

	var by_rack := {0: [], 1: [], 2: []}
	for id: String in GameState.ITEMS:
		by_rack[int(GameState.ITEMS[id]["shelf"])].append(id)

	for rack_id: int in layout:
		var conf: Dictionary = layout[rack_id]
		var origin: Vector3 = conf["origin"]
		var dir: Vector3 = conf["dir"]
		var span: float = conf["span"]
		var items: Array = by_rack[rack_id]

		var centre: Vector3 = origin + dir * (span * 0.5)
		var carcass: Vector3 = Vector3(0.36, 1.75, span) if dir.z > 0.5 else Vector3(span, 1.75, 0.36)
		racks.add_child(ProcMesh.solid_box(carcass, centre + Vector3(0, 0.875, 0),
			mat("dark_steel"), "Rack%d" % rack_id))

		for i in items.size():
			var item_id: String = items[i]
			var level_y := 0.95 + float(i) * 0.46
			var slots: Array[MeshInstance3D] = []
			var box_mat := ProcMesh.mat(ProcTex.product(SHELF_TINTS.get(item_id, Color(0.5, 0.5, 0.5)),
				hash(item_id)))
			var count := 10
			for s in count:
				var along := 0.18 + float(s) * ((span - 0.36) / float(count - 1))
				var pos: Vector3 = origin + dir * along + Vector3(0, level_y, 0)
				var box := ProcMesh.box(Vector3(0.18, 0.24, 0.18), pos, box_mat, "%s_%d" % [item_id, s])
				box.rotation_degrees = Vector3(0, conf["rot"], 0)
				racks.add_child(box)
				slots.append(box)
			shelf_slots[item_id] = slots

			var mid: Vector3 = origin + dir * (span * 0.5) + Vector3(0, level_y, 0)
			var zone: Vector3 = Vector3(0.32, 0.40, span) if dir.z > 0.5 else Vector3(span, 0.40, 0.32)
			_interact_zone(racks, "shelf:" + item_id, mid, zone)


func refresh_shelves() -> void:
	for item_id: String in shelf_slots:
		var units := GameState.shelf_units(item_id)
		var slots: Array = shelf_slots[item_id]
		for i in slots.size():
			(slots[i] as MeshInstance3D).visible = i < units


# --- Stockroom ---------------------------------------------------------------

## Everything you have not put out yet lives back here, on pallet racking, in
## the dark, behind a door. Restocking is now a walk rather than a keypress.
func _build_stockroom() -> void:
	var room := Node3D.new()
	room.name = "Stockroom"
	add_child(room)

	var w := STOCK_MAX_X - STOCK_MIN_X
	var d := STOCK_MAX_Z - STOCK_MIN_Z
	var cx := (STOCK_MIN_X + STOCK_MAX_X) * 0.5
	var cz := (STOCK_MIN_Z + STOCK_MAX_Z) * 0.5

	room.add_child(ProcMesh.solid_box(Vector3(w, 0.2, d), Vector3(cx, -0.1, cz),
		mat("concrete"), "StockFloor"))
	room.add_child(ProcMesh.solid_box(Vector3(w + 0.4, 0.2, d + 0.4),
		Vector3(cx, STOCK_CEILING + 0.1, cz), mat("ceiling"), "StockCeiling"))
	room.add_child(ProcMesh.solid_box(Vector3(w + 0.4, STOCK_CEILING, 0.2),
		Vector3(cx, STOCK_CEILING * 0.5, STOCK_MAX_Z + 0.1), mat("concrete"), "StockBack"))
	room.add_child(ProcMesh.solid_box(Vector3(0.2, STOCK_CEILING, d),
		Vector3(STOCK_MIN_X - 0.1, STOCK_CEILING * 0.5, cz), mat("concrete"), "StockLeft"))
	room.add_child(ProcMesh.solid_box(Vector3(0.2, STOCK_CEILING, d),
		Vector3(STOCK_MAX_X + 0.1, STOCK_CEILING * 0.5, cz), mat("concrete"), "StockRight"))

	# The near wall, either side of the doorway back into the shop.
	for piece: Array in [[STOCK_MIN_X, BACK_DOOR_X - BACK_DOOR_W * 0.5],
			[BACK_DOOR_X + BACK_DOOR_W * 0.5, STOCK_MAX_X]]:
		var seg: float = piece[1] - piece[0]
		if seg <= 0.02:
			continue
		room.add_child(ProcMesh.solid_box(Vector3(seg, STOCK_CEILING, 0.2),
			Vector3((piece[0] + piece[1]) * 0.5, STOCK_CEILING * 0.5, STOCK_MIN_Z + 0.1),
			mat("concrete"), "StockFront"))

	stock_light = OmniLight3D.new()
	stock_light.position = Vector3(cx, STOCK_CEILING - 0.30, cz - 0.4)
	stock_light.light_color = Color(1.0, 0.88, 0.66)
	stock_light.light_energy = 3.4
	stock_light.omni_range = 12.0
	add_child(stock_light)
	room.add_child(ProcMesh.box(Vector3(0.30, 0.10, 0.30), Vector3(cx, STOCK_CEILING - 0.10, cz - 0.4),
		ProcMesh.mat(ProcTex.flat(Color(1.0, 0.92, 0.74)), 1.0, Color(1.0, 0.88, 0.66), 1.4), "StockBulb"))

	# A second bulb over the far end, or the racking is a black hole.
	var back_light := OmniLight3D.new()
	back_light.position = Vector3(cx - 0.6, STOCK_CEILING - 0.30, STOCK_MAX_Z - 1.2)
	back_light.light_color = Color(1.0, 0.90, 0.70)
	back_light.light_energy = 2.6
	back_light.omni_range = 10.0
	add_child(back_light)

	# Pallet racking down the left-hand wall, loaded with cases.
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150
	for bay in 3:
		var bz := STOCK_MIN_Z + 1.1 + float(bay) * 1.75
		room.add_child(ProcMesh.solid_box(Vector3(0.9, 2.2, 1.5),
			Vector3(STOCK_MIN_X + 0.55, 1.1, bz), mat("dark_steel"), "Bay%d" % bay))
		for level in 3:
			for c in 2:
				var case_mat := ProcMesh.mat(ProcTex.product(
					SHELF_TINTS.values()[rng.randi() % SHELF_TINTS.size()], rng.randi()))
				room.add_child(ProcMesh.box(Vector3(0.42, 0.34, 0.42),
					Vector3(STOCK_MIN_X + 0.55, 0.42 + float(level) * 0.72, bz - 0.35 + float(c) * 0.70),
					case_mat, "Case"))

	# Loose cardboard, a stack of pallets, a mop. Somebody works back here.
	for i in 7:
		room.add_child(ProcMesh.box(Vector3(rng.randf_range(0.4, 0.7), rng.randf_range(0.3, 0.5),
			rng.randf_range(0.4, 0.7)),
			Vector3(rng.randf_range(STOCK_MIN_X + 1.6, STOCK_MAX_X - 0.6), 0.25,
				rng.randf_range(STOCK_MIN_Z + 0.9, STOCK_MAX_Z - 1.4)),
			mat("cardboard"), "Box%d" % i))
	room.add_child(ProcMesh.box(Vector3(1.1, 0.34, 0.9),
		Vector3(STOCK_MAX_X - 0.9, 0.17, STOCK_MIN_Z + 0.9), mat("cardboard"), "Pallets"))

	# The crates you actually draw from when restocking.
	_interactable(room, "crates", "Crates", Vector3(1.40, 0.85, 0.70),
		Vector3(STOCK_MIN_X + 2.3, 0.42, STOCK_MAX_Z - 0.7), mat("counter"))

	# The manhole. A rim, a lifted cover leaning against it, and a dark hole.
	room.add_child(ProcMesh.cylinder(0.52, 0.06, MANHOLE + Vector3(0, 0.03, 0), mat("dark_steel"), 12))
	room.add_child(ProcMesh.cylinder(0.44, 0.10, MANHOLE + Vector3(0, -0.06, 0),
		ProcMesh.mat(ProcTex.flat(Color(0.02, 0.02, 0.03))), 12))
	var cover := ProcMesh.cylinder(0.46, 0.05, MANHOLE + Vector3(0.75, 0.30, 0.1), mat("steel"), 12)
	cover.rotation_degrees = Vector3(0, 0, 78)
	room.add_child(cover)
	_interact_zone(room, "manhole", MANHOLE + Vector3(0, 0.5, 0), Vector3(1.1, 1.0, 1.1))

	anchors["manhole"] = MANHOLE
	anchors["sewer_shaft_bottom"] = Vector3(MANHOLE.x, SEWER_Y + 0.15, MANHOLE.z)
	anchors["stock_centre"] = Vector3(cx, 0, cz)


# --- Cash lying about --------------------------------------------------------

func scatter_cash(rng: RandomNumberGenerator) -> void:
	for node: Node3D in cash_pickups:
		if is_instance_valid(node):
			node.queue_free()
	cash_pickups.clear()

	# Now spread across the shop floor, the stockroom and the pavement outside,
	# so looking around the whole place is worth something.
	var spots := [
		Vector3(-3.0, 0.06, 1.9), Vector3(3.0, 0.06, 1.6), Vector3(-0.8, 0.06, 2.1),
		Vector3(3.1, 0.06, -1.6), Vector3(-3.1, 0.06, -1.5), Vector3(1.4, 0.06, 2.0),
		Vector3(-1.9, 1.16, -SHOP_HALF_Z + 0.44), Vector3(2.6, 0.06, 0.4),
		Vector3(STOCK_MIN_X + 2.6, 0.06, STOCK_MIN_Z + 1.4),
		Vector3(STOCK_MAX_X - 1.1, 0.06, STOCK_MAX_Z - 1.9),
		Vector3(-1.5, 0.06, STOCK_MAX_Z - 0.9),
		Vector3(SHOP_HALF_X + 1.4, 0.20, 1.5),
		Vector3(-2.2, 0.20, -SHOP_HALF_Z - 1.9),
	]
	spots.shuffle()
	var count := rng.randi_range(3, 6)
	for i in mini(count, spots.size()):
		var value := rng.randi_range(3, 18)
		var body := _interact_zone(self, "cash", spots[i], Vector3(0.34, 0.28, 0.34))
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


## A trigger volume with no visible body and no collision against the player.
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


func interact_zone(parent: Node3D, id: String, pos: Vector3, size: Vector3) -> StaticBody3D:
	return _interact_zone(parent, id, pos, size)


func set_breach_points(points: Array[Vector3]) -> void:
	_breach_points = points


func breach_points() -> Array[Vector3]:
	return _breach_points


func set_shutter_closed(closed: bool) -> void:
	var shutter: Node3D = anchors.get("shutter")
	if shutter == null:
		return
	var target: float = anchors["shutter_closed_y"] if closed else anchors["shutter_open_y"]
	var tw := create_tween()
	tw.tween_property(shutter, "position:y", target, 1.4).set_trans(Tween.TRANS_SINE)
