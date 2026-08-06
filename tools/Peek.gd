extends Node
## Cuts one rectangle out of a contact sheet and writes it somewhere you can
## look at it.
##
##   godot --headless --path . tools/Peek.tscn -- \
##       --sheet=kiosk.png --rect=26,364,185,150 --out=/tmp/peek.png
##
## Exists because every wrong crop in this pack has been argued about from a
## thumbnail of the whole sheet, where four pixels of caption is smaller than
## one pixel of thumbnail. `--pad` widens the rectangle so the crop can be seen
## in context, which is the only way to tell whether an edge is the border of a
## swatch or the top of the next one.


func _ready() -> void:
	Log.mute(true)
	var sheet := ""
	var rect := Rect2i(0, 0, 128, 128)
	var out := "user://peek.png"
	var pad := 0
	var scale := 1
	for arg: String in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if arg.begins_with("--sheet="):
			sheet = arg.substr(8)
		elif arg.begins_with("--rect="):
			var p := arg.substr(7).split(",")
			if p.size() >= 4:
				rect = Rect2i(int(p[0]), int(p[1]), int(p[2]), int(p[3]))
		elif arg.begins_with("--out="):
			out = arg.substr(6)
		elif arg.begins_with("--pad="):
			pad = int(arg.substr(6))
		elif arg.begins_with("--scale="):
			scale = maxi(1, int(arg.substr(8)))

	var img := Image.new()
	var path := "res://art/sheets/".path_join(sheet)
	if img.load(path) != OK:
		printerr("cannot read %s" % path)
		get_tree().quit(1)
		return

	rect = rect.grow(pad)
	rect.position.x = clampi(rect.position.x, 0, img.get_width() - 1)
	rect.position.y = clampi(rect.position.y, 0, img.get_height() - 1)
	rect.size.x = mini(rect.size.x, img.get_width() - rect.position.x)
	rect.size.y = mini(rect.size.y, img.get_height() - rect.position.y)

	var piece := img.get_region(rect)

	# Row-by-row numbers for the first and last few lines of the crop. The
	# cutter decides what to trim from exactly these three figures, and reading
	# them off a magnified picture is guesswork.
	if OS.get_cmdline_user_args().has("--stats"):
		print("[peek] rows of %s" % str(rect))
		for row: int in _edge_rows(piece.get_height()):
			var black := 0
			var total := 0.0
			var lightest := 0.0
			for x in piece.get_width():
				var c := piece.get_pixel(x, row)
				var l := c.r + c.g + c.b
				total += l
				lightest = maxf(lightest, l)
				if l < 0.20:
					black += 1
			print("  y%-4d mean %.3f  lightest %.3f  black %.0f%%" % [
				row, total / float(piece.get_width()), lightest,
				100.0 * float(black) / float(piece.get_width())])

	if scale > 1:
		piece.resize(piece.get_width() * scale, piece.get_height() * scale,
			Image.INTERPOLATE_NEAREST)
	if piece.save_png(out) != OK:
		printerr("cannot write %s" % out)
		get_tree().quit(1)
		return
	print("[peek] %s %s -> %s (%dx%d)" % [
		sheet, str(rect), out, piece.get_width(), piece.get_height()])
	get_tree().quit(0)


static func _edge_rows(h: int) -> Array[int]:
	var rows: Array[int] = []
	for i in mini(8, h):
		rows.append(i)
	for i in range(maxi(0, h - 8), h):
		if not rows.has(i):
			rows.append(i)
	return rows
