if (-not (Get-Command Show-KATKHeader -ErrorAction SilentlyContinue)) {
    $katkBase = if ($global:KATK_BaseUrl) { $global:KATK_BaseUrl } else { "https://raw.githubusercontent.com/katk410/KATK-Tools/stable" }
    Invoke-Expression ((Invoke-RestMethod -Uri "$katkBase/core/UI.ps1" -UseBasicParsing).TrimStart([char]0xFEFF))
}
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

function Show-Menu {
    Clear-Host
    Show-KATKHeader "THAY ĐỔI NGÔN NGỮ HIỂN THỊ WINDOWS"
    Write-Host "`nLƯU Ý:" -ForegroundColor Yellow
    Write-Host "    Tính năng chưa hỗ trợ kiến trúc Windows ARM" -ForegroundColor White
    Write-Host "    Sau khi hệ thống hoàn tất quá trình cài đặt, vui lòng khởi động lại máy!`n" -ForegroundColor White
    Write-Host "LỰA CHỌN NGÔN NGỮ:" -ForegroundColor Yellow
    Write-Host "────────────────────────────────────────`n" -ForegroundColor DarkGray
    Write-Host " [1] Tiếng Việt" -ForegroundColor White
    Write-Host " [2] English" -ForegroundColor White
    Write-Host " [3] 中文(简体) - Tiếng Trung Giản Thể" -ForegroundColor White
    Write-Host " [4] 中文(繁體) - Tiếng Trung Phồn Thể" -ForegroundColor White
    Write-Host ""; Write-KATKBackOption
    Write-Host "────────────────────────────────────────" -ForegroundColor DarkGray
}

function Test-IsAdmin {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal(
        [Security.Principal.WindowsIdentity]::GetCurrent()
    )
    return $currentPrincipal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
}

function Test-InternetConnection {
    try {
        Invoke-WebRequest -Uri "https://www.microsoft.com" -TimeoutSec 5 -UseBasicParsing | Out-Null
        return $true
    } catch { return $false }
}

function Set-Language {
    param(
        [string]$LanguageTag,
        [string]$DisplayName,
        [string]$HexCode
    )

    Show-Step "Đang xử lý $DisplayName ($LanguageTag)"

    Write-Host "→ Đang cài gói ngôn ngữ và Local Experience Pack..." -ForegroundColor Yellow
    Write-Host "  Quá trình có thể mất 30-40 phút tùy vào tốc độ mạng. Vui lòng không đóng cửa sổ cài đặt trong quá trình chờ!" -ForegroundColor DarkGray
    try {
        Install-Language -Language $LanguageTag -ErrorAction Stop
        Write-Host "✔ Cài đặt thành công" -ForegroundColor Green
    } catch {
        Write-Host "❌ Lỗi: $($_.Exception.Message)" -ForegroundColor Red
        Wait-KATKBack
        return $false
    }

    Write-Host "→ Đặt ngôn ngữ hiển thị..." -ForegroundColor Yellow
    try {
        $langList = New-WinUserLanguageList -Language $LanguageTag
        Set-WinUserLanguageList -LanguageList $langList -Force -ErrorAction Stop
    } catch {
        Write-Host "⚠ Lỗi: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    Write-Host "→ Ghi đè UI Language..." -ForegroundColor Yellow
    try {
        Set-WinUILanguageOverride -Language $LanguageTag -ErrorAction Stop
    } catch {
        Write-Host "Lỗi: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    Write-Host "→ Thay đổi System Locale..." -ForegroundColor Yellow
    try {
        Set-WinSystemLocale -SystemLocale $LanguageTag -ErrorAction Stop
    } catch {
        Write-Host "⚠ Lỗi: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    Write-Host "→ Cập nhật registry..." -ForegroundColor Yellow

    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Nls\Language" /v Default /t REG_SZ /d $HexCode /f 2>$null
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Nls\Language" /v InstallLanguage /t REG_SZ /d $HexCode /f 2>$null
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Nls\Language" /v InstallLanguageFallback /t REG_SZ /d $HexCode /f 2>$null

    reg add "HKCU\Control Panel\International" /v LocaleName /t REG_SZ /d $LanguageTag /f 2>$null
    reg add "HKCU\Control Panel\International" /v UserLocale /t REG_SZ /d $LanguageTag /f 2>$null
    reg add "HKCU\Control Panel\Desktop" /v UserLocale /t REG_SZ /d $LanguageTag /f 2>$null
    reg add "HKCU\Control Panel\Desktop\MuiCached" /v PreferredUILanguages /t REG_SZ /d $LanguageTag /f 2>$null
    reg add "HKCU\Control Panel\Desktop\MuiCached" /v MachinePreferredUILanguages /t REG_SZ /d $LanguageTag /f 2>$null
    reg add "HKCU\Software\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultLanguage /t REG_SZ /d $HexCode /f 2>$null

    reg add "HKU\.DEFAULT\Control Panel\International" /v LocaleName /t REG_SZ /d $LanguageTag /f 2>$null
    reg add "HKU\.DEFAULT\Control Panel\International" /v UserLocale /t REG_SZ /d $LanguageTag /f 2>$null
    reg add "HKU\.DEFAULT\Software\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultLanguage /t REG_SZ /d $HexCode /f 2>$null

    Write-Host "✔ Đã cập nhật registry." -ForegroundColor Green

    Show-Step "Verify"
    Write-Host "→ DISM /Online /Get-Intl:" -ForegroundColor Cyan
    dism /online /Get-Intl | Select-String -Pattern "Default system UI language|System locale|Installed language"

    Write-Host "`n→ Get-WinUserLanguageList:" -ForegroundColor Cyan
    Get-WinUserLanguageList | Format-Table -AutoSize

    Write-Host "`n→ Get-WinUILanguageOverride:" -ForegroundColor Cyan
    Get-WinUILanguageOverride

    Write-Host "`n→ Get-WinSystemLocale:" -ForegroundColor Cyan
    Get-WinSystemLocale

    Write-Host ""
    Write-Host "✅ CÀI ĐẶT HOÀN TẤT!" -ForegroundColor Green
    Write-Host "Để áp dụng, hãy khởi động lại máy sau khi hệ thống login." -ForegroundColor Yellow
    Write-Host "Hệ thống sẽ tự logout sau 15 giây." -ForegroundColor Yellow
    Write-Host "Nhấn Ctrl+C để hủy quá trình logout. Bạn sẽ phải thao tác logout thủ công!" -ForegroundColor Gray

    Start-Sleep -Seconds 15
    shutdown /l /f
    return $true
}

Assert-KATKAdmin

if (-not (Test-InternetConnection)) {
    Write-Host "❌ Không có kết nối Internet!" -ForegroundColor Red
    Wait-KATKBack
    Exit-KATKModule
}

$languages = @{
    "1" = @{ Tag = "vi-VN"; Name = "Tiếng Việt"; Hex = "042A" }
    "2" = @{ Tag = "en-US"; Name = "English"; Hex = "0409" }
    "3" = @{ Tag = "zh-CN"; Name = "中文(简体)"; Hex = "0804" }
    "4" = @{ Tag = "zh-TW"; Name = "中文(繁體)"; Hex = "0404" }
}

do {
    Show-Menu
    $choice = Read-Host "Nhập lựa chọn"
    if ($choice -eq '0') { break }
    if ($languages.ContainsKey($choice)) {
        $lang = $languages[$choice]
        Set-Language -LanguageTag $lang.Tag -DisplayName $lang.Name -HexCode $lang.Hex
        break
    } else {
        Write-Host "❌ Lựa chọn không hợp lệ!" -ForegroundColor Red
        Start-Sleep -Seconds 1
    }
} while ($true)
