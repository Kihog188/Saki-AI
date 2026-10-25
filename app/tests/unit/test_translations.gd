extends GutTest
## Every tr("KEY") used in the code must have a Vietnamese text in i18n/strings.csv.

const CSV_PATH: String = "res://i18n/strings.csv"
const SCAN_DIRS: PackedStringArray = ["res://core", "res://services", "res://renderers", "res://ui", "res://modes"]


func test_every_tr_key_has_a_vietnamese_text() -> void:
	var known: Dictionary = _csv_keys()
	# Any quoted ALL_CAPS string with an underscore is a translation key: this catches
	# tr("KEY"), I18n.t("KEY") and keys returned by functions (PackRules.check_path).
	var regex := RegEx.create_from_string("\"([A-Z][A-Z0-9]*_[A-Z0-9_]+)\"")
	var missing: PackedStringArray = []
	for path: String in _script_files():
		var text: String = FileAccess.get_file_as_string(path)
		for m: RegExMatch in regex.search_all(text):
			if not known.has(m.get_string(1)):
				missing.append("%s: %s" % [path, m.get_string(1)])
	assert_eq(missing, PackedStringArray(), "keys missing in strings.csv")


func test_csv_rows_are_complete() -> void:
	var f := FileAccess.open(CSV_PATH, FileAccess.READ)
	var header: PackedStringArray = f.get_csv_line()
	assert_eq(header[0], "keys")
	assert_true(header.has("vi"))
	var line_no: int = 1
	while not f.eof_reached():
		var row: PackedStringArray = f.get_csv_line()
		line_no += 1
		if row.size() == 1 and row[0] == "":
			continue
		assert_eq(row.size(), header.size(), "line %d has the wrong number of columns" % line_no)
		assert_ne(row[header.find("vi")], "", "line %d has no Vietnamese text" % line_no)


func test_locale_is_vietnamese() -> void:
	TranslationServer.set_locale("vi")
	assert_eq(tr("APP_TITLE"), "Saki")


func _csv_keys() -> Dictionary:
	var keys: Dictionary = {}
	var f := FileAccess.open(CSV_PATH, FileAccess.READ)
	f.get_csv_line()
	while not f.eof_reached():
		var row: PackedStringArray = f.get_csv_line()
		if row.size() > 0 and row[0] != "":
			keys[row[0]] = true
	return keys


func _script_files() -> PackedStringArray:
	var out: PackedStringArray = []
	var stack: PackedStringArray = SCAN_DIRS.duplicate()
	while not stack.is_empty():
		var dir: String = stack[stack.size() - 1]
		stack.remove_at(stack.size() - 1)
		if not DirAccess.dir_exists_absolute(dir):
			continue
		for sub: String in DirAccess.get_directories_at(dir):
			stack.append(dir.path_join(sub))
		for file: String in DirAccess.get_files_at(dir):
			if file.ends_with(".gd") or file.ends_with(".tscn"):
				out.append(dir.path_join(file))
	return out
