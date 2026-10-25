extends CharacterRenderer
## Renderer for packs of type "2d": static images, sprite sheets and frame lists.
## Plays the animation chosen by PackData.get_animation (fallback chain included). If the
## pack has nothing usable, it draws the placeholder face instead of crashing.

var _anim: Dictionary = {}
var _frame: int = 0
var _elapsed: float = 0.0
var _fallback: CharacterRenderer = null


func _ready() -> void:
	set_process(false)


func natural_size() -> Vector2:
	var tex: Texture2D = _current_texture()
	if tex == null:
		return super.natural_size()
	return tex.get_size() * (pack.manifest.base_scale if pack != null else 1.0)


func get_alpha_outline() -> PackedVector2Array:
	if _anim.is_empty():
		return _fallback.get_alpha_outline() if _fallback != null else super.get_alpha_outline()
	var outlines: Array = _anim.get("outlines", [])
	var outline: PackedVector2Array = outlines[_frame] if _frame < outlines.size() else AlphaOutline.full_rect()
	return AlphaOutline.map_to_rect(outline, get_visible_rect())


func _on_pack_loaded() -> void:
	_pick_animation()


func _on_display_changed() -> void:
	_pick_animation()
	if _fallback != null:
		_fallback.set_emotion(emotion)
		_fallback.set_state(state)


func _on_quality_changed() -> void:
	_update_processing()
	if _fallback != null:
		_fallback.set_quality(quality)


func _on_unload() -> void:
	_anim = {}
	set_process(false)
	if _fallback != null:
		_fallback.unload()


func _pick_animation() -> void:
	var next: Dictionary = pack.get_animation(emotion, state) if pack != null else {}
	if next.get("name", "") != _anim.get("name", "") or next.is_empty():
		_anim = next
		_frame = 0
		_elapsed = 0.0
	_use_fallback(_anim.is_empty())
	_update_processing()


## The placeholder face as a child, when the pack has nothing to show.
func _use_fallback(on: bool) -> void:
	if on and _fallback == null:
		_fallback = RendererRegistry.create("placeholder")
		if _fallback == null:
			return # placeholder renderer removed: draw nothing
		_fallback.set_anchors_preset(Control.PRESET_FULL_RECT)
		_fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_fallback)
		_fallback.set_quality(quality)
		_fallback.set_emotion(emotion)
		_fallback.set_state(state)
	elif not on and _fallback != null:
		_fallback.queue_free()
		_fallback = null


func _update_processing() -> void:
	var frames: Array = _anim.get("frames", [])
	set_process(frames.size() > 1 and animations_enabled())


func _process(delta: float) -> void:
	var frames: Array = _anim.get("frames", [])
	var fps: float = _anim.get("fps", 8.0)
	_elapsed += delta
	var step: float = 1.0 / maxf(fps, 0.5)
	if _elapsed < step:
		return
	_elapsed = fmod(_elapsed, step)
	var next: int = _frame + 1
	if next >= frames.size():
		if not _anim.get("loop", true):
			set_process(false)
			return
		next = 0
	_frame = next
	_changed()


func _current_texture() -> Texture2D:
	var frames: Array = _anim.get("frames", [])
	return frames[_frame] if _frame < frames.size() else null


func _draw() -> void:
	var tex: Texture2D = _current_texture()
	if tex != null:
		draw_texture_rect(tex, get_visible_rect(), false)
