extends Node
## Asks one question: does a wall hide what is behind it?
##
##   xvfb-run -a godot --path . tools/DepthProof.tscn
##
## Opaque geometry is drawn front to back against a depth buffer, so whatever is
## nearest wins and everything behind it is never shaded. Transparent geometry is
## drawn after all of that, sorted per object by its distance from the camera,
## and — unless it is asked to — writes no depth at all. Two transparent boxes
## therefore draw in whatever order their origins happen to sort in, which
## changes as the camera moves.
##
## A spatial shader in Godot 4 becomes transparent simply by writing to ALPHA.
## Nothing warns you. The game still renders, most of it still looks right, and
## the symptom is that objects show through walls and swap in and out as you walk
## around — which is exactly what this game was reported as doing.
##
## So: one bright red box, one grey wall in front of it, one camera. If any red
## reaches the screen, the wall is not hiding what is behind it.

const RED := Color(1.0, 0.0, 0.0)


func _ready() -> void:
	var world := Node3D.new()
	add_child(world)

	var cam := Camera3D.new()
	cam.position = Vector3(0, 0, 4)
	cam.current = true
	world.add_child(cam)

	# The thing that must not be visible: bright, and behind the wall's face.
	var hidden := ProcMesh.box(Vector3(1.2, 1.2, 0.2), Vector3(0, 0, -4.0),
		ProcMesh.mat(ProcTex.flat(RED), 1.0, RED, 3.0), "Hidden")
	world.add_child(hidden)

	# The wall. Long, and running away from the camera, so that its *surface* is
	# nearer than the red box while its *origin* is very much further away.
	#
	# That asymmetry is the whole test. Transparent geometry is sorted by how far
	# each object's origin is from the camera, so this wall sorts as the distant
	# one and gets drawn first, and the red box behind it is painted on top.
	# Opaque geometry never asks: the depth buffer compares the pixels that are
	# actually there, and the wall's near face wins.
	#
	# It is also the shape of the real problem. This game is built out of long
	# boxes — a hundred metres of road, a shop wall, a counter — with small props
	# scattered among them, and an origin ten metres away with a face at arm's
	# length is every one of them.
	var wall := ProcMesh.box(Vector3(6.0, 6.0, 20.0), Vector3(0, 0, -12.0),
		ProcMesh.mat(ProcTex.flat(Color(0.55, 0.55, 0.58))), "Wall")
	world.add_child(wall)

	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, 1.5, 3.0)
	lamp.light_energy = 4.0
	lamp.omni_range = 12.0
	world.add_child(lamp)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.4, 0.4, 0.4)
	env.ambient_light_energy = 1.0
	var holder := WorldEnvironment.new()
	holder.environment = env
	world.add_child(holder)

	for _i in 8:
		await get_tree().process_frame
	for _i in 4:
		await RenderingServer.frame_post_draw

	var img := get_viewport().get_texture().get_image()
	var reddest := 0.0
	var red_pixels := 0
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			var c := img.get_pixel(x, y)
			# Red that is not just a warm grey: clearly more red than anything else.
			var redness: float = c.r - maxf(c.g, c.b)
			reddest = maxf(reddest, redness)
			if redness > 0.25:
				red_pixels += 1

	print("\n=== does a wall hide what is behind it? ===\n")
	print("  reddest pixel on screen : %.3f above its own green and blue" % reddest)
	print("  pixels that red         : %d" % red_pixels)
	if red_pixels > 0:
		print("\n  NO. The box behind the wall is being drawn over it.")
		print("  Every surface in this game is transparent, so nothing writes depth")
		print("  and everything sorts by how far its origin is from the camera.")
		print("  That is the geometry that appears and disappears as you move.\n")
		get_tree().quit(1)
		return
	print("\n  Yes. Opaque geometry, depth buffer doing its job.\n")
	get_tree().quit(0)
