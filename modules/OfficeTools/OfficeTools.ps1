if (-not (Get-Command Show-KATKHeader -ErrorAction SilentlyContinue)) {
    $katkBase = if ($global:KATK_BaseUrl) { $global:KATK_BaseUrl } else { "https://raw.githubusercontent.com/katk410/KATK-Tools/stable" }
    Invoke-Expression ((Invoke-RestMethod -Uri "$katkBase/core/UI.ps1" -UseBasicParsing).TrimStart([char]0xFEFF))
}
Assert-KATKAdmin

[System.Net.ServicePointManager]::DefaultConnectionLimit = 80
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

$global:tempDir = "C:\KATK-Tools"
if (-not (Test-Path $global:tempDir)) {
    New-Item -ItemType Directory -Path $global:tempDir -Force | Out-Null
}
$taskName = "KATK_Cleanup"
$taskCommand = "cmd.exe /c rmdir /s /q C:\KATK-Tools"
schtasks /delete /tn $taskName /f 2>$null | Out-Null
schtasks /create /tn $taskName /tr "$taskCommand" /sc onstart /ru SYSTEM /rl HIGHEST /f | Out-Null

if (-not $global:KATK_BaseUrl) { $global:KATK_BaseUrl = "https://raw.githubusercontent.com/katk410/KATK-Tools/stable" }
$officeBase = "$global:KATK_BaseUrl/modules/OfficeTools"
$global:KATK_OfficeBin = Join-Path $global:tempDir "OfficeTools"

try {
    foreach ($sub in "Uninstall.ps1", "Install.ps1", "Troubleshoot.ps1") {
        $code = (Invoke-RestMethod -Uri "$officeBase/$sub" -UseBasicParsing -ErrorAction Stop).TrimStart([char]0xFEFF)
        . ([ScriptBlock]::Create($code))
    }

    if (-not (Test-Path $global:KATK_OfficeBin)) { New-Item -ItemType Directory -Path $global:KATK_OfficeBin -Force | Out-Null }
    $progressPreference = 'SilentlyContinue'
    foreach ($bin in "OfficeLicenseRemover.exe", "cssemerg97275.diagcab") {
        Invoke-WebRequest -Uri "$officeBase/bin/$bin" -OutFile (Join-Path $global:KATK_OfficeBin $bin) -UseBasicParsing -ErrorAction Stop
    }
    $progressPreference = 'Continue'
}
catch {
    Write-Host "❌ Lỗi không thể tải, vui lòng kiểm tra lại hoặc liên hệ ADMIN!" -ForegroundColor Red
    Write-Host "Chi tiết: $($_.Exception.Message)" -ForegroundColor DarkGray
    return
}

function Show-Menu {
    Clear-Host
    Show-KATKHeader "OFFICE TOOLS"

    Write-Host ""
    Write-Host "LỰA CHỌN CÔNG CỤ:" -ForegroundColor Yellow
    Write-Host "────────────────────────────────────────" -ForegroundColor DarkGray

    Write-Host " [1] Gỡ sạch Office" -ForegroundColor White
    Write-Host "     Gỡ chuẩn + quét dọn toàn bộ dấu vết Office còn sót`n" -ForegroundColor DarkGray

    Write-Host " [2] Install Office" -ForegroundColor White
    Write-Host "     Cài đặt Office mới`n" -ForegroundColor DarkGray

    Write-Host " [3] Troubleshoot" -ForegroundColor White
    Write-Host "     Chạy trình sửa lỗi`n" -ForegroundColor DarkGray

    Write-Host " [4] Active - Key" -ForegroundColor White
    Write-Host "     Mở trang nhập Key của Microsoft`n" -ForegroundColor DarkGray

    Write-KATKBackOption
    Write-Host "────────────────────────────────────────" -ForegroundColor DarkGray
}

do {
    Show-Menu
    $choice = Read-Host "`nNhập lựa chọn của bạn"

    if ($choice -eq '4') {
        Write-Host ""
        Write-Host "Đang mở trình duyệt đến trang https://setup.office.com ..." -ForegroundColor Cyan
        Start-Process "https://setup.office.com"
        Write-Host "`nNhấn phím bất kỳ để quay lại menu Office Tools..." -ForegroundColor Gray
        $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        continue
    }

    switch ($choice) {
        '1' { Uninstall-Office }
        '2' { Install-Office }
        '3' { Invoke-Troubleshoot }
        '0' { Exit-KATKModule }
        default {
            Write-Host "❌ Lựa chọn không hợp lệ!" -ForegroundColor Red
        }
    }

    if ($choice -ne '0') {
        Read-Host "`nNhấn Enter để quay lại menu!"
    }
} while ($true)
