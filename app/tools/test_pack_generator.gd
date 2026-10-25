class_name TestPackGenerator
extends RefCounted
## Writes small, valid 2d pack folders (dev/testing tool, not used by the app itself).
## Used by tools/generate_test_packs.gd and by the pack index performance test.


## A solid-colour PNG with a darker circle, as bytes.
static func png_bytes(w: int, h: int, color: Color = Color(0.95, 0.7, 0.8)) -> PackedByteArray:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Vector2(w, h) / 2.0
	var r: float = minf(w, h) * 0.45
	for y: int in h:
		for x: int in w:
			if Vector2(x, y).distance_to(c) <= r:
				img.set_pixel(x, y, color)
	return img.save_png_to_buffer()


## Manifest dictionary for a pack with a static neutral and a 2x1 happy sheet.
static func manifest(id: String, name: String) -> Dictionary:
	return {
		"format": 1, "id": id, "name": name, "author": "generator", "version": "1.0.0",
		"type": "2d", "thumbnail": "neutral.png", "default_emotion": "neutral",
		"emotions": {
			"neutral": {"image": "neutral.png"},
			"happy": {"sheet": "happy_sheet.png", "columns": 2, "rows": 1, "fps": 4},
		},
	}


## Creates `count` packs named test-pack-000.. under `root`. Returns the ids.
static func generate(root: String, count: int, size: int = 64) -> PackedStringArray:
	DirAccess.make_dir_recursive_absolute(root)
	var neutral: PackedByteArray = png_bytes(size, size)
	var sheet: PackedByteArray = png_bytes(size * 2, size, Color(0.6, 0.8, 1.0))
	var ids: PackedStringArray = []
	for i: int in count:
		var id: String = "test-pack-%03d" % i
		var dir: String = root.path_join(id)
		DirAccess.make_dir_recursive_absolute(dir)
		_write(dir.path_join("manifest.json"), JSON.stringify(manifest(id, "Gói thử %03d" % i), "\t").to_utf8_buffer())
		_write(dir.path_join("neutral.png"), neutral)
		_write(dir.path_join("happy_sheet.png"), sheet)
		ids.append(id)
	return ids


static func _write(path: String, data: PackedByteArray) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(data)
	f.close()
