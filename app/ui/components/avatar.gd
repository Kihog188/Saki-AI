class_name SakiAvatar
extends TextureRect
## Small round picture of the character, shown next to its chat messages. One reusable
## piece: today it always shows DEFAULT_PATH; a pack can pass its own image later
## (set_image_path).
##
## The round mask is baked into the texture once per (image, size) and the texture is
## shared, so a long chat does not hold one copy per message, and no shader is needed.
## avatar.png is imported as an Image (not a texture): reading its pixels needs no GPU
## read-back, which also works in headless tests.

const DEFAULT_PATH: String = "res://assets/avatar.png"
const SIZE: int = 32
## The texture is made at this multiple of the display size so it stays sharp on scaled
## displays; the TextureRect scales it down.
const OVERSAMPLE: int = 2

static var _cache: Dictionary = {} # "path@px" -> Texture2D (null = could not load)


func _init(p_size: int = SIZE) -> void:
	custom_minimum_size = Vector2(p_size, p_size)
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_image_path(DEFAULT_PATH)


func set_image_path(path: String) -> void:
	texture = SakiAvatar.round_texture(path, int(custom_minimum_size.x) * OVERSAMPLE)


## The image at `path`, cropped to a centred square, `px` wide, with a round alpha mask
## (1 px soft edge). Cached; null if the image cannot be loaded.
static func round_texture(path: String, px: int) -> Texture2D:
	var key: String = "%s@%d" % [path, px]
	if _cache.has(key):
		return _cache[key]
	var img: Image = null
	if ResourceLoader.exists(path):
		var res: Resource = load(path)
		if res is Image:
			img = res as Image
		elif res is Texture2D:
			img = (res as Texture2D).get_image()
	var tex: Texture2D = null
	if img != null and not img.is_empty():
		tex = ImageTexture.create_from_image(SakiAvatar.round_image(img, px))
	else:
		push_warning("Avatar image not found: %s" % path)
	_cache[key] = tex
	return tex


## A new `px` x `px` image: the centred square of `img`, outside the circle transparent.
static func round_image(img: Image, px: int) -> Image:
	var out: Image = img.duplicate() as Image
	if out.is_compressed():
		out.decompress()
	out.convert(Image.FORMAT_RGBA8)
	var side: int = mini(out.get_width(), out.get_height())
	out = out.get_region(Rect2i((out.get_width() - side) / 2, (out.get_height() - side) / 2, side, side))
	out.resize(px, px, Image.INTERPOLATE_LANCZOS)
	var radius: float = px / 2.0
	for y: int in px:
		for x: int in px:
			var d: float = Vector2(x + 0.5, y + 0.5).distance_to(Vector2(radius, radius))
			var c: Color = out.get_pixel(x, y)
			c.a *= clampf(radius - d, 0.0, 1.0)
			out.set_pixel(x, y, c)
	return out
