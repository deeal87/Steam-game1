extends Node
## Cuts the individual albedo swatches out of the texture contact sheets.
##
##   godot --headless --path . tools/CutTextures.tscn
##
## The pack arrives as presentation sheets: one big image per theme, each
## showing a grid of labelled swatches with albedo, normal and roughness side by
## side. They are made to be looked at, not loaded, so the game cannot use them
## as they are — every wall would be a picture of a page of walls.
##
## This takes the albedo panel out of each one and writes it as a texture the
## game can put on a surface. Normal and roughness are ignored on purpose: the
## world is lit per vertex with roughness pinned at 1.0, which is what makes it
## look like the era it is pretending to be, and a normal map would need
## per-pixel lighting and would undo that.
##
## Two things are done to each cut:
##
##   * the border the sheet draws around every swatch is trimmed off, found
##     rather than assumed, so a slightly wrong crop rectangle self-corrects;
##   * the result is made to tile, because a swatch off a contact sheet does not
##     and a wall that does not tile shows a seam every few metres.

const SHEET_DIR := "res://art/sheets"
const OUT_DIR := "res://textures"

## sheet file -> [[name, x, y, w, h], ...] of the albedo panel of each swatch.
## Read off the sheets by eye and then trimmed to the panel edge in code.
const CUTS := {
	"street.png": [
		["asphalt", 22, 142, 126, 138],
		["pavement", 786, 142, 126, 138],
		["kerb", 1196, 142, 126, 138],
		["asphalt_wet", 404, 142, 126, 138],
		["manhole", 22, 344, 126, 138],
		["drain", 404, 344, 126, 138],
		["brick_far", 786, 344, 150, 138],
		["concrete", 1160, 344, 150, 138],
		["fence", 22, 514, 110, 130],
		["bin", 310, 514, 150, 130],
		["lamp_post", 660, 514, 90, 130],
		["lamp_head", 884, 514, 120, 130],
	],
	# Products are cut but never mirrored: a photograph of a can of cola folded
	# back on itself is not a can of cola. They go on a box the size of a fist
	# and are meant to read as one object, not as a surface.
	"products.png": [
		["item_soda", 100, 152, 64, 112],
		["item_beer", 258, 152, 64, 112],
		["item_coffee", 486, 152, 64, 112],
		["item_crisps", 568, 152, 70, 112],
		["item_smokes", 1106, 152, 76, 112],
		["item_lighter", 1286, 152, 50, 112],
		["item_noodles", 954, 358, 74, 114],
	],
	"kiosk.png": [
		["floor", 26, 112, 190, 190],
		["floor_worn", 790, 112, 190, 190],
		["wall", 1160, 112, 90, 150],
		["wall_painted", 26, 364, 185, 150],
		["shelf_wood", 790, 364, 185, 150],
		["shelf_metal", 1160, 364, 150, 150],
		["counter_front", 26, 592, 185, 150],
		["counter_top", 408, 592, 185, 150],
		["counter_side", 790, 592, 185, 150],
		["fridge", 1160, 592, 150, 150],
		["stock_floor", 26, 812, 160, 180],
		["ceiling", 330, 812, 185, 180],
	],
}


func _ready() -> void:
	Log.mute(true)
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var made := 0
	for sheet: String in CUTS:
		var img := Image.new()
		var path := SHEET_DIR.path_join(sheet)
		if img.load(path) != OK:
			printerr("cannot read %s" % path)
			continue
		for cut: Array in CUTS[sheet]:
			var piece := _cut(img, cut[1], cut[2], cut[3], cut[4])
			if piece == null:
				printerr("  %s: nothing there" % cut[0])
				continue
			# Surfaces have to tile. Objects must not be folded.
			if not str(cut[0]).begins_with("item_"):
				piece = _tileable(piece)
			var out := OUT_DIR.path_join("%s.png" % cut[0])
			if piece.save_png(out) == OK:
				print("  %-14s %3dx%-3d -> %s" % [
					cut[0], piece.get_width(), piece.get_height(), out])
				made += 1
	print("\n%d textures cut\n" % made)
	get_tree().quit(0 if made > 0 else 1)


## Crops, then walks in from each edge while the row or column is part of the
## sheet's border rather than part of the picture.
func _cut(sheet: Image, x: int, y: int, w: int, h: int) -> Image:
	x = clampi(x, 0, sheet.get_width() - 1)
	y = clampi(y, 0, sheet.get_height() - 1)
	w = mini(w, sheet.get_width() - x)
	h = mini(h, sheet.get_height() - y)
	if w < 8 or h < 8:
		return null
	var piece := sheet.get_region(Rect2i(x, y, w, h))
	var l := 0
	var r := piece.get_width() - 1
	var t := 0
	var b := piece.get_height() - 1
	while l < r and _edge_is_border(piece, l, true):
		l += 1
	while r > l and _edge_is_border(piece, r, true):
		r -= 1
	# And back off the normal map, which sits immediately to the right of every
	# albedo on these sheets. A crop estimated by eye lands a little wide about
	# half the time, and a strip of tangent-space blue baked into a wall texture
	# is unmistakable. Normal maps are the one thing here with a colour
	# signature nothing real has, so they can be found rather than avoided.
	while r > l and _is_normal_map(piece, r):
		r -= 1
	while r > l and _edge_is_border(piece, r, true):
		r -= 1
	while t < b and _edge_is_border(piece, t, false):
		t += 1
	while b > t and _edge_is_border(piece, b, false):
		b -= 1
	if r - l < 8 or b - t < 8:
		return piece
	return piece.get_region(Rect2i(l, t, r - l + 1, b - t + 1))


## A border row or column is nearly uniform and nearly black — the sheets draw a
## thin dark rule around every swatch.
func _edge_is_border(img: Image, at: int, vertical: bool) -> bool:
	var n: int = img.get_height() if vertical else img.get_width()
	var total := 0.0
	var lightest := 0.0
	for i in range(0, n, 2):
		var c: Color = img.get_pixel(at, i) if vertical else img.get_pixel(i, at)
		var l := c.r + c.g + c.b
		total += l
		lightest = maxf(lightest, l)
	var mean := total / float(maxi(1, n / 2))
	return mean < 0.16 and lightest < 0.45


## Whether a column is part of a normal map: blue well ahead of red and green,
## across most of its height. Concrete, brick, wood and rust are never that.
func _is_normal_map(img: Image, x: int) -> bool:
	var h := img.get_height()
	var bluish := 0
	var counted := 0
	for y in range(0, h, 2):
		var c := img.get_pixel(x, y)
		counted += 1
		if c.b > c.r + 0.10 and c.b > c.g + 0.06 and c.b > 0.35:
			bluish += 1
	return counted > 0 and float(bluish) / float(counted) > 0.55


## Makes a crop tile by mirroring it into a quarter of the output.
##
## Crude next to a proper offset-and-heal, and it is the right crude: it cannot
## produce a seam, it keeps the grain and the colour of the original exactly, and
## on a wall at this resolution, in this light, the symmetry does not read.
func _tileable(src: Image) -> Image:
	var w := src.get_width()
	var h := src.get_height()
	var out := Image.create(w * 2, h * 2, false, Image.FORMAT_RGB8)
	for y in h:
		for x in w:
			var c := src.get_pixel(x, y)
			out.set_pixel(x, y, c)
			out.set_pixel(w * 2 - 1 - x, y, c)
			out.set_pixel(x, h * 2 - 1 - y, c)
			out.set_pixel(w * 2 - 1 - x, h * 2 - 1 - y, c)
	return out
