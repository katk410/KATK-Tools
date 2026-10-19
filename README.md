# KATK Tools

Bộ script tự động thiết lập Windows — DEV BY BaoTV6 (CMU K7 Sông Đốc).

## Cách dùng

Mở **PowerShell / Terminal (Admin)** và chạy:

```powershell
irm https://s.pro.vn/katk | iex
```

Link gốc (không qua rút gọn):

```powershell
irm https://raw.githubusercontent.com/katk410/KATK-Tools/stable/KATK.ps1 | iex
```

## Nhánh & phát hành

| Nhánh    | Dành cho   | Lệnh |
|----------|-----------|------|
| `stable` | Người dùng | `irm https://s.pro.vn/katk \| iex` |
| `dev`    | Test       | `irm https://raw.githubusercontent.com/katk410/KATK-Tools/dev/dev.ps1 \| iex` |

Quy trình (KATK Studio → KATK TOOLS → Cập nhật & phát hành):
1. Sửa code → **Đẩy lên dev** → chạy lệnh test.
2. Ổn → **Phát hành cho người dùng** (dev → stable, gắn tag `v<KATK_Version>`).

Không sửa trực tiếp nhánh `stable`.
## Cấu trúc

```
KATK.ps1                         Menu chính (entry point) - ghi version tại đây
core/UI.ps1                      Giao diện dùng chung (header, khung, quay lại menu)
modules/
  AutoSetup/AutoSetup.ps1        [1] Cài đặt tự động hệ thống
  AutoSetup/AppModule.ps1        [2] Cài đặt ứng dụng
  DisplayLanguage/DisplayLanguage.ps1   [3] Đổi ngôn ngữ hiển thị
  WindowsLicense/WindowsLicense.ps1     [4] Đổi phiên bản Windows
  WindowsConfiguration/WindowsConfiguration.ps1  [5] Tối ưu Windows
  OfficeTools/OfficeTools.ps1    [6] Menu Office Tools
  OfficeTools/Uninstall.ps1 | Install.ps1 | Troubleshoot.ps1
  OfficeTools/bin/               File phụ trợ (.exe, .diagcab)
```

## Thêm module mới

1. Tạo `modules/<TenModule>/<TenModule>.ps1`, mở đầu bằng khối "KATK UI dùng chung" (copy từ module có sẵn).
2. Thêm 1 dòng vào `$KATK_Modules` trong `KATK.ps1`.

Quy ước giao diện trong module:

| Dùng                          | Thay cho                              |
|-------------------------------|---------------------------------------|
| `Show-KATKHeader "TÊN MODULE"` | Khung tiêu đề tự vẽ (tác giả tự thêm)  |
| `Show-KATKBox "Nội dung"`      | Khung thông báo 1 dòng                 |
| `Show-Step` / `Show-Banner`   | Tiêu đề bước                           |
| `Write-KATKBackOption`        | Dòng `[0] Thoát` cuối menu             |
| `Exit-KATKModule`             | `exit` (exit sẽ đóng cả cửa sổ)        |
| `Wait-KATKBack`               | "Nhấn phím bất kỳ để thoát..."         |
| `Assert-KATKAdmin`            | Đoạn kiểm tra quyền Admin              |

Không ghi version trong module — version chỉ nằm ở `KATK.ps1`.