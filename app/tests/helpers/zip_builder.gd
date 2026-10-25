class_name TestZipBuilder
extends RefCounted
## Builds "stored" (uncompressed) zip files byte by byte, so tests can create archives
## that normal zip tools refuse to make: "../" names, symlink entries, duplicate names,
## lying size fields. Test-only.

var _entries: Array[Dictionary] = []

static var _crc_table: PackedInt64Array = []


## Adds a file. `opts`: "symlink": bool, "declared_size": int (fake uncompressed size),
## "declared_compressed": int, "method": int, "encrypted": bool.
func add(name: String, data: PackedByteArray, opts: Dictionary = {}) -> TestZipBuilder:
	_entries.append({"name": name, "data": data, "opts": opts})
	return self


func add_text(name: String, text: String, opts: Dictionary = {}) -> TestZipBuilder:
	return add(name, text.to_utf8_buffer(), opts)


func write(path: String) -> void:
	var out := PackedByteArray()
	var central := PackedByteArray()
	for e: Dictionary in _entries:
		var name_bytes: PackedByteArray = String(e["name"]).to_utf8_buffer()
		var data: PackedByteArray = e["data"]
		var opts: Dictionary = e["opts"]
		var crc: int = TestZipBuilder.crc32(data)
		var size: int = opts.get("declared_size", data.size())
		var csize: int = opts.get("declared_compressed", data.size())
		var method: int = opts.get("method", 0)
		var flags: int = 0x0800 | (1 if opts.get("encrypted", false) else 0) # UTF-8 names
		var offset: int = out.size()
		# Local file header
		_u32(out, 0x04034b50); _u16(out, 20); _u16(out, flags); _u16(out, method)
		_u16(out, 0); _u16(out, 0x21) # time, date
		_u32(out, crc); _u32(out, csize); _u32(out, size)
		_u16(out, name_bytes.size()); _u16(out, 0)
		out.append_array(name_bytes)
		out.append_array(data)
		# Central directory header
		var made_by: int = (3 << 8) | 20 # Unix, so the mode bits are meaningful
		var mode: int = 0xA1FF if opts.get("symlink", false) else 0x81A4
		_u32(central, 0x02014b50); _u16(central, made_by); _u16(central, 20); _u16(central, flags)
		_u16(central, method); _u16(central, 0); _u16(central, 0x21)
		_u32(central, crc); _u32(central, csize); _u32(central, size)
		_u16(central, name_bytes.size()); _u16(central, 0); _u16(central, 0)
		_u16(central, 0); _u16(central, 0); _u32(central, mode << 16); _u32(central, offset)
		central.append_array(name_bytes)
	var cd_offset: int = out.size()
	out.append_array(central)
	_u32(out, 0x06054b50); _u16(out, 0); _u16(out, 0)
	_u16(out, _entries.size()); _u16(out, _entries.size())
	_u32(out, central.size()); _u32(out, cd_offset); _u16(out, 0)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(out)
	f.close()


static func crc32(data: PackedByteArray) -> int:
	if _crc_table.is_empty():
		_crc_table.resize(256)
		for n: int in 256:
			var c: int = n
			for _k: int in 8:
				c = (0xEDB88320 ^ (c >> 1)) if (c & 1) else (c >> 1)
			_crc_table[n] = c
	var crc: int = 0xFFFFFFFF
	for b: int in data:
		crc = _crc_table[(crc ^ b) & 0xFF] ^ (crc >> 8)
	return crc ^ 0xFFFFFFFF


static func _u16(buf: PackedByteArray, v: int) -> void:
	buf.append(v & 0xFF); buf.append((v >> 8) & 0xFF)


static func _u32(buf: PackedByteArray, v: int) -> void:
	for i: int in 4:
		buf.append((v >> (8 * i)) & 0xFF)
