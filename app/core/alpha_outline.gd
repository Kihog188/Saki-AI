class_name AlphaOutline
## Builds a cheap outline of the visible pixels of an image, for the pet's mouse
## passthrough region (DisplayServer.window_set_mouse_passthrough takes ONE polygon).
##
## The outline is x-monotone: the image is cut into horizontal bands, and for each band we
## keep the leftmost and rightmost visible pixel. The polygon walks down the left edges and
## back up the right edges. Holes are filled in, which is fine for clicking a character.
## Points are normalised to 0..1 of the image size, so one outline serves any scale.

const DEFAULT_BANDS: int = 24
const ALPHA_THRESHOLD: float = 0.1


## Outline of `img` (or of its `region`), normalised to 0..1. Empty if nothing is visible.
static func from_image(img: Image, region: Rect2i = Rect2i(), bands: int = DEFAULT_BANDS) -> PackedVector2Array:
	if region.size == Vector2i.ZERO:
		region = Rect2i(Vector2i.ZERO, img.get_size())
	var w: int = region.size.x
	var h: int = region.size.y
	if w <= 0 or h <= 0:
		return PackedVector2Array()
	bands = clampi(bands, 1, h)
	# Sample at most ~64 columns and a few rows per band: this runs at load time for
	# every frame, so it must stay cheap even for big images.
	var step_x: int = maxi(1, w / 64)
	var left: PackedVector2Array = []
	var right: PackedVector2Array = []
	for b: int in bands:
		var y0: int = b * h / bands
		var y1: int = maxi(y0 + 1, (b + 1) * h / bands)
		var step_y: int = maxi(1, (y1 - y0) / 4)
		var lo: int = w
		var hi: int = -1
		for y: int in range(y0, y1, step_y):
			for x: int in range(0, w, step_x):
				if img.get_pixel(region.position.x + x, region.position.y + y).a > ALPHA_THRESHOLD:
					lo = mini(lo, x)
					break
			for x: int in range(w - 1, -1, -step_x):
				if img.get_pixel(region.position.x + x, region.position.y + y).a > ALPHA_THRESHOLD:
					hi = maxi(hi, x)
					break
		if hi < 0:
			continue
		# Widen by one sample step so the outline never cuts into visible pixels.
		var l: float = maxf(0.0, float(lo - step_x)) / w
		var r: float = minf(float(w), float(hi + 1 + step_x)) / w
		left.append(Vector2(l, float(y0) / h))
		left.append(Vector2(l, float(y1) / h))
		right.append(Vector2(r, float(y0) / h))
		right.append(Vector2(r, float(y1) / h))
	if left.is_empty():
		return PackedVector2Array()
	var poly: PackedVector2Array = left.duplicate()
	right.reverse()
	poly.append_array(right)
	return poly


## A full rectangle outline (for images without useful alpha, e.g. JPEG).
static func full_rect() -> PackedVector2Array:
	return PackedVector2Array([Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0)])


## Maps a normalised outline into `rect` (screen or local coordinates).
static func map_to_rect(outline: PackedVector2Array, rect: Rect2) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(outline.size())
	for i: int in outline.size():
		out[i] = rect.position + outline[i] * rect.size
	return out
