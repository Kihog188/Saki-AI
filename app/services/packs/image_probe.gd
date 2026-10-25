class_name ImageProbe
## Reads image size from the file header WITHOUT decoding pixels, so a huge image is
## rejected before it can eat memory. Also decodes a buffer by its real format (magic
## bytes), never by trusting the file extension.


## Returns Vector2i(width, height), or Vector2i.ZERO if the data is not a PNG/JPEG/WebP.
static func size_of(data: PackedByteArray) -> Vector2i:
	match format_of(data):
		"png":
			if data.size() >= 24:
				return Vector2i(_be32(data, 16), _be32(data, 20))
		"jpg":
			return _jpeg_size(data)
		"webp":
			return _webp_size(data)
	return Vector2i.ZERO


## "png", "jpg", "webp" or "" from the magic bytes.
static func format_of(data: PackedByteArray) -> String:
	if data.size() >= 8 and data[0] == 0x89 and data[1] == 0x50 and data[2] == 0x4E and data[3] == 0x47:
		return "png"
	if data.size() >= 3 and data[0] == 0xFF and data[1] == 0xD8 and data[2] == 0xFF:
		return "jpg"
	if data.size() >= 16 and data.slice(0, 4).get_string_from_ascii() == "RIFF" \
			and data.slice(8, 12).get_string_from_ascii() == "WEBP":
		return "webp"
	return ""


## Decodes `data` into an Image (null on failure). Size limits must be checked first.
static func decode(data: PackedByteArray) -> Image:
	var img := Image.new()
	var err: int = ERR_FILE_UNRECOGNIZED
	match format_of(data):
		"png":
			err = img.load_png_from_buffer(data)
		"jpg":
			err = img.load_jpg_from_buffer(data)
		"webp":
			err = img.load_webp_from_buffer(data)
	return img if err == OK and not img.is_empty() else null


## "" if the size is within the hard limits, otherwise a Vietnamese reason.
static func check_size(file: String, size: Vector2i) -> String:
	if size == Vector2i.ZERO:
		return I18n.t("PACK_ERR_IMAGE_UNREADABLE", {"file": file})
	if size.x > PackRules.MAX_IMAGE_SIDE or size.y > PackRules.MAX_IMAGE_SIDE \
			or size.x * size.y > PackRules.MAX_IMAGE_PIXELS:
		return I18n.t("PACK_ERR_IMAGE_TOO_BIG", {"file": file, "w": size.x, "h": size.y, "max": PackRules.MAX_IMAGE_SIDE})
	return ""


static func _jpeg_size(data: PackedByteArray) -> Vector2i:
	var i: int = 2
	while i + 9 < data.size():
		if data[i] != 0xFF:
			return Vector2i.ZERO
		var marker: int = data[i + 1]
		if marker == 0xFF: # fill byte
			i += 1
			continue
		if marker == 0xD8 or marker == 0x01 or (marker >= 0xD0 and marker <= 0xD7):
			i += 2
			continue
		var length: int = (data[i + 2] << 8) | data[i + 3]
		# SOF0..SOF15 except DHT (C4), JPG (C8) and DAC (CC) carry the frame size.
		if marker >= 0xC0 and marker <= 0xCF and marker != 0xC4 and marker != 0xC8 and marker != 0xCC:
			var h: int = (data[i + 5] << 8) | data[i + 6]
			var w: int = (data[i + 7] << 8) | data[i + 8]
			return Vector2i(w, h)
		i += 2 + length
	return Vector2i.ZERO


static func _webp_size(data: PackedByteArray) -> Vector2i:
	if data.size() < 30:
		return Vector2i.ZERO
	var chunk: String = data.slice(12, 16).get_string_from_ascii()
	match chunk:
		"VP8 ":
			return Vector2i(data.decode_u16(26) & 0x3FFF, data.decode_u16(28) & 0x3FFF)
		"VP8L":
			var b0: int = data[21]
			var b1: int = data[22]
			var b2: int = data[23]
			var b3: int = data[24]
			return Vector2i(1 + (b0 | ((b1 & 0x3F) << 8)), 1 + ((b1 >> 6) | (b2 << 2) | ((b3 & 0x0F) << 10)))
		"VP8X":
			var w: int = 1 + (data[24] | (data[25] << 8) | (data[26] << 16))
			var h: int = 1 + (data[27] | (data[28] << 8) | (data[29] << 16))
			return Vector2i(w, h)
	return Vector2i.ZERO


static func _be32(data: PackedByteArray, at: int) -> int:
	return (data[at] << 24) | (data[at + 1] << 16) | (data[at + 2] << 8) | data[at + 3]
