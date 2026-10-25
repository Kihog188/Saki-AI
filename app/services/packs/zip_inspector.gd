class_name ZipInspector
## Reads the central directory of a zip file WITHOUT extracting anything.
##
## Godot's ZIPReader does not expose declared sizes, symlink flags or encryption, and it
## silently merges duplicate names, so the pack validator needs this to check a .sakip
## before a single byte is inflated. Only what the validator needs is parsed.
##
## inspect(path) -> {"error": "" or translation key, "entries": Array[Dictionary]}
## Each entry: {"name": String, "compressed": int, "uncompressed": int, "method": int,
##              "is_dir": bool, "is_symlink": bool, "encrypted": bool}

const SIG_EOCD: int = 0x06054b50
const SIG_CENTRAL: int = 0x02014b50
const SIG_ZIP64_LOCATOR: int = 0x07064b50
const EOCD_MIN_SIZE: int = 22
const MAX_COMMENT: int = 0xFFFF
## Host systems in "version made by" whose external attributes carry Unix mode bits.
const HOST_UNIX: int = 3
const HOST_OSX: int = 19
const S_IFMT: int = 0xF000
const S_IFLNK: int = 0xA000
const FLAG_ENCRYPTED: int = 0x1


static func inspect(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"error": "PACK_ERR_ZIP_OPEN", "entries": []}
	var size: int = f.get_length()
	if size < EOCD_MIN_SIZE:
		return {"error": "PACK_ERR_ZIP_CORRUPT", "entries": []}
	# The end-of-central-directory record is in the last 22 + 65535 bytes.
	var tail_len: int = mini(size, EOCD_MIN_SIZE + MAX_COMMENT)
	f.seek(size - tail_len)
	var tail: PackedByteArray = f.get_buffer(tail_len)
	var eocd: int = -1
	for i: int in range(tail_len - EOCD_MIN_SIZE, -1, -1):
		if tail.decode_u32(i) == SIG_EOCD:
			eocd = i
			break
	if eocd < 0:
		return {"error": "PACK_ERR_ZIP_CORRUPT", "entries": []}
	if eocd >= 20 and tail.decode_u32(eocd - 20) == SIG_ZIP64_LOCATOR:
		return {"error": "PACK_ERR_ZIP64", "entries": []}
	var disk: int = tail.decode_u16(eocd + 4)
	var count: int = tail.decode_u16(eocd + 10)
	var cd_size: int = tail.decode_u32(eocd + 12)
	var cd_offset: int = tail.decode_u32(eocd + 16)
	if disk != 0:
		return {"error": "PACK_ERR_ZIP_MULTIDISK", "entries": []}
	if count == 0xFFFF or cd_offset == 0xFFFFFFFF:
		return {"error": "PACK_ERR_ZIP64", "entries": []}
	if cd_offset + cd_size > size:
		return {"error": "PACK_ERR_ZIP_CORRUPT", "entries": []}

	f.seek(cd_offset)
	var cd: PackedByteArray = f.get_buffer(cd_size)
	var entries: Array[Dictionary] = []
	var pos: int = 0
	for _i: int in count:
		if pos + 46 > cd.size() or cd.decode_u32(pos) != SIG_CENTRAL:
			return {"error": "PACK_ERR_ZIP_CORRUPT", "entries": []}
		var made_by: int = cd.decode_u16(pos + 4)
		var flags: int = cd.decode_u16(pos + 8)
		var method: int = cd.decode_u16(pos + 10)
		var compressed: int = cd.decode_u32(pos + 20)
		var uncompressed: int = cd.decode_u32(pos + 24)
		var name_len: int = cd.decode_u16(pos + 28)
		var extra_len: int = cd.decode_u16(pos + 30)
		var comment_len: int = cd.decode_u16(pos + 32)
		var ext_attr: int = cd.decode_u32(pos + 38)
		if pos + 46 + name_len > cd.size():
			return {"error": "PACK_ERR_ZIP_CORRUPT", "entries": []}
		var name: String = cd.slice(pos + 46, pos + 46 + name_len).get_string_from_utf8()
		var host: int = made_by >> 8
		var unix_mode: int = (ext_attr >> 16) & 0xFFFF
		entries.append({
			"name": name,
			"compressed": compressed,
			"uncompressed": uncompressed,
			"method": method,
			"is_dir": name.ends_with("/"),
			"is_symlink": (host == HOST_UNIX or host == HOST_OSX) and (unix_mode & S_IFMT) == S_IFLNK,
			"encrypted": (flags & FLAG_ENCRYPTED) != 0,
		})
		pos += 46 + name_len + extra_len + comment_len
	return {"error": "", "entries": entries}
