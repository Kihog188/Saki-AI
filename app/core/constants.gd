class_name SakiConst
## Shared names and limits used by every layer.
##
## Emotions and states are OPEN lists: these are the names the app knows about, but any
## other string coming from the backend or a pack must be accepted without crashing
## (see PackData.resolve_entry for the fallback chain).

## Version of the backend protocol this app speaks (GET /health -> protocol_version).
const PROTOCOL_VERSION: int = 1

## Emotions the backend sends today. Order is the order shown in pack previews.
const EMOTIONS: PackedStringArray = [
	"neutral", "happy", "sad", "thinking", "surprised", "embarrassed",
]
const DEFAULT_EMOTION: String = "neutral"

## App states. `listening` is reserved for voice input (later phase).
const STATE_IDLE: StringName = &"idle"
const STATE_THINKING: StringName = &"thinking"
const STATE_TALKING: StringName = &"talking"
const STATE_LISTENING: StringName = &"listening"
const STATES: PackedStringArray = ["idle", "thinking", "talking", "listening"]

## Display modes. A new mode only needs a new scene registered in main.gd.
const MODE_CHAT: StringName = &"chat"
const MODE_PET: StringName = &"pet"

## Backend connection states (EventBus.backend_state_changed).
const CONN_STARTING: StringName = &"starting"
const CONN_CONNECTING: StringName = &"connecting"
const CONN_CONNECTED: StringName = &"connected"
const CONN_DISCONNECTED: StringName = &"disconnected"
const CONN_FAILED: StringName = &"failed"

## Where the app keeps its files. user:// is %APPDATA%\Saki (see project.godot).
const SETTINGS_PATH: String = "user://app_settings.json"
const USER_PACKS_DIR: String = "user://characters"
const DEV_PACKS_DIR: String = "user://characters_dev"
const BUILTIN_PACKS_DIR: String = "res://packs"
const PACK_INDEX_FILE: String = "index.json"
const DEFAULT_PACK_ID: String = "default"

## Chat history paging.
const HISTORY_PAGE_SIZE: int = 50
## At most this many message nodes are alive in a message list; older ones are freed
## (and reloaded from the model when the user scrolls back up).
const MAX_LIVE_MESSAGES: int = 120

## Speech bubble auto-hide: BASE + PER_CHAR * length, capped at MAX (seconds).
const BUBBLE_BASE_SEC: float = 2.5
const BUBBLE_PER_CHAR_SEC: float = 0.06
const BUBBLE_MAX_SEC: float = 12.0
## Longer replies are cut in the bubble with "…xem tiếp".
const BUBBLE_MAX_CHARS: int = 180

## Seconds after the last activity before the character goes back to neutral.
const DEFAULT_IDLE_SECONDS: float = 10.0
## Length of the reaction when the pet is clicked.
const CLICK_REACTION_SEC: float = 1.5
const CLICK_REACTION_EMOTION: String = "surprised"
