class_name StreetBuilder
extends RefCounted
## The road the kiosk stands on.
##
## It runs about a hundred metres east to west and you can walk all of it. The
## lamps thin out as you go west until there are none, which is the only signal
## the game gives that there is anything down there.

const PAVEMENT_Z_MIN := -4.6
const PAVEMENT_Z_MAX := 9.0
const ROAD_Z_MIN := -15.0


static func build(world: World) -> void:
	var street := Node3D.new()
	street.name = "Street"
	world.add_child(street)

	var rng := RandomNumberGenerator.new()
	rng.seed = 404

	_ground(world, street)
	_terrace(world, street, rng)
	_lamps(world, street)
	_clutter(world, street, rng)
	_writing_on_the_walls(world, street, rng)
	_far_end(world, street, rng)

	world.set_breach_points([
		Vector3(3.6, 0, -5.2),
		Vector3(-3.8, 0, -5.6),
		Vector3(0.0, 0, -8.0),
		Vector3(World.SHOP_HALF_X + 3.0, 0, 2.0),
	])


static func _ground(world: World, street: Node3D) -> void:
	var length := World.STREET_EAST - World.STREET_WEST
	var mid := (World.STREET_EAST + World.STREET_WEST) * 0.5

	# Road surface, and a kerbed pavement the kiosk sits on.
	street.add_child(ProcMesh.solid_box(Vector3(length, 0.4, PAVEMENT_Z_MIN - ROAD_Z_MIN),
		Vector3(mid, -0.2, (ROAD_Z_MIN + PAVEMENT_Z_MIN) * 0.5), world.mat("asphalt"), "Road"))
	street.add_child(ProcMesh.solid_box(Vector3(length, 0.4, PAVEMENT_Z_MAX - PAVEMENT_Z_MIN),
		Vector3(mid, -0.2, (PAVEMENT_Z_MIN + PAVEMENT_Z_MAX) * 0.5), world.mat("pavement"), "Pavement"))
	street.add_child(ProcMesh.box(Vector3(length, 0.14, 0.24),
		Vector3(mid, 0.05, PAVEMENT_Z_MIN), world.mat("kerb"), "Kerb"))

	# Walls closing the street at both ends, so you cannot walk off the world.
	street.add_child(ProcMesh.solid_box(Vector3(0.6, 14.0, 30.0),
		Vector3(World.STREET_WEST, 7.0, -3.0), world.mat("brick_far"), "WestEnd"))
	street.add_child(ProcMesh.solid_box(Vector3(0.6, 14.0, 30.0),
		Vector3(World.STREET_EAST, 7.0, -3.0), world.mat("brick_far"), "EastEnd"))
	street.add_child(ProcMesh.solid_box(Vector3(World.STREET_EAST - World.STREET_WEST, 14.0, 0.6),
		Vector3(mid, 7.0, PAVEMENT_Z_MAX), world.mat("brick_far"), "BackFence"))

	# A lid on the street.
	#
	# Looking up gave you the environment's clear colour, which is very nearly
	# black, so the street read as a room with no ceiling rather than as outside
	# at night. One panel of cloud above the roof line fixes that for the cost of
	# a single quad. High enough to clear the tallest terrace block, which tops
	# out at fifteen metres, and wide enough that its edges are never in frame
	# from the pavement.
	street.add_child(ProcMesh.box(Vector3(length + 40.0, 0.4, 60.0),
		Vector3(mid, 24.0, -3.0), world.mat("sky"), "Sky"))

	# And the far side of the road, which had nothing.
	#
	# The terrace over there is solid, but it is built as separate blocks with a
	# random half-metre to two metres between them — and the road surface stops a
	# metre short of where those blocks begin. So any one of those gaps was a way
	# to walk off the edge of the ground: you drop out of the world, and on the
	# way down you get a clear look at the sewer, which is the other half of why
	# the tunnels were visible from the street.
	#
	# Placed at the road edge rather than behind the terrace, so it seals the
	# gaps rather than the buildings. It is never seen — the terrace is in front
	# of it and the fog takes whatever is left.
	street.add_child(ProcMesh.solid_box(Vector3(World.STREET_EAST - World.STREET_WEST, 14.0, 0.6),
		Vector3(mid, 7.0, ROAD_Z_MIN + 0.3), world.mat("brick_far"), "FarFence"))


## A terrace on the far side of the road, and blocks behind the kiosk. Both are
## mostly fog; they exist to give the street edges.
static func _terrace(world: World, street: Node3D, rng: RandomNumberGenerator) -> void:
	var x := World.STREET_WEST + 3.0
	var i := 0
	while x < World.STREET_EAST - 3.0:
		var w := rng.randf_range(4.0, 9.0)
		var h := rng.randf_range(7.0, 15.0)
		street.add_child(ProcMesh.solid_box(Vector3(w, h, 7.0),
			Vector3(x + w * 0.5, h * 0.5, ROAD_Z_MIN - 2.5), world.mat("brick_far"), "Block%d" % i))
		# The occasional lit window, high up. Nobody is looking out of it.
		if rng.randf() < 0.28:
			var wy := rng.randf_range(3.0, h - 1.5)
			street.add_child(ProcMesh.box(Vector3(0.9, 1.1, 0.1),
				Vector3(x + w * 0.5 + rng.randf_range(-w * 0.3, w * 0.3), wy, ROAD_Z_MIN + 1.05),
				ProcMesh.mat(ProcTex.flat(Color(0.86, 0.74, 0.44)), 1.0,
					Color(0.9, 0.72, 0.38), 0.9), "Window"))
		x += w + rng.randf_range(0.4, 2.2)
		i += 1

	# Buildings behind the kiosk, leaving a gap for the shop's side door.
	var bx := World.STREET_WEST + 5.0
	var j := 0
	while bx < World.STREET_EAST - 5.0:
		var bw := rng.randf_range(5.0, 10.0)
		if absf(bx - World.SHOP_HALF_X) > 12.0:
			var bh := rng.randf_range(6.0, 12.0)
			street.add_child(ProcMesh.solid_box(Vector3(bw, bh, 8.0),
				Vector3(bx + bw * 0.5, bh * 0.5, PAVEMENT_Z_MAX + 3.0),
				world.mat("brick_far"), "Rear%d" % j))
		bx += bw + rng.randf_range(1.0, 3.0)
		j += 1


## Lamps thin out to the west. This is the only breadcrumb toward the far end.
static func _lamps(world: World, street: Node3D) -> void:
	var spec := [
		{"x": 10.0, "on": true}, {"x": 4.0, "on": true}, {"x": -6.0, "on": false},
		{"x": -14.0, "on": true}, {"x": -23.0, "on": false}, {"x": -31.0, "on": false},
		{"x": -39.0, "on": true}, {"x": -47.0, "on": false},
	]
	for conf: Dictionary in spec:
		_lamp_post(world, street, Vector3(float(conf["x"]), 0, -4.9), bool(conf["on"]))


static func _lamp_post(world: World, parent: Node3D, pos: Vector3, working: bool) -> void:
	parent.add_child(ProcMesh.cylinder(0.09, 5.4, pos + Vector3(0, 2.7, 0),
		world.mat("lamp_post"), 6))
	parent.add_child(ProcMesh.box(Vector3(0.9, 0.10, 0.30), pos + Vector3(0.4, 5.35, 0),
		world.mat("lamp_post"), "Arm"))
	# A lit head is a flat emissive box, because it is the light. A dead one is
	# the pack's photograph of a lamp head, which is a thing you can look at.
	parent.add_child(ProcMesh.box(Vector3(0.5, 0.14, 0.28), pos + Vector3(0.78, 5.26, 0),
		world.mat("lamp") if working else world.mat("lamp_head_off"), "Head"))
	if working:
		var l := OmniLight3D.new()
		l.position = pos + Vector3(0.78, 5.1, 0)
		l.light_color = Color(1.0, 0.86, 0.60)
		# Brightness, not reach. What leaked through the brick was the nine-metre
		# radius below, and shortening it was right; what it also did was leave
		# the road too dark to walk down — "like walking in a black box". Energy
		# fills the pool without extending it a centimetre, so the lamps light
		# the pavement properly and still stop at the wall.
		l.light_energy = 11.0
		# Nine metres, not eighteen.
		#
		# A sodium lamp five metres above a pavement throws a pool about seven
		# metres across; eighteen was reaching fourteen metres *through the shop's
		# brick wall* to light the floor behind the counter. That is wrong on its
		# own terms, and it was also what pushed the counter to nine simultaneous
		# lights against the eight-per-object limit GL Compatibility enforces
		# silently — so the renderer was dropping one, and which one it dropped
		# could change as the camera turned.
		#
		# Tighter pools also suit the street better: the lamps are meant to thin
		# out into darkness as you walk west, and a smaller circle of light does
		# more of that than a large soft one.
		l.omni_range = 9.0
		# Flatter falloff, so the pool has a usable middle rather than a hot spot
		# under the lamp and nothing two paces away.
		l.omni_attenuation = 1.0
		parent.add_child(l)


static func _clutter(world: World, street: Node3D, rng: RandomNumberGenerator) -> void:
	street.add_child(ProcMesh.solid_box(Vector3(0.7, 1.1, 0.7), Vector3(-4.6, 0.75, -3.4),
		world.mat("bin"), "Bin"))
	# The car has been there long enough that nobody remembers whose it is.
	street.add_child(ProcMesh.solid_box(Vector3(2.0, 0.8, 4.4), Vector3(10.5, 0.60, -9.0),
		world.mat("rusted"), "DeadCarBody"))
	street.add_child(ProcMesh.box(Vector3(1.8, 0.6, 2.1), Vector3(10.5, 1.30, -9.3),
		world.mat("glass"), "DeadCarCab"))
	street.add_child(ProcMesh.solid_box(Vector3(2.4, 1.3, 1.6), Vector3(-19.0, 0.85, -3.2),
		world.mat("skip"), "Skip"))

	# Scraps of newspaper rather than chips of pavement. Same sixty pieces of
	# litter, but you can now tell what they are when you walk over one.
	for i in 60:
		street.add_child(ProcMesh.box(Vector3(0.18, 0.02, 0.24),
			Vector3(rng.randf_range(World.STREET_WEST + 2.0, World.STREET_EAST - 2.0), 0.22,
				rng.randf_range(-11.0, 4.0)),
			world.mat("litter"), "Litter%d" % i))

	_yards(world, street, rng)


## What is stacked against the walls between the kiosk and the far end.
##
## The street was a hundred metres of empty pavement with a bin, a skip and a
## dead car on it, which is a very long way to walk past nothing. These are the
## things a back street actually has — bins, drums, pallets, stacked crates,
## tyres, bags nobody collected — and every one of them is wearing a photograph
## from the pack rather than the grey metal everything used to share.
##
## Laid out from a fixed seed against the buildings on both sides, so it dresses
## the street without ever standing where somebody walks: the pavement in front
## of the kiosk and the two manhole covers are left clear on purpose.
static func _yards(world: World, street: Node3D, rng: RandomNumberGenerator) -> void:
	var kinds := [
		["drum", Vector3(0.58, 0.88, 0.58)],
		["crate_wood", Vector3(0.72, 0.56, 0.72)],
		["crate_plastic", Vector3(0.60, 0.42, 0.60)],
		["crate_milk", Vector3(0.44, 0.36, 0.44)],
		["bin_bag", Vector3(0.62, 0.52, 0.62)],
		["pallet", Vector3(1.15, 0.14, 0.95)],
		["tyres", Vector3(0.74, 0.26, 0.74)],
		["bucket", Vector3(0.34, 0.36, 0.34)],
		["board", Vector3(0.16, 1.45, 1.10)],
	]

	var x := World.STREET_WEST + 6.0
	var n := 0
	while x < World.STREET_EAST - 6.0:
		x += rng.randf_range(3.5, 9.0)
		# Clear of the shop front, and clear of both ways out of the sewer.
		if absf(x) < World.SHOP_HALF_X + 3.5 \
				or absf(x - World.SEWER_EXIT.x) < 2.5 \
				or absf(x - World.SEWER_MID_EXIT.x) < 2.5:
			continue
		# Against the buildings, north side or south side. The north figure stops
		# well short of PAVEMENT_Z_MAX: the fence that closes the street is at
		# 9.0 and the buildings behind it start at 8.0, so anything past about
		# 7.6 is standing inside a wall.
		var north := rng.randf() < 0.5
		var z := (PAVEMENT_Z_MAX - rng.randf_range(1.4, 2.6)) if north \
			else (ROAD_Z_MIN + rng.randf_range(1.4, 2.6))
		var stack := rng.randi_range(1, 3)
		var y := 0.0
		for s in stack:
			var kind: Array = kinds[rng.randi() % kinds.size()]
			var size: Vector3 = kind[1]
			# Nothing balances on a pallet or a board, so those end a stack.
			if s > 0 and (str(kind[0]) == "pallet" or str(kind[0]) == "board"):
				break
			var piece := ProcMesh.solid_box(size,
				Vector3(x + rng.randf_range(-0.4, 0.4), y + size.y * 0.5,
					z + rng.randf_range(-0.3, 0.3)),
				world.mat(str(kind[0])), "Yard%d_%s" % [n, kind[0]])
			piece.rotation_degrees = Vector3(0, rng.randf_range(-18.0, 18.0), 0)
			street.add_child(piece)
			y += size.y
			n += 1


## Graffiti and gutter drains along the street.
##
## Flat panels a centimetre off the brick rather than decals — the game draws
## everything with one texture per surface and has no second UV channel to put a
## decal in, and a quad standing slightly proud of a wall is what a decal looks
## like from any distance you would ever see one of these from. No collision on
## any of it: they are paint, and walking into paint should do nothing.
##
## The drains are on the road, flat, at the kerb line where a real one is.
static func _writing_on_the_walls(world: World, street: Node3D, rng: RandomNumberGenerator) -> void:
	var tags := ["graffiti_large_a", "graffiti_large_b", "graffiti_c"]
	var bills := ["poster_a", "poster_b", "poster_torn"]
	var x := World.STREET_WEST + 8.0
	var i := 0
	while x < World.STREET_EAST - 8.0:
		x += rng.randf_range(7.0, 16.0)
		if absf(x) < World.SHOP_HALF_X + 2.0:
			continue
		# On the terrace across the road, facing back at the pavement.
		var w := rng.randf_range(1.8, 3.4)
		var h := w * rng.randf_range(0.5, 0.8)
		street.add_child(ProcMesh.box(Vector3(w, h, 0.06),
			Vector3(x, rng.randf_range(1.2, 2.6), ROAD_Z_MIN + 0.65),
			world.mat(tags[i % tags.size()]), "Tag%d" % i))
		# And a bill flyposted next to it, more often than not. Portrait, at
		# reading height, the way they are actually pasted up.
		if rng.randf() < 0.7:
			street.add_child(ProcMesh.box(Vector3(0.62, 0.88, 0.06),
				Vector3(x + rng.randf_range(2.0, 3.4), rng.randf_range(1.4, 2.1),
					ROAD_Z_MIN + 0.65),
				world.mat(bills[i % bills.size()]), "Bill%d" % i))
		i += 1

	# And a couple on the shop's own end walls, which is where anybody standing
	# at the hatch is actually looking.
	#
	# Clear of the cladding, which is the outermost thing on that wall: the side
	# wall runs to 5.20 and the panel over it to 5.26, so paint at 5.26 shares a
	# plane with the panel it is painted on and the two flicker against each
	# other from every angle.
	for side: int in [-1, 1]:
		street.add_child(ProcMesh.box(Vector3(0.06, 1.3, 2.2),
			Vector3(side * (World.SHOP_HALF_X + 0.33), 1.7, 1.2),
			world.mat(tags[(side + 1) % tags.size()]), "ShopTag%d" % side))
		street.add_child(ProcMesh.box(Vector3(0.05, 0.88, 0.62),
			Vector3(side * (World.SHOP_HALF_X + 0.33), 1.6, -1.9),
			world.mat(bills[(side + 1) % bills.size()]), "ShopBill%d" % side))

	# Gutter drains, at the kerb, where the rain goes.
	for at: float in [6.0, -9.0, -21.0, -36.0]:
		street.add_child(ProcMesh.box(Vector3(0.62, 0.04, 0.34),
			Vector3(at, 0.02, PAVEMENT_Z_MIN - 0.45), world.mat("drain"), "Drain%d" % int(at)))
		# And standing water beside each of them, which is where it collects.
		# Flat panels on the road rather than anything that moves — they exist to
		# catch the lamp above them, and a lit puddle is most of what says the
		# street is wet.
		street.add_child(ProcMesh.box(
			Vector3(rng.randf_range(2.2, 3.8), 0.02, rng.randf_range(1.4, 2.4)),
			Vector3(at + rng.randf_range(-1.5, 1.5), 0.015,
				PAVEMENT_Z_MIN - rng.randf_range(1.4, 3.2)),
			world.mat("wet_road"), "Puddle%d" % int(at)))


## The last twenty metres. No lamps, an alcove between two blocks, and the
## thing in it. Also where the sewer comes back up.
static func _far_end(world: World, street: Node3D, rng: RandomNumberGenerator) -> void:
	var ex := World.STREET_END

	# An alcove: two blocks with a gap, set back off the pavement.
	street.add_child(ProcMesh.solid_box(Vector3(6.0, 9.0, 6.0),
		Vector3(ex + 5.2, 4.5, 4.5), world.mat("brick_far"), "AlcoveEast"))
	street.add_child(ProcMesh.solid_box(Vector3(6.0, 9.0, 6.0),
		Vector3(ex - 5.2, 4.5, 4.5), world.mat("brick_far"), "AlcoveWest"))
	# Peeling paint on the one wall at the end of the road. It is the highest
	# contrast surface in the pack and the wrong thing for a room, and this is
	# the one place with nothing else to look at.
	street.add_child(ProcMesh.solid_box(Vector3(4.4, 9.0, 0.4),
		Vector3(ex, 4.5, 6.6), world.mat("peeling"), "AlcoveBack"))

	# A skip pushed across the mouth of it, so the board is not visible until
	# you have walked round the obstacle rather than past it.
	street.add_child(ProcMesh.solid_box(Vector3(3.4, 1.6, 1.5),
		Vector3(ex + 0.6, 1.0, 2.1), world.mat("skip"), "AlcoveSkip"))
	var junk := ["cardboard", "cardboard_printed", "crate_wood", "board", "bin_bag"]
	for i in 5:
		street.add_child(ProcMesh.box(Vector3(0.5, 0.4, 0.5),
			Vector3(ex + rng.randf_range(-1.2, 2.0), 1.9, 2.1 + rng.randf_range(-0.4, 0.4)),
			world.mat(junk[i % junk.size()]), "SkipJunk%d" % i))

	var egg := EasterEgg.new()
	egg.position = Vector3(ex, 0, 5.9)
	street.add_child(egg)
	egg.build_visuals(world)
	world.anchors["easter_egg"] = egg

	# The sewer's other end, in the same dark corner.
	var exit_pos := World.SEWER_EXIT
	street.add_child(ProcMesh.cylinder(0.52, 0.06, exit_pos + Vector3(0, 0.03, 0),
		world.mat("manhole_cover"), 12))
	street.add_child(ProcMesh.cylinder(0.44, 0.10, exit_pos + Vector3(0, -0.06, 0),
		ProcMesh.mat(ProcTex.flat(Color(0.02, 0.02, 0.03))), 12))
	world.interact_zone(street, "manhole_street", exit_pos + Vector3(0, 0.5, 0), Vector3(1.1, 1.0, 1.1))
	world.anchors["sewer_exit_top"] = exit_pos
	world.anchors["sewer_exit_bottom"] = Vector3(exit_pos.x, World.SEWER_Y + 0.15, exit_pos.z)

	# And the middle one, out in the open half way along. Same cover, much worse
	# place to be seen climbing out of.
	var mid_pos := World.SEWER_MID_EXIT
	street.add_child(ProcMesh.cylinder(0.52, 0.06, mid_pos + Vector3(0, 0.03, 0),
		world.mat("manhole_cover"), 12))
	street.add_child(ProcMesh.cylinder(0.44, 0.10, mid_pos + Vector3(0, -0.06, 0),
		ProcMesh.mat(ProcTex.flat(Color(0.02, 0.02, 0.03))), 12))
	world.interact_zone(street, "manhole_mid", mid_pos + Vector3(0, 0.5, 0), Vector3(1.1, 1.0, 1.1))
	world.anchors["sewer_mid_top"] = mid_pos
