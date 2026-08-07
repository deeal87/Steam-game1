extends Node
## Finds out what happens to the geometry that keeps disappearing.
##
##   xvfb-run -a godot --path . tools/VanishAudit.tscn -- --at=0,1.7,3 --sweep=yaw
##
## "Things vanish and come back depending how far away I am and which way I am
## looking" has been diagnosed twice from a screenshot and fixed twice without
## going away. A screenshot cannot tell the difference between the two things it
## could be, and they need opposite fixes:
##
##   * the renderer is not drawing it — a culling problem, and the object count
##     for the frame drops;
##   * the renderer is drawing it black — a lighting problem, and the object
##     count does not move while the picture goes dark.
##
## So this sweeps the camera through a range of angles and distances at a fixed
## piece of the world and prints, for each pose, how many objects the frame
## drew and how bright it came out. A number that jumps around while the camera
## barely moves is the bug, and which column it jumps in says what it is.

var _game: Node3D
var _rows: Array[Dictionary] = []


func _ready() -> void:
	var opts := _args()
	_game = load("res://scenes/Boot.tscn").instantiate()
	add_child(_game)

	for _i in 40:
		await get_tree().process_frame
	var report: Node = _game.get("report")
	if report != null and report.has_method("_continue"):
		report._continue()
	for _i in 40:
		await get_tree().process_frame

	var player: Node3D = _game.get("player")
	if player == null:
		printerr("[vanish] no player")
		get_tree().quit(1)
		return
	player.set_physics_process(false)
	player.ui_locked = true

	print("\n=== what happens to the geometry ===\n")
	print("  %-28s %8s %10s %9s" % ["pose", "objects", "primitives", "light"])
	print("  " + "-".repeat(58))

	match str(opts["sweep"]):
		"yaw":
			await _sweep_yaw(player, opts["at"])
		"distance":
			await _sweep_distance(player, opts["at"], opts["look_at"])
		_:
			await _sweep_yaw(player, opts["at"])
			await _sweep_distance(player, opts["at"], opts["look_at"])

	_verdict()
	get_tree().quit(0)


## Turning on the spot. The scene in front of the camera changes gradually, so
## the object count should change gradually too.
func _sweep_yaw(player: Node3D, at: Vector3) -> void:
	for step in 24:
		var yaw := float(step) * 15.0
		await _measure(player, at, deg_to_rad(yaw), 0.0, "yaw %3d°" % int(yaw))


## Walking towards something. Nothing should leave the frame on the way in.
func _sweep_distance(player: Node3D, at: Vector3, look_at: Vector3) -> void:
	var away := at - look_at
	var yaw := atan2(away.x, away.z)
	for step in 20:
		var t := 1.0 - float(step) / 22.0
		var here := look_at + away * t
		here.y = at.y
		await _measure(player, here, yaw, 0.0,
			"%.1f m away" % here.distance_to(look_at))


func _measure(player: Node3D, at: Vector3, yaw: float, pitch: float, label: String) -> void:
	player.global_position = at
	player.rotation = Vector3(0, yaw, 0)
	var cam: Camera3D = player.get("camera")
	if cam != null:
		cam.rotation = Vector3(pitch, 0, 0)
	if player.has_method("_apply_view_layer"):
		player._apply_view_layer()
	for _i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var objects := RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
	var prims := RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	var light := _brightness()
	_rows.append({"label": label, "objects": objects, "prims": prims, "light": light})
	print("  %-28s %8d %10d %9.1f" % [label, objects, prims, light])


## Mean brightness of the world buffer, which is the thing that goes dark. The
## interface is drawn separately at full size and would drown the measurement.
func _brightness() -> float:
	var view: SubViewport = _game.get("viewport_3d")
	if view == null:
		return -1.0
	var img := view.get_texture().get_image()
	if img == null or img.get_width() == 0:
		return -1.0
	var total := 0.0
	var n := 0
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			var c := img.get_pixel(x, y)
			total += (c.r + c.g + c.b) * 85.0
			n += 1
	return total / float(maxi(1, n))


## The two numbers that would tell the story, and which of them moved.
func _verdict() -> void:
	if _rows.size() < 2:
		return
	var worst_objects := 0
	var worst_light := 0.0
	var where_objects := ""
	var where_light := ""
	for i in range(1, _rows.size()):
		var a: Dictionary = _rows[i - 1]
		var b: Dictionary = _rows[i]
		var d_obj: int = absi(int(b["objects"]) - int(a["objects"]))
		var d_light: float = absf(float(b["light"]) - float(a["light"]))
		if d_obj > worst_objects:
			worst_objects = d_obj
			where_objects = "%s -> %s" % [a["label"], b["label"]]
		if d_light > worst_light:
			worst_light = d_light
			where_light = "%s -> %s" % [a["label"], b["label"]]

	var lo := 999999
	var hi := 0
	for r: Dictionary in _rows:
		lo = mini(lo, int(r["objects"]))
		hi = maxi(hi, int(r["objects"]))

	print("\n  objects drawn: %d to %d over the sweep" % [lo, hi])
	print("  biggest jump in objects : %d   (%s)" % [worst_objects, where_objects])
	print("  biggest jump in light   : %.1f   (%s)" % [worst_light, where_light])
	print("")
	if worst_objects > 12:
		print("  -> geometry is leaving the frame. That is culling, not lighting.")
	elif worst_light > 12.0:
		print("  -> the object count holds while the picture goes dark. That is lighting.")
	else:
		print("  -> nothing jumped. Whatever it is, this sweep did not cross it.")
	print("")


func _args() -> Dictionary:
	var out := {
		"at": Vector3(-0.60, 1.70, 3.05),
		"look_at": Vector3(-1.60, 1.20, -4.00),
		"sweep": "",
	}
	for arg: String in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if arg.begins_with("--at="):
			out["at"] = _vec3(arg.substr(5), out["at"])
		elif arg.begins_with("--look-at="):
			out["look_at"] = _vec3(arg.substr(10), out["look_at"])
		elif arg.begins_with("--sweep="):
			out["sweep"] = arg.substr(8)
	return out


static func _vec3(text: String, fallback: Vector3) -> Vector3:
	var parts := text.split(",")
	if parts.size() < 3:
		return fallback
	return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
