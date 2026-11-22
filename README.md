# OpenKey Lite

Bộ gõ tiếng Việt tối giản cho macOS: chỉ gõ **Telex**, xuất **Unicode dựng sẵn**, nằm gọn trên thanh menu.
*A minimal Vietnamese input app for macOS: Telex typing, Unicode output, menu bar only.*

OpenKey Lite được xây dựng từ **[OpenKey](https://github.com/tuyenvm/OpenKey) của Mai Vũ Tuyên (Tuyen Mai)**. Toàn bộ cơ chế gõ (bộ máy Telex, kiểm tra chính tả, đặt dấu, kỹ thuật gửi phím `Backspace`) là của OpenKey. Bản này chỉ cắt gọn tính năng và giao diện.
*OpenKey Lite is built on [OpenKey](https://github.com/tuyenvm/OpenKey) by Tuyen Mai. The typing mechanism (Telex engine, spell checking, tone placement and the backspace technique) is OpenKey's; this project only trims features and the interface.*

## Cách dùng

Không có cửa sổ cài đặt. Mọi thứ nằm trong menu trên thanh menu:

| Mục | Ý nghĩa |
| --- | --- |
| **Gõ tiếng Việt** | Bật/tắt tiếng Việt. Phím tắt hiện bên cạnh (mặc định ⌥Z). Biểu tượng: **V** đặc = tiếng Việt, **E** viền = tiếng Anh. |
| **Đặt dấu kiểu mới: hoà, uý** | Tắt để đặt dấu kiểu cũ: hòa, úy. |
| **Giữ nguyên từ không phải tiếng Việt** | Gõ "windows" vẫn ra "windows", không thành "ưindows". |
| **Kêu bíp khi chuyển chế độ** | Phát tiếng bíp khi đổi tiếng Việt/tiếng Anh bằng phím tắt. |
| **Mở cùng macOS** | Tự mở OpenKey Lite khi đăng nhập. |

Lần đầu mở, macOS sẽ hỏi quyền điều khiển máy (macOS 27: *Device Control and Data Access*, bản cũ hơn: *Trợ năng*). Bật quyền là gõ được ngay, không cần mở lại ứng dụng.

Nên tắt các bộ gõ tiếng Việt khác khi dùng OpenKey Lite để tránh xung đột.

## Khác gì so với OpenKey

| | OpenKey 2.0.4 | OpenKey Lite |
| --- | --- | --- |
| Kiểu gõ | Telex, VNI, Simple Telex | Telex |
| Bảng mã | Unicode, TCVN3, VNI Windows, Unicode tổ hợp, CP 1258 | Unicode dựng sẵn |
| Giao diện | Bảng điều khiển 4 thẻ, gõ tắt, chuyển mã, giới thiệu | Chỉ menu trên thanh menu |
| Gõ tắt, chuyển mã, chuyển chế độ thông minh, Quick Telex, tự viết hoa, cập nhật tự động | Có | Không |
| Nền tảng | macOS, Windows, Linux (đang phát triển) | macOS 13 trở lên |
| Kích thước ứng dụng | 1.7 MB | khoảng 480 KB |

## Tự build

Yêu cầu: macOS 13 trở lên, Xcode.

1. Mở `Sources/OpenKey/macOS/OpenKey.xcodeproj`.
2. Chọn scheme **OpenKey**, bấm **Product → Build** (hoặc **Archive** để có bản phát hành).

Hoặc dùng dòng lệnh:

```
xcodebuild -project Sources/OpenKey/macOS/OpenKey.xcodeproj -scheme OpenKey -configuration Release build
```

Dự án ký ứng dụng kiểu *Sign to Run Locally* (ad-hoc), không cần tài khoản Apple Developer. Mỗi lần build lại, macOS coi đó là ứng dụng mới nên cần cấp lại quyền.

## Kiểm thử bộ gõ

```
Tests/run.sh
```

Chạy các ca kiểm thử Telex và so sánh kết quả với `Tests/golden.txt`. Nếu bạn cố ý thay đổi cách gõ, chạy `Tests/run.sh --update` để cập nhật file này.

## Ghi công và giấy phép

- Bộ máy gõ và mã nguồn gốc: **OpenKey** © 2019 Mai Vũ Tuyên, https://github.com/tuyenvm/OpenKey. Hãy ủng hộ tác giả gốc tại [trang của OpenKey](https://github.com/tuyenvm/OpenKey).
- OpenKey Lite là bản sửa đổi của OpenKey 2.0.4 (commit `89c2fd3`), do vuluonganh thực hiện từ tháng 11/2026. Các thay đổi được ghi trong [CHANGELOG.md](CHANGELOG.md).
- Phát hành theo giấy phép **GNU GPL v3**, giống bản gốc. Xem [LICENSE](LICENSE). Các ghi chú bản quyền gốc trong mã nguồn được giữ nguyên.
