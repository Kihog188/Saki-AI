class_name DesktopShortcut
## "Tạo lối tắt Desktop": a Windows .lnk to the exported Saki.exe, with its icon, created by
## a generated PowerShell command (WScript.Shell). Only for the exported app: from the
## editor the running program is Godot itself, not Saki.exe.


## True when there is an exported Saki.exe to point at.
static func available() -> bool:
	return OS.get_name() == "Windows" and OS.has_feature("template")


## Creates Saki.lnk on the user's Desktop. Returns {"ok": bool, "message": String}.
static func create() -> Dictionary:
	if not available():
		return {"ok": false, "message": I18n.t("SETTINGS_SHORTCUT_UNAVAILABLE")}
	var exe: String = OS.get_executable_path()
	var script: String = DesktopShortcut.build_script(exe, "Saki")
	var out: Array = []
	var code: int = OS.execute("powershell.exe", ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command", script], out, true, false)
	if code != 0:
		push_warning("Shortcut creation failed (%d): %s" % [code, "".join(out)])
		return {"ok": false, "message": I18n.t("SHORTCUT_FAILED")}
	return {"ok": true, "message": I18n.t("SHORTCUT_CREATED")}


## The PowerShell command. Paths are single-quoted with ' doubled, so any path is safe.
static func build_script(exe_path: String, name: String) -> String:
	var exe: String = _ps_quote(exe_path.replace("/", "\\"))
	var dir: String = _ps_quote(exe_path.get_base_dir().replace("/", "\\"))
	return ("$d = [Environment]::GetFolderPath('Desktop'); "
		+ "$s = (New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path $d %s)); " % _ps_quote(name + ".lnk")
		+ "$s.TargetPath = %s; $s.WorkingDirectory = %s; $s.IconLocation = %s; " % [exe, dir, _ps_quote(exe_path.replace("/", "\\") + ",0")]
		+ "$s.Description = 'Saki'; $s.Save()")


static func _ps_quote(s: String) -> String:
	return "'" + s.replace("'", "''") + "'"
