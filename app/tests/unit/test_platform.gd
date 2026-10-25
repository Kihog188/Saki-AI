extends GutTest
## Desktop shortcut command (never run here: tests must not touch the Desktop).


func test_shortcut_script_quotes_paths() -> void:
	var s: String = DesktopShortcut.build_script("C:/Program Files/Saki's App/Saki.exe", "Saki")
	assert_string_contains(s, "GetFolderPath('Desktop')")
	assert_string_contains(s, "$s.TargetPath = 'C:\\Program Files\\Saki''s App\\Saki.exe'")
	assert_string_contains(s, "$s.WorkingDirectory = 'C:\\Program Files\\Saki''s App'")
	assert_string_contains(s, "$s.IconLocation = 'C:\\Program Files\\Saki''s App\\Saki.exe,0'")
	assert_string_contains(s, "(Join-Path $d 'Saki.lnk')")


func test_shortcut_unavailable_in_editor_runs() -> void:
	assert_false(DesktopShortcut.available(), "tests run in the editor binary, not the exported exe")
	var r: Dictionary = DesktopShortcut.create()
	assert_false(r["ok"])
	assert_string_contains(r["message"], ".exe")
