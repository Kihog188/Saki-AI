# Kiến trúc app Saki (Godot)

Tài liệu cho người đọc hoặc sửa code trong `app/`. Cách cài Godot và chạy app nằm ở
[GODOT_BEGINNER.md](GODOT_BEGINNER.md). Định dạng gói nhân vật nằm ở
[PACK_GUIDE.md](PACK_GUIDE.md). Giao thức với backend nằm ở mục "Protocol" trong
[../README.md](../README.md).

Godot 4.7.2, renderer Compatibility (OpenGL/ANGLE), chỉ GDScript có khai báo kiểu. Lúc
chạy không dùng addon nào. GUT chỉ dùng để test và không có trong bản export.

## 1. Sơ đồ module

```
                 main.gd  (cửa sổ gốc: chứa chế độ hiện tại, kéo thả .sakip, thoát)
                    │
  ┌─────────────────▼──────────────────┐
  │ modes/                             │  chat_window/   pet/ (+ speech_bubble)
  │   display_mode.gd (giao diện chung)│
  └─────────────────┬──────────────────┘
                    │ dùng
  ┌─────────────────▼──────────────────┐
  │ ui/                                │  chat/ (ChatPanel, MessageList, MessageBubble,
  │   ui_context.gd (dịch vụ + hành động)│        SourcesList, ChatInput, StatusLine)
  │                                    │  character/CharacterView   panels/ (Memories,
  │                                    │  Settings, PackManager)   common/PanelWindow
  │                                    │  theme/   debug_overlay/
  └─────────────────┬──────────────────┘
                    │ dùng
  ┌─────────────────▼──────────────────┐
  │ renderers/                         │  character_renderer.gd (lớp cơ sở)
  │   renderer_registry.gd             │  sprite_2d/  placeholder/  fallback_renderer.gd
  └─────────────────┬──────────────────┘
                    │ dùng
  ┌─────────────────▼──────────────────┐
  │ services/                          │  backend/  packs/  settings/  performance/
  │                                    │  chat/ (ChatSession, MoodController)  platform/
  └─────────────────┬──────────────────┘
                    │ dùng
  ┌─────────────────▼──────────────────┐
  │ core/                              │  event_bus.gd  constants.gd (SakiConst)
  │                                    │  i18n.gd  alpha_outline.gd
  └────────────────────────────────────┘

  app.gd (autoload "App") = gốc lắp ráp: tạo mọi dịch vụ, nối chúng với nhau, tạo UiContext.
```

## 2. Các lớp và quy tắc phụ thuộc

Phụ thuộc **chỉ đi xuống**: `modes → ui → renderers → services → core`. Mỗi lớp chỉ được
dùng các lớp nằm dưới nó.

| Lớp | Chứa gì | Không được |
|---|---|---|
| `core/` | Tín hiệu chung (`EventBus`), hằng số (tên cảm xúc, trạng thái, đường dẫn, giới hạn), `I18n`, `AlphaOutline` | biết tới bất kỳ lớp nào khác |
| `services/` | Logic không có giao diện: backend, gói, cài đặt, hiệu năng, phiên chat, cửa sổ/OS | tạo node giao diện; gọi thẳng dịch vụ khác |
| `renderers/` | Vẽ nhân vật từ một `PackData` | dùng dịch vụ, autoload hay node khác |
| `ui/` | Thành phần giao diện dùng chung cho cả hai chế độ | dùng autoload `App`; biết đang ở chế độ nào |
| `modes/` | Một chế độ hiển thị: bố cục cửa sổ, ghép các thành phần `ui/` | biết tới chế độ khác |

Quy tắc cụ thể:

1. **Chỉ có hai autoload:** `EventBus` (tín hiệu) và `App` (gốc lắp ráp). Không thêm
   singleton nào khác.
2. **Chỉ `App` tạo dịch vụ.** Dịch vụ nhận thứ nó cần qua hàm khởi tạo. Ví dụ
   `BackendClient.new(bus, ws_transport, http_transport, url)` nhận cả bus lẫn transport,
   nên test truyền được bản giả vào.
3. **Dịch vụ không gọi nhau.** Khi một dịch vụ cần phản ứng với dịch vụ khác, `App` nối
   tín hiệu giữa hai bên. Ví dụ `quality_tier_changed` được nối tới
   `packs.set_max_texture_size`.
4. **UI nhận `UiContext`.** Trong đó có các dịch vụ và các hành động
   (`restart_backend`, `detect_tier`, `switch_mode`, `create_shortcut`). Thành phần UI
   không đọc autoload `App`, nên có thể đặt vào một scene trống để test.
5. **API công khai thì nhỏ và có chú thích `##`.** Tên bắt đầu bằng `_` là riêng tư theo
   quy ước.
6. **Chữ hiển thị đi qua bản dịch.** Mọi chuỗi người dùng thấy đều có khóa trong
   `i18n/strings.csv` (cột `vi`). Code tĩnh dùng `I18n.t("KHOA", {...})`, node dùng
   `tr("KHOA")`. Test `test_translations.gd` báo lỗi nếu code dùng một khóa chưa có trong
   bảng.
7. **Gói nhân vật chỉ là dữ liệu.** App không bao giờ nạp script, scene hay resource từ
   gói. Chỉ đọc JSON và ảnh, sau khi đã kiểm tra.

Kiểm tra thủ công (cả hai lệnh đều phải không in ra gì, trừ dòng chú thích `##`):

```
grep -rn "App\.\|EventBus\." --include=*.gd ui renderers services core
grep -rn "modes/\|ChatPanel\|MessageList" --include=*.gd renderers services core
```

## 3. Danh sách tín hiệu `EventBus`

Nguồn: [core/event_bus.gd](core/event_bus.gd). Dịch vụ phát tín hiệu, UI và chế độ lắng
nghe. Bus chỉ chở sự kiện ("vừa có một đoạn chữ"), không dùng để ra lệnh cho dịch vụ.

| Tín hiệu | Ai phát | Ý nghĩa |
|---|---|---|
| `backend_state_changed(state, message)` | BackendProcess, BackendClient | `SakiConst.CONN_*` và dòng trạng thái tiếng Việt |
| `llm_reachability_changed(reachable)` | BackendClient | `/health` báo mô hình (Ollama) có trả lời không |
| `turn_status(state)` | BackendClient | `"thinking"` hoặc `"searching"` |
| `turn_started(emotion, system)` | BackendClient | sự kiện `start` |
| `turn_delta(text)` | BackendClient | một đoạn chữ đang stream |
| `turn_reset()` | BackendClient | bỏ chữ đã stream (backend đang sinh lại câu trả lời) |
| `turn_ended(emotion, text, sources, system)` | BackendClient | sự kiện `end`; chữ cuối cùng là chuẩn |
| `turn_error(message)` | BackendClient | lỗi của lượt này, hoặc mất kết nối giữa lượt |
| `turn_cancelled()` | BackendClient | lượt bị dừng ("(đã dừng)") |
| `busy_changed(busy)` | BackendClient | backend đang làm một lượt |
| `character_emotion_changed(emotion)` | MoodController | nhân vật nên thể hiện cảm xúc nào |
| `character_state_changed(state)` | MoodController | `idle` / `thinking` / `talking` |
| `character_reaction(emotion, seconds)` | chế độ pet | phản ứng ngắn khi bấm vào pet |
| `active_pack_changed(pack_id)` | PackService | đã đổi gói đang dùng |
| `packs_changed()` | PackService | danh sách gói thay đổi (nhập, xóa, tải lại) |
| `pack_import_progress(progress, text)` | PackService | tiến độ nhập gói, từ 0 đến 1 |
| `pack_import_finished(ok, message)` | PackService | kết quả nhập gói |
| `memories_changed()` | ChatSession | sau khi có trả lời của `/rmb` hoặc `/fgt` |
| `history_cleared()` | ChatSession | sau `/clear` |
| `setting_changed(key, value)` | SettingsService | một cài đặt của app đã đổi |
| `quality_tier_changed(tier)` | PerformanceService | đã đổi mức chất lượng |
| `theme_changed(theme)` | App | đã đổi giao diện sáng hoặc tối |
| `mode_change_requested(mode)` | UI | yêu cầu đổi chế độ |
| `panel_requested(panel)` | UI | yêu cầu mở bảng `memories`/`settings`/`packs`/`chat` |
| `hotkey_pressed()` | BackendClient | người dùng bấm phím tắt toàn cục |
| `notice(text)` | nhiều nơi | thông báo ngắn cho người dùng |

## 4. Luồng sự kiện của một lượt chat

```
Người dùng gõ "chào" rồi Enter
  ChatInput ──submitted──▶ ChatPanel ──▶ ChatSession.send("chào")
      ChatSession thêm tin của người dùng (message_added) ──▶ MessageList vẽ bong bóng
      BackendClient.send_message()  (nếu lượt cũ còn chạy: gửi cancel, chờ tối đa 3 s)
          WebSocket ──{"type":"user_message"}──▶ backend

backend ──{"type":"status","state":"thinking"}──▶ BackendClient
  EventBus.busy_changed(true)  ──▶ PerformanceService: FPS "busy" (thấp, nhường CPU cho mô hình)
  EventBus.turn_status         ──▶ StatusLine "Saki đang suy nghĩ..."
                               ──▶ MoodController ──character_state_changed(thinking)──▶ CharacterView ──▶ renderer.set_state

backend ──start {emotion}──▶ turn_started ──▶ ChatSession tạo bong bóng của Saki
                                          ──▶ MoodController: state talking + emotion của lượt
backend ──delta {text}  ──▶ turn_delta   ──▶ ChatSession nối chữ (message_changed) ──▶ MessageBubble
backend ──reset         ──▶ turn_reset   ──▶ ChatSession xóa chữ của bong bóng hiện tại
backend ──end {text, sources}──▶ turn_ended ──▶ ChatSession đặt chữ cuối cùng + nguồn
                                            ──▶ chế độ.show_message()  (pet: bong bóng thoại)
                                            ──▶ MoodController: emotion của lượt, sau idle_seconds về neutral
  EventBus.busy_changed(false) ──▶ PerformanceService: về FPS "active", rồi "idle"
```

Lỗi, dừng và mất kết nối:
- `error` từ backend: `turn_error`, bong bóng hiện lỗi.
- Bấm Dừng: gửi `cancel`, backend đáp `cancelled`, phát `turn_cancelled`, bong bóng hiện
  "(đã dừng)". Nếu sau 3 s chưa có trả lời, app tự kết thúc lượt.
- Mất WebSocket giữa lượt: lượt kết thúc với "Mất kết nối với Saki". Sau đó app kết nối
  lại sau 1, 2, 5 rồi 10 s, và tải lại lịch sử khi đã kết nối.

## 5. Ba yêu cầu kiến trúc và cách kiểm tra

### 5.1 Modularization

| Cơ chế | Kiểm tra |
|---|---|
| Năm lớp, phụ thuộc chỉ đi xuống (mục 2) | hai lệnh `grep` ở mục 2 không in ra gì |
| Chỉ hai autoload, `App` là gốc lắp ráp duy nhất | `[autoload]` trong `project.godot` chỉ có `EventBus` và `App` |
| Transport là interface: `WsTransport`, `HttpTransport`, `ProcessLauncher` | `tests/unit/test_backend_client.gd` dùng transport giả (`tests/helpers/fakes.gd`), không đụng tới code UI |
| Thiếu bộ vẽ thì dùng bộ dự phòng | `test_renderers.gd` giả lập một thư mục bộ vẽ bị xóa: gói chuyển sang `FallbackRenderer` (ảnh thumbnail + "Loại gói này chưa được hỗ trợ") |

### 5.2 Scalability

| Cơ chế | Kiểm tra / số đo |
|---|---|
| Bảng đăng ký bộ vẽ: thêm bộ vẽ = một thư mục + một dòng (mục 6) | `RendererRegistry.RENDERERS` |
| Cache `index.json`: liệt kê gói không mở từng gói | 200 gói: danh sách mở trong 32 ms khi có cache, 2,2 s lần quét đầu (`tools/generate_test_packs.gd`) |
| Chỉ nạp gói đang dùng; đổi gói thì giải phóng texture cũ | `PackService.activate` gọi `unload()`; có test đếm texture |
| Lịch sử theo trang: 50 tin mới nhất, trang cũ khi cuộn lên, tối đa 120 node tin nhắn | `tools/message_list_bench.gd`, 1.000 tin: trung vị 16,6 ms/khung, p95 17,7 ms, không lúc nào quá 120 node |
| Mức chất lượng là dữ liệu: `services/performance/tiers/*.tres` | thêm mức = thêm một file `.tres` |
| Chế độ hiển thị độc lập, cùng một giao diện `display_mode.gd` | thêm chế độ = một script trong `modes/` + một dòng trong `main.gd` `MODES` |
| Cảm xúc và trạng thái là danh sách mở, có chuỗi dự phòng | `test_renderers.gd` / `test_pack_index.gd`: cảm xúc lạ không gây lỗi |
| Chữ hiển thị qua `tr()` | thêm tiếng Anh = thêm cột `en` vào `strings.csv` |

### 5.3 Reusability

| Cơ chế | Kiểm tra |
|---|---|
| Hai chế độ dùng chung `ChatPanel` và các bảng (mini chat của pet = `ChatPanel` với `compact = true`) | không có code vẽ tin nhắn trong `modes/` (`grep -rn "Label.new" modes` chỉ ra tên nhân vật, thông báo ngắn và bong bóng thoại của pet) |
| Bộ vẽ tự đủ | `test_renderers.gd` chạy từng bộ vẽ trong một scene trống, chỉ với một gói và một cảm xúc |
| Kiểm tra và nhập gói không phụ thuộc UI | `PackValidator`, `PackImporter` chỉ dùng `core/`; test gọi thẳng chúng |
| `BackendClient` không phụ thuộc UI | `tools/backend_smoke.gd` dùng nó không cần cửa sổ |
| Màu giao diện và mức chất lượng là `Resource` | `ui/theme/light.tres`, `dark.tres`; `tiers/*.tres` |

## 6. Thêm một bộ vẽ mới trong 5 bước

Ví dụ thêm bộ vẽ cho gói `"type": "3d-gltf"`:

1. **Tạo thư mục** `renderers/gltf/` và file `gltf_renderer.gd`, bắt đầu bằng
   `extends CharacterRenderer`.
2. **Ghi đè các hook:** `_on_pack_loaded()` (đọc `pack.manifest` và file của gói),
   `_on_display_changed()` (đổi cảm xúc hoặc trạng thái: đọc `emotion` và `state`),
   `_on_quality_changed()` (dùng `quality`: `animations`, `effects`,
   `max_texture_size`), `_on_unload()` (giải phóng mọi tài nguyên). Nếu vẽ không bằng
   `_draw()` thì thêm node con.
3. **Báo hình dạng cho chế độ pet:** ghi đè `natural_size()`, `get_visible_rect()` và
   `get_alpha_outline()`. Lớp cơ sở tự gọi `_changed()` (phát `visual_changed`) sau khi
   nạp gói hoặc đổi cảm xúc. Nếu hình còn đổi vào lúc khác, ví dụ sang khung hình tiếp
   theo, thì tự gọi `_changed()` để vùng click-through được cập nhật.
4. **Đăng ký bằng đúng một dòng** trong `renderers/renderer_registry.gd`:
   ```gdscript
   const RENDERERS: Dictionary = {
   	"2d": "res://renderers/sprite_2d/sprite_renderer.gd",
   	"placeholder": "res://renderers/placeholder/placeholder_renderer.gd",
   	"3d-gltf": "res://renderers/gltf/gltf_renderer.gd",   # dòng mới
   }
   ```
5. **Thêm test** vào `tests/unit/test_renderers.gd`: tạo bộ vẽ trong scene trống bằng
   `RendererRegistry.create("3d-gltf")`, nạp một gói mẫu, đổi cảm xúc, rồi `unload()`.
   Nếu kiểu mới có trường riêng trong manifest, kiểm tra chúng trong bộ vẽ hoặc thêm vào
   `PackManifest._read` (sau dòng `if type != "2d": return`).

Ngoài ra không phải sửa gì khác: chế độ, UI và trình quản lý gói chỉ làm việc với
`CharacterRenderer`. Xóa thư mục bộ vẽ thì gói kiểu đó tự chuyển sang `FallbackRenderer`.

## 7. Bản đồ thư mục

| Đường dẫn | Nội dung |
|---|---|
| `app.gd` | gốc lắp ráp: `boot()` / `shutdown()`, nối dịch vụ, áp giao diện |
| `main.gd`, `main.tscn` | scene chính: bảng `MODES`, `switch_mode`, kéo thả `.sakip`, thoát |
| `core/` | `event_bus.gd`, `constants.gd`, `i18n.gd`, `alpha_outline.gd` |
| `services/backend/` | `BackendProcess` (tìm repo, chạy `pythonw -m saki` ẩn, dừng), `BackendClient` (health, WebSocket, REST, kết nối lại), các transport |
| `services/packs/` | `PackRules`, `PackManifest`, `PackAutoManifest` (manifest from file names for a plain image folder), `ZipInspector`, `PackValidator`, `ImageProbe`, `PackImporter`, `PackIndex`, `PackData`, `PackService` |
| `services/settings/` | `SettingsService`: JSON có phiên bản, ghi qua file tạm, chuyển đổi định dạng cũ |
| `services/performance/` | `QualityTier`, `TierSelector`, `PerformanceService`, `tiers/*.tres` |
| `services/chat/` | `ChatSession` (mô hình tin nhắn chung), `MoodController` |
| `services/platform/` | `WindowService` (nhiều màn hình, vùng click-through), `DesktopShortcut` |
| `renderers/` | lớp cơ sở, bảng đăng ký, `sprite_2d/`, `placeholder/`, bộ dự phòng |
| `ui/` | thành phần dùng chung (mục 1) |
| `modes/` | `chat_window/`, `pet/` |
| `i18n/strings.csv` | khóa → tiếng Việt |
| `tests/` | test GUT (`unit/`) và hàm hỗ trợ (`helpers/`) |
| `tools/` | script chạy tay: tạo gói thử, smoke test backend, benchmark danh sách tin, chụp UI, tạo icon |
