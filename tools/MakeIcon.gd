extends Node
## Writes the icon files the exporters need.
##
##   godot --headless --path . res://tools/MakeIcon.tscn
##
## The drawing itself lives in `ProcIcon` and is generated, not imported. This
## script only rasterises it at the sizes each platform wants and packs those
## into the container formats:
##
##   icon.png    the project icon, and the one to upload to a store page
##   icon.ico    Windows — embedded into the .exe at export, if rcedit is set up
##   icon.icns   macOS — written into the .app bundle by Godot's own exporter
##
## Both containers are written by hand here. They are simple enough that pulling
## in a tool to make them would be more moving parts than the twenty lines it
## takes to emit the headers, and it keeps the build to one dependency: Godot.

const OUT_DIR := "res://"
const PNG_SIZE := 1024
const ICO_SIZES := [16, 32, 48, 64, 128, 256]
## macOS chunk type per pixel size. The names are fixed by the format.
const ICNS_CHUNKS := {128: "ic07", 256: "ic08", 512: "ic09", 1024: "ic10"}


func _ready() -> void:
	print("\n=== KIOSK AT MIDNIGHT · icon ===\n")
	var failed := false

	var master := ProcIcon.build(PNG_SIZE)
	failed = _write_png(master) or failed
	failed = _write_ico() or failed
	failed = _write_icns() or failed

	print("")
	get_tree().quit(1 if failed else 0)


func _write_png(img: Image) -> bool:
	var path := OUT_DIR + "icon.png"
	var err := img.save_png(path)
	if err != OK:
		printerr("  could not write %s (error %d)" % [path, err])
		return true
	print("  icon.png   %d×%d" % [img.get_width(), img.get_height()])
	return false


## Windows .ico: a six-byte directory header, one sixteen-byte entry per size,
## then the payloads. PNG payloads are legal in .ico from Vista onward and are a
## fraction of the size of the BMP form.
func _write_ico() -> bool:
	var blobs: Array[PackedByteArray] = []
	for size: int in ICO_SIZES:
		blobs.append(ProcIcon.build(size).save_png_to_buffer())

	var out := PackedByteArray()
	out.resize(6)
	out.encode_u16(0, 0)                    # reserved
	out.encode_u16(2, 1)                    # 1 = icon
	out.encode_u16(4, ICO_SIZES.size())

	# Payloads start after the header and the whole directory.
	var offset := 6 + 16 * ICO_SIZES.size()
	for i in ICO_SIZES.size():
		var size: int = ICO_SIZES[i]
		var entry := PackedByteArray()
		entry.resize(16)
		# 256 is stored as 0 — the field is one byte and 256 does not fit.
		entry.encode_u8(0, 0 if size >= 256 else size)
		entry.encode_u8(1, 0 if size >= 256 else size)
		entry.encode_u8(2, 0)               # palette entries
		entry.encode_u8(3, 0)               # reserved
		entry.encode_u16(4, 1)              # colour planes
		entry.encode_u16(6, 32)             # bits per pixel
		entry.encode_u32(8, blobs[i].size())
		entry.encode_u32(12, offset)
		offset += blobs[i].size()
		out.append_array(entry)
	for b in blobs:
		out.append_array(b)

	return _save(OUT_DIR + "icon.ico", out,
		"icon.ico   %s" % ", ".join(ICO_SIZES.map(func(s: int) -> String: return str(s))))


## macOS .icns: the magic, the total length, then a chunk per size. Each chunk
## is a four-character type, a big-endian length *including its own eight-byte
## header*, and the PNG.
func _write_icns() -> bool:
	var body := PackedByteArray()
	var written: Array[String] = []
	for size: int in ICNS_CHUNKS:
		var png := ProcIcon.build(size).save_png_to_buffer()
		var chunk := PackedByteArray()
		chunk.append_array(String(ICNS_CHUNKS[size]).to_ascii_buffer())
		chunk.append_array(_be32(png.size() + 8))
		chunk.append_array(png)
		body.append_array(chunk)
		written.append(str(size))

	var out := PackedByteArray()
	out.append_array("icns".to_ascii_buffer())
	out.append_array(_be32(body.size() + 8))
	out.append_array(body)

	return _save(OUT_DIR + "icon.icns", out, "icon.icns  %s" % ", ".join(written))


## The .icns format is big-endian throughout, which nothing else here is.
static func _be32(value: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(4)
	b.encode_u8(0, (value >> 24) & 0xFF)
	b.encode_u8(1, (value >> 16) & 0xFF)
	b.encode_u8(2, (value >> 8) & 0xFF)
	b.encode_u8(3, value & 0xFF)
	return b


func _save(path: String, bytes: PackedByteArray, note: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		printerr("  could not write %s (error %d)" % [path, FileAccess.get_open_error()])
		return true
	f.store_buffer(bytes)
	f.close()
	print("  %s   (%d bytes)" % [note, bytes.size()])
	return false
