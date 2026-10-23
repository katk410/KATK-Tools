if (-not (Get-Command Show-KATKHeader -ErrorAction SilentlyContinue)) {
    $katkBase = if ($global:KATK_BaseUrl) { $global:KATK_BaseUrl } else { "https://raw.githubusercontent.com/katk410/KATK-Tools/stable" }
    Invoke-Expression ((Invoke-RestMethod -Uri "$katkBase/core/UI.ps1" -UseBasicParsing).TrimStart([char]0xFEFF))
}
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

$script:EstimatedSizeMB = 450
$script:MaxAttempts = 3
$script:WuPolicyKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
$script:WuAuPolicyKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"

function Show-Menu {
    Clear-Host
    Show-KATKHeader "THAY ĐỔI NGÔN NGỮ HIỂN THỊ WINDOWS"
    Write-Host "`nPhiên bản: $script:EditionName" -ForegroundColor Cyan
    Write-Host "Ngôn ngữ hiện tại: $script:CurrentUILanguage" -ForegroundColor Cyan
    if (-not $script:IsSingleLanguage) {
        Write-Host "    Máy không phải Home Single Language, sẽ bỏ qua bước ghi đè ngôn ngữ hệ thống." -ForegroundColor DarkGray
    }
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

function Test-InternetConnection {
    try {
        Invoke-WebRequest -Uri "https://www.microsoft.com" -TimeoutSec 5 -UseBasicParsing | Out-Null
        return $true
    } catch { return $false }
}

function Test-IsArm {
    $arch = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
    return $arch -match 'ARM'
}

function Get-CurrentUILanguage {
    if (Get-Command Get-SystemPreferredUILanguage -ErrorAction SilentlyContinue) {
        try { return Get-SystemPreferredUILanguage } catch {}
    }
    return (Get-UICulture).Name
}

function Read-YesNo([string]$Prompt) {
    do {
        $answer = (Read-Host "$Prompt (Y/N)").Trim().ToUpper()
    } while ($answer -ne 'Y' -and $answer -ne 'N')
    return $answer -eq 'Y'
}

function Set-RegValue([string]$Key, [string]$Name, [string]$Value) {
    reg add $Key /v $Name /t REG_SZ /d $Value /f 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  ⚠ Không ghi được $Key\$Name" -ForegroundColor Yellow
        return $false
    }
    return $true
}

function Format-Size([double]$Bytes) {
    if ($Bytes -ge 1GB) { return "{0:N2} GB" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return "{0:N1} MB" -f ($Bytes / 1MB) }
    return "{0:N0} KB" -f ($Bytes / 1KB)
}

function Format-Duration([double]$Seconds) {
    $t = [TimeSpan]::FromSeconds([math]::Max(0, $Seconds))
    if ($t.TotalHours -ge 1) { return "{0}:{1:D2}:{2:D2}" -f [int][math]::Floor($t.TotalHours), $t.Minutes, $t.Seconds }
    return "{0:D2}:{1:D2}" -f $t.Minutes, $t.Seconds
}

function Get-ReceivedBytes {
    try {
        return (Get-NetAdapterStatistics -ErrorAction Stop | Measure-Object -Property ReceivedBytes -Sum).Sum
    } catch { return 0 }
}

function Get-PolicyValue([string]$Key, [string]$Name) {
    $item = Get-ItemProperty -Path $Key -Name $Name -ErrorAction SilentlyContinue
    if ($item) { return $item.$Name }
    return $null
}

function Enable-UpdatePrerequisites {
    $state = @{ Services = @(); Policies = @() }

    Write-Host "→ Kiểm tra dịch vụ Windows Update..." -ForegroundColor Yellow
    foreach ($name in 'wuauserv', 'BITS', 'UsoSvc', 'InstallService') {
        $svc = Get-CimInstance Win32_Service -Filter "Name='$name'" -ErrorAction SilentlyContinue
        if (-not $svc) { continue }
        if ($svc.StartMode -eq 'Disabled') {
            Write-Host "  ⚠ Dịch vụ $name đang bị tắt, tạm bật lại." -ForegroundColor Yellow
            $state.Services += $name
            Set-Service -Name $name -StartupType Manual -ErrorAction SilentlyContinue
        }
        if ($svc.State -ne 'Running') {
            Start-Service -Name $name -ErrorAction SilentlyContinue
        }
    }

    Write-Host "→ Kiểm tra chính sách chặn tải từ Windows Update..." -ForegroundColor Yellow
    foreach ($p in @(
        @{ Key = $script:WuPolicyKey; Name = 'DoNotConnectToWindowsUpdateInternetLocations' },
        @{ Key = $script:WuAuPolicyKey; Name = 'UseWUServer' }
    )) {
        $value = Get-PolicyValue $p.Key $p.Name
        if ($value -eq 1) {
            Write-Host "  ⚠ Chính sách $($p.Name) đang chặn, tạm tắt trong lúc cài." -ForegroundColor Yellow
            $state.Policies += $p
            Set-ItemProperty -Path $p.Key -Name $p.Name -Value 0 -Type DWord -ErrorAction SilentlyContinue
        }
    }
    if ($state.Policies.Count -gt 0) { Restart-Service wuauserv -Force -ErrorAction SilentlyContinue }

    return $state
}

function Restore-UpdatePrerequisites($State) {
    if (-not $State) { return }
    foreach ($p in $State.Policies) {
        Set-ItemProperty -Path $p.Key -Name $p.Name -Value 1 -Type DWord -ErrorAction SilentlyContinue
    }
    foreach ($name in $State.Services) {
        Stop-Service -Name $name -Force -ErrorAction SilentlyContinue
        Set-Service -Name $name -StartupType Disabled -ErrorAction SilentlyContinue
    }
    if ($State.Policies.Count -gt 0 -or $State.Services.Count -gt 0) {
        Write-Host "→ Đã khôi phục cài đặt Windows Update như ban đầu." -ForegroundColor DarkGray
    }
}

function Test-Prerequisites {
    $ok = $true

    $freeGB = [math]::Round((Get-PSDrive -Name ($env:SystemDrive.TrimEnd(':'))).Free / 1GB, 1)
    if ($freeGB -lt 2) {
        Write-Host "❌ Ổ $env:SystemDrive chỉ còn $freeGB GB, cần ít nhất 2 GB." -ForegroundColor Red
        $ok = $false
    } else {
        Write-Host "✔ Ổ $env:SystemDrive còn trống $freeGB GB" -ForegroundColor Green
    }

    if (Get-AppxPackage -Name Microsoft.WindowsStore -AllUsers -ErrorAction SilentlyContinue) {
        Write-Host "✔ Microsoft Store có sẵn" -ForegroundColor Green
    } else {
        Write-Host "⚠ Không tìm thấy Microsoft Store. Gói giao diện (LXP) có thể không cài được, Start/Settings có thể còn tiếng Anh." -ForegroundColor Yellow
    }

    return $ok
}

function Show-InstallProgress([string]$Line) {
    $width = [math]::Max(40, $Host.UI.RawUI.WindowSize.Width - 1)
    if ($Line.Length -gt $width) { $Line = $Line.Substring(0, $width) }
    Write-Host ("`r" + $Line.PadRight($width)) -NoNewline -ForegroundColor Cyan
}

function Invoke-LanguageInstall([string]$LanguageTag) {
    $job = Start-Job -ScriptBlock {
        param($tag)
        Import-Module LanguagePackManagement -ErrorAction SilentlyContinue
        Install-Language -Language $tag -CopyToSettings -ErrorAction Stop | Out-Null
    } -ArgumentList $LanguageTag

    $spinner = '|', '/', '-', '\'
    $start = Get-Date
    $baseBytes = Get-ReceivedBytes
    $lastBytes = $baseBytes
    $lastTime = $start
    $speed = 0.0
    $estimate = $script:EstimatedSizeMB * 1MB
    $tick = 0

    while ($job.State -eq 'Running' -or $job.State -eq 'NotStarted') {
        Start-Sleep -Milliseconds 1000
        $tick++
        $now = Get-Date
        $bytes = Get-ReceivedBytes
        $interval = ($now - $lastTime).TotalSeconds
        if ($interval -gt 0 -and $bytes -ge $lastBytes) {
            $current = ($bytes - $lastBytes) / $interval
            $speed = if ($speed -eq 0) { $current } else { $speed * 0.7 + $current * 0.3 }
        }
        $lastBytes = $bytes
        $lastTime = $now

        $downloaded = [math]::Max(0, $bytes - $baseBytes)
        $elapsed = ($now - $start).TotalSeconds
        if ($downloaded -gt $estimate) { $estimate = $downloaded * 1.1 }
        $percent = [math]::Min(99, [math]::Floor($downloaded / $estimate * 100))
        $avgSpeed = if ($elapsed -gt 0) { $downloaded / $elapsed } else { 0 }
        $eta = if ($avgSpeed -gt 1KB) { Format-Duration (($estimate - $downloaded) / $avgSpeed) } else { "--:--" }

        $bar = ('█' * [math]::Floor($percent / 5)).PadRight(20, '░')
        $spin = $spinner[$tick % 4]
        Show-InstallProgress (" $spin $bar ~$percent%  $(Format-Size $downloaded)  $(Format-Size $speed)/s  Đã chạy $(Format-Duration $elapsed)  Còn ~$eta")
    }
    Write-Host ""

    $failed = $job.State -ne 'Completed'
    $message = $null
    try {
        Receive-Job -Job $job -ErrorAction Stop | Out-Null
    } catch {
        $failed = $true
        $message = $_.Exception.Message
    }
    if (-not $message -and $job.ChildJobs[0].JobStateInfo.Reason) {
        $message = $job.ChildJobs[0].JobStateInfo.Reason.Message
    }
    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue

    $installed = Get-InstalledLanguage -ErrorAction SilentlyContinue | Where-Object { $_.LanguageId -eq $LanguageTag }
    return @{ Success = (-not $failed -and $installed); Message = $message; Duration = (Get-Date) - $start; Installed = $installed }
}

function Register-PostRebootCheck([string]$LanguageTag, [string]$DisplayName) {
    $script = @"
Add-Type -AssemblyName PresentationFramework
`$target = '$LanguageTag'
`$sys = try { Get-SystemPreferredUILanguage } catch { '' }
`$ui = (Get-UICulture).Name
if (`$sys -eq `$target -or `$ui -eq `$target) {
    [System.Windows.MessageBox]::Show("Đã chuyển ngôn ngữ hiển thị sang $DisplayName (`$target) thành công.``n``nMột vài ứng dụng có sẵn sẽ tự đổi ngôn ngữ sau khi Microsoft Store cập nhật.", 'KATK Tools', 'OK', 'Information') | Out-Null
} else {
    [System.Windows.MessageBox]::Show("Chưa chuyển được sang $DisplayName (`$target).``nNgôn ngữ hệ thống: `$sys``nNgôn ngữ giao diện: `$ui``n``nHãy khởi động lại máy thêm một lần, nếu vẫn chưa được hãy chạy lại tính năng trong KATK Tools.", 'KATK Tools', 'OK', 'Warning') | Out-Null
}
"@
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($script))
    $command = "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -EncodedCommand $encoded"
    try {
        New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce" -Force -ErrorAction SilentlyContinue | Out-Null
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce" -Name "KATKLanguageCheck" -Value $command -ErrorAction Stop
        Write-Host "✔ Đã hẹn kiểm tra kết quả ở lần đăng nhập tới." -ForegroundColor Green
    } catch {
        Write-Host "⚠ Không tạo được bước kiểm tra sau khởi động: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

function Set-Language {
    param(
        [string]$LanguageTag,
        [string]$DisplayName,
        [string]$HexCode
    )

    Show-Step "Đang xử lý $DisplayName ($LanguageTag)"

    if (-not (Test-Prerequisites)) {
        Wait-KATKBack
        return $false
    }

    $changeLocale = Read-YesNo "Đổi cả System Locale (ảnh hưởng font/bảng mã của phần mềm cũ không hỗ trợ Unicode)?"

    $installed = Get-InstalledLanguage -ErrorAction SilentlyContinue | Where-Object { $_.LanguageId -eq $LanguageTag }
    if ($installed) {
        Write-Host "✔ Gói ngôn ngữ $LanguageTag đã có sẵn, bỏ qua bước tải." -ForegroundColor Green
    } else {
        $wuState = Enable-UpdatePrerequisites
        try {
            $result = $null
            for ($attempt = 1; $attempt -le $script:MaxAttempts; $attempt++) {
                Write-Host "→ Đang cài gói ngôn ngữ và Local Experience Pack (lần $attempt/$script:MaxAttempts)..." -ForegroundColor Yellow
                Write-Host "  Dung lượng và thời gian chỉ là ước lượng. Vui lòng không đóng cửa sổ trong quá trình chờ!" -ForegroundColor DarkGray
                $result = Invoke-LanguageInstall $LanguageTag
                if ($result.Success) { break }
                Write-Host "⚠ Lần $attempt thất bại: $($result.Message)" -ForegroundColor Yellow
                if ($attempt -lt $script:MaxAttempts) {
                    Write-Host "  Thử lại sau 10 giây..." -ForegroundColor DarkGray
                    Start-Sleep -Seconds 10
                }
            }
        } finally {
            Restore-UpdatePrerequisites $wuState
        }
        if (-not $result.Success) {
            Write-Host "❌ Không cài được gói ngôn ngữ sau $script:MaxAttempts lần thử." -ForegroundColor Red
            Write-Host "  Hãy kiểm tra kết nối mạng, mở Windows Update xem có lỗi không, rồi chạy lại." -ForegroundColor DarkGray
            Wait-KATKBack
            return $false
        }
        Write-Host "✔ Cài đặt thành công sau $(Format-Duration $result.Duration.TotalSeconds)" -ForegroundColor Green
        Write-Host "  Thành phần: $($result.Installed.LanguagePacks)" -ForegroundColor DarkGray
    }

    Write-Host "→ Đặt ngôn ngữ hiển thị..." -ForegroundColor Yellow
    try {
        $langList = New-WinUserLanguageList -Language $LanguageTag
        foreach ($existing in Get-WinUserLanguageList) {
            if ($existing.LanguageTag -ne $LanguageTag) { $langList.Add($existing) }
        }
        Set-WinUserLanguageList -LanguageList $langList -Force -ErrorAction Stop
    } catch {
        Write-Host "⚠ Lỗi: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    Write-Host "→ Ghi đè UI Language..." -ForegroundColor Yellow
    try {
        Set-WinUILanguageOverride -Language $LanguageTag -ErrorAction Stop
    } catch {
        Write-Host "⚠ Lỗi: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    if (Get-Command Set-SystemPreferredUILanguage -ErrorAction SilentlyContinue) {
        Write-Host "→ Đặt ngôn ngữ hệ thống..." -ForegroundColor Yellow
        try {
            Set-SystemPreferredUILanguage -Language $LanguageTag -ErrorAction Stop
        } catch {
            Write-Host "⚠ Lỗi: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    if ($changeLocale) {
        Write-Host "→ Thay đổi System Locale..." -ForegroundColor Yellow
        try {
            Set-WinSystemLocale -SystemLocale $LanguageTag -ErrorAction Stop
        } catch {
            Write-Host "⚠ Lỗi: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    } else {
        Write-Host "→ Giữ nguyên System Locale." -ForegroundColor DarkGray
    }

    Write-Host "→ Cập nhật registry..." -ForegroundColor Yellow
    $regs = @(
        @("HKCU\Control Panel\International", "LocaleName", $LanguageTag),
        @("HKCU\Control Panel\International", "UserLocale", $LanguageTag),
        @("HKCU\Control Panel\Desktop", "UserLocale", $LanguageTag),
        @("HKCU\Control Panel\Desktop\MuiCached", "PreferredUILanguages", $LanguageTag),
        @("HKCU\Control Panel\Desktop\MuiCached", "MachinePreferredUILanguages", $LanguageTag),
        @("HKCU\Software\Microsoft\Windows NT\CurrentVersion\Winlogon", "DefaultLanguage", $HexCode),
        @("HKU\.DEFAULT\Control Panel\International", "LocaleName", $LanguageTag),
        @("HKU\.DEFAULT\Control Panel\International", "UserLocale", $LanguageTag),
        @("HKU\.DEFAULT\Software\Microsoft\Windows NT\CurrentVersion\Winlogon", "DefaultLanguage", $HexCode)
    )
    if ($script:IsSingleLanguage) {
        $regs += @(
            @("HKLM\SYSTEM\CurrentControlSet\Control\Nls\Language", "Default", $HexCode),
            @("HKLM\SYSTEM\CurrentControlSet\Control\Nls\Language", "InstallLanguage", $HexCode),
            @("HKLM\SYSTEM\CurrentControlSet\Control\Nls\Language", "InstallLanguageFallback", $HexCode)
        )
    }
    $failed = 0
    foreach ($r in $regs) {
        if (-not (Set-RegValue $r[0] $r[1] $r[2])) { $failed++ }
    }
    if ($failed -eq 0) {
        Write-Host "✔ Đã cập nhật registry." -ForegroundColor Green
    } else {
        Write-Host "⚠ Có $failed/$($regs.Count) khóa registry không ghi được." -ForegroundColor Yellow
    }

    if (Get-Command Copy-UserInternationalSettingsToSystem -ErrorAction SilentlyContinue) {
        Write-Host "→ Áp dụng cho màn hình chào và tài khoản mới..." -ForegroundColor Yellow
        try {
            Copy-UserInternationalSettingsToSystem -WelcomeScreen $true -NewUser $true -ErrorAction Stop
        } catch {
            Write-Host "⚠ Lỗi: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

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
    Register-PostRebootCheck $LanguageTag $DisplayName

    Write-Host ""
    Write-Host "✅ CÀI ĐẶT HOÀN TẤT!" -ForegroundColor Green
    Write-Host "Cần khởi động lại máy để ngôn ngữ mới có hiệu lực." -ForegroundColor Yellow
    if ($script:IsSingleLanguage) {
        Write-Host "Lưu ý: sau mỗi bản cập nhật Windows lớn (ví dụ 24H2 → 25H2), máy có thể quay về ngôn ngữ gốc, khi đó hãy chạy lại tính năng này." -ForegroundColor DarkGray
    }
    if (Read-YesNo "Khởi động lại ngay?") {
        Write-Host "Máy sẽ khởi động lại sau 10 giây..." -ForegroundColor Yellow
        shutdown /r /t 10
    } else {
        Write-Host "Hãy tự khởi động lại máy sau khi lưu công việc." -ForegroundColor Gray
        Wait-KATKBack
    }
    return $true
}

Assert-KATKAdmin

if (Test-IsArm) {
    Write-Host "❌ Tính năng chưa hỗ trợ Windows ARM!" -ForegroundColor Red
    Wait-KATKBack
    Exit-KATKModule
}

if (-not (Get-Command Install-Language -ErrorAction SilentlyContinue)) {
    Write-Host "❌ Windows này chưa có lệnh Install-Language (cần Windows 10 21H2 trở lên đã cập nhật hoặc Windows 11)." -ForegroundColor Red
    Wait-KATKBack
    Exit-KATKModule
}

if (-not (Test-InternetConnection)) {
    Write-Host "❌ Không có kết nối Internet!" -ForegroundColor Red
    Wait-KATKBack
    Exit-KATKModule
}

$editionId = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction SilentlyContinue).EditionID
$script:IsSingleLanguage = $editionId -eq 'CoreSingleLanguage'
$script:EditionName = if ($script:IsSingleLanguage) { "Home Single Language" } elseif ($editionId) { $editionId } else { "Không xác định" }
$script:CurrentUILanguage = Get-CurrentUILanguage

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
        Set-Language -LanguageTag $lang.Tag -DisplayName $lang.Name -HexCode $lang.Hex | Out-Null
        break
    } else {
        Write-Host "❌ Lựa chọn không hợp lệ!" -ForegroundColor Red
        Start-Sleep -Seconds 1
    }
} while ($true)
