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
		Vector3(mid, 0.05, PAVEMENT_Z_MIN), world.mat("pavement"), "Kerb"))

	# Walls closing the street at both ends, so you cannot walk off the world.
	street.add_child(ProcMesh.solid_box(Vector3(0.6, 14.0, 30.0),
		Vector3(World.STREET_WEST, 7.0, -3.0), world.mat("brick_far"), "WestEnd"))
	street.add_child(ProcMesh.solid_box(Vector3(0.6, 14.0, 30.0),
		Vector3(World.STREET_EAST, 7.0, -3.0), world.mat("brick_far"), "EastEnd"))
	street.add_child(ProcMesh.solid_box(Vector3(World.STREET_EAST - World.STREET_WEST, 14.0, 0.6),
		Vector3(mid, 7.0, PAVEMENT_Z_MAX), world.mat("brick_far"), "BackFence"))


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
	parent.add_child(ProcMesh.cylinder(0.09, 5.4, pos + Vector3(0, 2.7, 0), world.mat("dark_steel"), 6))
	parent.add_child(ProcMesh.box(Vector3(0.9, 0.10, 0.30), pos + Vector3(0.4, 5.35, 0),
		world.mat("dark_steel"), "Arm"))
	parent.add_child(ProcMesh.box(Vector3(0.5, 0.14, 0.28), pos + Vector3(0.78, 5.26, 0),
		world.mat("lamp") if working else world.mat("dark_steel"), "Head"))
	if working:
		var l := OmniLight3D.new()
		l.position = pos + Vector3(0.78, 5.1, 0)
		l.light_color = Color(1.0, 0.86, 0.60)
		l.light_energy = 4.6
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
		l.omni_attenuation = 1.6
		parent.add_child(l)


static func _clutter(world: World, street: Node3D, rng: RandomNumberGenerator) -> void:
	street.add_child(ProcMesh.solid_box(Vector3(0.7, 1.1, 0.7), Vector3(-4.6, 0.75, -3.4),
		world.mat("dark_steel"), "Bin"))
	street.add_child(ProcMesh.solid_box(Vector3(2.0, 0.8, 4.4), Vector3(10.5, 0.60, -9.0),
		world.mat("dark_steel"), "DeadCarBody"))
	street.add_child(ProcMesh.box(Vector3(1.8, 0.6, 2.1), Vector3(10.5, 1.30, -9.3),
		world.mat("glass"), "DeadCarCab"))
	street.add_child(ProcMesh.solid_box(Vector3(2.4, 1.3, 1.6), Vector3(-19.0, 0.85, -3.2),
		world.mat("dark_steel"), "Skip"))

	for i in 60:
		street.add_child(ProcMesh.box(Vector3(0.18, 0.02, 0.24),
			Vector3(rng.randf_range(World.STREET_WEST + 2.0, World.STREET_EAST - 2.0), 0.22,
				rng.randf_range(-11.0, 4.0)),
			world.mat("pavement"), "Litter%d" % i))


## The last twenty metres. No lamps, an alcove between two blocks, and the
## thing in it. Also where the sewer comes back up.
static func _far_end(world: World, street: Node3D, rng: RandomNumberGenerator) -> void:
	var ex := World.STREET_END

	# An alcove: two blocks with a gap, set back off the pavement.
	street.add_child(ProcMesh.solid_box(Vector3(6.0, 9.0, 6.0),
		Vector3(ex + 5.2, 4.5, 4.5), world.mat("brick_far"), "AlcoveEast"))
	street.add_child(ProcMesh.solid_box(Vector3(6.0, 9.0, 6.0),
		Vector3(ex - 5.2, 4.5, 4.5), world.mat("brick_far"), "AlcoveWest"))
	street.add_child(ProcMesh.solid_box(Vector3(4.4, 9.0, 0.4),
		Vector3(ex, 4.5, 6.6), world.mat("brick"), "AlcoveBack"))

	# A skip pushed across the mouth of it, so the board is not visible until
	# you have walked round the obstacle rather than past it.
	street.add_child(ProcMesh.solid_box(Vector3(3.4, 1.6, 1.5),
		Vector3(ex + 0.6, 1.0, 2.1), world.mat("dark_steel"), "AlcoveSkip"))
	for i in 5:
		street.add_child(ProcMesh.box(Vector3(0.5, 0.4, 0.5),
			Vector3(ex + rng.randf_range(-1.2, 2.0), 1.9, 2.1 + rng.randf_range(-0.4, 0.4)),
			world.mat("cardboard"), "SkipJunk%d" % i))

	var egg := EasterEgg.new()
	egg.position = Vector3(ex, 0, 5.9)
	street.add_child(egg)
	egg.build_visuals(world)
	world.anchors["easter_egg"] = egg

	# The sewer's other end, in the same dark corner.
	var exit_pos := World.SEWER_EXIT
	street.add_child(ProcMesh.cylinder(0.52, 0.06, exit_pos + Vector3(0, 0.03, 0),
		world.mat("dark_steel"), 12))
	street.add_child(ProcMesh.cylinder(0.44, 0.10, exit_pos + Vector3(0, -0.06, 0),
		ProcMesh.mat(ProcTex.flat(Color(0.02, 0.02, 0.03))), 12))
	world.interact_zone(street, "manhole_street", exit_pos + Vector3(0, 0.5, 0), Vector3(1.1, 1.0, 1.1))
	world.anchors["sewer_exit_top"] = exit_pos
	world.anchors["sewer_exit_bottom"] = Vector3(exit_pos.x, World.SEWER_Y + 0.15, exit_pos.z)

	# And the middle one, out in the open half way along. Same cover, much worse
	# place to be seen climbing out of.
	var mid_pos := World.SEWER_MID_EXIT
	street.add_child(ProcMesh.cylinder(0.52, 0.06, mid_pos + Vector3(0, 0.03, 0),
		world.mat("dark_steel"), 12))
	street.add_child(ProcMesh.cylinder(0.44, 0.10, mid_pos + Vector3(0, -0.06, 0),
		ProcMesh.mat(ProcTex.flat(Color(0.02, 0.02, 0.03))), 12))
	world.interact_zone(street, "manhole_mid", mid_pos + Vector3(0, 0.5, 0), Vector3(1.1, 1.0, 1.1))
	world.anchors["sewer_mid_top"] = mid_pos
