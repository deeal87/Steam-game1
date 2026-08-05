class_name ProcMesh
extends RefCounted
## Geometry helpers.
##
## The whole world is boxes and cylinders assembled in code. That is not a
## shortcut so much as a style: the reference era built its environments from
## exactly these primitives.

const PS1_SHADER := preload("res://shaders/ps1.gdshader")

static var _shader_cache: Shader = null

# --- Resource sharing ---------------------------------------------------------
#
# Meshes and materials here are immutable once built, so two things that look
# the same can *be* the same. Before this, the shop built 376 MeshInstance3Ds
# backed by 376 separate BoxMesh resources — every crate, every shelf plank and
# every brick of the kiosk carrying its own copy of a shape that a dozen others
# already had. Each unique mesh and material pair is a draw call the renderer
# cannot combine, so this was costing memory and draw calls at the same time.
#
# Sharing is safe precisely because nothing mutates them: `box()` sets size once
# at creation, and per-instance differences live on the MeshInstance3D
# (position, name) rather than on the resource.

static var _box_cache: Dictionary = {}    ## "x,y,z" -> BoxMesh
static var _cyl_cache: Dictionary = {}    ## "r,h,sides" -> CylinderMesh
static var _quad_cache: Dictionary = {}   ## "x,y" -> QuadMesh
static var _mat_cache: Dictionary = {}    ## parameter digest -> ShaderMaterial


static func cache_sizes() -> Dictionary:
	return {
		"box": _box_cache.size(), "cylinder": _cyl_cache.size(),
		"quad": _quad_cache.size(), "material": _mat_cache.size(),
	}


static func clear_caches() -> void:
	_box_cache.clear()
	_cyl_cache.clear()
	_quad_cache.clear()
	_mat_cache.clear()
	_shape_cache.clear()


static func shader() -> Shader:
	if _shader_cache == null:
		_shader_cache = PS1_SHADER
	return _shader_cache


## Rounded to a tenth of a millimetre before it becomes a key, so sizes that
## differ only by floating-point noise still share one resource.
static func _size_key(v: Vector3) -> String:
	return "%.4f,%.4f,%.4f" % [v.x, v.y, v.z]


static func box_mesh(size: Vector3) -> BoxMesh:
	var key := _size_key(size)
	var hit: Variant = _box_cache.get(key)
	if hit != null:
		return hit
	var mesh := BoxMesh.new()
	mesh.size = size
	_box_cache[key] = mesh
	return mesh


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
	# Keyed on the texture's identity rather than its contents — ProcTex already
	# hands back the same ImageTexture for the same request, so two materials
	# built from the same picture and the same numbers really are the same
	# material.
	var key := "%d|%.4f|%s|%.4f|%s|%.4f|%.4f" % [
		tex.get_instance_id() if tex != null else 0, uv_scale, emission.to_html(true),
		emission_strength, tint.to_html(true), snap, affine,
	]
	var hit: Variant = _mat_cache.get(key)
	if hit != null:
		return hit

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
	_mat_cache[key] = m
	return m


static func colour_mat(c: Color, emission_strength: float = 0.0) -> ShaderMaterial:
	return mat(ProcTex.flat(c), 1.0, c, emission_strength)


# --- Primitives --------------------------------------------------------------

static func box(size: Vector3, pos: Vector3, material: Material, name: String = "Box") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = box_mesh(size)
	mi.material_override = material
	mi.position = pos
	mi.name = name
	return mi


static func cylinder(radius: float, height: float, pos: Vector3, material: Material, sides: int = 8) -> MeshInstance3D:
	var key := "%.4f,%.4f,%d" % [radius, height, sides]
	var mesh: CylinderMesh = _cyl_cache.get(key)
	if mesh == null:
		mesh = CylinderMesh.new()
		mesh.top_radius = radius
		mesh.bottom_radius = radius
		mesh.height = height
		mesh.radial_segments = sides
		mesh.rings = 1
		_cyl_cache[key] = mesh
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	return mi


static func quad(size: Vector2, pos: Vector3, material: Material) -> MeshInstance3D:
	var key := "%.4f,%.4f" % [size.x, size.y]
	var mesh: QuadMesh = _quad_cache.get(key)
	if mesh == null:
		mesh = QuadMesh.new()
		mesh.size = size
		_quad_cache[key] = mesh
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
	shape.shape = box_shape(size)
	body.add_child(shape)
	return body


## Collision shapes share the same way meshes do, and for the same reason: the
## physics server stores one copy and every body points at it.
static var _shape_cache: Dictionary = {}


static func box_shape(size: Vector3) -> BoxShape3D:
	var key := _size_key(size)
	var hit: Variant = _shape_cache.get(key)
	if hit != null:
		return hit
	var bs := BoxShape3D.new()
	bs.size = size
	_shape_cache[key] = bs
	return bs


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
	var outfit_index := rng.randi() % OUTFITS.size()
	var outfit: Dictionary = OUTFITS[outfit_index]

	var root := Node3D.new()
	root.name = "Body"

	# Cloth grime is seeded from the *outfit*, not the person.
	#
	# It used to be seeded per person, which meant a fresh 32x32 noise texture
	# for every coat and every pair of trousers that ever walked in — and nobody
	# alive can tell one customer from another by the dirt pattern on their coat.
	# Six outfits means twelve textures for the whole game instead of two per
	# customer, and it is the difference between a spawn costing three and a half
	# milliseconds and costing a quarter of one. The face, which *is* how you tell
	# people apart, stays unique per person.
	var coat_mat := mat(ProcTex.grime(outfit["coat"], 0.35, 1100 + outfit_index, 32))
	var trouser_mat := mat(ProcTex.grime(outfit["trouser"], 0.3, 2200 + outfit_index, 32))
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
