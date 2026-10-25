class_name ProcessLauncher
extends RefCounted
## Starts and stops OS processes. Tests replace it with a fake, so no test ever starts a
## real backend. This default implementation uses Godot's OS API.


## Starts `path args` without a console window, with extra environment variables.
## Returns the process id, or -1.
func start(path: String, args: PackedStringArray, env: Dictionary) -> int:
	# OS.create_process has no environment or working-directory parameter: the child
	# inherits this process's environment, so set the variables here first.
	for key: String in env:
		OS.set_environment(key, env[key])
	return OS.create_process(path, args, false)


func is_running(pid: int) -> bool:
	return pid > 0 and OS.is_process_running(pid)


## Kills the process and its children (Windows: taskkill /T /F).
func kill_tree(pid: int) -> void:
	if pid <= 0:
		return
	if OS.get_name() == "Windows":
		var out: Array = []
		OS.execute("taskkill", ["/PID", str(pid), "/T", "/F"], out, true, false)
	else:
		OS.kill(pid)
