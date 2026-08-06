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
		["item_soda", 100, 152, 64, 112, true],
		["item_beer", 258, 152, 64, 112, true],
		["item_coffee", 486, 152, 64, 112, true],
		["item_crisps", 568, 152, 70, 112, true],
		["item_smokes", 1106, 152, 76, 112, true],
		["item_lighter", 1286, 152, 50, 112, true],
		["item_noodles", 954, 358, 74, 114, true],
	],
	"industrial.png": [
		["sewer_wall_brick", 20, 138, 86, 92],
		["sewer_wall_concrete", 112, 138, 86, 92],
		["sewer_wall_wet", 296, 138, 86, 92],
		["sewer_wall_mossy", 390, 138, 86, 92],
		["sewer_wall_tile", 482, 138, 84, 92],
		["sewer_floor_wet", 778, 138, 86, 92],
		["sewer_floor_puddles", 963, 138, 86, 92],
		["sewer_floor_brick", 1425, 138, 86, 92],
		["sewer_floor_grate", 1147, 138, 86, 92],
		["corrugated_metal", 978, 340, 70, 74],
		["riveted_metal", 1055, 340, 70, 74],
		["concrete_panel", 1210, 340, 70, 74],
		["dirty_plaster", 1465, 340, 56, 74],
	],
	"furniture.png": [
		["shelf_rack_metal", 290, 158, 68, 102, true],
		["shelf_rack_wood", 375, 158, 68, 102, true],
		["counter_unit", 22, 378, 76, 106, true],
		["vending_machine", 780, 378, 74, 106, true],
		["crt_screen", 650, 378, 72, 106, true],
		["door_metal", 22, 596, 76, 108, true],
		["door_wooden", 105, 596, 76, 108, true],
		["light_fluorescent", 1128, 378, 80, 106, true],
		["light_wall", 1210, 378, 74, 106, true],
		["garbage_bin", 950, 596, 74, 108, true],
		["newspaper", 22, 816, 60, 96, true],
	],
	"weapons.png": [
		["weapon_revolver", 462, 158, 96, 96, true],
		["weapon_shotgun", 118, 158, 100, 96, true],
		["weapon_rifle", 345, 158, 106, 96, true],
		["weapon_pistol", 22, 158, 96, 96, true],
		["weapon_crowbar", 655, 158, 68, 96, true],
		["gear_flashlight", 700, 356, 74, 104, true],
		["gear_evidence_bag", 1030, 356, 92, 104, true],
		["gear_medkit", 22, 552, 92, 100, true],
		["gear_ammo_box", 1030, 552, 92, 100, true],
	],
	"signage.png": [
		["sign_kiosk", 566, 145, 66, 92, true],
		["sign_staff_only", 186, 145, 84, 90, true],
		["sign_exit", 20, 145, 84, 90, true],
		["sign_no_smoking", 272, 145, 80, 90, true],
		["sign_notice", 355, 145, 78, 90, true],
		["graffiti_a", 20, 300, 78, 86, true],
		["graffiti_b", 210, 300, 74, 86, true],
		["graffiti_c", 400, 300, 68, 86, true],
		["note_paper", 20, 678, 76, 96, true],
	],
	"props.png": [
		["pallet_wood", 22, 138, 104, 118, true],
		["cardboard", 650, 138, 104, 118, true],
		["cardboard_printed", 937, 138, 104, 118, true],
		["plastic_crate", 1225, 138, 104, 118, true],
		["milk_crate", 22, 316, 104, 118, true],
		["bucket", 650, 316, 104, 118, true],
		["garbage_bag", 22, 493, 104, 118, true],
		["wooden_board", 937, 493, 104, 118, true],
		["metal_drum", 345, 668, 104, 118, true],
		["wooden_crate", 937, 668, 104, 118, true],
		["tyres", 1225, 668, 104, 118, true],
	],
	"architecture.png": [
		["wall_concrete", 118, 136, 82, 78],
		["wall_panel_metal", 645, 136, 86, 78],
		["wall_peeling", 428, 136, 82, 78],
		["floor_concrete", 762, 136, 84, 78],
		["floor_tile", 855, 136, 82, 78],
		["ceiling_concrete", 25, 313, 86, 74],
		["ceiling_drop", 218, 313, 78, 74],
		["ceiling_beam", 535, 313, 82, 74],
	],
	"sewer.png": [
		["sewer_brick", 22, 138, 120, 132],
		["sewer_brick_damaged", 400, 138, 120, 132],
		["sewer_concrete", 778, 138, 120, 132],
		["sewer_floor", 1156, 138, 120, 132],
		["sewer_mud", 22, 334, 120, 132],
		["water", 400, 334, 120, 132],
		["water_flow", 778, 334, 120, 132],
		["pipe_metal", 20, 530, 100, 100],
		["pipe_rusted", 300, 530, 100, 100],
		["steel", 20, 694, 100, 106],
		["grate", 585, 694, 96, 106],
	],
	# The decals sheet is built for a decal projector, which this game does not
	# have and does not need one to use half of it. Two kinds of thing on it work
	# as ordinary textures: surfaces that happen to be described as damage —
	# corroded metal is just metal — and the large pieces in row 11, which go on
	# a panel standing a centimetre off a wall and read as exactly what they are.
	#
	# The blood is left where it is. It is the best art on the sheet and the game
	# has nowhere honest to put it: a handprint painted into the world is on the
	# wall of a shop on night one, before anything has happened, which tells the
	# player a story that is not theirs.
	"decals.png": [
		["metal_corroded", 363, 606, 109, 83],
		["rust_patches", 253, 606, 102, 83],
		# Tags and flyposting. Objects, so they are never folded: half a word
		# mirrored back at itself is not graffiti, it is wallpaper.
		["graffiti_large_a", 20, 755, 167, 99, true],
		["graffiti_large_b", 192, 755, 100, 99, true],
		["poster_a", 300, 755, 90, 99, true],
		["poster_b", 397, 755, 88, 99, true],
		["poster_torn", 491, 755, 91, 99, true],
	],
	# The lighting sheet is mostly reference — pictures of what the engine ought
	# to make, which the engine has to make for itself. Four things on it are
	# real textures a surface can wear, and they are four of the most useful in
	# the pack: the sky, the warning signs, a caged tunnel lamp and a monitor
	# with something on it.
	"lighting.png": [
		# Sky. Tiled, because it goes on one very large panel above the street.
		["sky_clear", 18, 746, 106, 88],
		["sky_cloudy", 132, 746, 109, 88],
		# The signs a place like this is covered in. Cleaner and far more
		# readable than the ones on the signage sheet, which are photographs of
		# signs on a wall rather than the signs themselves.
		["warn_no_smoking", 608, 894, 62, 102, true],
		["warn_wet_floor", 676, 894, 63, 102, true],
		["warn_staff_only", 746, 894, 62, 102, true],
		["warn_no_entry", 814, 894, 62, 102, true],
		["warn_danger_electric", 883, 894, 62, 102, true],
		# A caged bulkhead lamp for the tunnels, and the green box over a fire
		# door. Both cropped tight to the fitting: the panels they sit in are
		# mostly the wall behind them.
		["light_bulkhead", 495, 152, 52, 98, true],
		["sign_emergency", 587, 167, 78, 73, true],
		# Screens with something on them.
		["screen_no_signal", 258, 904, 82, 88, true],
		["screen_cctv", 356, 907, 63, 70, true],
	],
	"kiosk.png": [
		["floor", 26, 112, 190, 190],
		["floor_worn", 790, 112, 190, 190],
		["wall", 1160, 112, 90, 150],
		# The wall only. This used to run from 364 to 514, which caught the
		# caption above the swatch at one end and the skirting board and a strip
		# of floor at the other — so the shop's walls had a dark rail through
		# them at eye height, mirrored, which is the seam behind the counter that
		# would not go away however the repeat was tuned.
		["wall_painted", 28, 374, 182, 128],
		["shelf_wood", 790, 364, 185, 150],
		["shelf_metal", 1160, 364, 150, 150],
		["counter_front", 26, 592, 185, 150],
		["counter_top", 408, 592, 185, 150],
		["counter_side", 790, 592, 185, 150],
		["fridge", 1160, 592, 150, 150],
		["stock_floor", 26, 812, 160, 180],
		["ceiling", 330, 812, 185, 180],
		# The lit fitting from the presentation render rather than the swatch
		# under it. The swatch is the tube seen from the side and is nearly black;
		# this is the fitting seen from below, lit, which is the only angle a
		# player ever sees a ceiling light from.
		["light_strip", 663, 881, 250, 42, true],
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
			# Surfaces have to tile. Objects must not be folded — a crate mirrored
			# into a two-by-two is four crates, and a can of cola folded back on
			# itself is not a can of cola. The sixth column says which this is.
			if cut.size() < 6 or not bool(cut[5]):
				piece = _tileable(piece)
			var out := OUT_DIR.path_join("%s.png" % cut[0])
			if piece.save_png(out) == OK:
				_write_keep_import(out)
				print("  %-14s %3dx%-3d -> %s" % [
					cut[0], piece.get_width(), piece.get_height(), out])
				made += 1
	print("\n%d textures cut\n" % made)
	get_tree().quit(0 if made > 0 else 1)


## Writes the `.import` that stops Godot compiling this PNG into a `.ctex` and
## dropping the readable file from the build.
##
## Done here rather than by hand because it has now been forgotten twice, and
## the way it fails is silent: the game reads these with `Image.load` and falls
## back to the generator for anything missing, so an export with no textures in
## it runs perfectly and looks exactly like it did before the pack existed.
## Nothing throws. The only sign is a number in the log.
func _write_keep_import(png_path: String) -> void:
	var f := FileAccess.open(png_path + ".import", FileAccess.WRITE)
	if f == null:
		push_error("cannot write import for %s" % png_path)
		return
	f.store_string("[remap]\n\nimporter=\"keep\"\n\n[deps]\n\nfiles=[]\n\n"
		+ "source_file=\"%s\"\ndest_files=[]\n\n[params]\n\n" % png_path)
	f.close()


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
	while l < r and _is_furniture(piece, l, true):
		l += 1
	while r > l and _is_furniture(piece, r, true):
		r -= 1
	# And back off the normal map, which sits immediately to the right of every
	# albedo on these sheets. A crop estimated by eye lands a little wide about
	# half the time, and a strip of tangent-space blue baked into a wall texture
	# is unmistakable. Normal maps are the one thing here with a colour
	# signature nothing real has, so they can be found rather than avoided.
	while r > l and _is_normal_map(piece, r):
		r -= 1
	while r > l and _is_furniture(piece, r, true):
		r -= 1
	while t < b and _is_furniture(piece, t, false):
		t += 1
	while b > t and _is_furniture(piece, b, false):
		b -= 1
	if r - l < 8 or b - t < 8:
		return piece
	return piece.get_region(Rect2i(l, t, r - l + 1, b - t + 1))


## Anything at the edge of a crop that is part of the sheet rather than part of
## the picture: the rule drawn around each swatch, and the caption printed above
## it.
##
## The caption is the one that mattered. Every swatch on these sheets has its
## pixel size printed a few pixels above it — "512x512", "256x256" — and a crop
## estimated by eye lands on it about half the time. The rule test alone could
## not remove those, because it was written to *spare* rows with light pixels in
## them so it would stop at the top of a bright photograph rather than eat into
## it. So the caption survived, got mirrored by `_tileable` into all four
## corners, and the shop floor was tiled six times across with the words 512x512
## written on it. That shipped, and it is exactly the kind of thing that gets a
## pack called garbage.
func _is_furniture(img: Image, at: int, vertical: bool) -> bool:
	return _edge_is_border(img, at, vertical) or _edge_is_caption(img, at, vertical)


## A caption row: mostly the sheet's black background, with something white in
## it. That is text, and on these sheets text at the edge of a crop is always
## the swatch's pixel size printed above it.
##
## The white is what makes this safe. The darkest photographs in the pack — the
## sewer walls, a stack of tyres — are dark all the way across and never contain
## a pixel anywhere near white; the brightest thing in a row of tyres is about a
## fifth of the way up. So "70% black and something at 1.2 out of 3" cannot
## match a photograph, and matches every caption on every sheet.
func _edge_is_caption(img: Image, at: int, vertical: bool) -> bool:
	var n: int = img.get_height() if vertical else img.get_width()
	if n <= 0:
		return false
	var black := 0
	var lightest := 0.0
	for i in n:
		var c: Color = img.get_pixel(at, i) if vertical else img.get_pixel(i, at)
		var l := c.r + c.g + c.b
		if l < 0.20:
			black += 1
		lightest = maxf(lightest, l)
	return float(black) / float(n) > 0.70 and lightest > 1.2


## A border row or column: dark, and flat.
##
## Two tests rather than one because the gap between a caption and the swatch
## below it is not quite as black as the rule around the swatch, and the first
## test was written for the rule. The second is looser about the average and
## much stricter about the brightest pixel, which is the pair of conditions that
## separates a strip of empty card from a very dark photograph: the card has
## nothing in it, and the photograph always has something.
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
	return (mean < 0.16 and lightest < 0.45) or (mean < 0.22 and lightest < 0.30)


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
