# Godot cho người mới: chạy, test và đóng gói app Saki

Từng bước từ máy chưa có Godot tới khi có `Saki.exe` và lối tắt trên Desktop. Mọi lệnh
dùng PowerShell và chạy từ thư mục gốc của repo (ví dụ `D:\BOT\Saki`).

## 1. Cài đúng phiên bản Godot

App dùng **Godot 4.7.2-stable, bản thường (không phải .NET/Mono)**. Bản khác có thể
mở được nhưng không được kiểm tra.

1. Vào https://godotengine.org/download/archive/4.7.2-stable/ và tải
   **Windows 64-bit** (`Godot_v4.7.2-stable_win64.exe.zip`).
2. Giải nén vào một thư mục cố định, ví dụ `D:\App\Godot 4.7.2\`. Godot không cần cài:
   trong zip có hai file.
   - `Godot_v4.7.2-stable_win64.exe`: trình soạn thảo, dùng hằng ngày.
   - `Godot_v4.7.2-stable_win64_console.exe`: cùng chương trình nhưng có cửa sổ console
     để xem log. Script test dùng file này.
3. Nếu bạn đặt Godot ở thư mục khác `D:\App\Godot 4.7.2\`, khai báo cho script test:
   ```powershell
   [Environment]::SetEnvironmentVariable("GODOT", "E:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe", "User")
   ```
   Sau đó mở lại PowerShell.

App cũng cần **backend Python** của repo. Làm theo phần cài đặt trong
[../README.md](../README.md): tạo `.venv` rồi `pip install -r requirements.txt`. App tự
chạy `.venv\Scripts\pythonw.exe -m saki` ẩn, nên bạn không phải mở backend bằng tay.
Muốn trò chuyện thật thì Ollama phải đang chạy và có mô hình `saki` (xem README).

## 2. Mở project

1. Chạy `Godot_v4.7.2-stable_win64.exe`. Cửa sổ **Project Manager** hiện ra.
2. Bấm **Import**, chọn file `app\project.godot` trong repo, rồi **Import & Edit**.
3. Lần đầu Godot import ảnh và bản dịch (thanh tiến độ ở dưới), mất vài giây. Thư mục
   `app\.godot\` được tạo ra. Đó là cache, không có trong git, xóa lúc nào cũng được.

Một vài chỗ trong trình soạn thảo:
- **FileSystem** (góc dưới trái): các file của project. `res://` là thư mục `app\`.
- **Scene** (góc trên trái) và khung giữa: scene đang mở. Scene chính là `main.tscn`.
- **Output** (dưới cùng): log và lỗi khi chạy.
- **GUT** (tab dưới cùng): chạy test ngay trong trình soạn thảo.
- Bấm vào một file `.gd` để mở trình sửa code. Chú thích `##` của mỗi lớp giải thích lớp
  đó làm gì. Cách tổ chức code nằm ở [ARCHITECTURE.md](ARCHITECTURE.md).

## 3. Chạy app

- Trong trình soạn thảo: bấm **▶ Run Project** (hoặc **F5**) ở góc trên phải.
- Không mở trình soạn thảo:
  ```powershell
  & "D:\App\Godot 4.7.2\Godot_v4.7.2-stable_win64.exe" --path app
  ```

Khi chạy, app sẽ:
1. Tìm thư mục backend: theo thứ tự, thư mục đã lưu, thư mục của project hoặc `.exe`, và
   tối đa 4 cấp thư mục cha. Nếu không thấy, dòng trạng thái hiện **Chọn thư mục...** để
   bạn trỏ tới repo.
2. Chạy backend ẩn ở cổng 8765. Nếu cổng đó đã có một Saki đang chạy, app dùng luôn Saki
   đó.
3. Kết nối, tải lịch sử, rồi mở chế độ dùng lần trước (lần đầu là cửa sổ chat).

Đóng app thì backend do app khởi động cũng được tắt: trước hết nhẹ nhàng qua
`POST /shutdown`, sau 3 s thì `taskkill`. Backend bạn tự mở thì app để nguyên.

Phím hay dùng:
- **F3**: bật/tắt bảng thông số (FPS, bộ nhớ, mức chất lượng, gói đang dùng).
- **Ctrl+Shift+S** (mặc định, đổi trong Cài đặt): phím tắt toàn cục để gọi Saki lên.
- Ở chế độ pet:
  - Kéo để di chuyển.
  - **Ctrl + lăn chuột** để đổi cỡ.
  - Chuột phải để mở menu.
  - Bấm một lần để mở mini chat.

## 4. Chạy test (GUT)

```powershell
powershell -ExecutionPolicy Bypass -File app\run_tests.ps1
```

Script import project (cần cho bản clone mới), rồi chạy mọi test trong
`app\tests\unit\` mà không mở cửa sổ. Cuối kết quả có dòng `---- All tests passed! ----`
và mã thoát 0. Test không cần mạng, Ollama hay backend, và không đụng tới Desktop.

Trong trình soạn thảo: mở tab **GUT** ở dưới, bấm **Run All**.

Test backend Python thì chạy riêng: `.venv\Scripts\python -m pytest`.

Công cụ chạy tay trong `app\tools\` (không phải test tự động):

| Lệnh | Làm gì |
|---|---|
| `godot --headless --path app -s res://tools/generate_test_packs.gd -- --count 200` | tạo 200 gói thử trong `characters_dev` để đo tốc độ danh sách gói |
| `godot --headless --path app -s res://tools/backend_smoke.gd` | chạy backend thật với thư mục dữ liệu tạm, gửi `/help`, tắt, kiểm tra không còn tiến trình |
| `godot --path app -s res://tools/message_list_bench.gd` | đo tốc độ cuộn 1.000 tin nhắn (có cửa sổ) |
| `godot --path app -s res://tools/ui_snapshot.gd` | lưu ảnh PNG của các cửa sổ app để xem bố cục |
| `godot --path app -s res://tools/measure.gd` | đo RAM, CPU, tốc độ vòng lặp ở hai chế độ, và thời gian nạp từng cảm xúc của gói đang dùng |

Icon của app là `assets/icon.png` (cửa sổ, project) và `assets/icon.ico` (file `.exe`,
lối tắt, thanh tác vụ). Muốn đổi icon thì thay cả hai file bằng hình mới, rồi export lại.

(`godot` = đường dẫn tới `Godot_v4.7.2-stable_win64_console.exe`.)

## 5. Cài export templates

Muốn tạo `.exe`, Godot cần **export templates** đúng phiên bản 4.7.2. Bản tải về nặng
khoảng 1,3 GB và chỉ phải tải một lần.

1. Trong trình soạn thảo: menu **Editor → Manage Export Templates...**
2. Bấm **Download and Install**, đợi tải xong.

Nếu mạng chập chờn: tải `Godot_v4.7.2-stable_export_templates.tpz` ở trang tải bản
4.7.2, rồi trong cùng hộp thoại bấm **Install from File** và chọn file `.tpz`. Templates
được đặt vào `%APPDATA%\Godot\export_templates\4.7.2.stable\`.

## 6. Export `Saki.exe`

Cấu hình export đã có sẵn trong `app\export_presets.cfg` (preset **Windows Desktop**):
- 64-bit, gói dữ liệu nhúng trong `.exe`, có icon và thông tin phiên bản.
- Không chứa GUT, test và công cụ.

Trong trình soạn thảo:
1. **Project → Export...**
2. Chọn **Windows Desktop**, bấm **Export Project...**
3. Bỏ chọn **Export With Debug** để có bản phát hành, giữ đường dẫn `export/Saki.exe`,
   rồi bấm **Save**.

Hoặc dùng dòng lệnh:

```powershell
New-Item -ItemType Directory -Force app\export | Out-Null
& "D:\App\Godot 4.7.2\Godot_v4.7.2-stable_win64_console.exe" --headless --path app --export-release "Windows Desktop" export/Saki.exe
```

Kết quả nằm ở `app\export\Saki.exe` (thư mục `export\` không có trong git). Để
`Saki.exe` ở đó thì nó tự tìm thấy backend ở thư mục repo cha. Nếu chép đi nơi khác, lần
chạy đầu app sẽ hỏi thư mục backend.

Ghi chú:
- Godot có thể báo thiếu `rcedit` khi đổi icon của file `.exe`. Khi đó tải `rcedit-x64.exe`
  từ https://github.com/electron/rcedit/releases và khai báo đường dẫn ở **Editor →
  Editor Settings → Export → Windows → rcedit**. Không có rcedit thì `.exe` vẫn chạy,
  chỉ mang icon mặc định của Godot.
- Windows SmartScreen có thể cảnh báo vì `.exe` chưa được ký số. Bấm **More info → Run
  anyway**.

## 7. Tạo lối tắt trên Desktop

Chạy `Saki.exe`, mở **Cài đặt** → **Tạo lối tắt Desktop**. Trên Desktop xuất hiện
`Saki.lnk` có icon Saki. Nút này chỉ hoạt động trong bản `.exe` đã export. Chạy từ trình
soạn thảo thì chương trình đang chạy là Godot, nên app báo là cần bản `.exe`.

Làm bằng tay: chuột phải `Saki.exe` → **Send to → Desktop (create shortcut)**.

## 8. Log và cài đặt nằm ở đâu

Mọi thứ nằm trong `%APPDATA%\Saki\` (dán vào thanh địa chỉ của Explorer):

| File / thư mục | Nội dung |
|---|---|
| `app_settings.json` | cài đặt của app: chế độ, vị trí cửa sổ, cỡ pet, gói đang dùng, chất lượng, giao diện, phím tắt, thư mục backend, cổng. Xóa file này để về mặc định. File hỏng thì app đổi tên nó thành `.bak` rồi dùng mặc định |
| `logs\app.log` | log của app Godot (giữ 3 file gần nhất) |
| `logs\saki.log` | log của backend Python |
| `config.json` | cấu hình backend (địa chỉ Ollama, ...) nếu có |
| `saki.db` | lịch sử chat, ký ức, cài đặt xưng hô (SQLite) |
| `characters\` | gói nhân vật đã nhập; `characters\index.json` là cache danh sách |
| `characters_dev\` | gói thử (chế độ thư mục, xem [PACK_GUIDE.md](PACK_GUIDE.md)) |

Trong trình soạn thảo: **Project → Open User Data Folder** mở đúng thư mục này.

## 9. Gỡ rối

**Pet có nền đen hoặc trắng thay vì trong suốt.**
- App vẽ bằng OpenGL. Trên nhiều card đồ họa Intel đời cũ, Godot tự chạy OpenGL qua
  ANGLE (Direct3D 11); máy dev (Intel HD 4000) dùng cách này. Cửa sổ trong suốt cần
  Windows composition, tức là Windows 10/11 bình thường. Remote Desktop hoặc máy ảo có
  thể không hỗ trợ.
- Thử ép một driver khác:
  ```powershell
  & ".\Saki.exe" --rendering-driver opengl3_angle
  & ".\Saki.exe" --rendering-driver opengl3
  ```
  Nếu một trong hai lệnh chạy đúng, tạo lối tắt có thêm tham số đó.
- Không sửa được thì dùng chế độ cửa sổ chat. Chế độ này không cần trong suốt.

**Bấm vào chỗ trong suốt quanh pet mà không xuyên xuống cửa sổ bên dưới.** Vùng nhận
chuột theo hình nhân vật và được cập nhật tối đa 10 lần mỗi giây. Ảnh nhân vật có nhiều
điểm ảnh mờ (alpha thấp) ở viền làm vùng này rộng hơn. Hãy xóa sạch nền của ảnh.

**Báo lỗi đồ họa, cửa sổ đen, hoặc Godot không mở.**
- Cập nhật driver card đồ họa.
- Máy có hai card (Intel + NVIDIA/AMD): chọn card trong **Settings → System → Display →
  Graphics**.
- Xem `logs\app.log`.
- Máy yếu: trong **Cài đặt** đặt **Chất lượng = Thấp** (tắt hoạt ảnh, ảnh tối đa
  1.024 px), hoặc bấm **Đo lại** để app chọn lại mức tự động.

**Không cần trình duyệt hay WebView.** App vẽ mọi thứ bằng Godot, không dùng
WebView2/Chromium. Nếu thấy app mở trình duyệt, đó chỉ là khi bạn bấm vào một nguồn tin
của `/news` hoặc `/se`.

**Dòng trạng thái báo "Không tìm thấy backend Saki...".** Bấm **Chọn thư mục...** và
chọn thư mục repo (thư mục có `saki\` và `.venv\`). Nếu thiếu `.venv`, làm phần cài đặt
trong README.

**"Cổng 8765 đang bị một ứng dụng khác sử dụng".** Đóng chương trình đó, hoặc đổi `port`
trong `app_settings.json` và mở lại app.

**"Chưa kết nối được với mô hình".** Backend đang chạy nhưng không gọi được Ollama. Mở
Ollama và kiểm tra `ollama list` có mô hình `saki` (xem "Known issues" trong
[../HANDOFF.md](../HANDOFF.md) về lỗi cổng WinNAT).

**Phím tắt báo đang được một chương trình khác dùng.** Chọn tổ hợp khác trong Cài đặt,
ví dụ `Ctrl+Alt+S`.

**Test báo lỗi `Không tìm thấy Godot`.** Đặt biến môi trường `GODOT` như ở mục 1.
