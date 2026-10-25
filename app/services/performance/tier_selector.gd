class_name TierSelector
## Picks a quality tier from measurements. Pure function, no engine state: tested directly.
##
## Each measurement can only LOWER the result (the weakest part of the machine wins):
##   free RAM  < 1024 MB -> low,   < 2048 MB -> at most medium
##   GPU       software renderer -> low,   old Intel iGPU (HD 2000-4600, GMA) -> at most medium
##   frame time of a short benchmark  > 40 ms -> low,  > 22 ms -> at most medium
## (vsync caps the benchmark at about 16.7 ms, so the thresholds are above that.)

const RAM_LOW_MB: float = 1024.0
const RAM_MEDIUM_MB: float = 2048.0
const FRAME_LOW_MS: float = 40.0
const FRAME_MEDIUM_MS: float = 22.0

const SOFTWARE_GPUS: PackedStringArray = ["llvmpipe", "softpipe", "swiftshader", "microsoft basic render"]
const WEAK_GPU_PATTERNS: PackedStringArray = [
	"hd graphics 2000", "hd graphics 2500", "hd graphics 3000", "hd graphics 4000",
	"hd graphics 4200", "hd graphics 4400", "hd graphics 4600", "hd graphics 5000",
	"gma", "hd graphics (", "intel(r) hd graphics family",
]


## Returns "low", "medium" or "high". Pass a negative value for an unknown measurement.
static func select(free_ram_mb: float, adapter_name: String, frame_ms: float) -> String:
	var rank: int = 2
	if free_ram_mb >= 0.0:
		if free_ram_mb < RAM_LOW_MB:
			rank = 0
		elif free_ram_mb < RAM_MEDIUM_MB:
			rank = mini(rank, 1)
	var gpu: String = adapter_name.to_lower()
	for s: String in SOFTWARE_GPUS:
		if gpu.contains(s):
			rank = 0
	for w: String in WEAK_GPU_PATTERNS:
		if gpu.contains(w):
			rank = mini(rank, 1)
	if frame_ms >= 0.0:
		if frame_ms > FRAME_LOW_MS:
			rank = 0
		elif frame_ms > FRAME_MEDIUM_MS:
			rank = mini(rank, 1)
	return ["low", "medium", "high"][rank]


## Which FPS cap applies now. `minimized` wins, then busy, then active, then idle.
## Returns 0 for "stop rendering" (minimized chat window).
static func target_fps(tier: QualityTier, minimized: bool, busy: bool, active: bool) -> int:
	if minimized:
		return 0
	if busy:
		return tier.busy_fps
	if active:
		return tier.active_fps
	return tier.idle_fps
