# Hướng dẫn làm gói nhân vật Saki

Tài liệu cho người vẽ hoặc làm gói nhân vật. Không cần biết lập trình. Một gói nhân vật
gồm một file `manifest.json` (mô tả gói) và các file ảnh. App chỉ đọc JSON và ảnh, không
chạy thứ gì khác trong gói.

## 1. Cấu trúc thư mục

```
miku-chibi/               ← tên thư mục = "id" trong manifest
├── manifest.json         ← bắt buộc, nằm ngay ở gốc
├── thumb.png             ← ảnh đại diện (không bắt buộc)
├── neutral.png
├── happy_sheet.png
├── thinking/
│   ├── 01.png
│   ├── 02.png
│   └── 03.png
└── talk_sheet.png
```

Quy tắc tên file và thư mục:
- Chỉ dùng chữ không dấu, số, dấu chấm, `-` và `_`. Không có dấu cách và không bắt đầu
  bằng dấu chấm. Ví dụ `Ảnh vui.png` và `.hidden.png` đều bị từ chối.
- Trong manifest, đường dẫn dùng dấu `/` (ví dụ `thinking/01.png`), không dùng `\`,
  không có `..`, không có ổ đĩa (`C:`) và không bắt đầu bằng `/`.
- Lồng tối đa 4 cấp thư mục.
- Không được có hai file trùng tên khi bỏ qua hoa thường (ví dụ `Happy.png` và
  `happy.png`).
- Chỉ nhận các đuôi `.png .jpg .jpeg .webp .json .txt`. Mọi đuôi khác bị từ chối, kể cả
  `.svg`, `.gd`, `.tscn`, `.tres` và `.exe`. File `.txt` thường dùng cho giấy phép hoặc
  ghi chú.

## 2. manifest.json: từng trường

Ví dụ đầy đủ:

```json
{
  "format": 1,
  "id": "miku-chibi",
  "name": "Miku Chibi",
  "author": "Tên bạn",
  "version": "1.0.0",
  "license": "CC BY 4.0",
  "type": "2d",
  "thumbnail": "thumb.png",
  "default_emotion": "neutral",
  "base_scale": 1.0,
  "anchor": [0.5, 1.0],
  "idle_seconds": 10,
  "emotions": {
    "neutral":     { "image": "neutral.png" },
    "happy":       { "sheet": "happy_sheet.png", "columns": 4, "rows": 2, "frames": 8, "fps": 10, "loop": true },
    "thinking":    { "frames": ["thinking/01.png", "thinking/02.png", "thinking/03.png"], "fps": 6, "loop": true },
    "embarrassed": { "image": "embarrassed.png" }
  },
  "states": {
    "talking": { "sheet": "talk_sheet.png", "columns": 4, "rows": 1, "fps": 12, "loop": true }
  }
}
```

| Trường | Bắt buộc | Kiểu, giới hạn | Ý nghĩa |
|---|---|---|---|
| `format` | có | số nguyên, hiện là `1` | phiên bản định dạng. Số lớn hơn 1 thì gói được liệt kê là "mới hơn bản app hiện tại" |
| `id` | có | chữ thường không dấu, số, `-`, `_`; tối đa 64 ký tự; bắt đầu bằng chữ hoặc số | mã của gói, trùng với tên thư mục. Không được là `default` |
| `name` | có | chuỗi, tối đa 60 ký tự | tên hiển thị, có dấu thoải mái |
| `author` | không | chuỗi (cắt ở 60 ký tự) | tác giả |
| `version` | không | chuỗi (cắt ở 20 ký tự) | phiên bản của gói, ví dụ `1.0.0` |
| `license` | không | chuỗi (cắt ở 200 ký tự) | giấy phép |
| `type` | có | chuỗi | kiểu gói. Hiện chỉ có `2d`. Kiểu khác (ví dụ `3d-gltf`) vẫn được nhận nhưng chỉ hiện ảnh đại diện kèm "Loại gói này chưa được hỗ trợ" |
| `thumbnail` | không | đường dẫn ảnh | ảnh đại diện trong trình quản lý gói. Bỏ trống thì app dùng ảnh của `default_emotion` |
| `default_emotion` | không | tên cảm xúc, mặc định `neutral` | cảm xúc khi rảnh, và mục dự phòng khi thiếu một cảm xúc |
| `base_scale` | không | số 0.1–4.0, mặc định 1.0 | phóng to hoặc thu nhỏ nhân vật ở chế độ pet. Ảnh 512 px với `0.5` hiện cao khoảng 256 px khi pet ở cỡ "vừa" |
| `anchor` | không | `[x, y]`, mỗi số 0–1, mặc định `[0.5, 1.0]` | điểm neo của ảnh trong khung. `[0.5, 1.0]` = giữa đáy (chân nhân vật chạm đáy) |
| `idle_seconds` | không | số 1–3600 | số giây sau lượt chat thì quay về `default_emotion`. Bỏ trống thì dùng mặc định 10 s |
| `emotions` | có (*) | đối tượng: tên cảm xúc → mục hoạt ảnh | ảnh cho từng cảm xúc |
| `states` | không | đối tượng: tên trạng thái → mục hoạt ảnh | ảnh cho trạng thái `idle`, `thinking`, `talking` |

(*) Gói `2d` cần ít nhất một mục trong `emotions` hoặc `states`. Trường lạ không có trong
bảng sẽ bị bỏ qua, không báo lỗi.

### Tên cảm xúc và trạng thái

- Tên gồm chữ thường không dấu, số và `_`, bắt đầu bằng chữ, tối đa 32 ký tự.
- Backend hiện gửi 6 cảm xúc: `neutral`, `happy`, `sad`, `thinking`, `surprised`,
  `embarrassed`. Không cần vẽ đủ cả 6, và có thể thêm tên khác cho sau này.
- Trạng thái của app:
  - `idle`: đang rảnh.
  - `thinking`: Saki đang suy nghĩ hoặc tìm kiếm.
  - `talking`: chữ đang chạy ra.
  - `listening`: để dành cho giọng nói sau này.

Nhân vật hiển thị như sau:
- **`thinking`**: hiện `states.thinking` nếu có, nếu không thì hiện `emotions.thinking`.
- **`talking`**: hiện `states.talking` nếu có, nếu không thì hiện cảm xúc của câu trả lời.
- **`idle`**: hiện `states.idle` nếu có, nhưng chỉ khi đang ở cảm xúc mặc định. Khi Saki
  vừa trả lời bằng `happy`, nhân vật vẫn hiện `happy` cho tới hết `idle_seconds`.
- Thiếu một mục thì app thử lần lượt: cảm xúc được yêu cầu → `default_emotion` →
  `neutral` → cảm xúc đầu tiên có trong gói → hình vẽ sẵn của app. Một ảnh hỏng chỉ ghi
  vào log, app không bị lỗi.

## 3. Ba kiểu mục hoạt ảnh

Mỗi mục trong `emotions` hoặc `states` có **đúng một** trong ba khóa `image`, `sheet`
hoặc `frames`.

### 3.1 Ảnh tĩnh: `image`

```json
"neutral": { "image": "neutral.png" }
```

### 3.2 Sprite sheet: `sheet`

Một ảnh lưới chứa nhiều khung hình cùng kích thước. App đọc từ trái sang phải, hết hàng
thì xuống hàng dưới.

```json
"happy": { "sheet": "happy_sheet.png", "columns": 4, "rows": 2, "frames": 8, "fps": 10, "loop": true }
```

| Khóa | Bắt buộc | Giới hạn | Ý nghĩa |
|---|---|---|---|
| `sheet` | có | đường dẫn ảnh | ảnh lưới |
| `columns` | có | 1–64 | số cột |
| `rows` | có | 1–64 | số hàng |
| `frames` | không | 1–`columns × rows`, mặc định = `columns × rows` | số khung thực sự dùng, khi hàng cuối không đầy |
| `fps` | không | 0.5–60, mặc định 8 | số khung mỗi giây |
| `loop` | không | `true`/`false`, mặc định `true` | lặp lại hay dừng ở khung cuối |

Chiều rộng ảnh nên chia hết cho `columns` và chiều cao chia hết cho `rows`. Ví dụ 4 cột
× 256 px = 1024 px.

### 3.3 Danh sách khung: `frames`

Mỗi khung hình là một file riêng, hiện theo đúng thứ tự trong danh sách.

```json
"thinking": { "frames": ["thinking/01.png", "thinking/02.png", "thinking/03.png"], "fps": 6, "loop": true }
```

`fps` và `loop` giống như ở `sheet`. App chỉ nhận dạng danh sách liệt kê từng file, không
nhận kiểu mẫu tên (`happy_{:02d}.png`).

Một hoạt ảnh có tối đa **120 khung**. Ở mức chất lượng "Thấp", hoạt ảnh tắt và chỉ hiện
khung đầu tiên.

## 4. Giới hạn

| Giới hạn | Giá trị | Vượt thì |
|---|---|---|
| File `.sakip` (đã nén) | 50 MB | từ chối |
| Tổng dung lượng sau giải nén | 200 MB | từ chối |
| Số file | 2.000 | từ chối |
| `manifest.json` | 64 KB | từ chối |
| Tỉ lệ nén một file | 200 lần | từ chối (nghi là zip bomb) |
| Cạnh dài nhất của ảnh | 8.192 px; tối đa 8192 × 4096 điểm ảnh | từ chối |
| Cạnh dài nhất khi nhập | 4.096 px | tự thu nhỏ và báo "Đã thu nhỏ N ảnh…" |
| Khung mỗi hoạt ảnh | 120 | từ chối |
| Kiểu nén trong zip | Store, Deflate | từ chối (cả file có mật khẩu, ZIP64, zip nhiều phần, symlink) |

Khi chạy, app còn thu nhỏ ảnh theo mức chất lượng: Thấp 1.024 px, Vừa 2.048 px, Cao
4.096 px. Sprite sheet được thu nhỏ sao cho mọi ô vẫn bằng nhau. Kích thước gợi ý: nhân
vật cao 512–1.024 px, PNG có nền trong suốt.

## 5. Đóng gói thành `.sakip`

File `.sakip` là một file **zip** thường, chỉ đổi đuôi.

1. Mở thư mục gói, chọn **tất cả file bên trong**. `manifest.json` phải nằm ở gốc zip.
   Nếu zip chứa đúng một thư mục và gói nằm trong thư mục đó, app cũng chấp nhận.
2. Chuột phải → **Gửi tới** → **Thư mục nén (zipped)**. Hoặc dùng 7-Zip, định dạng
   `zip`, kiểu nén Deflate.
3. Đổi tên `miku-chibi.zip` thành `miku-chibi.sakip`.

Bằng PowerShell:

```powershell
Compress-Archive -Path .\miku-chibi\* -DestinationPath .\miku-chibi.zip
Rename-Item .\miku-chibi.zip miku-chibi.sakip
```

Để nhập vào Saki, **kéo file `.sakip` thả vào cửa sổ Saki** (cả chế độ chat lẫn pet),
hoặc mở **Gói nhân vật** → **Nhập gói**. Việc nhập chạy nền, có thanh tiến độ. App
thực hiện:
1. Kiểm tra mọi quy tắc trên.
2. Giải nén vào thư mục tạm.
3. Mã hóa lại từng ảnh (giữ định dạng; JPEG ở chất lượng 92) và thu nhỏ ảnh quá lớn.
4. Tạo ảnh đại diện 160 px.
5. Tính mã băm nội dung.
6. Đặt gói vào `%APPDATA%\Saki\characters\<id>\`.

Nhập một gói có `id` đã tồn tại sẽ **thay** gói cũ.

## 6. Chế độ thư mục (để thử gói nhanh)

Không cần nén mỗi lần sửa ảnh:

1. Mở **Gói nhân vật** → **Mở thư mục gói thử**. Thư mục đó là
   `%APPDATA%\Saki\characters_dev\`.
2. Chép thư mục gói vào đó. Tên thư mục phải trùng `id`, ví dụ
   `characters_dev\miku-chibi\manifest.json`.
3. Bấm **Quét lại**. Gói hiện với nhãn "gói thử".
4. Sửa ảnh hoặc manifest, rồi bấm **Tải lại** trên gói đó để thấy ngay.

Gói thử được kiểm tra như gói thật nhưng nạp nguyên trạng: không thu nhỏ, không mã hóa
lại. App không xóa gói thử, vì đó là thư mục của bạn.

Trong trình quản lý gói, bấm từng cảm xúc hoặc trạng thái để xem trước, sau đó bấm
**Dùng gói này**.

## 7. Lỗi thường gặp

Gói lỗi nằm trong mục **Gói bị lỗi**, kèm lý do chính xác. Các thông báo hay gặp:

| Thông báo | Nguyên nhân, cách sửa |
|---|---|
| Không tìm thấy manifest.json ở thư mục gốc của gói. | Lúc nén đã chọn thư mục cha chứa nhiều thứ, hoặc đặt tên sai (`Manifest.json`, `manifest.json.txt`). Hãy nén các file *bên trong* thư mục gói |
| manifest.json không phải JSON hợp lệ (dòng 12: …). | Thiếu dấu phẩy, thừa dấu phẩy cuối, hoặc dùng dấu nháy cong `“ ”`. Kiểm tra bằng một trình kiểm tra JSON |
| Thiếu trường “name” trong manifest.json. | Thêm trường bắt buộc: `format`, `id`, `name`, `type` |
| Trường “emotions.happy.fps” trong manifest.json không hợp lệ: phải nằm trong khoảng 0.5–60. | Giá trị nằm ngoài giới hạn ở mục 2–3 |
| Trường “emotions.Vui” … chỉ gồm chữ thường không dấu, số và _, bắt đầu bằng chữ. | Tên cảm xúc phải như `happy`, `vui_ve` |
| Mục “emotions.happy” phải có đúng một trong ba khóa: image, sheet hoặc frames. | Có cả `image` lẫn `sheet`, hoặc không có khóa nào |
| manifest.json nhắc tới tệp “happy.PNG”, nhưng trong gói không có tệp này. | Sai tên hoặc sai hoa thường. Tên trong manifest phải khớp đúng với tên file |
| Tệp “Ảnh 1.png” không hợp lệ: chỉ được dùng chữ không dấu, số, … | Đổi tên file: bỏ dấu tiếng Việt và dấu cách |
| Tệp “anim.gif” có đuôi không được phép. Chỉ nhận: png, jpg, jpeg, webp, json, txt. | Chuyển ảnh sang PNG hoặc WebP; xóa file thừa (`Thumbs.db`, `.psd`) |
| Ảnh “bg.png” quá lớn (10000×2000, tối đa 8192 px mỗi cạnh). | Thu nhỏ ảnh |
| Mục “emotions.happy” có quá nhiều khung hình (tối đa 120). | Bớt khung hình hoặc tách thành nhiều cảm xúc |
| “id” trong manifest.json (“miku”) phải trùng với tên thư mục (“miku-chibi”). | Chỉ gặp ở chế độ thư mục. Đổi tên thư mục hoặc `id` |
| Không thể dùng id “default”: đây là tên của gói có sẵn. | Chọn `id` khác |
| Gói này dùng định dạng 2, mới hơn bản app hiện tại. Hãy cập nhật Saki. | Gói làm cho bản Saki mới hơn |
| Tệp gói dùng định dạng ZIP64 … / có mật khẩu … / kiểu nén không hỗ trợ … | Nén lại bằng zip thường, không đặt mật khẩu, kiểu Deflate |

## 8. Gói có sẵn

App có sẵn gói `default` trong `app/packs/default/`. Khi thư mục này chưa có
`manifest.json` và ảnh, app vẽ một khuôn mặt đơn giản bằng code. Muốn thay, chỉ cần đặt
`manifest.json` và ảnh (theo định dạng trên, `"id": "default"`) vào `app/packs/default/`
(tạo thư mục nếu chưa có), không phải sửa code. Sau đó mở project trong Godot một lần,
hoặc chạy `app\run_tests.ps1`, để Godot import ảnh mới rồi mới export. Gói có sẵn không
xóa được trong app.
