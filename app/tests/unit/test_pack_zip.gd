extends GutTest
## .sakip validation (ZipInspector + PackValidator) and the importer.

const TMP: String = "user://test_tmp/zip"

var _root: String


func before_each() -> void:
	_root = TMP.path_join(str(randi()))
	DirAccess.make_dir_recursive_absolute(_root)


func after_each() -> void:
	PackFiles.remove_tree(_root)


func _manifest_text(overrides: Dictionary = {}) -> String:
	var d: Dictionary = TestPackGenerator.manifest("miku", "Miku")
	d.merge(overrides, true)
	return JSON.stringify(d)


func _good_zip() -> TestZipBuilder:
	return TestZipBuilder.new() \
		.add_text("manifest.json", _manifest_text()) \
		.add("neutral.png", TestPackGenerator.png_bytes(32, 32)) \
		.add("happy_sheet.png", TestPackGenerator.png_bytes(64, 32))


func _zip_path(name: String = "p.sakip") -> String:
	return _root.path_join(name)


func _validate(builder: TestZipBuilder) -> Dictionary:
	builder.write(_zip_path())
	return PackValidator.validate_zip(_zip_path())


func test_valid_pack() -> void:
	var r: Dictionary = _validate(_good_zip())
	assert_true(r["ok"], r["error"])
	assert_eq(r["files"].size(), 3)


func test_pack_inside_one_folder_is_accepted() -> void:
	var b := TestZipBuilder.new() \
		.add_text("miku/manifest.json", _manifest_text()) \
		.add("miku/neutral.png", TestPackGenerator.png_bytes(8, 8)) \
		.add("miku/happy_sheet.png", TestPackGenerator.png_bytes(16, 8))
	var r: Dictionary = _validate(b)
	assert_true(r["ok"], r["error"])
	assert_eq(r["prefix"], "miku/")


func test_rejections_name_file_and_rule() -> void:
	var png: PackedByteArray = TestPackGenerator.png_bytes(8, 8)
	var cases: Array = [
		[_good_zip().add("../evil.png", png), "../evil.png"],
		[_good_zip().add("/abs.png", png), "/abs.png"],
		[_good_zip().add("C:/win.png", png), "C:/win.png"],
		[_good_zip().add("a\\b.png", png), "dấu \\"],
		[_good_zip().add("script.gd", "extends Node".to_utf8_buffer()), "script.gd"],
		[_good_zip().add("scene.tscn", png), "scene.tscn"],
		[_good_zip().add("face.svg", png), "face.svg"],
		[_good_zip().add("run.exe", png), "run.exe"],
		[_good_zip().add("link.png", "neutral.png".to_utf8_buffer(), {"symlink": true}), "symlink"],
		[_good_zip().add("NEUTRAL.png", png), "bị trùng"],
		[_good_zip().add("locked.png", png, {"encrypted": true}), "mật khẩu"],
		[_good_zip().add("odd.png", png, {"method": 14}), "kiểu nén"],
		[_good_zip().add("bomb.txt", "x".to_utf8_buffer(), {"declared_size": 50 * 1048576, "declared_compressed": 1000}), "zip bomb"],
		[TestZipBuilder.new().add("neutral.png", png), "manifest.json"],
		[TestZipBuilder.new().add_text("manifest.json", _manifest_text()).add("neutral.png", png), "happy_sheet.png"],
	]
	for c: Array in cases:
		var r: Dictionary = _validate(c[0])
		assert_false(r["ok"], "should reject: " + c[1])
		assert_string_contains(r["error"], c[1])


func test_size_limits() -> void:
	var big_total := TestZipBuilder.new().add_text("manifest.json", _manifest_text())
	big_total.add("a.txt", "x".to_utf8_buffer(), {"declared_size": 60000, "declared_compressed": 60000})
	for i: int in 4:
		big_total.add("big%d.txt" % i, "x".to_utf8_buffer(), {"declared_size": 60 * 1048576, "declared_compressed": 1048576})
	assert_string_contains(_validate(big_total)["error"], "quá lớn")
	var many := _good_zip()
	for i: int in PackRules.MAX_FILES + 1:
		many.add("f%d.txt" % i, PackedByteArray([65]))
	assert_string_contains(_validate(many)["error"], "quá nhiều tệp")
	var huge_manifest := TestZipBuilder.new().add_text("manifest.json", " ".repeat(PackRules.MAX_MANIFEST_BYTES + 1))
	assert_string_contains(_validate(huge_manifest)["error"], "64 KB")


func test_not_a_zip() -> void:
	var f := FileAccess.open(_zip_path(), FileAccess.WRITE)
	f.store_string("hello, I am not a zip file at all")
	f.close()
	assert_string_contains(PackValidator.validate_zip(_zip_path())["error"], "không phải tệp zip")


func test_import_installs_optimised_copy() -> void:
	var users: String = _root.path_join("characters")
	var b := TestZipBuilder.new() \
		.add_text("manifest.json", _manifest_text()) \
		.add("neutral.png", TestPackGenerator.png_bytes(8, 8)) \
		.add("happy_sheet.png", TestPackGenerator.png_bytes(16, 8)) \
		.add_text("LICENSE.txt", "CC0")
	b.write(_zip_path())
	var importer := PackImporter.new(users, users.path_join(".thumbs"))
	var steps: Array = []
	importer.progress = func(p: float, _t: String) -> void: steps.append(p)
	var r: Dictionary = importer.import_zip(_zip_path())
	assert_true(r["ok"], r["message"])
	assert_string_contains(r["message"], "Đã nhập gói “Miku”")
	assert_true(FileAccess.file_exists(users.path_join("miku/neutral.png")))
	assert_true(FileAccess.file_exists(users.path_join("miku/LICENSE.txt")))
	assert_true(FileAccess.file_exists(r["entry"]["thumbnail"]))
	assert_eq(r["entry"]["hash"].length(), 64)
	assert_eq(r["reencoded"], 2)
	assert_eq(steps[-1], 1.0)
	# No temp folders left behind.
	for d: String in DirAccess.get_directories_at(users):
		assert_false(d.begins_with(".incoming") or d.begins_with(".old"), d)


func test_import_downscales_and_reports() -> void:
	var users: String = _root.path_join("characters")
	var big := Image.create(PackRules.IMPORT_MAX_TEXTURE + 100, 64, false, Image.FORMAT_RGBA8)
	var b := TestZipBuilder.new() \
		.add_text("manifest.json", _manifest_text()) \
		.add("neutral.png", big.save_png_to_buffer()) \
		.add("happy_sheet.png", TestPackGenerator.png_bytes(16, 8))
	b.write(_zip_path())
	var r: Dictionary = PackImporter.new(users, users.path_join(".thumbs")).import_zip(_zip_path())
	assert_true(r["ok"], r["message"])
	assert_eq(r["resized"], 1)
	assert_string_contains(r["message"], "Đã thu nhỏ 1 ảnh")
	var img := Image.load_from_file(ProjectSettings.globalize_path(users.path_join("miku/neutral.png")))
	assert_lte(img.get_width(), PackRules.IMPORT_MAX_TEXTURE)


func test_import_rejects_fake_and_oversized_images() -> void:
	var users: String = _root.path_join("characters")
	var fake := TestZipBuilder.new() \
		.add_text("manifest.json", _manifest_text()) \
		.add_text("neutral.png", "<svg onload=alert(1)>") \
		.add("happy_sheet.png", TestPackGenerator.png_bytes(16, 8))
	fake.write(_zip_path())
	var r: Dictionary = PackImporter.new(users, users.path_join(".thumbs")).import_zip(_zip_path())
	assert_false(r["ok"])
	assert_string_contains(r["message"], "neutral.png")
	# A PNG header that claims 20000 x 20000 is refused before decoding.
	var header: PackedByteArray = TestPackGenerator.png_bytes(4, 4)
	header.encode_u32(16, 0x204E0000) # big-endian 20000 = 0x00004E20
	header.encode_u32(20, 0x204E0000)
	var huge := TestZipBuilder.new() \
		.add_text("manifest.json", _manifest_text()) \
		.add("neutral.png", header) \
		.add("happy_sheet.png", TestPackGenerator.png_bytes(16, 8))
	huge.write(_zip_path())
	r = PackImporter.new(users, users.path_join(".thumbs")).import_zip(_zip_path())
	assert_false(r["ok"])
	assert_string_contains(r["message"], "20000×20000")
	assert_false(DirAccess.dir_exists_absolute(users.path_join("miku")), "nothing installed")


func test_import_refuses_default_id() -> void:
	var b := TestZipBuilder.new() \
		.add_text("manifest.json", _manifest_text({"id": "default"})) \
		.add("neutral.png", TestPackGenerator.png_bytes(8, 8)) \
		.add("happy_sheet.png", TestPackGenerator.png_bytes(16, 8))
	b.write(_zip_path())
	var users: String = _root.path_join("characters")
	var r: Dictionary = PackImporter.new(users, users.path_join(".thumbs")).import_zip(_zip_path())
	assert_false(r["ok"])
	assert_string_contains(r["message"], "default")


func test_real_deflate_zip_from_zippacker() -> void:
	var packer := ZIPPacker.new()
	packer.open(_zip_path())
	for item: Array in [["manifest.json", _manifest_text().to_utf8_buffer()], ["neutral.png", TestPackGenerator.png_bytes(8, 8)], ["happy_sheet.png", TestPackGenerator.png_bytes(16, 8)]]:
		packer.start_file(item[0])
		packer.write_file(item[1])
		packer.close_file()
	packer.close()
	var r: Dictionary = PackValidator.validate_zip(_zip_path())
	assert_true(r["ok"], r["error"])
