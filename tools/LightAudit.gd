extends Node
## Counts how many lights can reach one point at a time.
##
##   godot --headless --path . tools/LightAudit.tscn
##
## GL Compatibility gives every object a fixed number of the lights near it and
## silently drops the rest. Under vertex lighting an object that ends up with
## none renders black, and black against a black room is indistinguishable from
## not being drawn at all — which is what "things disappear depending how I walk
## up to them" looks like from the inside.
##
## Which lights an object gets is decided per frame from the camera, so the set
## changes as you move. That is the "and come back" half.

const BUDGET := 8


func _ready() -> void:
	Log.mute(true)
	var world := World.new()
	add_child(world)
	await get_tree().process_frame

	var lights: Array[Light3D] = []
	_collect(world, lights)
	var omnis := 0
	for l in lights:
		if l is OmniLight3D:
			omnis += 1
	print("\nlights in the world: %d omni, %d total" % [omnis, lights.size()])

	# Sample head height across the shop, the stockroom and the street.
	var worst := 0
	var worst_at := Vector3.ZERO
	var over := 0
	var samples := 0
	for zone: Array in [
			["the shop", -6.0, 6.0, -4.0, 3.0],
			["the stockroom", 4.0, 12.0, 2.0, 9.0],
			["the street", -30.0, 20.0, -12.0, 6.0]]:
		var zone_worst := 0
		var x: float = zone[1]
		while x <= float(zone[2]):
			var z: float = zone[3]
			while z <= float(zone[4]):
				var p := Vector3(x, 1.5, z)
				var n := 0
				for l in lights:
					var o := l as OmniLight3D
					if o == null:
						continue
					if o.global_position.distance_to(p) <= o.omni_range:
						n += 1
				samples += 1
				if n > BUDGET:
					over += 1
				zone_worst = maxi(zone_worst, n)
				if n > worst:
					worst = n
					worst_at = p
				z += 1.0
			x += 1.0
		print("  %-14s worst %d lights on one point" % [zone[0], zone_worst])

	print("\nbudget is %d per object" % BUDGET)
	print("worst anywhere: %d at %.0f,%.0f,%.0f" % [worst, worst_at.x, worst_at.y, worst_at.z])
	print("points over budget: %d of %d\n" % [over, samples])
	get_tree().quit(0)


func _collect(n: Node, out: Array) -> void:
	if n is Light3D:
		out.append(n)
	for c in n.get_children():
		_collect(c, out)
