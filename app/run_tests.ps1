# Runs the Godot unit tests (GUT) headless. Usage, from the repo root or app\:
#   powershell -ExecutionPolicy Bypass -File app\run_tests.ps1
# Set $env:GODOT to your Godot console executable if it is not at the default path.
$ErrorActionPreference = "Stop"
$godot = $env:GODOT
if (-not $godot) { $godot = "D:\App\Godot 4.7.2\Godot_v4.7.2-stable_win64_console.exe" }
if (-not (Test-Path $godot)) { Write-Error "Không tìm thấy Godot ở '$godot'. Đặt biến môi trường GODOT." }
$app = $PSScriptRoot
# Import first, so a fresh clone has its .godot cache and translation files.
& $godot --headless --path $app --import 2>&1 | Out-Null
& $godot --headless --path $app -s res://addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json
exit $LASTEXITCODE
