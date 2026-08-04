class_name ProcTex
extends RefCounted
## Procedural texture factory.
##
## Everything the game renders is painted here into small, low-resolution
## images. Small is not a limitation: at 64x64 with nearest filtering the
## textures read as late-90s console art, which is exactly the look we want.

static func _finish(img: Image) -> ImageTexture:
	return ImageTexture.create_from_image(img)


static func _rng(seed_val: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_val
	return r


## Value noise sampled on a coarse grid and smoothed, so surfaces get blotches
## rather than per-pixel confetti.
static func _value_noise(w: int, h: int, cells: int, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var grid := PackedFloat32Array()
	grid.resize((cells + 1) * (cells + 1))
	for i in grid.size():
		grid[i] = rng.randf()
	var out := PackedFloat32Array()
	out.resize(w * h)
	for y in h:
		for x in w:
			var fx := float(x) / w * cells
			var fy := float(y) / h * cells
			var x0 := int(fx)
			var y0 := int(fy)
			var tx := smoothstep(0.0, 1.0, fx - x0)
			var ty := smoothstep(0.0, 1.0, fy - y0)
			var a := grid[y0 * (cells + 1) + x0]
			var b := grid[y0 * (cells + 1) + x0 + 1]
			var c := grid[(y0 + 1) * (cells + 1) + x0]
			var d := grid[(y0 + 1) * (cells + 1) + x0 + 1]
			out[y * w + x] = lerpf(lerpf(a, b, tx), lerpf(c, d, tx), ty)
	return out


# --- Surfaces ----------------------------------------------------------------

static func grime(base: Color, amount: float, seed_val: int, size: int = 64) -> ImageTexture:
	var rng := _rng(seed_val)
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var n := _value_noise(size, size, 8, rng)
	for y in size:
		for x in size:
			var v := n[y * size + x]
			var speck := rng.randf() * 0.12
			var c := base.darkened((v * amount) + speck * 0.5)
			img.set_pixel(x, y, c)
	return _finish(img)


static func asphalt(seed_val: int, size: int = 64) -> ImageTexture:
	var rng := _rng(seed_val)
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var n := _value_noise(size, size, 12, rng)
	for y in size:
		for x in size:
			var v: float = n[y * size + x] * 0.35 + rng.randf() * 0.25
			var g: float = 0.055 + v * 0.09
			img.set_pixel(x, y, Color(g, g, g * 1.06))
	return _finish(img)


static func brick(seed_val: int, size: int = 64) -> ImageTexture:
	var rng := _rng(seed_val)
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var mortar := Color(0.14, 0.13, 0.12)
	var brick_h := 8
	var brick_w := 16
	for y in size:
		var row := int(y / brick_h)
		var offset := (row % 2) * int(brick_w / 2)
		for x in size:
			var bx := (x + offset) % brick_w
			var by := y % brick_h
			if bx < 1 or by < 1:
				img.set_pixel(x, y, mortar)
			else:
				var tone := 0.16 + rng.randf() * 0.07 + float((row * 7 + int((x + offset) / brick_w) * 13) % 5) * 0.012
				img.set_pixel(x, y, Color(tone * 1.25, tone * 0.85, tone * 0.75))
	return _finish(img)


static func corrugated(base: Color, seed_val: int, size: int = 64) -> ImageTexture:
	var rng := _rng(seed_val)
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	for y in size:
		for x in size:
			var ridge := sin(float(x) / size * TAU * 8.0) * 0.5 + 0.5
			var c := base.lerp(Color.BLACK, 0.35 * (1.0 - ridge))
			c = c.darkened(rng.randf() * 0.10)
			img.set_pixel(x, y, c)
	return _finish(img)


static func tiles(seed_val: int, size: int = 64) -> ImageTexture:
	var rng := _rng(seed_val)
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var cell := 16
	for y in size:
		for x in size:
			var edge: bool = (x % cell < 1) or (y % cell < 1)
			var tone: float = 0.20 + rng.randf() * 0.05
			# Long-unwashed linoleum: darker toward the middle of each tile.
			var cx := absf(float(x % cell) / cell - 0.5) * 2.0
			var cy := absf(float(y % cell) / cell - 0.5) * 2.0
			tone -= (1.0 - maxf(cx, cy)) * 0.05
			img.set_pixel(x, y, Color(0.09, 0.09, 0.10) if edge else Color(tone, tone * 1.02, tone * 0.95))
	return _finish(img)


static func metal(base: Color, seed_val: int, size: int = 32) -> ImageTexture:
	var rng := _rng(seed_val)
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	for y in size:
		for x in size:
			var scratch := 0.0
			if rng.randf() < 0.05:
				scratch = rng.randf() * 0.2
			img.set_pixel(x, y, base.lightened(scratch).darkened(rng.randf() * 0.12))
	return _finish(img)


static func flat(c: Color) -> ImageTexture:
	var img := Image.create(4, 4, false, Image.FORMAT_RGB8)
	img.fill(c)
	return _finish(img)


# --- Products ----------------------------------------------------------------

## A product box: a coloured field, a darker cap, and a couple of label bands.
## Read from two metres away it is unmistakably "a thing on a shelf".
static func product(base: Color, seed_val: int, size: int = 32) -> ImageTexture:
	var rng := _rng(seed_val)
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	img.fill(base)
	var band_top := int(size * 0.32)
	var band_h: int = maxi(3, int(size * 0.16))
	for y in range(band_top, mini(size, band_top + band_h)):
		for x in size:
			img.set_pixel(x, y, base.lightened(0.45))
	# Fake text: a broken run of dark pixels across the light band.
	var ty := band_top + int(band_h / 2)
	for x in range(3, size - 3):
		if rng.randf() < 0.62:
			img.set_pixel(x, ty, base.darkened(0.7))
	for y in range(0, int(size * 0.10)):
		for x in size:
			img.set_pixel(x, y, base.darkened(0.4))
	return _finish(img)


# --- Faces -------------------------------------------------------------------

const SKIN_TONES := [
	Color(0.87, 0.71, 0.58), Color(0.76, 0.59, 0.45), Color(0.58, 0.42, 0.31),
	Color(0.42, 0.29, 0.21), Color(0.31, 0.21, 0.16), Color(0.93, 0.79, 0.68),
]
const HAIR_TONES := [
	Color(0.08, 0.07, 0.06), Color(0.22, 0.14, 0.08), Color(0.45, 0.32, 0.16),
	Color(0.62, 0.58, 0.55), Color(0.30, 0.10, 0.07),
]

## Draws a 32x32 face used both on the character model and in the terminal's
## ID photo, so the person at the counter and the person on screen match.
static func face(seed_val: int, size: int = 32) -> ImageTexture:
	var rng := _rng(seed_val)
	var skin: Color = SKIN_TONES[rng.randi() % SKIN_TONES.size()]
	var hair: Color = HAIR_TONES[rng.randi() % HAIR_TONES.size()]
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	img.fill(skin)

	# Shading down the sides of the face.
	for y in size:
		for x in size:
			var edge := absf(float(x) / size - 0.5) * 2.0
			img.set_pixel(x, y, skin.darkened(pow(edge, 3.0) * 0.45 + rng.randf() * 0.05))

	var hair_line := int(size * rng.randf_range(0.14, 0.30))
	for y in hair_line:
		for x in size:
			img.set_pixel(x, y, hair.darkened(rng.randf() * 0.15))
	# Sideburns, of varying commitment.
	var burn := int(size * rng.randf_range(0.30, 0.55))
	for y in range(hair_line, burn):
		for w in range(0, int(size * 0.14)):
			img.set_pixel(w, y, hair.darkened(0.1))
			img.set_pixel(size - 1 - w, y, hair.darkened(0.1))

	var eye_y := int(size * rng.randf_range(0.42, 0.50))
	var eye_dx := int(size * rng.randf_range(0.17, 0.23))
	var eye_w: int = maxi(2, int(size * 0.10))
	for side: int in [-1, 1]:
		var ex := int(size / 2) + side * eye_dx
		for dx in range(-eye_w, eye_w):
			for dy in range(-1, 2):
				var px := ex + dx
				var py := eye_y + dy
				if px >= 0 and px < size and py >= 0 and py < size:
					var is_pupil: bool = absi(dx) <= 1 and dy == 0
					img.set_pixel(px, py, Color(0.06, 0.05, 0.05) if is_pupil else Color(0.9, 0.9, 0.88))
		# Brow.
		for dx in range(-eye_w - 1, eye_w + 1):
			var bx := ex + dx
			if bx >= 0 and bx < size:
				img.set_pixel(bx, maxi(0, eye_y - 3), hair.darkened(0.05))

	var mouth_y := int(size * rng.randf_range(0.68, 0.76))
	var mouth_w := int(size * rng.randf_range(0.12, 0.20))
	for dx in range(-mouth_w, mouth_w):
		var mx := int(size / 2) + dx
		if mx >= 0 and mx < size:
			img.set_pixel(mx, mouth_y, skin.darkened(0.55))

	# Nose shadow.
	for dy in range(int(size * 0.52), int(size * 0.66)):
		img.set_pixel(int(size / 2) + 1, dy, skin.darkened(0.20))

	if rng.randf() < 0.28:  # stubble
		for y in range(mouth_y - 2, size):
			for x in size:
				if rng.randf() < 0.30:
					img.set_pixel(x, y, img.get_pixel(x, y).darkened(0.22))
	return _finish(img)


## The dominant hair colour for a given face seed, so the 3D head's hair cap
## can be tinted to match the texture without sampling it back.
static func hair_for(seed_val: int) -> Color:
	var rng := _rng(seed_val)
	rng.randi()  # consume the skin roll, keeping parity with face()
	return HAIR_TONES[rng.randi() % HAIR_TONES.size()]


static func skin_for(seed_val: int) -> Color:
	var rng := _rng(seed_val)
	return SKIN_TONES[rng.randi() % SKIN_TONES.size()]


# --- Signage -----------------------------------------------------------------

## The kiosk's own neon sign. Bright letters-ish shapes on a dark plate; it is
## the only saturated thing on the street, which is the point.
static func neon_sign(tint: Color, seed_val: int, w: int = 128, h: int = 32) -> ImageTexture:
	var rng := _rng(seed_val)
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	img.fill(Color(0.03, 0.03, 0.04))
	var x := 8
	while x < w - 10:
		var glyph_w := rng.randi_range(5, 9)
		var top := rng.randi_range(6, 9)
		var bottom := h - rng.randi_range(6, 9)
		for gy in range(top, bottom):
			img.set_pixel(x, gy, tint)
			img.set_pixel(mini(w - 1, x + glyph_w), gy, tint)
		for gx in range(x, mini(w, x + glyph_w + 1)):
			img.set_pixel(gx, top, tint)
			img.set_pixel(gx, int((top + bottom) / 2), tint.darkened(0.15))
		x += glyph_w + rng.randi_range(3, 6)
	return _finish(img)
