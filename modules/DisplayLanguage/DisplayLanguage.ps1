if (-not (Get-Command Show-KATKHeader -ErrorAction SilentlyContinue)) {
    $katkBase = if ($global:KATK_BaseUrl) { $global:KATK_BaseUrl } else { "https://raw.githubusercontent.com/katk410/KATK-Tools/stable" }
    Invoke-Expression ((Invoke-RestMethod -Uri "$katkBase/core/UI.ps1" -UseBasicParsing).TrimStart([char]0xFEFF))
}
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

$script:EstimatedSizeMB = 450
$script:BasePackMB = 150
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

function Test-PendingReboot {
    $keys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\PackagesPending",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
    )
    foreach ($k in $keys) { if (Test-Path $k) { return $true } }
    return $false
}

function Test-PendingRebootError([string]$Message) {
    return $Message -match '-2146498554|0x800F0806'
}

function Request-KATKRestart {
    if (Read-YesNo "Khởi động lại ngay?") {
        Write-Host "Máy sẽ khởi động lại sau 10 giây..." -ForegroundColor Yellow
        shutdown /r /t 10
    } else {
        Write-Host "Hãy tự khởi động lại máy sau khi lưu công việc." -ForegroundColor Gray
        Wait-KATKBack
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

function Get-LanguageDownloadSize([string]$LanguageTag) {
    $fontMap = @{ 'zh-CN' = 'Hans'; 'zh-TW' = 'Hant'; 'ja-JP' = 'Jpan'; 'ko-KR' = 'Kore'; 'th-TH' = 'Thai' }
    $total = 0.0
    try {
        $caps = Get-WindowsCapability -Online -ErrorAction Stop | Where-Object {
            $_.State -ne 'Installed' -and (
                $_.Name -like "Language.*~~~$LanguageTag~*" -or
                ($fontMap.ContainsKey($LanguageTag) -and $_.Name -like "Language.Fonts.$($fontMap[$LanguageTag])~*")
            )
        }
        foreach ($cap in $caps) {
            $detail = Get-WindowsCapability -Online -Name $cap.Name -ErrorAction SilentlyContinue
            if ($detail -and $detail.DownloadSize -gt 0) { $total += $detail.DownloadSize }
        }
    } catch {}
    if ($total -gt 0) { return $total + $script:BasePackMB * 1MB }
    return [double]($script:EstimatedSizeMB * 1MB)
}

function Get-DeliverySnapshot {
    $map = @{}
    try {
        foreach ($s in Get-DeliveryOptimizationStatus -ErrorAction Stop) {
            if ($s.FileId) { $map[$s.FileId] = @{ Size = [double]$s.FileSize; Done = [double]$s.TotalBytesDownloaded } }
        }
    } catch { return $null }
    return $map
}

function Measure-DeliveryProgress($Baseline, $Current) {
    $downloaded = 0.0
    $remaining = 0.0
    $files = 0
    foreach ($id in $Current.Keys) {
        $now = $Current[$id]
        $before = if ($Baseline -and $Baseline.ContainsKey($id)) { $Baseline[$id].Done } else { 0 }
        $delta = $now.Done - $before
        if ($delta -le 0) { continue }
        $files++
        $downloaded += $delta
        if ($now.Size -gt $now.Done) { $remaining += $now.Size - $now.Done }
    }
    return @{ Downloaded = $downloaded; Remaining = $remaining; Files = $files }
}

function Invoke-LanguageInstall([string]$LanguageTag) {
    Write-Host "  Đang tính dung lượng cần tải..." -ForegroundColor DarkGray
    $estimate = Get-LanguageDownloadSize $LanguageTag
    $doBaseline = Get-DeliverySnapshot
    $netBase = Get-ReceivedBytes

    $job = Start-Job -ScriptBlock {
        param($tag)
        Import-Module LanguagePackManagement -ErrorAction SilentlyContinue
        Install-Language -Language $tag -CopyToSettings -ErrorAction Stop | Out-Null
    } -ArgumentList $LanguageTag

    $spinner = '|', '/', '-', '\'
    $start = Get-Date
    $lastDownloaded = 0.0
    $lastTime = $start
    $speed = 0.0
    $tick = 0

    while ($job.State -eq 'Running' -or $job.State -eq 'NotStarted') {
        Start-Sleep -Milliseconds 1000
        $tick++
        $now = Get-Date

        $remaining = 0.0
        $doNow = if ($null -ne $doBaseline) { Get-DeliverySnapshot } else { $null }
        $doProgress = if ($doNow) { Measure-DeliveryProgress $doBaseline $doNow } else { $null }
        if ($doProgress -and $doProgress.Files -gt 0) {
            $downloaded = $doProgress.Downloaded
            $remaining = $doProgress.Remaining
        } else {
            $downloaded = [math]::Max(0, (Get-ReceivedBytes) - $netBase)
        }

        $interval = ($now - $lastTime).TotalSeconds
        if ($interval -gt 0 -and $downloaded -ge $lastDownloaded) {
            $current = ($downloaded - $lastDownloaded) / $interval
            $speed = if ($speed -eq 0) { $current } else { $speed * 0.7 + $current * 0.3 }
        }
        $lastDownloaded = $downloaded
        $lastTime = $now

        $total = [math]::Max($estimate, $downloaded + $remaining)
        $elapsed = ($now - $start).TotalSeconds
        $percent = [math]::Min(99, [math]::Floor($downloaded / $total * 100))
        $avgSpeed = if ($elapsed -gt 0) { $downloaded / $elapsed } else { 0 }
        $rate = if ($speed -gt 1KB) { $speed } else { $avgSpeed }
        $eta = if ($rate -gt 1KB) { Format-Duration (($total - $downloaded) / $rate) } else { "--:--" }

        $bar = ('█' * [math]::Floor($percent / 5)).PadRight(20, '░')
        Show-InstallProgress (" $($spinner[$tick % 4]) $bar $("$percent%".PadLeft(3))  ·  Đã chạy $(Format-Duration $elapsed)  ·  $(Format-Size $speed)/s  ·  Còn ~$eta")
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
function Test-Match(`$v) { `$v -and (`$v -eq `$target -or `$target -like "`$v-*" -or `$v -like "`$target-*") }
if ((Test-Match `$sys) -or (Test-Match `$ui)) {
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
        if (Test-PendingReboot) {
            Write-Host "❌ Windows đang chờ khởi động lại để hoàn tất cập nhật hoặc cài đặt trước đó." -ForegroundColor Red
            Write-Host "  Cài gói ngôn ngữ lúc này sẽ lỗi 0x800F0806. Hãy khởi động lại máy rồi chạy lại tính năng này." -ForegroundColor DarkGray
            Request-KATKRestart
            return $false
        }
        $wuState = Enable-UpdatePrerequisites
        try {
            $result = $null
            $needReboot = $false
            for ($attempt = 1; $attempt -le $script:MaxAttempts; $attempt++) {
                Write-Host "→ Đang cài gói ngôn ngữ và Local Experience Pack (lần $attempt/$script:MaxAttempts)..." -ForegroundColor Yellow
                Write-Host "  Dung lượng và thời gian chỉ là ước lượng. Vui lòng không đóng cửa sổ trong quá trình chờ!" -ForegroundColor DarkGray
                $result = Invoke-LanguageInstall $LanguageTag
                if ($result.Success) { break }
                Write-Host "⚠ Lần $attempt thất bại: $($result.Message)" -ForegroundColor Yellow
                if (Test-PendingRebootError $result.Message) {
                    $needReboot = $true
                    break
                }
                if ($attempt -lt $script:MaxAttempts) {
                    Write-Host "  Thử lại sau 10 giây..." -ForegroundColor DarkGray
                    Start-Sleep -Seconds 10
                }
            }
        } finally {
            Restore-UpdatePrerequisites $wuState
        }
        if ($needReboot) {
            Write-Host "❌ Windows đang có bản cập nhật hoặc gói cài đặt chờ khởi động lại (0x800F0806)." -ForegroundColor Red
            Write-Host "  Một phần gói ngôn ngữ có thể đã được cài. Hãy khởi động lại máy rồi chạy lại tính năng này để cài nốt." -ForegroundColor DarkGray
            Request-KATKRestart
            return $false
        }
        if (-not $result.Success) {
            Write-Host "❌ Không cài được gói ngôn ngữ sau $script:MaxAttempts lần thử." -ForegroundColor Red
            Write-Host "  Hãy kiểm tra kết nối mạng, mở Windows Update xem có lỗi không, rồi chạy lại." -ForegroundColor DarkGray
            Wait-KATKBack
            return $false
        }
        Write-Host "✔ Cài đặt thành công sau $(Format-Duration $result.Duration.TotalSeconds)" -ForegroundColor Green
    }

    Write-Host "→ Đặt ngôn ngữ hiển thị..." -ForegroundColor Yellow
    try {
        $langList = Get-WinUserLanguageList
        for ($i = $langList.Count - 1; $i -ge 0; $i--) {
            $existingTag = $langList[$i].LanguageTag
            if ($existingTag -eq $LanguageTag -or $LanguageTag -like "$existingTag-*") { $langList.RemoveAt($i) }
        }
        $langList.Insert(0, $LanguageTag)
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
    $nls = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Nls\Language" -ErrorAction SilentlyContinue
    $override = Get-WinUILanguageOverride
    $checks = @(
        @{ Name = "Ngôn ngữ hệ thống (sau khởi động lại)"; Value = (Get-CurrentUILanguage); Expect = $LanguageTag },
        @{ Name = "UI Language Override"; Value = $(if ($override) { $override.Name } else { "" }); Expect = $LanguageTag },
        @{ Name = "Ngôn ngữ đầu danh sách"; Value = (Get-WinUserLanguageList)[0].LanguageTag; Expect = $LanguageTag },
        @{ Name = "System Locale"; Value = (Get-WinSystemLocale).Name; Expect = $(if ($changeLocale) { $LanguageTag } else { $null }) },
        @{ Name = "Nls InstallLanguage"; Value = $nls.InstallLanguage; Expect = $(if ($script:IsSingleLanguage) { $HexCode } else { $null }) }
    )
    foreach ($c in $checks) {
        $label = $c.Name.PadRight(40)
        if (-not $c.Expect) {
            Write-Host "  • $label $($c.Value)" -ForegroundColor Gray
        } elseif ($c.Value -and ($c.Value -eq $c.Expect -or $c.Expect -like "$($c.Value)-*" -or $c.Value -like "$($c.Expect)-*")) {
            Write-Host "  ✔ $label $($c.Value)" -ForegroundColor Green
        } else {
            Write-Host "  ⚠ $label $($c.Value) (cần $($c.Expect))" -ForegroundColor Yellow
        }
    }
    Write-Host "  Ngôn ngữ đã cài: $((Get-InstalledLanguage -ErrorAction SilentlyContinue | ForEach-Object { $_.LanguageId }) -join ', ')" -ForegroundColor Gray

    Write-Host ""
    Register-PostRebootCheck $LanguageTag $DisplayName

    Write-Host ""
    Write-Host "✅ CÀI ĐẶT HOÀN TẤT!" -ForegroundColor Green
    Write-Host "Cần khởi động lại máy để ngôn ngữ mới có hiệu lực." -ForegroundColor Yellow
    if ($script:IsSingleLanguage) {
        Write-Host "Lưu ý: sau mỗi bản cập nhật Windows lớn (ví dụ 24H2 → 25H2), máy có thể quay về ngôn ngữ gốc, khi đó hãy chạy lại tính năng này." -ForegroundColor DarkGray
    }
    Request-KATKRestart
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
