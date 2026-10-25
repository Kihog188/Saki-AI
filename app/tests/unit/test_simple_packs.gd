extends GutTest
## Packs without manifest.json: a plain folder (or zip) of images named after emotions.

const TMP: String = "user://test_tmp/simple"

var _root: String
var _users: String


func before_each() -> void:
	_root = TMP.path_join(str(randi()))
	_users = _root.path_join("characters")
	DirAccess.make_dir_recursive_absolute(_users)


func after_each() -> void:
	PackFiles.remove_tree(_root)


func _png() -> PackedByteArray:
	return TestPackGenerator.png_bytes(16, 16) # transparent corners


func _opaque_png() -> PackedByteArray:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 0.8, 0.8, 1))
	return img.save_png_to_buffer()


## A folder `name` under the test root with the given files (name -> bytes).
func _folder(name: String, files: Dictionary) -> String:
	var dir: String = _root.path_join(name)
	for f: String in files:
		var path: String = dir.path_join(f)
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var out := FileAccess.open(path, FileAccess.WRITE)
		out.store_buffer(files[f])
		out.close()
	return dir


func _importer() -> PackImporter:
	return PackImporter.new(_users, _users.path_join(".thumbs"))


func _has_warning(warnings: PackedStringArray, part: String) -> bool:
	for w: String in warnings:
		if w.contains(part):
			return true
	return false


func test_folder_without_manifest_is_a_pack() -> void:
	var dir: String = _folder("Saki Hồng", {"neutral.png": _png(), "happy.png": _png(), "sad.png": _png()})
	var r: Dictionary = PackValidator.validate_folder(dir)
	assert_true(r["ok"], r["error"])
	assert_true(r["auto"])
	var m: PackManifest = r["manifest"]
	assert_eq(m.name, "Saki Hồng")
	assert_eq(m.id, "saki-hong")
	assert_eq(m.type, "2d")
	assert_eq(m.default_emotion, "neutral")
	assert_eq(m.author, "")
	assert_eq(m.emotions["happy"]["files"], PackedStringArray(["happy.png"]))
	assert_true(r["warnings"].is_empty(), str(r["warnings"]))


func test_import_folder_copies_and_writes_manifest() -> void:
	var dir: String = _folder("Saki Hồng", {"neutral.png": _png(), "happy.png": _png(), "notes.txt": "hi".to_utf8_buffer()})
	var before: PackedStringArray = DirAccess.get_files_at(dir)
	var r: Dictionary = _importer().import_folder(dir)
	assert_true(r["ok"], r["message"])
	var installed: String = _users.path_join("saki-hong")
	assert_true(FileAccess.file_exists(installed.path_join("manifest.json")))
	assert_true(FileAccess.file_exists(installed.path_join("happy.png")))
	assert_false(FileAccess.file_exists(installed.path_join("notes.txt")), "unused files are not copied")
	assert_true(FileAccess.file_exists(r["entry"]["thumbnail"]), "thumbnail from neutral")
	assert_eq(DirAccess.get_files_at(dir), before, "the source folder is not changed")
	# The installed copy is a normal pack with a manifest: the index accepts it as is.
	var index := PackIndex.new(_users, _root.path_join("dev"), _root.path_join("builtin"))
	index.refresh()
	var e: Dictionary = index.get_entry("saki-hong")
	assert_true(e["valid"], e["error"])
	assert_eq(e["name"], "Saki Hồng")


func test_zip_without_manifest_at_root_and_in_one_folder() -> void:
	var at_root := TestZipBuilder.new().add("neutral.png", _png()).add("happy.png", _png())
	at_root.write(_root.path_join("Bé Mây.sakip"))
	var r: Dictionary = PackValidator.validate_zip(_root.path_join("Bé Mây.sakip"))
	assert_true(r["ok"], r["error"])
	assert_eq((r["manifest"] as PackManifest).name, "Bé Mây", "zip name = pack name")
	assert_eq((r["manifest"] as PackManifest).id, "be-may")

	var in_folder := TestZipBuilder.new().add("Saki Hồng/neutral.png", _png()).add("Saki Hồng/sad.png", _png())
	in_folder.write(_root.path_join("x.sakip"))
	r = PackValidator.validate_zip(_root.path_join("x.sakip"))
	assert_true(r["ok"], r["error"])
	assert_eq(r["prefix"], "Saki Hồng/")
	assert_eq((r["manifest"] as PackManifest).name, "Saki Hồng", "folder name inside the zip = pack name")
	var imported: Dictionary = _importer().import_zip(_root.path_join("x.sakip"))
	assert_true(imported["ok"], imported["message"])
	assert_true(FileAccess.file_exists(_users.path_join("saki-hong/sad.png")))


func test_names_match_case_insensitively() -> void:
	var dir: String = _folder("Mixed", {"NEUTRAL.png": _png(), "Happy.PNG": _png(), "sAd.Jpg": _png()})
	var r: Dictionary = PackValidator.validate_folder(dir)
	assert_true(r["ok"], r["error"])
	var m: PackManifest = r["manifest"]
	assert_eq(m.emotions["neutral"]["files"][0], "NEUTRAL.png")
	assert_eq(m.emotions["happy"]["files"][0], "Happy.PNG", "the real file name is kept")
	assert_true(m.emotions.has("sad"))


func test_numbered_files_are_frames_and_win() -> void:
	var dir: String = _folder("Anim", {
		"neutral.png": _png(), "happy.png": _png(),
		"happy_10.png": _png(), "happy_02.png": _png(), "happy_01.png": _png(),
		"talking_1.png": _png(), "talking_2.png": _png(),
	})
	var r: Dictionary = PackValidator.validate_folder(dir)
	assert_true(r["ok"], r["error"])
	var happy: Dictionary = (r["manifest"] as PackManifest).emotions["happy"]
	assert_eq(happy["kind"], "frames")
	assert_eq(happy["files"], PackedStringArray(["happy_01.png", "happy_02.png", "happy_10.png"]))
	assert_eq(happy["fps"], 8.0)
	assert_true(happy["loop"])
	assert_eq((r["manifest"] as PackManifest).states["talking"]["frames"], 2, "talking is a state")
	assert_true(_has_warning(r["warnings"], "happy.png"), "frames win over happy.png: " + str(r["warnings"]))
	assert_false(r["files"].has("happy.png"), "happy.png is not used")


func test_missing_neutral_uses_first_image() -> void:
	var dir: String = _folder("NoNeutral", {"sad.png": _png(), "happy.png": _png()})
	var r: Dictionary = PackValidator.validate_folder(dir)
	assert_true(r["ok"], r["error"])
	var m: PackManifest = r["manifest"]
	assert_eq(m.emotions["neutral"]["files"][0], "happy.png", "first image by name")
	assert_true(_has_warning(r["warnings"], "neutral.png"))
	# A single image with any name is enough.
	r = PackValidator.validate_folder(_folder("One", {"saki.png": _png()}))
	assert_true(r["ok"], r["error"])
	assert_eq((r["manifest"] as PackManifest).emotions["neutral"]["files"][0], "saki.png")
	assert_true(r["warnings"].size() == 1, "only the neutral note, saki.png is used: " + str(r["warnings"]))


func test_unknown_files_are_ignored_with_a_warning() -> void:
	var dir: String = _folder("Extra", {
		"neutral.png": _png(), "angry.png": _png(), "ảnh 1.png": _png(),
		"readme.txt": "x".to_utf8_buffer(), "tool.gd": "extends Node".to_utf8_buffer(),
		"old/happy.png": _png(), "Thumbs.db": PackedByteArray([0]),
	})
	var r: Dictionary = PackValidator.validate_folder(dir)
	assert_true(r["ok"], r["error"])
	assert_eq(r["files"], PackedStringArray(["neutral.png"]), "only used files are read")
	assert_eq(r["warnings"].size(), 1, str(r["warnings"]))
	for name: String in ["angry.png", "ảnh 1.png", "readme.txt", "tool.gd", "old/happy.png"]:
		assert_string_contains(r["warnings"][0], name)
	assert_false(r["warnings"][0].contains("Thumbs.db"), "OS files are skipped silently")


func test_folder_without_any_image_is_rejected() -> void:
	var r: Dictionary = PackValidator.validate_folder(_folder("Empty", {"notes.txt": "x".to_utf8_buffer()}))
	assert_false(r["ok"])
	assert_string_contains(r["error"], "Không tìm thấy ảnh")
	assert_string_contains(r["error"], "manifest.json")


func test_opaque_image_warns_but_imports() -> void:
	var dir: String = _folder("Opaque", {"neutral.png": _png(), "happy.png": _opaque_png()})
	var r: Dictionary = _importer().import_folder(dir)
	assert_true(r["ok"], r["message"])
	assert_has(r["warnings"], "Ảnh happy.png chưa xóa nền, nhân vật sẽ có khung nền.")
	assert_string_contains(r["message"], "1 lưu ý")
	assert_has(r["entry"]["warnings"], "Ảnh happy.png chưa xóa nền, nhân vật sẽ có khung nền.")
	# Saved with the pack, so the pack manager still shows it after a fresh scan.
	var index := PackIndex.new(_users, _root.path_join("dev"), _root.path_join("builtin"))
	index.refresh()
	assert_has(index.get_entry("opaque")["warnings"], "Ảnh happy.png chưa xóa nền, nhân vật sẽ có khung nền.")
	# Several opaque images: one note listing them.
	var many: Dictionary = _importer().import_folder(_folder("Many", {"neutral.png": _opaque_png(), "sad.png": _opaque_png()}))
	assert_true(many["ok"], many["message"])
	assert_string_contains(many["warnings"][-1], "neutral.png, sad.png")


func test_name_collision_gets_a_unique_id() -> void:
	var dir: String = _folder("Saki Hồng", {"neutral.png": _png()})
	var first: Dictionary = _importer().import_folder(dir)
	var second: Dictionary = _importer().import_folder(dir)
	assert_true(first["ok"] and second["ok"])
	assert_eq(first["entry"]["id"], "saki-hong")
	assert_eq(second["entry"]["id"], "saki-hong-2", "an existing pack is never replaced")
	assert_true(FileAccess.file_exists(_users.path_join("saki-hong/neutral.png")))
	var reserved: Dictionary = _importer().import_folder(_folder("Default", {"neutral.png": _png()}))
	assert_true(reserved["ok"], reserved["message"])
	assert_eq(reserved["entry"]["id"], "default-2", "the built-in id is never used")


func test_manifest_still_wins_when_present() -> void:
	var manifest: Dictionary = TestPackGenerator.manifest("miku", "Miku")
	var dir: String = _folder("Some Folder", {
		"manifest.json": JSON.stringify(manifest).to_utf8_buffer(),
		"neutral.png": _png(), "happy_sheet.png": TestPackGenerator.png_bytes(32, 16),
		"sad.png": _png(),
	})
	var r: Dictionary = PackValidator.validate_folder(dir)
	assert_true(r["ok"], r["error"])
	assert_false(r["auto"])
	var m: PackManifest = r["manifest"]
	assert_eq(m.id, "miku")
	assert_eq(m.emotions["happy"]["kind"], "sheet")
	assert_false(m.emotions.has("sad"), "file names are not guessed when a manifest exists")
	# And the naming rules stay strict for manifest packs.
	_folder("Some Folder", {"bad name.png": _png()})
	assert_false(PackValidator.validate_folder(dir)["ok"])


func test_security_limits_still_apply_without_manifest() -> void:
	# Oversized image (header claims 20000 x 20000): refused before decoding.
	var header: PackedByteArray = _png()
	header.encode_u32(16, 0x204E0000)
	header.encode_u32(20, 0x204E0000)
	var r: Dictionary = _importer().import_folder(_folder("Huge", {"neutral.png": header}))
	assert_false(r["ok"])
	assert_string_contains(r["message"], "20000×20000")
	# A fake image is refused, not ignored.
	r = _importer().import_folder(_folder("Fake", {"neutral.png": "<svg onload=alert(1)>".to_utf8_buffer()}))
	assert_false(r["ok"])
	assert_string_contains(r["message"], "neutral.png")
	# Too many files.
	var many: Dictionary = {"neutral.png": _png()}
	for i: int in PackRules.MAX_FILES + 1:
		many["f%d.txt" % i] = PackedByteArray([65])
	assert_string_contains(PackValidator.validate_folder(_folder("Many", many))["error"], "quá nhiều tệp")
	# Zip rules: traversal, symlinks and zip bombs reject the pack even without a manifest.
	var png: PackedByteArray = _png()
	var cases: Array = [
		[TestZipBuilder.new().add("neutral.png", png).add("../evil.png", png), "../evil.png"],
		[TestZipBuilder.new().add("Saki Hồng/neutral.png", png).add("Saki Hồng/../../x.png", png), ".."],
		[TestZipBuilder.new().add("neutral.png", png).add("link.png", png, {"symlink": true}), "symlink"],
		[TestZipBuilder.new().add("neutral.png", png).add("bomb.txt", "x".to_utf8_buffer(), {"declared_size": 50 * 1048576, "declared_compressed": 1000}), "zip bomb"],
	]
	for c: Array in cases:
		(c[0] as TestZipBuilder).write(_root.path_join("bad.sakip"))
		var v: Dictionary = PackValidator.validate_zip(_root.path_join("bad.sakip"))
		assert_false(v["ok"], "should reject: " + c[1])
		assert_string_contains(v["error"], c[1])
	assert_eq(DirAccess.get_directories_at(_users).size(), 0, "nothing installed")


func test_hand_copied_folder_in_packs_folder_is_listed_and_loads() -> void:
	_folder("characters/Bé Mây", {"neutral.png": _png(), "happy.png": _png()})
	var index := PackIndex.new(_users, _root.path_join("dev"), _root.path_join("builtin"))
	index.refresh()
	var e: Dictionary = index.get_entry("Bé Mây")
	assert_true(e["valid"], e["error"])
	assert_eq(e["name"], "Bé Mây")
	var pack: PackData = PackService.load_pack(e, 1024)
	assert_false(pack.get_animation("happy").is_empty(), "loads without a manifest file")
	pack.unload()


func test_slug() -> void:
	assert_eq(PackAutoManifest.slug("Saki Hồng"), "saki-hong")
	assert_eq(PackAutoManifest.slug("Đường Mây!! 2"), "duong-may-2")
	assert_eq(PackAutoManifest.slug("Hồng"), "hong", "decomposed accents")
	assert_eq(PackAutoManifest.slug("!!!"), "nhan-vat")
	assert_eq(PackAutoManifest.slug("x".repeat(100)).length(), 64)
