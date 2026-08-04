class_name SewerBuilder
extends RefCounted
## The tunnels under the street.
##
## One run of brick from the manhole in the stockroom, west, to a ladder that
## comes up in the dark corner at the end of the road. Two things use it: it is
## the quiet way to the far end, and it is the way out when the door goes.
##
## Ladders are handled as an interaction that moves you rather than as climbable
## geometry. Climbing is a whole physics problem for no gameplay, and a hatch
## you press E on is unambiguous in a way a ladder collider never is.
##
## The shafts and the tunnel have to be cut into each other or the whole thing
## is a sealed box: a shaft built as four solid walls puts a slab straight
## across the tunnel, and a tunnel roof built in one piece caps the shaft. So
## the roof is built in segments that leave a hole under each shaft, and the
## shafts only exist above the roof line.

const TUNNEL_H := 2.55
const SHAFT_HALF := 0.95
const LAMP_SPACING := 7.0
## The tunnel runs a little past each shaft so the openings are not right on
## the end cap.
const OVERRUN := 2.2


static func build(world: World) -> void:
	var sewer := Node3D.new()
	sewer.name = "Sewer"
	world.add_child(sewer)

	var y: float = World.SEWER_Y
	var roof_y: float = y + TUNNEL_H
	var stock := Vector2(World.MANHOLE.x, World.MANHOLE.z)
	var street := Vector2(World.SEWER_EXIT.x, World.SEWER_EXIT.z)

	# Main run: west along the stockroom's Z, then a dogleg south to the exit.
	#
	# The corner is the fiddly part. The main run has to lose a slice of its
	# south wall where the dogleg joins, and neither piece may cap the end that
	# faces the other, or the junction is bricked up.
	var main_a := Vector3(street.x - World.SEWER_HALF_W, y, stock.y)
	var main_b := Vector3(stock.x + OVERRUN, y, stock.y)
	_tunnel(world, sewer, main_a, main_b, [stock.x], {-1: [street.x]}, false, true)

	var leg_a := Vector3(street.x, y, street.y - OVERRUN)
	var leg_b := Vector3(street.x, y, stock.y)
	_tunnel(world, sewer, leg_a, leg_b, [street.y], {}, true, false)

	# Shafts sit in the holes left in the roof and go up to ground level.
	_shaft(world, sewer, Vector3(stock.x, 0, stock.y), roof_y)
	_shaft(world, sewer, Vector3(street.x, 0, street.y), roof_y)

	# Where the ladders put you. Offset clear of the shaft walls so nobody ever
	# lands inside a brick.
	var stock_bottom := Vector3(stock.x - SHAFT_HALF - 0.7, y + 0.2, stock.y)
	var street_bottom := Vector3(street.x, y + 0.2, street.y - SHAFT_HALF - 0.7)
	world.anchors["sewer_shaft_bottom"] = stock_bottom
	world.anchors["sewer_exit_bottom"] = street_bottom

	world.interact_zone(sewer, "ladder_up_stock",
		Vector3(stock.x, y + 1.0, stock.y), Vector3(1.6, 2.0, 1.6))
	world.interact_zone(sewer, "ladder_up_street",
		Vector3(street.x, y + 1.0, street.y), Vector3(1.6, 2.0, 1.6))

	world.anchors["sewer_y"] = y


## Decorative brick shaft between the tunnel roof and the street. The player is
## teleported rather than climbing, so this only ever has to look like a reason.
static func _shaft(world: World, parent: Node3D, top: Vector3, from_y: float) -> void:
	var height := top.y - from_y
	if height <= 0.05:
		return
	var centre_y := from_y + height * 0.5

	for side: int in [-1, 1]:
		parent.add_child(ProcMesh.solid_box(Vector3(0.3, height, SHAFT_HALF * 2),
			Vector3(top.x + side * SHAFT_HALF, centre_y, top.z),
			world.mat("sewer_brick"), "ShaftX"))
		parent.add_child(ProcMesh.solid_box(Vector3(SHAFT_HALF * 2, height, 0.3),
			Vector3(top.x, centre_y, top.z + side * SHAFT_HALF),
			world.mat("sewer_brick"), "ShaftZ"))

	for rung in maxi(1, int(height / 0.32)):
		parent.add_child(ProcMesh.box(Vector3(0.42, 0.05, 0.05),
			Vector3(top.x, from_y + 0.25 + float(rung) * 0.32, top.z + SHAFT_HALF - 0.14),
			world.mat("steel"), "Rung"))

	var glow := OmniLight3D.new()
	glow.position = Vector3(top.x, from_y - 0.8, top.z)
	glow.light_color = Color(0.72, 0.86, 0.80)
	glow.light_energy = 2.4
	glow.omni_range = 8.0
	parent.add_child(glow)


## A straight run between two points. `roof_gaps` lists positions along the run
## where the roof is left open for a shaft to drop through.
static func _tunnel(world: World, parent: Node3D, a: Vector3, b: Vector3,
		roof_gaps: Array, wall_gaps: Dictionary, cap_a: bool, cap_b: bool) -> void:
	var delta := b - a
	var length := delta.length()
	if length < 0.1:
		return
	var mid := (a + b) * 0.5
	var along_x: bool = absf(delta.x) > absf(delta.z)
	var half_w := World.SEWER_HALF_W

	var floor_size := Vector3(length, 0.3, half_w * 2) if along_x else Vector3(half_w * 2, 0.3, length)
	parent.add_child(ProcMesh.solid_box(floor_size, mid + Vector3(0, -0.15, 0),
		world.mat("sewer_brick"), "TunnelFloor"))

	var water := Vector3(length, 0.06, half_w * 0.9) if along_x else Vector3(half_w * 0.9, 0.06, length)
	parent.add_child(ProcMesh.box(water, mid + Vector3(0, 0.03, 0), world.mat("water"), "Water"))

	var lo: float = minf(a.x, b.x) if along_x else minf(a.z, b.z)
	var hi: float = maxf(a.x, b.x) if along_x else maxf(a.z, b.z)
	var cross: float = a.z if along_x else a.x

	for side: int in [-1, 1]:
		var gaps: Array = wall_gaps.get(side, [])
		for span: Array in _spans(lo, hi, gaps):
			var seg: float = span[1] - span[0]
			var centre: float = (span[0] + span[1]) * 0.5
			var wall := Vector3(seg, TUNNEL_H, 0.3) if along_x else Vector3(0.3, TUNNEL_H, seg)
			var pos := (Vector3(centre, a.y + TUNNEL_H * 0.5, cross + side * half_w) if along_x
				else Vector3(cross + side * half_w, a.y + TUNNEL_H * 0.5, centre))
			parent.add_child(ProcMesh.solid_box(wall, pos, world.mat("sewer_brick"), "TunnelWall"))

	# End caps, so a run does not simply stop in mid-air. The end that meets
	# another run is left open.
	for entry: Array in [[a, cap_a], [b, cap_b]]:
		if not bool(entry[1]):
			continue
		var cap: Vector3 = entry[0]
		var cap_size := Vector3(0.3, TUNNEL_H, half_w * 2) if along_x else Vector3(half_w * 2, TUNNEL_H, 0.3)
		var toward := (mid - cap).normalized() * -0.15
		parent.add_child(ProcMesh.solid_box(cap_size, cap + Vector3(0, TUNNEL_H * 0.5, 0) + toward,
			world.mat("sewer_brick"), "TunnelCap"))

	_roof(world, parent, a, b, along_x, half_w, roof_gaps)

	var lamps := maxi(1, int(length / LAMP_SPACING))
	for i in lamps:
		var t := (float(i) + 0.5) / float(lamps)
		var pos := a.lerp(b, t) + Vector3(0, TUNNEL_H - 0.35, 0)
		var l := OmniLight3D.new()
		l.position = pos
		l.light_color = Color(0.80, 0.88, 0.74)
		l.light_energy = 3.2
		l.omni_range = 13.0
		parent.add_child(l)
		parent.add_child(ProcMesh.box(Vector3(0.18, 0.08, 0.18), pos + Vector3(0, 0.16, 0),
			ProcMesh.mat(ProcTex.flat(Color(0.85, 0.95, 0.8)), 1.0, Color(0.78, 0.9, 0.72), 1.2),
			"TunnelBulb"))


## Builds the roof as a run of segments, skipping the footprint of each shaft.
static func _roof(world: World, parent: Node3D, a: Vector3, b: Vector3,
		along_x: bool, half_w: float, gaps: Array) -> void:
	var start: float = a.x if along_x else a.z
	var end: float = b.x if along_x else b.z
	var lo: float = minf(start, end)
	var hi: float = maxf(start, end)
	var cross: float = a.z if along_x else a.x
	var roof_y: float = a.y + TUNNEL_H

	for span: Array in _spans(lo, hi, gaps):
		_roof_piece(world, parent, span[0], span[1], cross, roof_y, along_x, half_w)


## Splits the range [lo, hi] into the pieces left over once an opening of
## SHAFT_HALF either side of each gap centre has been removed.
static func _spans(lo: float, hi: float, gaps: Array) -> Array:
	var ranges: Array = []
	for g: float in gaps:
		var g_lo: float = maxf(lo, g - SHAFT_HALF)
		var g_hi: float = minf(hi, g + SHAFT_HALF)
		if g_hi > g_lo:
			ranges.append([g_lo, g_hi])
	ranges.sort_custom(func(p, q): return float(p[0]) < float(q[0]))

	var out: Array = []
	var cursor := lo
	for r: Array in ranges:
		if float(r[0]) - cursor > 0.05:
			out.append([cursor, float(r[0])])
		cursor = maxf(cursor, float(r[1]))
	if hi - cursor > 0.05:
		out.append([cursor, hi])
	return out


static func _roof_piece(world: World, parent: Node3D, from: float, to: float,
		cross: float, roof_y: float, along_x: bool, half_w: float) -> void:
	var seg := to - from
	if seg <= 0.05:
		return
	var centre := (from + to) * 0.5
	var size := Vector3(seg, 0.3, half_w * 2) if along_x else Vector3(half_w * 2, 0.3, seg)
	var pos := Vector3(centre, roof_y, cross) if along_x else Vector3(cross, roof_y, centre)
	parent.add_child(ProcMesh.solid_box(size, pos, world.mat("sewer_brick"), "TunnelRoof"))
