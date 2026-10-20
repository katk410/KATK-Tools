function Repair-Activation {
    Show-Step "SỬA LỖI ACTIVE OFFICE"

    $scriptDir = if ($global:KATK_OfficeBin) { $global:KATK_OfficeBin } else { Join-Path $PSScriptRoot "bin" }
    $diagFile = Join-Path $scriptDir "cssemerg97275.diagcab"
    
    if (-not (Test-Path $diagFile)) {
        Write-Host "❌ Không tìm thấy file thực thi..." -ForegroundColor Red
        Write-Host "   Đường dẫn: $diagFile" -ForegroundColor DarkGray
        Read-Host "Nhấn Enter để quay lại"
        return
    }
    
    Write-Host "→ Đang khởi chạy trình sửa lỗi..." -ForegroundColor Cyan
    try {
        Start-Process -FilePath $diagFile
        Write-Host "✔ Đã mở công cụ. Hãy làm theo hướng dẫn trên màn hình." -ForegroundColor Green
    }
    catch {
        Write-Host "❌ Không thể chạy file .diagcab." -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor DarkRed
    }
    
    Write-Host ""
    Read-Host "Nhấn Enter để quay lại menu Troubleshoot"
}

function Remove-License {
    Show-Step "XÓA LICENSE OFFICE"
    
    Write-Host "⚠ Lưu ý: Thao tác này sẽ xóa License hiện tại." -ForegroundColor Yellow
    Write-Host "   Office sẽ chuyển sang trạng thái chưa kích hoạt." -ForegroundColor Gray
    Write-Host ""
    
    $confirm = Read-Host "Bạn có chắc muốn tiếp tục? (Y/N)"
    if ($confirm -notmatch '^[Yy]$') {
        Write-Host "Đã hủy." -ForegroundColor Yellow
        return
    }

    $scriptDir = if ($global:KATK_OfficeBin) { $global:KATK_OfficeBin } else { Join-Path $PSScriptRoot "bin" }
    $removerExe = Join-Path $scriptDir "OfficeLicenseRemover.exe"
    
    if (-not (Test-Path $removerExe)) {
        Write-Host "❌ Không tìm thấy file thực thi..." -ForegroundColor Red
        Write-Host "   Đường dẫn: $removerExe" -ForegroundColor DarkGray
        Read-Host "Nhấn Enter để quay lại"
        return
    }
    
    Write-Host "→ Đang chạy OfficeLicenseRemover.exe..." -ForegroundColor Cyan
    try {
        Start-Process -FilePath $removerExe -Wait
        Write-Host " ✔ Xóa License thành công." -ForegroundColor Green
        Write-Host "   Office sẽ yêu cầu kích hoạt lại khi mở ứng dụng." -ForegroundColor Yellow
    }
    catch {
        Write-Host "❌ Lỗi thực thi..." -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor DarkRed
    }
    
    Write-Host ""
    Read-Host "Nhấn Enter để quay lại menu Troubleshoot"
}

function Show-TroubleshootMenu {
    Clear-Host
    Show-KATKHeader "TROUBLESHOOT"
    Write-Host "────────────────────────────────────────" -ForegroundColor DarkGray

    Write-Host "`n [1] Sửa lỗi Active" -ForegroundColor White
    Write-Host "     Sửa lỗi trong quá trình Active Office" -ForegroundColor DarkGray
    Write-Host " [2] Remove License" -ForegroundColor White
    Write-Host "     Xóa License hiện tại" -ForegroundColor DarkGray

    Write-Host " `n[0] Quay lại menu Office Tools" -ForegroundColor Red
    Write-Host "────────────────────────────────────────" -ForegroundColor DarkGray
}

function Invoke-Troubleshoot {
    do {
        Show-TroubleshootMenu
        $choice = Read-Host "`nNhập lựa chọn của bạn..."
        
        switch ($choice) {
            '1' { Repair-Activation }
            '2' { Remove-License }
            '0' { return }
            default {
                Write-Host "❌ Lựa chọn không hợp lệ!" -ForegroundColor Red
                Start-Sleep -Seconds 1
            }
        }
    } while ($true)
}