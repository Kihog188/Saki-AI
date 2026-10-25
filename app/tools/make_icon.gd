extends SceneTree
## Renders assets/icon.svg into assets/icon.ico (16-256 px, PNG entries; Windows Vista+).
## Run again after replacing icon.svg with the real art:
##
##   godot --headless --path app -s res://tools/make_icon.gd

const SIZES: Array[int] = [16, 24, 32, 48, 64, 128, 256]
const SVG: String = "res://assets/icon.svg"
const ICO: String = "res://assets/icon.ico"


func _init() -> void:
	var svg: String = FileAccess.get_file_as_string(SVG)
	var pngs: Array[PackedByteArray] = []
	for size: int in SIZES:
		var img := Image.new()
		# The SVG is 128 px: render big enough, then downscale smoothly.
		img.load_svg_from_string(svg, maxf(1.0, size / 128.0) * 2.0)
		img.resize(size, size, Image.INTERPOLATE_LANCZOS)
		pngs.append(img.save_png_to_buffer())
	var out := PackedByteArray()
	_u16(out, 0); _u16(out, 1); _u16(out, SIZES.size())
	var offset: int = 6 + 16 * SIZES.size()
	for i: int in SIZES.size():
		var s: int = SIZES[i]
		out.append(0 if s >= 256 else s); out.append(0 if s >= 256 else s)
		out.append(0); out.append(0)
		_u16(out, 1); _u16(out, 32)
		_u32(out, pngs[i].size()); _u32(out, offset)
		offset += pngs[i].size()
	for png: PackedByteArray in pngs:
		out.append_array(png)
	var f := FileAccess.open(ICO, FileAccess.WRITE)
	f.store_buffer(out)
	f.close()
	print("wrote %s (%d bytes, sizes %s)" % [ProjectSettings.globalize_path(ICO), out.size(), SIZES])
	quit()


func _u16(b: PackedByteArray, v: int) -> void:
	b.append(v & 0xFF); b.append((v >> 8) & 0xFF)


func _u32(b: PackedByteArray, v: int) -> void:
	for i: int in 4:
		b.append((v >> (8 * i)) & 0xFF)
