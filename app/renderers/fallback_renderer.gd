class_name FallbackRenderer
extends CharacterRenderer
## Used when no renderer exists for a pack's type (e.g. a future "3d-gltf" pack, or a
## renderer folder that was deleted). Shows the pack thumbnail and, for unknown types, the
## notice "Loại gói này chưa được hỗ trợ". Part of the renderer base: never delete it.

## True: the pack type is not supported (show the notice). False: placeholder stand-in.
var unsupported: bool = false

var _thumb: Texture2D = null
var _label: Label = null


func _ready() -> void:
	if unsupported:
		_label = Label.new()
		_label.text = tr("RENDERER_UNSUPPORTED")
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_label)


func natural_size() -> Vector2:
	return _thumb.get_size() * 2.0 if _thumb != null else Vector2(200, 200)


func _on_pack_loaded() -> void:
	_thumb = null
	if pack == null:
		return
	var path: String = pack.entry.get("thumbnail", "")
	if path == "":
		return
	if path.begins_with("res://"):
		_thumb = load(path) as Texture2D if ResourceLoader.exists(path) else null
	elif FileAccess.file_exists(path):
		# Thumbnails are written by the app itself (PackIndex), but decode safely anyway.
		var data: PackedByteArray = FileAccess.get_file_as_bytes(path)
		if ImageProbe.check_size(path.get_file(), ImageProbe.size_of(data)) == "":
			var img: Image = ImageProbe.decode(data)
			if img != null:
				_thumb = ImageTexture.create_from_image(img)


func _on_unload() -> void:
	_thumb = null


func _draw() -> void:
	var rect: Rect2 = get_visible_rect()
	if _thumb != null:
		draw_texture_rect(_thumb, rect, false)
		return
	# No thumbnail: a plain rounded shape so the window is never empty.
	var c: Vector2 = rect.get_center()
	var r: float = minf(rect.size.x, rect.size.y) * 0.4
	draw_circle(c, r, Color(0.85, 0.85, 0.9, 0.9))
	draw_arc(c, r, 0.0, TAU, 48, Color(0.4, 0.4, 0.5), 3.0, true)
