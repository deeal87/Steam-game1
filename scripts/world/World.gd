class_name World
extends Node3D
## Builds the shop, the street it stands on, and the tunnels underneath it.
##
## The kiosk grew into a small shop, because customers now walk in and do their
## own shopping. That needs room: an aisle wide enough to get round a rack, a
## checkout with a customer side and a staff side, and space behind the counter
## to work without standing in the doorway.
##
## Layout, looking down (-Z is the street):
##
##            [hatch]         [shop door]
##      +--------[==]------------[  ]--------+   z = -SHOP_HALF_Z
##      | [rack]                    [rack]   |
##      |                                    |
##      |           [island rack]            |    customers browse here
##      |                                    |
##      |   ==========CHECKOUT==========     |   z = CHECKOUT_Z
##      |                                    |
##      |            staff side              |
##      +-----------[stockroom]--------------+   z = +SHOP_HALF_Z
##                       |
##             +---------+----------+
##             |     STOCKROOM      |
##             | [pallet racks] (O) |          (O) manhole to the sewer
##             +--------------------+

# --- Shop floor --------------------------------------------------------------
const SHOP_HALF_X := 5.00
const SHOP_HALF_Z := 4.00
const CEILING := 3.00

## Serving hatch, kept for the shutter and for the raid to come through.
const HATCH_X := -1.60
const HATCH_WIDTH := 1.90
const HATCH_BOTTOM := 1.00
const HATCH_TOP := 1.95
const COUNTER_Y := 1.00

## The door customers actually use, in the front wall beside the hatch.
const FRONT_DOOR_X := 3.20
const FRONT_DOOR_W := 1.30
const DOOR_H := 2.20

## Opening in the back wall through to the stockroom.
const BACK_DOOR_X := -3.00
const BACK_DOOR_W := 1.40

# --- Checkout ----------------------------------------------------------------
## An island counter. Customers queue on the -Z face; you work on the +Z face,
## with the stockroom door behind you.
const CHECKOUT_Z := 0.75
const CHECKOUT_MIN_X := -2.80
const CHECKOUT_MAX_X := 1.60
const CHECKOUT_DEPTH := 0.75
const CHECKOUT_Y := 1.00
## How many things fit on the counter at once.
const CHECKOUT_SLOTS := 4

# --- Stockroom ---------------------------------------------------------------
const STOCK_MIN_X := -6.20
const STOCK_MAX_X := 0.20
const STOCK_MIN_Z := SHOP_HALF_Z
const STOCK_MAX_Z := 9.00
const STOCK_CEILING := 2.70

## Manhole down to the sewer, in the stockroom floor.
const MANHOLE := Vector3(-4.60, 0.0, 7.90)

# --- Sewer -------------------------------------------------------------------
# --- Render layers -------------------------------------------------------------
#
# The world is two spaces stacked four metres apart, and light does not care
# about the floor between them: with shadows off — which they are, everywhere,
# because this is a GL Compatibility build aimed at low-end hardware — a sewer
# lamp at y=-2.3 happily lights the stockroom floor above it.
#
# That was costing twice over. Visually the stockroom was being lit from below by
# lamps nobody can see. And on GL Compatibility every light is forward-rendered
# with a hard limit of eight per object, so with ten lights reaching the spot
# behind the counter the renderer was silently dropping two of them — and *which*
# two could change as the camera moved, which is how you get light popping.
#
# So the tunnels render on their own layer and their lamps only light that layer.
# Nothing above ground can see them and they cannot see anything above ground.
const LAYER_SURFACE := 1
const LAYER_UNDERGROUND := 2


## Puts a whole subtree on one visual layer, and points every light in it at the
## same layer only.
static func assign_layer(root: Node, layer: int) -> void:
	var bit := 1 << (layer - 1)
	if root is VisualInstance3D:
		(root as VisualInstance3D).layers = bit
	if root is Light3D:
		(root as Light3D).light_cull_mask = bit
	for child in root.get_children():
		assign_layer(child, layer)


const SEWER_Y := -4.50
const SEWER_HALF_W := 1.30
const SEWER_EXIT := Vector3(-55.0, 0.0, 1.60)
## A second way up, roughly half way along. Shorter, but it puts you back on the
## pavement within sight of your own front door — which is the last place you
## want to be standing on the night you went down there to get away from it.
const SEWER_MID_EXIT := Vector3(-28.0, 0.0, 1.60)
## A spur that goes nowhere, off the north side of the main run. There is
## something at the end of it and something else usually standing in the way.
const SEWER_SPUR_X := -40.0
const SEWER_SPUR_END_Z := 14.5

# --- Street ------------------------------------------------------------------
const STREET_WEST := -72.0
const STREET_EAST := 30.0
const STREET_END := -60.0

# --- Movement anchors --------------------------------------------------------
## Customers come off the street, through the front door, round the aisle and
## up to the counter. Walking those corners as waypoints keeps them off the
## furniture without needing a navigation mesh.
const CUSTOMER_STAND := Vector3(-0.60, 0, CHECKOUT_Z - 1.05)
## Clear of the dead car parked at (10.5, -9). Customers spawn here, so
## anything solid at this point leaves them wedged in it for the whole night.
const CUSTOMER_ENTRY := Vector3(13.5, 0, -6.2)
const CUSTOMER_EXIT := Vector3(-13.5, 0, -7.0)
const DOOR_OUTSIDE := Vector3(FRONT_DOOR_X, 0, -SHOP_HALF_Z - 1.40)
const DOOR_INSIDE := Vector3(FRONT_DOOR_X, 0, -SHOP_HALF_Z + 1.10)
const AISLE := Vector3(3.10, 0, CHECKOUT_Z - 1.05)

## The queue, front first. Slot 0 is being served; the rest wait along the
## customer side of the counter toward the door, which is the direction they
## came from and the direction they leave in.
const QUEUE_SLOTS := [
	Vector3(-0.60, 0, CHECKOUT_Z - 1.05),
	Vector3(0.70, 0, CHECKOUT_Z - 1.20),
	Vector3(1.90, 0, CHECKOUT_Z - 1.20),
	Vector3(3.05, 0, CHECKOUT_Z - 1.20),
]

var anchors: Dictionary = {}
var shelf_slots: Dictionary = {}      ## item_id -> Array[MeshInstance3D]
var shelf_points: Dictionary = {}     ## item_id -> Vector3 a shopper can stand at
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
	# Painted first, generated second.
	#
	# Every surface below names a texture and a repeat. `_surface()` hands back
	# the painted one if the pack has a file of that name and the generated one
	# if it does not, so the two can coexist and a half-finished pack is a game
	# with some hand-made walls rather than a broken one.
	_mats["asphalt"] = _surface("asphalt", ProcTex.asphalt(7), 14.0, 6.0)
	_mats["pavement"] = _surface("pavement", ProcTex.grime(Color(0.20, 0.20, 0.21), 0.5, 12), 10.0, 5.0)
	_mats["brick"] = _surface("brick_far", ProcTex.brick(21), 3.0, 2.0)
	_mats["brick_far"] = _surface("brick_far", ProcTex.brick(33), 6.0, 4.0, Color(0.55, 0.55, 0.6))
	# Six, not three. The cut is mirrored into a 2x2, so three repeats put a
	# six-tile grid across the shop and each tile came out about a metre across
	# — twice the size of a real floor tile and the first thing you notice.
	_mats["floor"] = _surface("floor", ProcTex.tiles(41), 6.0, 6.0)
	_mats["wall"] = _surface("wall", ProcTex.grime(Color(0.38, 0.37, 0.33), 0.45, 55), 4.0, 2.0)
	# And the ceiling the other way, though not as far as it first went. The cut
	# is itself a grid of four tiles, so mirroring made sixteen and repeating
	# three times put a hundred and forty-four overhead, which read as noise
	# rather than as a ceiling. One repeat smeared them into swirls instead.
	_mats["ceiling"] = _surface("ceiling", ProcTex.grime(Color(0.26, 0.26, 0.25), 0.5, 61), 4.0, 2.5)
	_mats["counter"] = _surface("counter_front", ProcTex.grime(Color(0.30, 0.24, 0.18), 0.4, 71), 2.0, 1.0)
	_mats["steel"] = _surface("steel", ProcTex.metal(Color(0.30, 0.31, 0.33), 81), 1.0, 1.0)
	_mats["dark_steel"] = ProcMesh.mat(ProcTex.metal(Color(0.14, 0.14, 0.16), 83))
	_mats["shutter"] = ProcMesh.mat(ProcTex.corrugated(Color(0.26, 0.26, 0.28), 91), 2.0)
	_mats["glass"] = ProcMesh.mat(ProcTex.flat(Color(0.30, 0.35, 0.38)), 1.0, Color(0.4, 0.5, 0.55), 0.06)
	_mats["screen"] = ProcMesh.mat(ProcTex.flat(Color(0.10, 0.35, 0.16)), 1.0, Color(0.20, 0.85, 0.35), 1.3)
	_mats["neon"] = ProcMesh.mat(ProcTex.neon_sign(Color(1.0, 0.25, 0.45), 5), 1.0, Color(1.0, 0.25, 0.45), 2.2)
	_mats["lamp"] = ProcMesh.mat(ProcTex.flat(Color(1.0, 0.92, 0.72)), 1.0, Color(1.0, 0.90, 0.66), 2.0)
	_mats["cash"] = ProcMesh.mat(ProcTex.flat(Color(0.55, 0.62, 0.42)), 1.0, Color(0.4, 0.5, 0.3), 0.25)
	_mats["concrete"] = _surface("concrete", ProcTex.grime(Color(0.40, 0.40, 0.38), 0.45, 131), 4.0, 3.0)
	# Lifted above 1.0 on purpose. The painted brick is a photograph of wet brick
	# in the dark, so it arrives already dim, and the tunnel is lit by a torch
	# and a handful of lamps — multiplying it down as well left the walls almost
	# unreadable. The generated brick never needed this because it was authored
	# at a usable brightness in the first place.
	_mats["sewer_brick"] = _surface("sewer_brick", ProcTex.brick(137), 5.0, 3.0,
		Color(1.55, 1.55, 1.50))
	# The channel running the length of the tunnel. The generated version carries
	# a faint emission so it reads as water in the dark; the painted one is
	# already lit water and does not need it, so `_surface` handles the choice
	# and the emission goes on only when the generator is what ends up used.
	_mats["water"] = _surface("water",
		ProcTex.grime(Color(0.10, 0.13, 0.12), 0.4, 141), 8.0, 4.0,
		Color.WHITE, Color(0.06, 0.10, 0.09), 0.15)
	_mats["cardboard"] = ProcMesh.mat(ProcTex.grime(Color(0.44, 0.33, 0.21), 0.35, 151), 1.0)


## One surface. Uses the painted texture if the pack has one under `name`, and
## the generated one otherwise, with its own repeat for each — a photographed
## brick wall and a generated one want different tiling to read at the same size.
## One surface. Uses the painted texture if the pack has one under `name`, and
## the generated one otherwise, with its own repeat for each — a photographed
## brick wall and a generated one want different tiling to read at the same size.
##
## `glow` and `glow_strength` apply to the generated texture only. They exist
## for surfaces the generator has to fake something on — water reads as water in
## a dark tunnel because it emits a little — and a painted texture that already
## has the light in it would come out twice lit.
func _surface(name: String, generated: Texture2D, repeat: float, painted_repeat: float,
		tint: Color = Color.WHITE, glow: Color = Color.BLACK,
		glow_strength: float = 0.0) -> Material:
	var tex := ProcTex.painted(name)
	if tex != null:
		return ProcMesh.mat(tex, painted_repeat, Color.BLACK, 0.0, tint)
	return ProcMesh.mat(generated, repeat, glow, glow_strength, tint)


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

	env.fog_enabled = true
	env.fog_light_color = Color(0.035, 0.038, 0.050)
	env.fog_density = 0.018
	env.fog_sky_affect = 0.0

	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	# A little sky on the street.
	#
	# The lamps throw tight pools, which is right — a sodium lamp does — but tight
	# pools with nothing between them left the road a void: you could see the
	# pavement at your feet and then absolutely nothing, which reads as walking
	# in a black box rather than as walking at night. No real street is like
	# that. There is always some sky, and it is what puts an edge on a building
	# forty metres away that you cannot otherwise see at all.
	#
	# Weak enough that it never competes with a lamp, angled down and slightly
	# along the road so walls catch it at a grazing angle and keep their shape.
	# A directional light does not count against the eight-lights-per-object
	# limit that made the lamp pools small in the first place.
	var sky := DirectionalLight3D.new()
	sky.name = "SkyGlow"
	sky.light_color = Color(0.46, 0.54, 0.78)
	sky.light_energy = 0.30
	sky.rotation_degrees = Vector3(-62, 28, 0)
	sky.shadow_enabled = false
	# Surface only. Down the ladder it is meant to be genuinely dark, and the
	# tunnels have their own lamps for that.
	sky.light_cull_mask = 1 << (LAYER_SURFACE - 1)
	add_child(sky)


# --- Shop shell --------------------------------------------------------------

func _build_shop_shell() -> void:
	var shop := Node3D.new()
	shop.name = "Shop"
	add_child(shop)

	shop.add_child(ProcMesh.solid_box(Vector3(SHOP_HALF_X * 2, 0.2, SHOP_HALF_Z * 2),
		Vector3(0, -0.1, 0), mat("floor"), "Floor"))
	shop.add_child(ProcMesh.solid_box(Vector3(SHOP_HALF_X * 2 + 0.4, 0.2, SHOP_HALF_Z * 2 + 0.4),
		Vector3(0, CEILING + 0.1, 0), mat("ceiling"), "Ceiling"))

	# Side walls are solid; the racks stand against them.
	for side: int in [-1, 1]:
		shop.add_child(ProcMesh.solid_box(Vector3(0.2, CEILING, SHOP_HALF_Z * 2),
			Vector3(side * (SHOP_HALF_X + 0.1), CEILING * 0.5, 0), mat("wall"), "SideWall%d" % side))

	# Back wall, with the doorway through to the stockroom.
	_wall_with_gap(shop, "BackWall", Vector3(0, 0, SHOP_HALF_Z + 0.1), true,
		SHOP_HALF_X * 2 + 0.4, CEILING, BACK_DOOR_X, BACK_DOOR_W, DOOR_H)

	# Front wall: two openings, the hatch and the shop door.
	_front_wall(shop)

	var shutter_h := HATCH_TOP - HATCH_BOTTOM
	var shutter := ProcMesh.box(Vector3(HATCH_WIDTH + 0.2, shutter_h, 0.06),
		Vector3(HATCH_X, CEILING - shutter_h * 0.5 + 0.02, -SHOP_HALF_Z - 0.16),
		mat("shutter"), "Shutter")
	shop.add_child(shutter)
	anchors["shutter"] = shutter
	anchors["shutter_open_y"] = shutter.position.y
	anchors["shutter_closed_y"] = (HATCH_TOP + HATCH_BOTTOM) * 0.5 - 0.05

	# Exterior dressing.
	shop.add_child(ProcMesh.box(Vector3(4.6, 0.55, 0.12), Vector3(0, 3.45, -SHOP_HALF_Z - 0.62),
		mat("neon"), "Sign"))
	sign_light = OmniLight3D.new()
	sign_light.position = Vector3(0, 3.15, -SHOP_HALF_Z - 1.1)
	sign_light.light_color = Color(1.0, 0.32, 0.50)
	sign_light.light_energy = 2.6
	sign_light.omni_range = 9.0
	add_child(sign_light)

	shop.add_child(ProcMesh.box(Vector3(SHOP_HALF_X * 2 + 1.2, 0.12, 1.2),
		Vector3(0, 3.12, -SHOP_HALF_Z - 0.55), mat("dark_steel"), "Awning"))
	shop.add_child(ProcMesh.box(Vector3(SHOP_HALF_X * 2 + 0.6, 0.3, SHOP_HALF_Z * 2 + 0.6),
		Vector3(0, CEILING + 0.30, 0), mat("shutter"), "Roof"))

	var hatch_light := OmniLight3D.new()
	hatch_light.position = Vector3(HATCH_X, 2.30, -SHOP_HALF_Z - 0.75)
	hatch_light.light_color = Color(1.0, 0.90, 0.74)
	hatch_light.light_energy = 2.8
	hatch_light.omni_range = 4.0
	add_child(hatch_light)

	# Two strip lights, because one no longer reaches the corners.
	strip_light = OmniLight3D.new()
	strip_light.position = Vector3(0, CEILING - 0.35, -1.4)
	strip_light.light_color = Color(0.85, 0.92, 1.0)
	# The strip lights carry the room on their own now.
	#
	# They used to be topped up by four street lamps reaching eighteen metres
	# through the front wall — which was wrong, and was also what pushed the
	# counter over the eight-lights-per-object limit. Pulling the lamps back to a
	# realistic pool took that accidental fill away with it, so the fittings that
	# are actually *in* the room do the work they were always supposed to.
	strip_light.light_energy = 3.6
	strip_light.omni_range = 13.0
	add_child(strip_light)
	shop.add_child(ProcMesh.box(Vector3(3.0, 0.08, 0.22), Vector3(0, CEILING - 0.12, -1.4),
		ProcMesh.mat(ProcTex.flat(Color(0.9, 0.95, 1.0)), 1.0, Color(0.85, 0.92, 1.0), 1.6), "Strip1"))

	var strip2 := OmniLight3D.new()
	strip2.position = Vector3(0, CEILING - 0.35, 2.0)
	strip2.light_color = Color(0.85, 0.92, 1.0)
	strip2.light_energy = 3.1
	strip2.omni_range = 12.0
	add_child(strip2)
	shop.add_child(ProcMesh.box(Vector3(3.0, 0.08, 0.22), Vector3(0, CEILING - 0.12, 2.0),
		ProcMesh.mat(ProcTex.flat(Color(0.9, 0.95, 1.0)), 1.0, Color(0.85, 0.92, 1.0), 1.6), "Strip2"))

	anchors["customer_stand"] = CUSTOMER_STAND
	anchors["customer_entry"] = CUSTOMER_ENTRY
	anchors["customer_exit"] = CUSTOMER_EXIT
	# Behind the counter, facing the customer side.
	anchors["player_spawn"] = Vector3(-0.60, 0.1, CHECKOUT_Z + 1.05)


## The front wall carries both the hatch and the shop door, so it is built as a
## run of pillars between the openings rather than by the generic helper.
func _front_wall(shop: Node3D) -> void:
	var z := -SHOP_HALF_Z - 0.1
	var openings := [
		{"centre": HATCH_X, "half": HATCH_WIDTH * 0.5},
		{"centre": FRONT_DOOR_X, "half": FRONT_DOOR_W * 0.5},
	]
	openings.sort_custom(func(a, b): return float(a["centre"]) < float(b["centre"]))

	var cursor := -SHOP_HALF_X - 0.2
	for o: Dictionary in openings:
		var edge: float = float(o["centre"]) - float(o["half"])
		if edge - cursor > 0.02:
			shop.add_child(ProcMesh.solid_box(Vector3(edge - cursor, CEILING, 0.2),
				Vector3((cursor + edge) * 0.5, CEILING * 0.5, z), mat("wall"), "FrontPier"))
		cursor = float(o["centre"]) + float(o["half"])
	if SHOP_HALF_X + 0.2 - cursor > 0.02:
		shop.add_child(ProcMesh.solid_box(Vector3(SHOP_HALF_X + 0.2 - cursor, CEILING, 0.2),
			Vector3((cursor + SHOP_HALF_X + 0.2) * 0.5, CEILING * 0.5, z), mat("wall"), "FrontPier"))

	# Sill and head around the hatch, and a head over the door.
	shop.add_child(ProcMesh.solid_box(Vector3(HATCH_WIDTH, HATCH_BOTTOM, 0.2),
		Vector3(HATCH_X, HATCH_BOTTOM * 0.5, z), mat("wall"), "HatchSill"))
	shop.add_child(ProcMesh.solid_box(Vector3(HATCH_WIDTH, CEILING - HATCH_TOP, 0.2),
		Vector3(HATCH_X, (CEILING + HATCH_TOP) * 0.5, z), mat("wall"), "HatchHead"))
	shop.add_child(ProcMesh.solid_box(Vector3(FRONT_DOOR_W, CEILING - DOOR_H, 0.2),
		Vector3(FRONT_DOOR_X, (CEILING + DOOR_H) * 0.5, z), mat("wall"), "DoorHead"))

	for side: int in [-1, 1]:
		shop.add_child(ProcMesh.box(Vector3(0.28, HATCH_TOP - HATCH_BOTTOM, 0.04),
			Vector3(HATCH_X + side * (HATCH_WIDTH * 0.5 - 0.14),
				(HATCH_TOP + HATCH_BOTTOM) * 0.5, z), mat("glass"), "Pane%d" % side))

	# A glass door leaf, propped open against the pier.
	shop.add_child(ProcMesh.box(Vector3(0.06, DOOR_H - 0.1, 1.0),
		Vector3(FRONT_DOOR_X - FRONT_DOOR_W * 0.5 - 0.1, DOOR_H * 0.5, z + 0.55),
		mat("glass"), "DoorLeaf"))


## Builds a wall with a rectangular doorway cut into it, as three solid pieces.
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

	var head := height - gap_height
	if head > 0.02:
		var size := Vector3(gap_width, head, 0.2) if along_x else Vector3(0.2, head, gap_width)
		var pos := centre + (Vector3(gap_centre, gap_height + head * 0.5, 0) if along_x
			else Vector3(0, gap_height + head * 0.5, gap_centre))
		parent.add_child(ProcMesh.solid_box(size, pos, mat("wall"), node_name + "Head"))


# --- Checkout ----------------------------------------------------------------

func _build_counter() -> void:
	var counter := Node3D.new()
	counter.name = "Counter"
	add_child(counter)

	# The old serving ledge under the hatch stays. It is no longer where you
	# trade — it is the window the shutter covers and the raid comes through.
	counter.add_child(ProcMesh.solid_box(Vector3(HATCH_WIDTH + 0.6, 0.10, 0.45),
		Vector3(HATCH_X, COUNTER_Y, -SHOP_HALF_Z + 0.23), mat("counter"), "HatchLedge"))
	counter.add_child(ProcMesh.solid_box(Vector3(HATCH_WIDTH + 0.6, COUNTER_Y - 0.05, 0.36),
		Vector3(HATCH_X, (COUNTER_Y - 0.05) * 0.5, -SHOP_HALF_Z + 0.18), mat("counter"), "HatchKick"))

	var width := CHECKOUT_MAX_X - CHECKOUT_MIN_X
	var cx := (CHECKOUT_MIN_X + CHECKOUT_MAX_X) * 0.5
	counter.add_child(ProcMesh.solid_box(Vector3(width, CHECKOUT_Y, CHECKOUT_DEPTH),
		Vector3(cx, CHECKOUT_Y * 0.5, CHECKOUT_Z), mat("counter"), "Checkout"))
	counter.add_child(ProcMesh.box(Vector3(width + 0.08, 0.06, CHECKOUT_DEPTH + 0.10),
		Vector3(cx, CHECKOUT_Y + 0.03, CHECKOUT_Z), mat("dark_steel"), "CheckoutTop"))

	# Where the customer's shopping lands, spread along the customer side.
	var slots: Array[Vector3] = []
	for i in CHECKOUT_SLOTS:
		var t := (float(i) + 0.5) / float(CHECKOUT_SLOTS)
		slots.append(Vector3(lerpf(CHECKOUT_MIN_X + 0.45, CHECKOUT_MAX_X - 1.15, t),
			CHECKOUT_Y + 0.15, CHECKOUT_Z - 0.16))
	anchors["checkout_slots"] = slots

	var bag_spot := Vector3(CHECKOUT_MAX_X - 0.45, CHECKOUT_Y + 0.12, CHECKOUT_Z + 0.12)
	anchors["bag_spot"] = bag_spot
	counter.add_child(ProcMesh.box(Vector3(0.30, 0.34, 0.22), bag_spot + Vector3(0, 0.10, 0),
		mat("cardboard"), "Bag"))

	_interactable(counter, "till", "Till", Vector3(0.44, 0.32, 0.42),
		Vector3(CHECKOUT_MIN_X + 0.50, CHECKOUT_Y + 0.22, CHECKOUT_Z + 0.12), mat("steel"))
	_interactable(counter, "terminal", "Terminal", Vector3(0.58, 0.48, 0.44),
		Vector3(CHECKOUT_MIN_X + 1.45, CHECKOUT_Y + 0.30, CHECKOUT_Z + 0.16), mat("dark_steel"))

	var screen := ProcMesh.quad(Vector2(0.48, 0.36),
		Vector3(CHECKOUT_MIN_X + 1.45, CHECKOUT_Y + 0.33, CHECKOUT_Z + 0.39), mat("screen"))
	screen.rotation_degrees = Vector3(-10, 180, 0)
	counter.add_child(screen)
	var glow := OmniLight3D.new()
	glow.position = Vector3(CHECKOUT_MIN_X + 1.45, CHECKOUT_Y + 0.42, CHECKOUT_Z + 0.65)
	glow.light_color = Color(0.35, 1.0, 0.45)
	glow.light_energy = 0.9
	glow.omni_range = 2.8
	counter.add_child(glow)
	anchors["terminal_glow"] = glow

	_interactable(counter, "stash", "Stash", Vector3(0.46, 0.32, 0.38),
		Vector3(cx + 0.7, 0.28, CHECKOUT_Z + 0.16), mat("dark_steel"))
	_interactable(counter, "scanner", "Scanner", Vector3(0.15, 0.10, 0.28),
		Vector3(CHECKOUT_MAX_X - 1.20, CHECKOUT_Y + 0.11, CHECKOUT_Z + 0.18), mat("steel"))

	anchors["counter_y"] = CHECKOUT_Y
	anchors["handover"] = Vector3(cx, CHECKOUT_Y + 0.12, CHECKOUT_Z - 0.16)


func _build_fittings() -> void:
	var fit := Node3D.new()
	fit.name = "Fittings"
	add_child(fit)

	_interactable(fit, "shop", "Supplier Phone", Vector3(0.20, 0.34, 0.12),
		Vector3(-SHOP_HALF_X + 0.16, 1.45, CHECKOUT_Z + 1.6), mat("dark_steel"))
	_interactable(fit, "shutter_control", "Shutter Control", Vector3(0.16, 0.24, 0.10),
		Vector3(-SHOP_HALF_X + 0.16, 1.40, -SHOP_HALF_Z + 0.70), mat("steel"))

	fit.add_child(ProcMesh.box(Vector3(0.16, 0.12, 0.26),
		Vector3(SHOP_HALF_X - 0.30, CEILING - 0.30, -SHOP_HALF_Z + 0.40), mat("dark_steel"), "Camera"))

	fit.add_child(ProcMesh.cylinder(0.16, 0.62, Vector3(1.9, 0.31, CHECKOUT_Z + 0.9),
		mat("dark_steel"), 6))
	fit.add_child(ProcMesh.box(Vector3(0.16, 0.22, 0.16), Vector3(-4.4, 0.85, 3.2),
		mat("steel"), "Kettle"))
	fit.add_child(ProcMesh.box(Vector3(0.34, 0.16, 0.16), Vector3(-4.3, 1.62, SHOP_HALF_Z - 0.25),
		mat("dark_steel"), "Radio"))

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

## Three racks in the shopping half of the floor: one against each side wall and
## a free-standing island between them, so there is an aisle to walk down on
## both sides of it.
func _build_shelving() -> void:
	var racks := Node3D.new()
	racks.name = "Shelving"
	add_child(racks)

	var layout := {
		0: {"origin": Vector3(-SHOP_HALF_X + 0.28, 0, -3.30), "dir": Vector3(0, 0, 1),
			"rot": 90.0, "span": 3.1, "browse": Vector3(-SHOP_HALF_X + 1.30, 0, -1.80)},
		1: {"origin": Vector3(SHOP_HALF_X - 0.28, 0, -3.30), "dir": Vector3(0, 0, 1),
			"rot": -90.0, "span": 2.4, "browse": Vector3(SHOP_HALF_X - 1.30, 0, -2.10)},
		2: {"origin": Vector3(-1.80, 0, -1.90), "dir": Vector3(1, 0, 0),
			"rot": 0.0, "span": 3.6, "browse": Vector3(0.0, 0, -1.00)},
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
		var carcass: Vector3 = Vector3(0.40, 1.80, span) if dir.z > 0.5 else Vector3(span, 1.80, 0.40)
		racks.add_child(ProcMesh.solid_box(carcass, centre + Vector3(0, 0.90, 0),
			mat("dark_steel"), "Rack%d" % rack_id))

		for i in items.size():
			var item_id: String = items[i]
			var level_y := 0.98 + float(i) * 0.48
			var slots: Array[MeshInstance3D] = []
			# A painted product if the pack has one for this item, and a
			# generated carton in the item's colour if not. Never tiled — the
			# picture is of one object and wants to stay one object.
			var painted := ProcTex.painted("item_%s" % item_id)
			var box_mat := ProcMesh.mat(painted, 1.0) if painted != null \
				else ProcMesh.mat(ProcTex.product(
					SHELF_TINTS.get(item_id, Color(0.5, 0.5, 0.5)), hash(item_id)))
			var count := 10
			for s in count:
				var along := 0.20 + float(s) * ((span - 0.40) / float(count - 1))
				var pos: Vector3 = origin + dir * along + Vector3(0, level_y, 0)
				var box := ProcMesh.box(Vector3(0.18, 0.24, 0.18), pos, box_mat, "%s_%d" % [item_id, s])
				box.rotation_degrees = Vector3(0, conf["rot"], 0)
				racks.add_child(box)
				slots.append(box)
			shelf_slots[item_id] = slots
			shelf_points[item_id] = conf["browse"]

			var mid: Vector3 = origin + dir * (span * 0.5) + Vector3(0, level_y, 0)
			var zone: Vector3 = Vector3(0.36, 0.42, span) if dir.z > 0.5 else Vector3(span, 0.42, 0.36)
			_interact_zone(racks, "shelf:" + item_id, mid, zone)


func refresh_shelves() -> void:
	for item_id: String in shelf_slots:
		var units := GameState.shelf_units(item_id)
		var slots: Array = shelf_slots[item_id]
		for i in slots.size():
			(slots[i] as MeshInstance3D).visible = i < units


## Where a shopper stands to take something off a given rack.
func browse_point(item_id: String) -> Vector3:
	return shelf_points.get(item_id, CUSTOMER_STAND)


# --- Stockroom ---------------------------------------------------------------

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
	for side: int in [-1, 1]:
		var x := STOCK_MIN_X - 0.1 if side < 0 else STOCK_MAX_X + 0.1
		room.add_child(ProcMesh.solid_box(Vector3(0.2, STOCK_CEILING, d),
			Vector3(x, STOCK_CEILING * 0.5, cz), mat("concrete"), "StockSide%d" % side))

	for piece: Array in [[STOCK_MIN_X, BACK_DOOR_X - BACK_DOOR_W * 0.5],
			[BACK_DOOR_X + BACK_DOOR_W * 0.5, STOCK_MAX_X]]:
		var seg: float = piece[1] - piece[0]
		if seg <= 0.02:
			continue
		room.add_child(ProcMesh.solid_box(Vector3(seg, STOCK_CEILING, 0.2),
			Vector3((piece[0] + piece[1]) * 0.5, STOCK_CEILING * 0.5, STOCK_MIN_Z + 0.1),
			mat("concrete"), "StockFront"))

	stock_light = OmniLight3D.new()
	stock_light.position = Vector3(cx, STOCK_CEILING - 0.30, cz - 0.8)
	stock_light.light_color = Color(1.0, 0.88, 0.66)
	stock_light.light_energy = 3.4
	stock_light.omni_range = 13.0
	add_child(stock_light)
	room.add_child(ProcMesh.box(Vector3(0.30, 0.10, 0.30), Vector3(cx, STOCK_CEILING - 0.10, cz - 0.8),
		ProcMesh.mat(ProcTex.flat(Color(1.0, 0.92, 0.74)), 1.0, Color(1.0, 0.88, 0.66), 1.4), "StockBulb"))

	var back_light := OmniLight3D.new()
	back_light.position = Vector3(cx - 0.6, STOCK_CEILING - 0.30, STOCK_MAX_Z - 1.4)
	back_light.light_color = Color(1.0, 0.90, 0.70)
	back_light.light_energy = 2.8
	back_light.omni_range = 11.0
	add_child(back_light)

	var rng := RandomNumberGenerator.new()
	rng.seed = 5150
	for bay in 4:
		var bz := STOCK_MIN_Z + 1.2 + float(bay) * 1.85
		room.add_child(ProcMesh.solid_box(Vector3(0.9, 2.3, 1.6),
			Vector3(STOCK_MIN_X + 0.55, 1.15, bz), mat("dark_steel"), "Bay%d" % bay))
		for level in 3:
			for c in 2:
				var case_mat := ProcMesh.mat(ProcTex.product(
					SHELF_TINTS.values()[rng.randi() % SHELF_TINTS.size()], rng.randi()))
				room.add_child(ProcMesh.box(Vector3(0.42, 0.34, 0.42),
					Vector3(STOCK_MIN_X + 0.55, 0.44 + float(level) * 0.74, bz - 0.38 + float(c) * 0.76),
					case_mat, "Case"))

	for i in 9:
		room.add_child(ProcMesh.box(Vector3(rng.randf_range(0.4, 0.7), rng.randf_range(0.3, 0.5),
			rng.randf_range(0.4, 0.7)),
			Vector3(rng.randf_range(STOCK_MIN_X + 1.8, STOCK_MAX_X - 0.7), 0.25,
				rng.randf_range(STOCK_MIN_Z + 1.0, STOCK_MAX_Z - 1.6)),
			mat("cardboard"), "Box%d" % i))
	room.add_child(ProcMesh.box(Vector3(1.2, 0.34, 1.0),
		Vector3(STOCK_MAX_X - 1.0, 0.17, STOCK_MIN_Z + 1.0), mat("cardboard"), "Pallets"))

	_interactable(room, "crates", "Crates", Vector3(1.60, 0.90, 0.80),
		Vector3(STOCK_MIN_X + 2.6, 0.45, STOCK_MAX_Z - 0.9), mat("counter"))

	room.add_child(ProcMesh.cylinder(0.52, 0.06, MANHOLE + Vector3(0, 0.03, 0), mat("dark_steel"), 12))
	room.add_child(ProcMesh.cylinder(0.44, 0.10, MANHOLE + Vector3(0, -0.06, 0),
		ProcMesh.mat(ProcTex.flat(Color(0.02, 0.02, 0.03))), 12))
	var cover := ProcMesh.cylinder(0.46, 0.05, MANHOLE + Vector3(0.75, 0.30, 0.1), mat("steel"), 12)
	cover.rotation_degrees = Vector3(0, 0, 78)
	room.add_child(cover)
	_interact_zone(room, "manhole", MANHOLE + Vector3(0, 0.5, 0), Vector3(1.1, 1.0, 1.1))

	anchors["manhole"] = MANHOLE
	anchors["stock_centre"] = Vector3(cx, 0, cz)


# --- Cash lying about --------------------------------------------------------

func scatter_cash(rng: RandomNumberGenerator) -> void:
	for node: Node3D in cash_pickups:
		if is_instance_valid(node):
			node.queue_free()
	cash_pickups.clear()

	var spots := [
		Vector3(-4.2, 0.06, 2.9), Vector3(4.3, 0.06, 2.4), Vector3(-1.2, 0.06, 3.2),
		Vector3(4.4, 0.06, -3.4), Vector3(-4.4, 0.06, -3.2), Vector3(2.2, 0.06, 3.1),
		Vector3(CHECKOUT_MIN_X + 0.9, CHECKOUT_Y + 0.16, CHECKOUT_Z + 0.28),
		Vector3(3.6, 0.06, 0.4), Vector3(-2.6, 0.06, -3.6),
		Vector3(STOCK_MIN_X + 2.8, 0.06, STOCK_MIN_Z + 1.6),
		Vector3(STOCK_MAX_X - 1.2, 0.06, STOCK_MAX_Z - 2.1),
		Vector3(-3.0, 0.06, STOCK_MAX_Z - 1.0),
		Vector3(FRONT_DOOR_X + 1.6, 0.20, -SHOP_HALF_Z - 1.9),
		Vector3(-7.0, 0.20, -5.4),
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

func _interactable(parent: Node3D, id: String, node_name: String, size: Vector3,
		pos: Vector3, material: Material) -> StaticBody3D:
	var body := ProcMesh.solid_box(size, pos, material, node_name)
	body.set_collision_layer_value(1, true)
	body.set_collision_layer_value(2, true)
	body.set_meta("interact", id)
	parent.add_child(body)
	return body


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
