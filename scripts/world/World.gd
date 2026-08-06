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
## The shelving, flattened to the floor plan. Used for routing shoppers around
## it rather than through it.
var _rack_rects: Array[Rect2] = []


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
	# Six, not two. Two repeats stretched one brick swatch across the whole
	# front of the kiosk, which at that size stops reading as brick and starts
	# reading as a wooden panel — and it is the size at which the mirroring
	# becomes obvious, because the fold line ends up a metre wide.
	_mats["brick"] = _surface("brick_far", ProcTex.brick(21), 3.0, 6.0)
	_mats["brick_far"] = _surface("brick_far", ProcTex.brick(33), 6.0, 9.0, Color(0.55, 0.55, 0.6))
	# Six, not three. The cut is mirrored into a 2x2, so three repeats put a
	# six-tile grid across the shop and each tile came out about a metre across
	# — twice the size of a real floor tile and the first thing you notice.
	_mats["floor"] = _surface("floor", ProcTex.tiles(41), 6.0, 6.0)
	# Painted plaster rather than the nicotine-stained panel.
	#
	# That swatch is a tall narrow crop with a rail across it, and folding a
	# thing with a horizontal line in it puts that line back at you mirrored —
	# which is the seam behind the counter. Painted plaster is close to
	# featureless, so it folds without leaving anything to notice, and four
	# repeats keeps whatever is left small.
	_mats["wall"] = _surface("wall_painted",
		ProcTex.grime(Color(0.38, 0.37, 0.33), 0.45, 55), 4.0, 4.0)
	# Plain concrete overhead rather than the tiled ceiling from the kiosk sheet.
	# That one is itself a grid of four tiles, so mirroring made sixteen and any
	# repeat above one put a hundred-odd of them over your head — busy in a way a
	# ceiling should never be, since it is the one surface with nothing on it to
	# look at. Concrete has almost no feature to repeat, so it can tile hard
	# without ever announcing that it is tiling.
	_mats["ceiling"] = _surface("ceiling_concrete",
		ProcTex.grime(Color(0.26, 0.26, 0.25), 0.5, 61), 4.0, 3.0)
	# The counter top, not the counter front.
	#
	# The front swatch is a photograph of a whole counter unit — a pale upper
	# panel over a dark green lower one — so stretching one copy across the
	# counter gave a big flat slab with a band through it that reads as plywood.
	# The top swatch is plain worn wood with no structure in it, which is what a
	# surface wants to be: it tiles three times along the counter without ever
	# showing where one copy ends.
	_mats["counter"] = _surface("counter_top",
		ProcTex.grime(Color(0.30, 0.24, 0.18), 0.4, 71), 2.0, 3.0)
	_mats["steel"] = _surface("steel", ProcTex.metal(Color(0.30, 0.31, 0.33), 81), 1.0, 1.0)
	# Lamp posts, bins, skips, the awning — the dull painted steel everything
	# outdoors is made of. The pipe swatch is the closest thing in the pack to a
	# surface rather than an object, which matters because this one goes on a
	# dozen shapes of wildly different size.
	_mats["dark_steel"] = _surface("pipe_metal",
		ProcTex.metal(Color(0.14, 0.14, 0.16), 83), 1.0, 2.0, Color(0.72, 0.72, 0.76))
	# The shutter keeps its generated corrugation. Nothing in the pack is ribbed
	# metal, and a flat panel over the front of the shop would lose the one thing
	# that says it is a shutter and not a wall.
	_mats["shutter"] = ProcMesh.mat(ProcTex.corrugated(Color(0.26, 0.26, 0.28), 91), 2.0)
	_mats["glass"] = ProcMesh.mat(ProcTex.flat(Color(0.30, 0.35, 0.38)), 1.0, Color(0.4, 0.5, 0.55), 0.06)
	# The terminal's monitor. Keeps its glow either way — the interface is drawn
	# on a panel in front of it, so this is the box the screen lives in, and a
	# dead grey box beside a lit interface reads as switched off.
	#
	# It said that in a comment for a while and did not do it: `_surface` drops
	# the emission on the painted branch by design, so the moment the pack landed
	# the one lit object on the counter went dark. `_lit` is the branch that
	# means what this comment says.
	#
	# The painted one glows less. Emission is added on top of the texture rather
	# than multiplied through it, so the strength that makes a flat green box
	# read as a lit screen turns a photograph of a monitor into a green blob with
	# a monitor somewhere underneath it.
	_mats["screen"] = _lit("crt_screen", ProcTex.flat(Color(0.10, 0.35, 0.16)),
		Color(0.20, 0.85, 0.35), 1.3, 1.0, Color(0.85, 1.0, 0.88), 0.45)
	# The shop's own sign. The pack has one that says KIOSK 24/7, which is what
	# the place is called, so it replaces the generated neon strip entirely — and
	# the glow comes down with it, because a lit box sign is a photograph of
	# something already lit rather than a tube that has to emit to read as one.
	_mats["neon"] = _surface("sign_kiosk",
		ProcTex.neon_sign(Color(1.0, 0.25, 0.45), 5), 1.0, 1.0,
		Color(1.35, 1.30, 1.15), Color(1.0, 0.25, 0.45), 2.2)
	_mats["lamp"] = ProcMesh.mat(ProcTex.flat(Color(1.0, 0.92, 0.72)), 1.0, Color(1.0, 0.90, 0.66), 2.0)
	_mats["cash"] = ProcMesh.mat(ProcTex.flat(Color(0.55, 0.62, 0.42)), 1.0, Color(0.4, 0.5, 0.3), 0.25)
	_mats["concrete"] = _surface("wall_concrete",
		ProcTex.grime(Color(0.40, 0.40, 0.38), 0.45, 131), 4.0, 3.0)
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
	# Moving water for the doglegs, where the runs come down off the street and
	# there is somewhere for it to be going.
	_mats["water_flow"] = _surface("water_flow",
		ProcTex.grime(Color(0.10, 0.13, 0.12), 0.4, 143), 8.0, 4.0,
		Color.WHITE, Color(0.06, 0.10, 0.09), 0.15)
	# The kiosk sheet has a swatch called "storage room floor", and this is the
	# storage room floor. It was wearing the street's concrete because the pack
	# was wired up a sheet at a time and this one arrived last.
	_mats["stock_floor"] = _surface("stock_floor",
		ProcTex.grime(Color(0.30, 0.30, 0.29), 0.5, 161), 5.0, 4.0)
	_mats["sewer_floor"] = _surface("sewer_floor", ProcTex.brick(137), 5.0, 4.0,
		Color(1.35, 1.35, 1.30))
	# Back to generated metal.
	#
	# I put the furniture sheet's shelf-unit photograph on this, which was wrong
	# twice over: it is a picture of a whole shelving unit, shelves and all, and
	# the rack carcass is a plain box the length of a wall. Stretched over that
	# it became a field of metal blobs with no shelf in it anywhere, so the stock
	# sitting on the racks looked like it was floating in mid air.
	#
	# A photograph of a thing is not a material for that thing.
	_mats["rack"] = ProcMesh.mat(ProcTex.metal(Color(0.14, 0.14, 0.16), 83))
	# The boards the stock actually sits on. A photograph of a shelf unit is no
	# good as a material for a rack — that was the mistake above — but it is
	# exactly right on a board, because a board is the thing the photograph is
	# mostly of. Two repeats along a three metre run.
	_mats["shelf_board"] = _surface("shelf_wood",
		ProcTex.grime(Color(0.32, 0.26, 0.19), 0.4, 181), 1.0, 2.0)
	_mats["shelf_board_metal"] = _surface("shelf_metal",
		ProcTex.metal(Color(0.28, 0.29, 0.31), 183), 1.0, 2.0)
	_mats["cardboard"] = _surface("cardboard",
		ProcTex.grime(Color(0.44, 0.33, 0.21), 0.35, 151), 1.0, 1.0)

	# --- Everything the pack had that the world was not asking for -----------
	#
	# The pack arrived as a hundred-odd cut swatches and the world named twenty
	# of them. The other eighty were on disk, loaded into memory at launch and
	# drawn nowhere — a bin painted as a bin, sitting in the texture table while
	# the bin in the street wore a photograph of a drainpipe.
	#
	# This is the rest of it. Nothing here is a new kind of surface; it is the
	# same objects the street and the shop already had, asking for the picture of
	# themselves instead of the nearest grey metal.

	# Street furniture. Each of these is one object with one photograph on it, so
	# they go through `_thing` and are never tiled.
	_mats["kerb"] = _surface("kerb", ProcTex.grime(Color(0.24, 0.24, 0.23), 0.4, 171), 8.0, 30.0)
	_mats["bin"] = _thing("garbage_bin", _mats["dark_steel"])
	_mats["street_bin"] = _thing("bin", _mats["dark_steel"])
	# A skip is a big steel box that has been outside for years, which is what
	# the corroded plate off the decals sheet is a photograph of. Tiled twice so
	# the corrosion stays the size of corrosion on something three metres long.
	_mats["skip"] = _surface("metal_corroded",
		ProcTex.metal(Color(0.22, 0.20, 0.18), 87), 1.0, 2.0)
	_mats["rusted"] = _surface("rust_patches",
		ProcTex.metal(Color(0.34, 0.22, 0.15), 97), 1.0, 2.0)
	_mats["manhole_cover"] = _thing("manhole", _mats["dark_steel"])
	# The pack has a lamp post and a lamp head, and the street has eight of each.
	_mats["lamp_post"] = _surface("lamp_post",
		ProcTex.metal(Color(0.14, 0.14, 0.16), 83), 1.0, 1.0)
	_mats["lamp_head_off"] = _thing("lamp_head", _mats["dark_steel"])
	_mats["drain"] = _thing("drain", _mats["dark_steel"])
	_mats["grate"] = _thing("grate", _mats["steel"])
	_mats["fence"] = _surface("fence", ProcTex.metal(Color(0.20, 0.21, 0.22), 89), 1.0, 4.0)
	_mats["litter"] = _thing("newspaper", ProcMesh.mat(ProcTex.flat(Color(0.62, 0.60, 0.55))))

	# Yard clutter. The street had four objects in it and a hundred metres to put
	# them in; these are what the rest of it is made of.
	_mats["drum"] = _thing("metal_drum", _mats["dark_steel"])
	_mats["pallet"] = _thing("pallet_wood", _mats["cardboard"])
	_mats["crate_wood"] = _thing("wooden_crate", _mats["cardboard"])
	_mats["crate_plastic"] = _thing("plastic_crate", _mats["cardboard"])
	_mats["crate_milk"] = _thing("milk_crate", _mats["cardboard"])
	_mats["tyres"] = _thing("tyres", ProcMesh.mat(ProcTex.flat(Color(0.09, 0.09, 0.10))))
	_mats["bin_bag"] = _thing("garbage_bag", ProcMesh.mat(ProcTex.flat(Color(0.07, 0.07, 0.08))))
	_mats["bucket"] = _thing("bucket", _mats["cardboard"])
	_mats["board"] = _thing("wooden_board", _mats["cardboard"])
	_mats["cardboard_printed"] = _thing("cardboard_printed", _mats["cardboard"])

	# Doors. The shop has three openings and every one of them was a hole.
	_mats["door_metal"] = _thing("door_metal", _mats["steel"])
	_mats["door_wood"] = _thing("door_wooden", _mats["counter"])

	# White goods, which the shop had none of and every shop like it has.
	_mats["fridge"] = _thing("fridge", _mats["steel"])
	_mats["vending"] = _thing("vending_machine", _mats["steel"])

	# Signs and the writing on the walls. Small quads, and between them most of
	# what tells you where you are.
	#
	# The warning signs come off the lighting sheet rather than the signage one.
	# Both sheets have a no-smoking sign; the signage version is a photograph of
	# a sign on a wall, at an angle, with the wall in it, and the lighting
	# version is the sign square on and nothing else. On a 30cm quad in a dark
	# shop that is the difference between a sign and a smudge.
	for sign: String in ["warn_staff_only", "warn_no_smoking", "warn_wet_floor",
			"warn_no_entry", "warn_danger_electric", "sign_notice", "note_paper",
			"graffiti_large_a", "graffiti_large_b", "graffiti_c",
			"poster_a", "poster_b", "poster_torn"]:
		_mats[sign] = _thing(sign, _mats["wall"])
	# The way out, lit, because that is the whole point of one.
	_mats["sign_exit"] = _lit("sign_emergency", ProcTex.flat(Color(0.20, 0.75, 0.35)),
		Color(0.25, 0.90, 0.42), 1.1, 1.0, Color.WHITE, 0.35)

	# The sky over the street.
	#
	# One very large panel above the roofs rather than a skybox: the world is
	# drawn one render layer at a time and a skybox would show through the road
	# the same way the tunnels did. It also answers the complaint that the street
	# is a black box — the box had no lid, and looking up gave you the clear
	# colour of the environment and nothing else. Emissive at a fraction,
	# because nothing lights the sky.
	#
	# Cloud most nights and clear every third one, so the weather is something
	# that changes rather than something the game has one of. Off the night
	# number rather than a shuffle: a run that carries over should look the same
	# on the same night twice.
	_mats["sky"] = _lit(sky_for_night(GameState.night),
		ProcTex.grime(Color(0.05, 0.06, 0.09), 0.4, 191),
		Color(0.10, 0.12, 0.18), 0.55, 3.0, Color(1.55, 1.55, 1.70), 0.42)

	# Light fittings. `_lit` rather than `_surface`, or the painted tube is a grey
	# stripe on the ceiling of a dark shop.
	#
	# Only the shop's strips are painted. The tunnel and the stockroom are lit by
	# things the size of a fist, and a photograph of a lamp on an eighteen
	# centimetre box is four dark pixels and a bright one — worse than the flat
	# white it replaces, on the one object in the room whose whole job is to be
	# the bright thing in it.
	_mats["strip_light"] = _lit("light_strip",
		ProcTex.flat(Color(0.9, 0.95, 1.0)), Color(0.85, 0.92, 1.0), 1.6)
	_mats["bulb"] = ProcMesh.mat(ProcTex.flat(Color(1.0, 0.92, 0.74)), 1.0,
		Color(1.0, 0.88, 0.66), 1.4)
	# The tunnels get the caged bulkhead lamp, which is what is actually bolted
	# to the wall of a place like that, on a fitting big enough to see it on.
	_mats["tunnel_bulb"] = _lit("light_bulkhead", ProcTex.flat(Color(0.85, 0.95, 0.8)),
		Color(0.78, 0.9, 0.72), 1.2, 1.0, Color.WHITE, 0.5)
	_mats["cctv"] = _lit("screen_cctv", ProcTex.flat(Color(0.14, 0.20, 0.16)),
		Color(0.30, 0.55, 0.35), 0.9, 1.0, Color.WHITE, 0.30)

	# Surfaces the back rooms and the tunnels wanted and did not have.
	#
	# The nicotine-stained wall off the kiosk sheet, at five repeats rather than
	# three. It is a photograph of the inside of a place exactly like this one
	# that has been open a very long time, which is what the room behind the shop
	# should look like, and at five copies whatever is in it stays small. Three
	# repeats of anything with real contrast in it gives metre-wide blooms with a
	# mirror line down the middle of each — five copies of nearly nothing is a
	# wall, one copy of something is a mural.
	_mats["stock_wall"] = _surface("wall",
		ProcTex.grime(Color(0.36, 0.35, 0.32), 0.5, 173), 4.0, 5.0)
	# The peeling paint goes on one small wall at the far end of the street,
	# where there is nothing else to look at and its contrast is the point.
	_mats["peeling"] = _surface("wall_peeling",
		ProcTex.grime(Color(0.34, 0.32, 0.28), 0.5, 177), 4.0, 2.0)
	_mats["clad_metal"] = _surface("wall_panel_metal",
		ProcTex.metal(Color(0.24, 0.25, 0.27), 175), 1.0, 3.0)
	_mats["roof_panel"] = _surface("concrete_panel",
		ProcTex.corrugated(Color(0.26, 0.26, 0.28), 91), 2.0, 4.0)
	_mats["awning"] = _surface("riveted_metal",
		ProcTex.metal(Color(0.22, 0.20, 0.18), 87), 1.0, 4.0)
	_mats["beam"] = _surface("ceiling_beam",
		ProcTex.grime(Color(0.24, 0.24, 0.23), 0.5, 185), 4.0, 3.0)
	_mats["corrugated"] = _surface("corrugated_metal",
		ProcTex.corrugated(Color(0.26, 0.26, 0.28), 91), 2.0, 3.0)
	_mats["pipe_rusted"] = _surface("pipe_rusted",
		ProcTex.metal(Color(0.34, 0.20, 0.12), 93), 1.0, 2.0)
	# The two counter panels. Objects rather than surfaces: each is a photograph
	# of one whole counter, and the side has an "Under 18" notice on it that only
	# reads as one if there is exactly one of it.
	_mats["counter_face"] = _thing("counter_front", _mats["counter"])
	_mats["counter_end"] = _thing("counter_side", _mats["counter"])
	# A body bag is an evidence bag with somebody in it.
	_mats["body_bag"] = _thing("gear_evidence_bag",
		ProcMesh.mat(ProcTex.flat(Color(0.045, 0.05, 0.055))))
	_mats["ammo_box"] = _thing("gear_ammo_box", _mats["cardboard"])
	# Standing water on the road, for the puddles.
	_mats["wet_road"] = _surface("asphalt_wet", ProcTex.asphalt(7), 14.0, 2.0)
	# The shelving units in the back. This is the one place a photograph of a
	# whole shelving unit belongs — on a whole shelving unit.
	_mats["bay_metal"] = _thing("shelf_rack_metal", _mats["dark_steel"])
	_mats["bay_wood"] = _thing("shelf_rack_wood", _mats["cardboard"])
	# Four faces of the same tunnel, so a hundred metres of it is not one wall
	# repeated. All lifted the same way the main brick is, for the same reason:
	# they are photographs of wet walls in the dark and arrive already dim.
	for pair: Array in [["sewer_wet", "sewer_wall_wet"], ["sewer_mossy", "sewer_wall_mossy"],
			["sewer_tile", "sewer_wall_tile"], ["sewer_plain", "sewer_wall_concrete"],
			["sewer_broken", "sewer_brick_damaged"], ["sewer_old", "sewer_wall_brick"],
			["sewer_poured", "sewer_concrete"]]:
		_mats[str(pair[0])] = _surface(str(pair[1]), ProcTex.brick(137), 5.0, 3.0,
			Color(1.55, 1.55, 1.50))
	for pair: Array in [["sewer_floor_wet", "sewer_floor_wet"],
			["sewer_floor_grate", "sewer_floor_grate"],
			["sewer_floor_brick", "sewer_floor_brick"],
			["sewer_floor_mud", "sewer_mud"],
			["sewer_floor_puddles", "sewer_floor_puddles"]]:
		_mats[str(pair[0])] = _surface(str(pair[1]), ProcTex.brick(137), 5.0, 4.0,
			Color(1.35, 1.35, 1.30))


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


## A surface that is a light fitting, or a screen, or anything else whose job is
## to be the bright thing in a dark room.
##
## The difference from `_surface` is the one thing `_surface` deliberately will
## not do: the glow goes on whichever texture is used. That rule is right for a
## wall — a photograph of a wet floor already has the reflection in it and does
## not want emission on top — and wrong for a strip light, where the photograph
## is of a tube that is on, and drawn without emission it is a grey stripe on a
## ceiling in a dark shop. The lamp is what tells you the room is lit.
##
## `painted_strength` is there because emission is added to the shaded colour
## rather than multiplied through it. A flat green box needs a lot of it before
## it reads as a screen that is switched on; a photograph of a lit monitor
## already has the light in it and needs a fraction of the same number, or the
## picture disappears under the glow. Left at -1 the two are the same.
func _lit(name: String, generated: Texture2D, glow: Color, glow_strength: float,
		repeat: float = 1.0, tint: Color = Color.WHITE,
		painted_strength: float = -1.0) -> Material:
	var tex := ProcTex.painted(name)
	if tex != null:
		return ProcMesh.mat(tex, repeat, glow,
			glow_strength if painted_strength < 0.0 else painted_strength, tint)
	return ProcMesh.mat(generated, repeat, glow, glow_strength, tint)


## Something the pack has a photograph of, drawn at one copy per face.
##
## Every one of these is a picture of an object rather than a material, so it is
## never tiled and never mirrored, and if the pack does not have it the caller's
## generated material is used unchanged. Kept separate from `_surface` because
## the two fail in opposite directions: a surface with the wrong repeat looks
## like a bad wall, and an object with any repeat at all looks like four of
## itself.
func _thing(name: String, fallback: Material, tint: Color = Color.WHITE) -> Material:
	var tex := ProcTex.painted(name)
	if tex == null:
		return fallback
	return ProcMesh.mat(tex, 1.0, Color.BLACK, 0.0, tint)


func mat(id: String) -> Material:
	return _mats.get(id, _mats["wall"])


## Which sky is over the street tonight.
##
## Its own function rather than a conditional buried in the material table, so
## that both branches can be asked for without building two worlds — a texture
## only one night in three reaches for is exactly the kind that gets cut,
## wired, quietly broken and never noticed.
static func sky_for_night(night: int) -> String:
	return "sky_clear" if night % 3 == 0 else "sky_cloudy"


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
		Vector3(0, 3.12, -SHOP_HALF_Z - 0.55), mat("awning"), "Awning"))
	shop.add_child(ProcMesh.box(Vector3(SHOP_HALF_X * 2 + 0.6, 0.3, SHOP_HALF_Z * 2 + 0.6),
		Vector3(0, CEILING + 0.30, 0), mat("roof_panel"), "Roof"))

	# Cladding on the outside of the side walls. A kiosk is a box somebody put
	# on a pavement; from the street it should read as panel, not as the painted
	# plaster of the room inside it.
	for side: int in [-1, 1]:
		shop.add_child(ProcMesh.box(Vector3(0.06, CEILING - 0.1, SHOP_HALF_Z * 2),
			Vector3(side * (SHOP_HALF_X + 0.23), CEILING * 0.5, 0),
			mat("clad_metal"), "Cladding%d" % side))

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
		mat("strip_light"), "Strip1"))

	var strip2 := OmniLight3D.new()
	strip2.position = Vector3(0, CEILING - 0.35, 2.0)
	strip2.light_color = Color(0.85, 0.92, 1.0)
	strip2.light_energy = 3.1
	strip2.omni_range = 12.0
	add_child(strip2)
	shop.add_child(ProcMesh.box(Vector3(3.0, 0.08, 0.22), Vector3(0, CEILING - 0.12, 2.0),
		mat("strip_light"), "Strip2"))

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

	# Panels on the three faces anybody sees.
	#
	# The counter is one box wearing the worn wood of its own top, so its front —
	# the surface a customer stands looking at for the whole transaction — was
	# the tabletop stretched down a metre. The pack has a photograph of the front
	# of a counter exactly like this one, stickers and all, and a box cannot wear
	# a different texture per face, so the faces are their own thin panels.
	counter.add_child(ProcMesh.box(Vector3(width, CHECKOUT_Y - 0.06, 0.04),
		Vector3(cx, (CHECKOUT_Y - 0.06) * 0.5, CHECKOUT_Z - CHECKOUT_DEPTH * 0.5 - 0.03),
		mat("counter_face"), "CounterFront"))
	for side: int in [-1, 1]:
		counter.add_child(ProcMesh.box(Vector3(0.04, CHECKOUT_Y - 0.06, CHECKOUT_DEPTH),
			Vector3(cx + side * (width * 0.5 + 0.03), (CHECKOUT_Y - 0.06) * 0.5, CHECKOUT_Z),
			mat("counter_end"), "CounterEnd%d" % side))

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

	_signs(fit)
	_cold_cabinet(fit)
	_outside_dressing(fit)

	anchors["back_door"] = Vector3(BACK_DOOR_X, 0, SHOP_HALF_Z)


## The paper on the walls.
##
## A shop like this is covered in it — the licence, the no-smoking notice, the
## sign on the staff door, the exit sign nobody has changed the bulb in — and
## the pack has all four. They are flat panels a few centimetres proud of the
## wall, with no collision: a customer who walks into the licence notice should
## walk into the wall behind it, not into a piece of paper.
func _signs(fit: Node3D) -> void:
	# Over the shop door, and the only one that is lit.
	fit.add_child(ProcMesh.box(Vector3(0.62, 0.24, 0.05),
		Vector3(FRONT_DOOR_X, DOOR_H + 0.28, -SHOP_HALF_Z + 0.14), mat("sign_exit"), "ExitSign"))
	# On the door through to the back.
	fit.add_child(ProcMesh.box(Vector3(0.30, 0.44, 0.05),
		Vector3(BACK_DOOR_X, DOOR_H - 0.40, SHOP_HALF_Z - 0.14), mat("warn_staff_only"), "StaffSign"))
	# On the side walls, so these are thin along X rather than along Z. A sign
	# built the wrong way round is edge-on to the room and invisible from every
	# angle a player is ever standing at, which is a very quiet way to lose an
	# hour.
	# Behind the counter, where the person working is the one who ignores it.
	fit.add_child(ProcMesh.box(Vector3(0.05, 0.38, 0.26),
		Vector3(-SHOP_HALF_X + 0.16, 2.05, CHECKOUT_Z + 0.4), mat("warn_no_smoking"), "NoSmoking"))
	# The licence and whatever else the council makes you display, by the hatch.
	fit.add_child(ProcMesh.box(Vector3(0.34, 0.46, 0.05),
		Vector3(HATCH_X + 1.55, 1.70, -SHOP_HALF_Z + 0.14), mat("sign_notice"), "Notice"))
	# Somebody's list, taped to the wall by the till.
	fit.add_child(ProcMesh.box(Vector3(0.04, 0.30, 0.22),
		Vector3(SHOP_HALF_X - 0.16, 1.55, CHECKOUT_Z + 0.9), mat("note_paper"), "TapedNote"))
	# The camera in the corner has to be looking at something. A small monitor on
	# a bracket beside the till, showing the aisle it points down.
	fit.add_child(ProcMesh.box(Vector3(0.16, 0.24, 0.30),
		Vector3(SHOP_HALF_X - 0.30, 2.20, CHECKOUT_Z - 0.30), mat("dark_steel"), "MonitorCase"))
	fit.add_child(ProcMesh.box(Vector3(0.04, 0.19, 0.25),
		Vector3(SHOP_HALF_X - 0.40, 2.20, CHECKOUT_Z - 0.30), mat("cctv"), "MonitorScreen"))

	# The stockroom is a working room and it has the signs to prove it.
	fit.add_child(ProcMesh.box(Vector3(0.05, 0.40, 0.28),
		Vector3(STOCK_MIN_X + 0.24, 1.85, STOCK_MAX_Z - 2.2), mat("warn_danger_electric"), "DangerSign"))
	fit.add_child(ProcMesh.box(Vector3(0.05, 0.40, 0.28),
		Vector3(STOCK_MAX_X - 0.24, 1.75, STOCK_MIN_Z + 1.4), mat("warn_wet_floor"), "WetFloorSign"))
	# And one on the wall beside the hole in the floor.
	fit.add_child(ProcMesh.box(Vector3(0.05, 0.40, 0.28),
		Vector3(STOCK_MIN_X + 0.24, 1.60, MANHOLE.z), mat("warn_no_entry"), "ManholeSign"))


## What is bolted to the outside of the building.
##
## A vending machine beside the front door and the stockroom's fire door, both
## of which the pack had a photograph of and neither of which existed. The
## machine also puts a little light on the pavement outside the door, which is
## the stretch a customer walks down to reach the hatch.
func _outside_dressing(fit: Node3D) -> void:
	var at := Vector3(FRONT_DOOR_X + 1.55, 0.0, -SHOP_HALF_Z - 0.45)
	fit.add_child(ProcMesh.solid_box(Vector3(0.90, 1.85, 0.60), at + Vector3(0, 0.925, 0),
		mat("vending"), "VendingMachine"))
	var glow := OmniLight3D.new()
	glow.position = at + Vector3(0, 1.30, -0.55)
	glow.light_color = Color(0.86, 0.92, 1.0)
	glow.light_energy = 1.4
	glow.omni_range = 3.2
	fit.add_child(glow)

	# The fire door out of the stockroom. A leaf, shut, in the wall it belongs
	# to — no collision of its own, because the wall behind it already has some
	# and two overlapping bodies in a doorway is how a player gets stuck.
	fit.add_child(ProcMesh.box(Vector3(0.05, 2.00, 0.90),
		Vector3(STOCK_MIN_X - 0.02, 1.00, STOCK_MAX_Z - 1.8), mat("door_metal"), "FireDoor"))
	# And a wooden one on the shop side of the back doorway, propped open flat
	# against the wall the way it has been for years.
	fit.add_child(ProcMesh.box(Vector3(0.90, 2.05, 0.05),
		Vector3(BACK_DOOR_X + 1.20, 1.02, SHOP_HALF_Z - 0.16), mat("door_wood"), "BackDoorLeaf"))


## The drinks cabinet against the back wall.
##
## The shop sells cold beer and soda out of nothing at all — the racks are dry
## shelving and there was no fridge in the building. The pack has one, so now
## there is: a cabinet with a lit glass front, which also puts a second source
## of light in the far corner of a room that has always been dark at that end.
func _cold_cabinet(fit: Node3D) -> void:
	var at := Vector3(SHOP_HALF_X - 0.62, 0.0, SHOP_HALF_Z - 1.35)
	var body := ProcMesh.solid_box(Vector3(1.10, 1.95, 0.70), at + Vector3(0, 0.975, 0),
		mat("fridge"), "ColdCabinet")
	fit.add_child(body)
	# The glass, and the strip inside it. Proud of the front face so the two do
	# not fight over the same pixels.
	fit.add_child(ProcMesh.box(Vector3(0.92, 1.55, 0.04), at + Vector3(0, 1.10, -0.38),
		mat("glass"), "CabinetGlass"))
	var glow := OmniLight3D.new()
	glow.position = at + Vector3(0, 1.35, -0.55)
	glow.light_color = Color(0.78, 0.90, 1.0)
	glow.light_energy = 1.6
	glow.omni_range = 3.4
	fit.add_child(glow)


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
			mat("rack"), "Rack%d" % rack_id))
		# Remembered as a flat rectangle so a shopper can be routed round it. A
		# customer walks in a straight line at whatever they want next, and the
		# line from the right-hand rack to the left-hand one goes through the
		# middle of the island — which is why they were seen walking through the
		# shelves rather than round them.
		_rack_rects.append(Rect2(
			Vector2(centre.x - carcass.x * 0.5, centre.z - carcass.z * 0.5),
			Vector2(carcass.x, carcass.z)))

		for i in items.size():
			var item_id: String = items[i]
			var level_y := 0.98 + float(i) * 0.48

			# A board under each level.
			#
			# The rack was a plain box with cartons hovering at three heights
			# against it and nothing between them, which is why the stock looked
			# like it was floating in mid air. A shelf is the board; the carcass
			# is just what holds the boards up.
			var board: Vector3 = Vector3(0.42, 0.04, span) if dir.z > 0.5 \
				else Vector3(span, 0.04, 0.42)
			racks.add_child(ProcMesh.box(board,
				centre + Vector3(0, level_y - 0.13, 0),
				mat("shelf_board" if rack_id != 1 else "shelf_board_metal"),
				"Board%d_%d" % [rack_id, i]))
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


## How wide a body has to be treated as when routing it round the shelving.
## The capsule is narrower than the person drawn on it, and it is the person you
## can see going through a shelf.
const BODY_CLEARANCE := 0.45
## How far past the clearance a way-round point sits, so it is unambiguously
## outside the rectangle it is going round.
const DETOUR_MARGIN := 0.20


## A detour, if walking straight from `from` to `to` would go through a rack.
##
## Returns the points to visit on the way, which is either nothing or one place
## to stand. Customers steer straight at whatever they want next and slide off
## whatever they hit, which works everywhere in this shop except the island: the
## line from the right-hand rack to the left-hand one runs the length of it, so
## a shopper wanting something off both ends up grinding along the middle of the
## shelving with their shoulder inside it.
##
## The detour goes round whichever end of the rack is nearer, and always on the
## side of it closer to the middle of the room — that is the aisle, and it is
## where a person would walk. Going the other way round is sometimes shorter and
## always looks like a mistake, because it means squeezing between the shelf and
## the wall.
func detour(from: Vector3, to: Vector3) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var cursor := from
	# Going round one rack can put you on a line that crosses the next, so this
	# walks the route rather than checking the original leg once against each.
	# Four is more corners than this floor plan has; the cap is there so a shape
	# nobody has drawn yet cannot hang the game.
	for _guard in 4:
		var via: Array[Vector3] = _first_detour(cursor, to)
		if via.is_empty():
			break
		out.append(via[0])
		cursor = via[0]
	return out


## The way round the first rack this leg goes through, as a list of one — or an
## empty list if it goes through none of them. A list rather than a nullable
## Vector3 because there is no such thing.
func _first_detour(from: Vector3, to: Vector3) -> Array[Vector3]:
	var a := Vector2(from.x, from.z)
	var b := Vector2(to.x, to.z)
	for rect: Rect2 in _rack_rects:
		var grown := rect.grow(BODY_CLEARANCE)
		# Standing at a shelf means standing right up against it, so the ends of
		# this leg are usually inside the grown rectangle. Only the middle of the
		# walk is a crossing worth avoiding.
		if grown.has_point(a) or grown.has_point(b):
			continue
		if not _segment_hits(a, b, grown):
			continue

		var long_x: bool = rect.size.x > rect.size.y
		var mid := grown.get_center()
		# Past the end of the rack, on the aisle side of it, and a little past
		# that again. Sitting exactly on the corner of the grown rectangle put
		# the point on a boundary that `Rect2.has_point` decides by floating
		# point equality, so the next leg sometimes believed it was starting
		# inside the rack and skipped the check that would have routed it round
		# the other end.
		var toward_room := signf(-mid.y) if long_x else signf(-mid.x)
		if is_zero_approx(toward_room):
			toward_room = 1.0
		var options: Array[Vector2] = []
		if long_x:
			var out_z: float = mid.y + toward_room * (grown.size.y * 0.5 + DETOUR_MARGIN)
			options.append(Vector2(grown.position.x, out_z))
			options.append(Vector2(grown.end.x, out_z))
		else:
			var out_x: float = mid.x + toward_room * (grown.size.x * 0.5 + DETOUR_MARGIN)
			options.append(Vector2(out_x, grown.position.y))
			options.append(Vector2(out_x, grown.end.y))
		# Never the corner already being stood on. Going round one end of the
		# island puts you exactly on that corner, and "walk to where you already
		# are" is always the shortest of the two — so without this the second
		# time round the loop picks the same corner again and the leg past the
		# far end never gets made.
		var choices: Array[Vector2] = []
		for option: Vector2 in options:
			if a.distance_to(option) > 0.05:
				choices.append(option)
		if choices.is_empty():
			continue

		# The end nearer to where you are standing, which is the one you can walk
		# to without going through the rack you are going round. Picking the end
		# that makes the whole journey shortest is tempting and wrong: from the
		# right-hand rack the far corner of the island is a hair closer overall,
		# and the walk to it goes straight down the middle of the shelving.
		# Getting past the near end first is the point. The loop above then makes
		# the rest of the journey from there, so nothing doubles back.
		var here: Vector2 = choices[0]
		for option: Vector2 in choices:
			if a.distance_to(option) < a.distance_to(here):
				here = option
		return [Vector3(here.x, from.y, here.y)] as Array[Vector3]
	return [] as Array[Vector3]


## Whether a segment crosses a rectangle. Both ends are known to be outside it,
## so it is enough to ask whether the segment meets any of the four edges.
static func _segment_hits(a: Vector2, b: Vector2, rect: Rect2) -> bool:
	var tl := rect.position
	var br := rect.end
	var tr := Vector2(br.x, tl.y)
	var bl := Vector2(tl.x, br.y)
	for edge: Array in [[tl, tr], [tr, br], [br, bl], [bl, tl]]:
		if Geometry2D.segment_intersects_segment(a, b, edge[0], edge[1]) != null:
			return true
	return false


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
		mat("stock_floor"), "StockFloor"))
	# Beams overhead rather than the shop's flat concrete. It is the one room in
	# the building with its structure showing.
	room.add_child(ProcMesh.solid_box(Vector3(w + 0.4, 0.2, d + 0.4),
		Vector3(cx, STOCK_CEILING + 0.1, cz), mat("beam"), "StockCeiling"))
	# Peeling paint back here rather than the bare concrete of the street. It is
	# the inside of a building that has been the inside of a building for a long
	# time, and it wants to look different from the wall outside it.
	room.add_child(ProcMesh.solid_box(Vector3(w + 0.4, STOCK_CEILING, 0.2),
		Vector3(cx, STOCK_CEILING * 0.5, STOCK_MAX_Z + 0.1), mat("stock_wall"), "StockBack"))
	for side: int in [-1, 1]:
		var x := STOCK_MIN_X - 0.1 if side < 0 else STOCK_MAX_X + 0.1
		room.add_child(ProcMesh.solid_box(Vector3(0.2, STOCK_CEILING, d),
			Vector3(x, STOCK_CEILING * 0.5, cz), mat("stock_wall"), "StockSide%d" % side))

	for piece: Array in [[STOCK_MIN_X, BACK_DOOR_X - BACK_DOOR_W * 0.5],
			[BACK_DOOR_X + BACK_DOOR_W * 0.5, STOCK_MAX_X]]:
		var seg: float = piece[1] - piece[0]
		if seg <= 0.02:
			continue
		room.add_child(ProcMesh.solid_box(Vector3(seg, STOCK_CEILING, 0.2),
			Vector3((piece[0] + piece[1]) * 0.5, STOCK_CEILING * 0.5, STOCK_MIN_Z + 0.1),
			mat("stock_wall"), "StockFront"))

	stock_light = OmniLight3D.new()
	stock_light.position = Vector3(cx, STOCK_CEILING - 0.30, cz - 0.8)
	stock_light.light_color = Color(1.0, 0.88, 0.66)
	stock_light.light_energy = 3.4
	stock_light.omni_range = 13.0
	add_child(stock_light)
	room.add_child(ProcMesh.box(Vector3(0.30, 0.10, 0.30), Vector3(cx, STOCK_CEILING - 0.10, cz - 0.8),
		mat("bulb"), "StockBulb"))

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
		# Two of steel and two of wood, wearing the pack's photographs of whole
		# shelving units — which is the one thing those photographs are right
		# for. Putting one on the shop's rack carcass was a mistake made once
		# already: that is a plain box the length of a wall, and this is a
		# shelving unit the size of a shelving unit.
		room.add_child(ProcMesh.solid_box(Vector3(0.9, 2.3, 1.6),
			Vector3(STOCK_MIN_X + 0.55, 1.15, bz),
			mat("bay_metal" if bay % 2 == 0 else "bay_wood"), "Bay%d" % bay))
		for level in 3:
			for c in 2:
				var case_mat := ProcMesh.mat(ProcTex.product(
					SHELF_TINTS.values()[rng.randi() % SHELF_TINTS.size()], rng.randi()))
				room.add_child(ProcMesh.box(Vector3(0.42, 0.34, 0.42),
					Vector3(STOCK_MIN_X + 0.55, 0.44 + float(level) * 0.74, bz - 0.38 + float(c) * 0.76),
					case_mat, "Case"))

	# Boxes on the floor. Printed cartons, plain ones, crates and a milk crate,
	# rather than nine copies of the same brown box — the pack has all of them
	# and the difference is what stops a stockroom reading as one texture.
	var loose := ["cardboard", "cardboard_printed", "crate_wood", "crate_plastic",
		"crate_milk", "ammo_box"]
	for i in 9:
		room.add_child(ProcMesh.box(Vector3(rng.randf_range(0.4, 0.7), rng.randf_range(0.3, 0.5),
			rng.randf_range(0.4, 0.7)),
			Vector3(rng.randf_range(STOCK_MIN_X + 1.8, STOCK_MAX_X - 0.7), 0.25,
				rng.randf_range(STOCK_MIN_Z + 1.0, STOCK_MAX_Z - 1.6)),
			mat(loose[i % loose.size()]), "Box%d" % i))
	room.add_child(ProcMesh.box(Vector3(1.2, 0.34, 1.0),
		Vector3(STOCK_MAX_X - 1.0, 0.17, STOCK_MIN_Z + 1.0), mat("pallet"), "Pallets"))

	# The crates you take an armful of stock off. Wood, because that is what
	# they are and the pack has a photograph of one.
	_interactable(room, "crates", "Crates", Vector3(1.60, 0.90, 0.80),
		Vector3(STOCK_MIN_X + 2.6, 0.45, STOCK_MAX_Z - 0.9), mat("crate_wood"))

	room.add_child(ProcMesh.cylinder(0.52, 0.06, MANHOLE + Vector3(0, 0.03, 0),
		mat("manhole_cover"), 12))
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
