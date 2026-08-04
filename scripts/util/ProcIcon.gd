class_name ProcIcon
## The game's icon, drawn rather than imported — like everything else here.
##
## It is one image described in normalised coordinates and rasterised at
## whatever size is asked for, so the 16px favicon and the 1024px store art are
## the same drawing rather than two things that have to be kept in step.
##
## The subject is the only thing this game looks like from outside: a lit hatch
## in a dark street with somebody standing at it. That has to survive being
## sixteen pixels across, which is why it is a bright rectangle in darkness with
## one dark shape in it and nothing else. Detail that only appears above 128px
## is treated as a bonus, never as the thing being read.

## Palette, taken from the game rather than invented for the icon.
const NIGHT := Color(0.020, 0.028, 0.030)
const ROAD := Color(0.055, 0.062, 0.070)
const FACADE := Color(0.075, 0.090, 0.105)
const LIGHT := Color(0.78, 0.96, 0.82)
const LIGHT_HOT := Color(0.92, 1.00, 0.93)
const FIGURE := Color(0.045, 0.055, 0.060)

## The hatch, in normalised coordinates. Everything else is placed around it.
const HATCH := Rect2(0.20, 0.30, 0.60, 0.42)


## Draws the icon at `size` × `size`. Above 64px it also gets scanlines and a
## frame; below that they would close up into mush and cost legibility.
##
## Written straight into a byte buffer rather than through `set_pixel`. At 1024
## that is a million calls across the scripting boundary, and it is the
## difference between this finishing in a second and finishing in minutes.
static func build(size: int) -> Image:
	var data := PackedByteArray()
	data.resize(size * size * 4)
	var detail := size >= 64
	var inv := 1.0 / float(size)
	# Scanlines are spaced as a fraction of the icon, not in pixels. At a fixed
	# two-pixel period a 1024px icon would carry five hundred hairlines, which
	# resolves to a flat grey wash and no scanlines at all.
	var period: int = maxi(2, int(round(float(size) / 72.0)) * 2)
	var at := 0

	for py in size:
		var v := (float(py) + 0.5) * inv
		var dark := detail and (py % period) >= (period >> 1)
		for px in size:
			var u := (float(px) + 0.5) * inv
			var c := _sample(u, v)

			if detail:
				if dark:
					c = c.darkened(0.10)
				# A frame, so it reads as a thing rather than as wallpaper when
				# it sits on a dark background in a library grid.
				var edge: float = minf(minf(u, v), minf(1.0 - u, 1.0 - v))
				if edge < 0.018:
					c = NIGHT
				elif edge < 0.032:
					c = c.lerp(FACADE, 0.55)

			data[at] = int(clampf(c.r, 0.0, 1.0) * 255.0)
			data[at + 1] = int(clampf(c.g, 0.0, 1.0) * 255.0)
			data[at + 2] = int(clampf(c.b, 0.0, 1.0) * 255.0)
			data[at + 3] = 255
			at += 4

	return Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, data)


## Colour at a point, in normalised coordinates. Written as a function of
## position rather than as a sequence of draw calls so that it resolves
## correctly at any resolution, including ones where a "1px line" is a fifth of
## a pixel.
static func _sample(u: float, v: float) -> Color:
	# Ground: the street is a shade less black than the sky, and wetter low down.
	var c := NIGHT.lerp(ROAD, smoothstep(0.72, 1.0, v))

	# The kiosk front.
	if u > 0.06 and u < 0.94 and v > 0.14:
		c = FACADE
		# A slight vertical fall-off so the box is not a flat slab.
		c = c.lerp(NIGHT, clampf((v - 0.14) * 0.55, 0.0, 0.45))

	# Light spilling out of the hatch, before the hatch itself is drawn over it.
	# Distance to the hatch rectangle, not to its centre, so the spill hugs the
	# opening's shape the way real light does.
	var d := _dist_to_rect(u, v, HATCH)
	if d > 0.0:
		var spill: float = pow(clampf(1.0 - d / 0.30, 0.0, 1.0), 2.2)
		c = c.lerp(LIGHT, spill * 0.42)
		# A puddle of it on the pavement, stretched and dimmer.
		if v > 0.72:
			var pool: float = pow(clampf(1.0 - absf(u - 0.5) / 0.42, 0.0, 1.0), 2.0)
			pool *= clampf(1.0 - (v - 0.72) / 0.24, 0.0, 1.0)
			c = c.lerp(LIGHT, pool * 0.16)

	# The hatch itself.
	if HATCH.has_point(Vector2(u, v)):
		# Brightest at the top, where the strip light is.
		var k: float = clampf((v - HATCH.position.y) / HATCH.size.y, 0.0, 1.0)
		c = LIGHT_HOT.lerp(LIGHT, k * 0.85)
		c = c.lerp(FACADE, pow(k, 2.6) * 0.30)

		if _figure(u, v):
			c = FIGURE

	return c


## Whoever is at the window: head, shoulders, body. Deliberately featureless —
## at icon size the silhouette is the whole character, and a face would only
## turn to noise.
##
## Kept small enough that light shows all the way round it. At sixteen pixels
## the reason this reads as a lit window at all is the bright margin; a figure
## sized to look right at 1024 fills that margin in and the icon goes dark.
static func _figure(u: float, v: float) -> bool:
	var x := u - 0.5
	# Head.
	if Vector2(x / 0.062, (v - 0.430) / 0.068).length() < 1.0:
		return true
	# Neck and shoulders, widening as they drop. Overlaps the head rather than
	# starting beneath it, so there is no notch where the two meet.
	if v > 0.470:
		var half: float = 0.040 + smoothstep(0.470, 0.555, v) * 0.098
		return absf(x) < half
	return false


## Signed distance from a point to a rectangle, zero inside it.
static func _dist_to_rect(u: float, v: float, r: Rect2) -> float:
	var dx: float = maxf(maxf(r.position.x - u, u - r.end.x), 0.0)
	var dy: float = maxf(maxf(r.position.y - v, v - r.end.y), 0.0)
	return sqrt(dx * dx + dy * dy)
