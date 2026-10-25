class_name WindowService
## Screen and window helpers for the display modes: multi-monitor aware placement and
## the mouse passthrough region. The math is static and tested; the rest wraps
## DisplayServer calls that only make sense with a real window.


## Usable area (without the taskbar) of every screen.
static func screens() -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	for i: int in DisplayServer.get_screen_count():
		out.append(DisplayServer.screen_get_usable_rect(i))
	return out


## Keeps `rect` if at least `min_visible` px of it (both directions) is on some screen,
## otherwise centres it on `screens[primary]` (e.g. a monitor was unplugged).
## `rect` is also shrunk to fit that screen if it is bigger.
static func fit_on_screen(rect: Rect2i, all_screens: Array[Rect2i], primary: int = 0, min_visible: int = 64) -> Rect2i:
	if all_screens.is_empty():
		return rect
	for s: Rect2i in all_screens:
		var inter: Rect2i = s.intersection(rect)
		if inter.size.x >= mini(min_visible, rect.size.x) and inter.size.y >= mini(min_visible, rect.size.y):
			# Title bar / top edge must not be above the screen, or it can't be dragged back.
			if rect.position.y < s.position.y:
				rect.position.y = s.position.y
			return rect
	var target: Rect2i = all_screens[clampi(primary, 0, all_screens.size() - 1)]
	var size := Vector2i(mini(rect.size.x, target.size.x), mini(rect.size.y, target.size.y))
	return Rect2i(target.position + (target.size - size) / 2, size)


## Where the pet goes the first time: bottom-right corner of the primary screen.
static func default_pet_position(size: Vector2i, screen: Rect2i, margin: int = 24) -> Vector2i:
	return screen.end - size - Vector2i(margin, margin)


## One polygon for window_set_mouse_passthrough: the character outline plus the speech
## bubble (if any), joined by a thin bridge so the result is a single shape.
## Empty `outline` -> the whole `fallback` rect is clickable.
static func passthrough_polygon(outline: PackedVector2Array, bubble: Rect2, fallback: Rect2) -> PackedVector2Array:
	var shape: PackedVector2Array = outline if outline.size() >= 3 else _rect_poly(fallback)
	if bubble.size.x <= 0.0 or bubble.size.y <= 0.0:
		return shape
	var top: float = INF
	var cx: float = 0.0
	for p: Vector2 in shape:
		if p.y < top:
			top = p.y
			cx = p.x
	var bridge := Rect2(cx - 10.0, bubble.end.y - 2.0, 20.0, maxf(4.0, top - bubble.end.y + 4.0))
	var merged: PackedVector2Array = _merge(_rect_poly(bubble), _rect_poly(bridge))
	merged = _merge(merged, shape)
	return merged


static func _merge(a: PackedVector2Array, b: PackedVector2Array) -> PackedVector2Array:
	var parts: Array[PackedVector2Array] = Geometry2D.merge_polygons(a, b)
	var best: PackedVector2Array = a
	var best_area: float = -1.0
	for p: PackedVector2Array in parts:
		if Geometry2D.is_polygon_clockwise(p) and parts.size() > 1:
			continue # holes come back clockwise; the outer shape is what we want
		var area: float = absf(_area(p))
		if area > best_area:
			best_area = area
			best = p
	return best


static func _area(p: PackedVector2Array) -> float:
	var a: float = 0.0
	for i: int in p.size():
		var j: int = (i + 1) % p.size()
		a += p[i].x * p[j].y - p[j].x * p[i].y
	return a * 0.5


static func _rect_poly(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
