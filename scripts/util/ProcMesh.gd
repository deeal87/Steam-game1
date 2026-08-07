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


## A ceiling on the materials held at once.
##
## Materials are keyed on the identity of the texture they were built from, and
## a face texture belongs to one person, so every person who has ever come to
## the window left one behind. Comfortably more than can be on screen and in the
## terminal at the same time, so nothing in use is ever thrown away.
const MAT_CACHE_MAX := 192

## A ceiling on geometry held at once.
##
## Snapping sizes to five millimetres and body types to a fixed grid bounds this
## set in principle — but eleven boxes per person across two hundred and seventy
## body types is still a few thousand shapes, which is bounded far too late to
## be worth anything. What is actually in use at one moment is the shop's
## fittings and the half-dozen people in it: under a hundred. This leaves room
## for three times that and drops the rest.
##
## Evicting costs nothing that is still on screen. A mesh in use is held by the
## node drawing it; leaving the cache only means the next request for that exact
## shape builds it again.
const MESH_CACHE_MAX := 256


## Inserts, and drops the oldest entry once the cache is over its ceiling.
## GDScript dictionaries keep insertion order, so the first key is the one that
## has gone longest without being written.
static func _bounded_put(cache: Dictionary, key: String, value: Variant, cap: int) -> void:
	cache[key] = value
	while cache.size() > cap:
		cache.erase(cache.keys()[0])


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


## The grid every mesh size is snapped to before it becomes a key.
##
## This was a tenth of a millimetre, which sounds harmlessly precise and was
## the whole problem. Everybody who walks in is built from boxes scaled by their
## own height and build — continuous numbers — so at that resolution no two
## people ever shared a mesh, the cache never hit for any of it, and it grew by
## a hundred-odd BoxMesh resources every night for as long as the run lasted.
##
## Five millimetres on a person is not visible. It is the difference between a
## cache that holds a few dozen shapes and reuses them all night, and one that
## holds every shape the game has ever drawn.
const SIZE_STEP := 0.005


## Never smaller than one step, so a deliberately thin panel does not round away
## to nothing.
static func _quantise(v: Vector3) -> Vector3:
	return Vector3(
		maxf(SIZE_STEP, snappedf(v.x, SIZE_STEP)),
		maxf(SIZE_STEP, snappedf(v.y, SIZE_STEP)),
		maxf(SIZE_STEP, snappedf(v.z, SIZE_STEP)))


static func _size_key(v: Vector3) -> String:
	return "%.3f,%.3f,%.3f" % [v.x, v.y, v.z]


static func box_mesh(size: Vector3) -> BoxMesh:
	var snapped_size := _quantise(size)
	var key := _size_key(snapped_size)
	var hit: Variant = _box_cache.get(key)
	if hit != null:
		return hit
	var mesh := BoxMesh.new()
	mesh.size = snapped_size
	_bounded_put(_box_cache, key, mesh, MESH_CACHE_MAX)
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
	_bounded_put(_mat_cache, key, m, MAT_CACHE_MAX)
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
	# Snapped for the same reason boxes are: a radius that came out of somebody's
	# build is a continuous number and would never be asked for twice.
	var r := maxf(SIZE_STEP, snappedf(radius, SIZE_STEP))
	var h := maxf(SIZE_STEP, snappedf(height, SIZE_STEP))
	var key := "%.3f,%.3f,%d" % [r, h, sides]
	var mesh: CylinderMesh = _cyl_cache.get(key)
	if mesh == null:
		mesh = CylinderMesh.new()
		mesh.top_radius = r
		mesh.bottom_radius = r
		mesh.height = h
		mesh.radial_segments = sides
		mesh.rings = 1
		_bounded_put(_cyl_cache, key, mesh, MESH_CACHE_MAX)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	return mi


static func quad(size: Vector2, pos: Vector3, material: Material) -> MeshInstance3D:
	var snapped_size := Vector2(
		maxf(SIZE_STEP, snappedf(size.x, SIZE_STEP)),
		maxf(SIZE_STEP, snappedf(size.y, SIZE_STEP)))
	var key := "%.3f,%.3f" % [snapped_size.x, snapped_size.y]
	var mesh: QuadMesh = _quad_cache.get(key)
	if mesh == null:
		mesh = QuadMesh.new()
		mesh.size = snapped_size
		_bounded_put(_quad_cache, key, mesh, MESH_CACHE_MAX)
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
	_bounded_put(_shape_cache, key, bs, MESH_CACHE_MAX)
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

## How many sets of painted clothes the pack has, counted once by asking for
## them until one is missing. Zero means everybody wears the generated colours,
## which is what the game did before there was a pack.
static var _painted_outfits: int = -1


static func painted_outfit_count() -> int:
	if _painted_outfits < 0:
		_painted_outfits = 0
		while ProcTex.has_painted("outfit_%02d_coat" % _painted_outfits) \
				and ProcTex.has_painted("outfit_%02d_legs" % _painted_outfits):
			_painted_outfits += 1
	return _painted_outfits


## A blocky standing figure, roughly 1.8 m tall, with named limb pivots so the
## walk cycle and the death ragdoll have something to grab.
##
## `outfit` picks the clothes. Passed in rather than drawn here, because what
## somebody is wearing is the most visible thing about them before they say a
## word and it must not correlate with whether they are police — the caller
## takes it off the stream that exists for exactly that guarantee. Left at -1 it
## falls back to the seed, which is what the sewer's inhabitants and anything
## else without a profile get.
static func human(seed_val: int, tall: float = 1.0, bulk: float = 1.0,
		outfit: int = -1) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var wardrobe: int = outfit if outfit >= 0 else rng.randi()
	# Consumed either way, so the hats and everything else after it fall the same
	# whether or not an outfit was handed in.
	if outfit >= 0:
		rng.randi()
	var outfit_index: int = wardrobe % OUTFITS.size()
	var colours: Dictionary = OUTFITS[outfit_index]

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
	#
	# The same argument is what makes the painted clothes affordable. They are
	# photographs of sixteen people off the pack's character sheet, shared
	# between everybody who draws that number, so the whole game holds
	# thirty-two small images rather than two per customer. Faces are not on the
	# sheet at a usable size, which is just as well: a fixed set of painted faces
	# would have two people in a night wearing the same one, and the face is the
	# thing this game asks you to remember.
	var coat_mat: Material
	var trouser_mat: Material
	var painted := painted_outfit_count()
	if painted > 0:
		var wear := wardrobe % painted
		coat_mat = mat(ProcTex.painted("outfit_%02d_coat" % wear))
		trouser_mat = mat(ProcTex.painted("outfit_%02d_legs" % wear))
	else:
		coat_mat = mat(ProcTex.grime(colours["coat"], 0.35, 1100 + outfit_index, 32))
		trouser_mat = mat(ProcTex.grime(colours["trouser"], 0.3, 2200 + outfit_index, 32))
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
