class_name ProcMesh
extends RefCounted
## Geometry helpers.
##
## The whole world is boxes and cylinders assembled in code. That is not a
## shortcut so much as a style: the reference era built its environments from
## exactly these primitives.

const PS1_SHADER := preload("res://shaders/ps1.gdshader")

static var _shader_cache: Shader = null


static func shader() -> Shader:
	if _shader_cache == null:
		_shader_cache = PS1_SHADER
	return _shader_cache


## Builds a material using the PS1 shader. `uv_scale` tiles the texture across
## large surfaces; `emission` makes a thing glow, which on this street means it
## is one of the very few objects you can actually see.
static func mat(
	tex: Texture2D,
	uv_scale: float = 1.0,
	emission: Color = Color(0, 0, 0),
	emission_strength: float = 0.0,
	tint: Color = Color.WHITE,
	snap: float = 1.0,
	affine: float = 1.0
) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader()
	m.set_shader_parameter("albedo_tex", tex)
	m.set_shader_parameter("uv_scale", uv_scale)
	m.set_shader_parameter("emission_tint", emission)
	m.set_shader_parameter("emission_strength", emission_strength)
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("snap_strength", snap)
	m.set_shader_parameter("affine_strength", affine)
	m.set_shader_parameter("snap_grid", 110.0)
	return m


static func colour_mat(c: Color, emission_strength: float = 0.0) -> ShaderMaterial:
	return mat(ProcTex.flat(c), 1.0, c, emission_strength)


# --- Primitives --------------------------------------------------------------

static func box(size: Vector3, pos: Vector3, material: Material, name: String = "Box") -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	mi.name = name
	return mi


static func cylinder(radius: float, height: float, pos: Vector3, material: Material, sides: int = 8) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = sides
	mesh.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	return mi


static func quad(size: Vector2, pos: Vector3, material: Material) -> MeshInstance3D:
	var mesh := QuadMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	return mi


## A box that the player cannot walk through.
static func solid_box(size: Vector3, pos: Vector3, material: Material, name: String = "Solid") -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = name
	body.position = pos
	body.add_child(box(size, Vector3.ZERO, material, name + "Mesh"))
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	shape.shape = bs
	body.add_child(shape)
	return body


# --- Characters --------------------------------------------------------------

const OUTFITS := [
	{"coat": Color(0.20, 0.21, 0.26), "trouser": Color(0.13, 0.13, 0.16)},
	{"coat": Color(0.30, 0.16, 0.14), "trouser": Color(0.16, 0.15, 0.14)},
	{"coat": Color(0.14, 0.22, 0.19), "trouser": Color(0.12, 0.12, 0.13)},
	{"coat": Color(0.34, 0.31, 0.22), "trouser": Color(0.18, 0.17, 0.16)},
	{"coat": Color(0.16, 0.18, 0.30), "trouser": Color(0.11, 0.11, 0.14)},
	{"coat": Color(0.24, 0.24, 0.25), "trouser": Color(0.15, 0.14, 0.13)},
]

## A blocky standing figure, roughly 1.8 m tall, with named limb pivots so the
## walk cycle and the death ragdoll have something to grab.
static func human(seed_val: int, tall: float = 1.0, bulk: float = 1.0) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var outfit: Dictionary = OUTFITS[rng.randi() % OUTFITS.size()]

	var root := Node3D.new()
	root.name = "Body"

	var coat_mat := mat(ProcTex.grime(outfit["coat"], 0.35, seed_val + 11, 32))
	var trouser_mat := mat(ProcTex.grime(outfit["trouser"], 0.3, seed_val + 22, 32))
	var skin_mat := mat(ProcTex.flat(ProcTex.skin_for(seed_val)))
	var face_mat := mat(ProcTex.face(seed_val))
	var hair_mat := mat(ProcTex.flat(ProcTex.hair_for(seed_val)))
	var shoe_mat := mat(ProcTex.flat(Color(0.07, 0.07, 0.08)))

	var h := 1.78 * tall
	var w := 0.42 * bulk

	# Legs hang from a hip pivot so they can swing.
	for side: int in [-1, 1]:
		var hip := Node3D.new()
		hip.name = "Hip" + ("L" if side < 0 else "R")
		hip.position = Vector3(side * w * 0.24, h * 0.48, 0)
		root.add_child(hip)
		hip.add_child(box(Vector3(w * 0.30, h * 0.46, w * 0.30), Vector3(0, -h * 0.23, 0), trouser_mat, "Leg"))
		hip.add_child(box(Vector3(w * 0.32, h * 0.05, w * 0.46), Vector3(0, -h * 0.465, w * 0.06), shoe_mat, "Shoe"))

	root.add_child(box(Vector3(w, h * 0.34, w * 0.55), Vector3(0, h * 0.66, 0), coat_mat, "Torso"))
	root.add_child(box(Vector3(w * 0.92, h * 0.10, w * 0.52), Vector3(0, h * 0.47, 0), trouser_mat, "Waist"))

	for side: int in [-1, 1]:
		var shoulder := Node3D.new()
		shoulder.name = "Shoulder" + ("L" if side < 0 else "R")
		shoulder.position = Vector3(side * (w * 0.5 + w * 0.10), h * 0.80, 0)
		root.add_child(shoulder)
		shoulder.add_child(box(Vector3(w * 0.22, h * 0.36, w * 0.24), Vector3(0, -h * 0.18, 0), coat_mat, "Arm"))
		shoulder.add_child(box(Vector3(w * 0.20, h * 0.07, w * 0.22), Vector3(0, -h * 0.38, 0), skin_mat, "Hand"))

	var neck := Node3D.new()
	neck.name = "Head"
	neck.position = Vector3(0, h * 0.86, 0)
	root.add_child(neck)
	neck.add_child(box(Vector3(w * 0.22, h * 0.05, w * 0.22), Vector3.ZERO, skin_mat, "Neck"))

	# The face is a separate slightly-proud quad on the front of the head cube,
	# so the portrait texture is never stretched around the sides of the skull.
	var head_size := w * 0.46
	neck.add_child(box(Vector3(head_size, head_size * 1.10, head_size), Vector3(0, head_size * 0.62, 0), hair_mat, "Skull"))
	var face := quad(Vector2(head_size * 0.94, head_size * 1.02), Vector3(0, head_size * 0.60, head_size * 0.505), face_mat)
	face.name = "Face"
	neck.add_child(face)

	if rng.randf() < 0.30:
		var cap_col := Color(0.10, 0.10, 0.12) if rng.randf() < 0.6 else Color(0.22, 0.16, 0.12)
		neck.add_child(box(Vector3(head_size * 1.08, head_size * 0.22, head_size * 1.08),
			Vector3(0, head_size * 1.12, 0), mat(ProcTex.flat(cap_col)), "Cap"))
		neck.add_child(box(Vector3(head_size * 1.02, head_size * 0.06, head_size * 0.5),
			Vector3(0, head_size * 1.02, head_size * 0.6), mat(ProcTex.flat(cap_col.darkened(0.2))), "Brim"))

	return root
