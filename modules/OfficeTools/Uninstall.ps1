function Write-KATKUnLog([string]$Text) {
    try { Add-Content -LiteralPath $st.Log -Value ("{0}  {1}" -f (Get-Date -Format 'HH:mm:ss'), $Text) -Encoding UTF8 } catch {}
}

function Get-KATKUnLogPath {
    $desk = [Environment]::GetFolderPath('Desktop')
    if (-not $desk -or -not (Test-Path -LiteralPath $desk)) { $desk = Join-Path $env:PUBLIC 'Desktop' }
    $path = Join-Path $desk 'KATK-GoOffice.log'
    try { if ((Test-Path -LiteralPath $path) -and (Get-Item -LiteralPath $path).Length -gt 5MB) { Remove-Item -LiteralPath $path -Force } } catch {}
    return $path
}

function Write-KATKUnLogHeader {
    $os = ""
    try {
        $cv = 'SOFTWARE\Microsoft\Windows NT\CurrentVersion'
        $cap = (Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).Caption
        $os = "$cap $(Get-KATKRegValue $hklm $cv 'DisplayVersion') build $(Get-KATKRegValue $hklm $cv 'CurrentBuild').$(Get-KATKRegValue $hklm $cv 'UBR') ($env:PROCESSOR_ARCHITECTURE)"
    }
    catch { $os = "khong doc duoc" }
    $branch = if ($global:KATK_Branch) { $global:KATK_Branch } else { "chay rieng" }
    try {
        Add-Content -LiteralPath $st.Log -Encoding UTF8 -Value @(
            "",
            ("=" * 70),
            "KATK - GO SACH OFFICE   $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
            "May: $env:COMPUTERNAME | Tai khoan: $env:USERNAME",
            "Windows: $os",
            "PowerShell: $($PSVersionTable.PSVersion) | KATK Tools: $global:KATK_Version ($branch)",
            ("-" * 70)
        )
    }
    catch {}
}

function Write-KATKInventoryLog([string]$Label, $Inv) {
    Write-KATKUnLog "--- $Label"
    if (Test-KATKInventoryEmpty $Inv) { Write-KATKUnLog "    (khong con dau vet Office)"; return }
    if ($Inv.C2R.Count) { Write-KATKUnLog "    C2R     : $($Inv.C2R -join ', ') $($Inv.C2RVersion)" }
    foreach ($a in $Inv.Arp) { Write-KATKUnLog "    ARP     : $($a.DisplayName) [$($a.Key)]" }
    foreach ($m in $Inv.Msi) { Write-KATKUnLog "    MSI     : $($m.Code) $($m.Name)" }
    foreach ($a in $Inv.Appx) { Write-KATKUnLog "    APPX    : $($a.PackageFullName)" }
    foreach ($k in $Inv.Keys) { Write-KATKUnLog "    KEY     : $k" }
    foreach ($s in $Inv.Services) { Write-KATKUnLog "    SERVICE : $s" }
    foreach ($t in $Inv.Tasks) { Write-KATKUnLog "    TASK    : $t" }
    foreach ($d in $Inv.Dirs) { Write-KATKUnLog "    THU MUC : $d" }
}

function Start-KATKUnStep([string]$Text) {
    Show-Step $Text
    Write-KATKUnLog "--- $Text"
}

function Initialize-KATKNative {
    if (-not ("KATK.NativeFile" -as [type])) {
        Add-Type -Namespace KATK -Name NativeFile -MemberDefinition '[DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)] public static extern bool MoveFileEx(string lpExistingFileName, string lpNewFileName, int dwFlags);'
    }
}

function ConvertFrom-KATKPacked([string]$Packed) {
    $p = $Packed.ToUpper()
    $g1 = -join $p.Substring(0, 8).ToCharArray()[7..0]
    $g2 = -join $p.Substring(8, 4).ToCharArray()[3..0]
    $g3 = -join $p.Substring(12, 4).ToCharArray()[3..0]
    $rest = ""
    for ($i = 16; $i -lt 32; $i += 2) { $rest += "$($p[$i + 1])$($p[$i])" }
    return "{" + $g1 + "-" + $g2 + "-" + $g3 + "-" + $rest.Substring(0, 4) + "-" + $rest.Substring(4) + "}"
}

function Get-KATKHive([string]$Name) {
    return [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::$Name, [Microsoft.Win32.RegistryView]::Registry64)
}

function Get-KATKRegValue($Root, [string]$Path, [string]$Name = '') {
    $k = $Root.OpenSubKey($Path)
    if ($null -eq $k) { return $null }
    try { return $k.GetValue($Name) } finally { $k.Close() }
}

function Get-KATKSubKeys($Root, [string]$Path) {
    $k = $Root.OpenSubKey($Path)
    if ($null -eq $k) { return @() }
    try { return $k.GetSubKeyNames() } finally { $k.Close() }
}

function Test-KATKRegKey($Root, [string]$Path) {
    $k = $Root.OpenSubKey($Path)
    if ($null -eq $k) { return $false }
    $k.Close()
    return $true
}

function Remove-KATKRegKey($Root, [string]$Path) {
    if (-not (Test-KATKRegKey $Root $Path)) { return }
    try {
        $Root.DeleteSubKeyTree($Path, $false)
        $st.Reg++
        Write-KATKUnLog "REG   $($Root.Name)\$Path"
    }
    catch {
        $st.Fail++
        Write-KATKUnLog "LOI   $($Root.Name)\$Path : $($_.Exception.Message)"
    }
}

function Remove-KATKRegValue($Root, [string]$Path, [string]$Name) {
    try {
        $k = $Root.OpenSubKey($Path, $true)
        if ($null -eq $k) { return }
        if ($k.GetValueNames() -contains $Name) {
            $k.DeleteValue($Name, $false)
            $st.Reg++
            Write-KATKUnLog "VAL   $($Root.Name)\$Path -> $Name"
        }
        $k.Close()
    }
    catch {
        $st.Fail++
        Write-KATKUnLog "LOI   $($Root.Name)\$Path -> $Name : $($_.Exception.Message)"
    }
}

function Remove-KATKPath([string]$Path) {
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return }
    try {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
        $st.Files++
        Write-KATKUnLog "XOA   $Path"
        return
    }
    catch {}
    Initialize-KATKNative
    $items = @(Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue | Sort-Object { $_.FullName.Length } -Descending)
    $self = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if ($self) { $items += $self }
    foreach ($it in $items) {
        if (-not (Test-Path -LiteralPath $it.FullName)) { continue }
        try { Remove-Item -LiteralPath $it.FullName -Recurse -Force -ErrorAction Stop }
        catch {
            if ([KATK.NativeFile]::MoveFileEx($it.FullName, $null, 4)) {
                $st.Pending++
                Write-KATKUnLog "BOOT  $($it.FullName)"
            }
            else {
                $st.Fail++
                Write-KATKUnLog "LOI   $($it.FullName)"
            }
        }
    }
    $st.Files++
    Write-KATKUnLog "XOA*  $Path"
}

function Get-KATKOfficeDirs {
    $pf = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramW6432) | Where-Object { $_ } | Select-Object -Unique
    $cf = @($env:CommonProgramFiles, ${env:CommonProgramFiles(x86)}, $env:CommonProgramW6432) | Where-Object { $_ } | Select-Object -Unique
    $dirs = @()
    foreach ($p in $pf) { $dirs += "$p\Microsoft Office", "$p\Microsoft Office 15", "$p\Microsoft Office 16" }
    foreach ($c in $cf) {
        $dirs += "$c\Microsoft Shared\ClickToRun", "$c\Microsoft Shared\OfficeSoftwareProtectionPlatform", "$c\Microsoft Shared\Source Engine"
        foreach ($v in 11..16) { $dirs += "$c\Microsoft Shared\OFFICE$v" }
    }
    $dirs += "$env:ProgramData\Microsoft\ClickToRun", "$env:ProgramData\Microsoft\Office", "$env:ProgramData\Microsoft\OfficeSoftwareProtectionPlatform", "$env:SystemDrive\MSOCache"
    return $dirs | Select-Object -Unique
}

function Get-KATKProfiles {
    $list = @()
    $base = 'SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
    foreach ($sid in Get-KATKSubKeys $hklm $base) {
        if ($sid -notmatch '^S-1-5-21-[\d-]+$') { continue }
        $p = Get-KATKRegValue $hklm "$base\$sid" 'ProfileImagePath'
        if (-not $p) { continue }
        $p = [Environment]::ExpandEnvironmentVariables($p)
        if (Test-Path -LiteralPath $p) { $list += [pscustomobject]@{ Sid = $sid; Path = $p } }
    }
    return $list
}

function Get-KATKOfficeInventory {
    $inv = [pscustomobject]@{ C2R = @(); C2RVersion = ""; Arp = @(); Msi = @(); Appx = @(); Dirs = @(); Services = @(); Tasks = @(); Keys = @() }
    $cfg = 'SOFTWARE\Microsoft\Office\ClickToRun\Configuration'
    $ids = [string](Get-KATKRegValue $hklm $cfg 'ProductReleaseIds')
    if ($ids) {
        $inv.C2R = @($ids -split ',' | Where-Object { $_ })
        $inv.C2RVersion = [string](Get-KATKRegValue $hklm $cfg 'VersionToReport')
    }
    foreach ($base in 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall') {
        foreach ($n in Get-KATKSubKeys $hklm $base) {
            $p = "$base\$n"
            $us = [string](Get-KATKRegValue $hklm $p 'UninstallString')
            $isC2R = $us -match '(?i)OfficeClickToRun\.exe'
            $isMsi = $n -match '(?i)^\{[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-0000000FF1CE\}$'
            $isSuite = ($n -match '(?i)^Office1[1-6]\.') -or ($us -match '(?i)Office Setup Controller')
            if (-not ($isC2R -or $isMsi -or $isSuite)) { continue }
            $inv.Arp += [pscustomobject]@{
                Key         = $p
                Name        = $n
                DisplayName = [string](Get-KATKRegValue $hklm $p 'DisplayName')
                Uninstall   = $us
                C2R         = $isC2R
                System      = ((Get-KATKRegValue $hklm $p 'SystemComponent') -eq 1)
            }
        }
    }
    foreach ($pk in Get-KATKSubKeys $hklm 'SOFTWARE\Classes\Installer\Products') {
        if ($pk -notmatch '(?i)^[0-9A-F]{26}F01FEC$') { continue }
        $inv.Msi += [pscustomobject]@{
            Packed = $pk.ToUpper()
            Code   = ConvertFrom-KATKPacked $pk
            Name   = [string](Get-KATKRegValue $hklm "SOFTWARE\Classes\Installer\Products\$pk" 'ProductName')
        }
    }
    try { $inv.Appx = @(Get-AppxPackage -AllUsers -ErrorAction Stop | Where-Object { $_.Name -like 'Microsoft.Office.Desktop*' }) } catch {}
    $inv.Dirs = @(Get-KATKOfficeDirs | Where-Object { Test-Path -LiteralPath $_ })
    $inv.Services = @(Get-Service -Name 'ClickToRunSvc', 'osppsvc', 'ose', 'ose64' -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
    $inv.Tasks = @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskPath -like '\Microsoft\Office\*' } | ForEach-Object { $_.TaskName })
    $inv.Keys = @(foreach ($cls in 'SoftwareLicensingProduct', 'OfficeSoftwareProtectionProduct') {
        try { Get-CimInstance -ClassName $cls -Filter "ApplicationID='$officeApp' AND PartialProductKey IS NOT NULL" -ErrorAction Stop | ForEach-Object { $_.Name } } catch {}
    })
    return $inv
}

function Test-KATKInventoryEmpty($Inv) {
    return ($Inv.C2R.Count + $Inv.Arp.Count + $Inv.Msi.Count + $Inv.Appx.Count + $Inv.Dirs.Count + $Inv.Services.Count + $Inv.Tasks.Count + $Inv.Keys.Count) -eq 0
}

function Show-KATKOfficeInventory($Inv) {
    Write-Host ""
    Write-Host "OFFICE PHÁT HIỆN TRÊN MÁY:" -ForegroundColor Yellow
    Write-KATKLine
    if ($Inv.C2R.Count) { Write-Host " • Click-to-Run : $($Inv.C2R -join ', ')  ($($Inv.C2RVersion))" -ForegroundColor White }
    foreach ($a in $Inv.Arp | Where-Object { -not $_.System }) { Write-Host " • Đã cài      : $($a.DisplayName)" -ForegroundColor White }
    $msiMain = @($Inv.Msi | Where-Object { $_.Name })
    if ($msiMain.Count) { Write-Host " • Gói MSI     : $($Inv.Msi.Count) gói ($((($msiMain | Select-Object -First 3).Name) -join ', ')$(if ($msiMain.Count -gt 3) { ', ...' }))" -ForegroundColor White }
    if ($Inv.Appx.Count) { Write-Host " • Bản Store   : $(($Inv.Appx.Name | Select-Object -Unique) -join ', ')" -ForegroundColor White }
    if ($Inv.Keys.Count) { Write-Host " • Key bản quyền: $($Inv.Keys.Count) ($(($Inv.Keys | Select-Object -Unique) -join ', '))" -ForegroundColor White }
    if ($Inv.Services.Count) { Write-Host " • Service     : $($Inv.Services -join ', ')" -ForegroundColor White }
    if ($Inv.Tasks.Count) { Write-Host " • Task        : $($Inv.Tasks.Count) tác vụ hẹn giờ" -ForegroundColor White }
    if ($Inv.Dirs.Count) { Write-Host " • Thư mục     : $($Inv.Dirs.Count) thư mục Office" -ForegroundColor White }
    if (Test-KATKInventoryEmpty $Inv) { Write-Host " Không phát hiện Office." -ForegroundColor Green }
    Write-KATKLine
}

function Stop-KATKOfficeApps([switch]$Engine) {
    $names = 'WINWORD', 'EXCEL', 'POWERPNT', 'OUTLOOK', 'ONENOTE', 'ONENOTEM', 'MSACCESS', 'MSPUB', 'VISIO', 'WINPROJ',
             'LYNC', 'GROOVE', 'MSOSYNC', 'MSOUC', 'msoia', 'msoadfsb', 'SDXHelper', 'IntegratedOffice', 'AppVShNotify', 'OfficeC2RClient'
    if ($Engine) { $names += 'OfficeClickToRun', 'OSPPSVC' }
    foreach ($n in $names) { Get-Process -Name $n -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue }
}

function Invoke-KATKC2RUninstall($Inv) {
    $items = @($Inv.Arp | Where-Object { $_.C2R })
    if (-not $items.Count) { Write-Host "  Không có bản Click-to-Run." -ForegroundColor DarkGray; return }
    foreach ($a in $items) {
        if ($a.Uninstall -notmatch '^\s*"([^"]+)"\s*(.*)$') { continue }
        $exe = $Matches[1]
        $argList = $Matches[2] + ' DisplayLevel=False'
        if (-not (Test-Path -LiteralPath $exe)) { Write-Host "  ⚠ Thiếu trình gỡ của $($a.DisplayName) - sẽ dọn thủ công." -ForegroundColor Yellow; Write-KATKUnLog "CANH  thieu trinh go: $exe"; continue }
        Write-Host "  → Đang gỡ $($a.DisplayName) (có thể mất 5-15 phút)..." -ForegroundColor Cyan
        Write-KATKUnLog "C2R   $exe $argList"
        $p = Start-Process -FilePath $exe -ArgumentList $argList -PassThru
        if (-not $p.WaitForExit(2700000)) { Write-Host "  ⚠ Quá thời gian chờ - tiếp tục dọn thủ công." -ForegroundColor Yellow; Write-KATKUnLog "CANH  C2R qua thoi gian cho"; continue }
        $t = 0
        while ((Get-Process -Name 'OfficeC2RClient' -ErrorAction SilentlyContinue) -and $t -lt 600) { Start-Sleep -Seconds 2; $t += 2 }
        if ($p.ExitCode -eq 0) { Write-Host "  ✔ Đã gỡ $($a.DisplayName)" -ForegroundColor Green }
        else { Write-Host "  ⚠ Trình gỡ trả mã $($p.ExitCode) - sẽ dọn thủ công." -ForegroundColor Yellow }
        Write-KATKUnLog "C2R   ma $($p.ExitCode)"
    }
}

function Invoke-KATKMsiUninstall($Inv) {
    if (-not $Inv.Msi.Count) { Write-Host "  Không có gói MSI." -ForegroundColor DarkGray; return }
    $sys = @{}
    foreach ($a in $Inv.Arp) { if ($a.System) { $sys[$a.Name.ToUpper()] = $true } }
    $ordered = @($Inv.Msi | Sort-Object { if ($sys.ContainsKey($_.Code.ToUpper())) { 1 } else { 0 } })
    foreach ($m in $ordered) {
        if (-not (Test-KATKRegKey $hklm "SOFTWARE\Classes\Installer\Products\$($m.Packed)")) { continue }
        $label = if ($m.Name) { $m.Name } else { $m.Code }
        Write-Host "  → Gỡ $label..." -ForegroundColor Cyan
        $p = Start-Process -FilePath "$env:SystemRoot\System32\msiexec.exe" -ArgumentList "/x $($m.Code) /qn /norestart REBOOT=ReallySuppress" -PassThru
        if (-not $p.WaitForExit(1800000)) { Write-Host "    ⚠ Quá thời gian chờ" -ForegroundColor Yellow; Write-KATKUnLog "CANH  MSI qua thoi gian cho: $($m.Code)"; continue }
        Write-KATKUnLog "MSI   $($m.Code) $label ma $($p.ExitCode)"
        switch ($p.ExitCode) {
            0       { Write-Host "    ✔ Xong" -ForegroundColor Green }
            1605    { Write-Host "    ✔ Đã được gỡ trước đó" -ForegroundColor DarkGray }
            1641    { Write-Host "    ✔ Xong (cần khởi động lại)" -ForegroundColor Green }
            3010    { Write-Host "    ✔ Xong (cần khởi động lại)" -ForegroundColor Green }
            default { Write-Host "    ⚠ Mã $($p.ExitCode) - sẽ dọn thủ công" -ForegroundColor Yellow }
        }
    }
}

function Remove-KATKOfficeKeys {
    $n = 0
    foreach ($cls in 'SoftwareLicensingProduct', 'OfficeSoftwareProtectionProduct') {
        try {
            Get-CimInstance -ClassName $cls -Filter "ApplicationID='$officeApp' AND PartialProductKey IS NOT NULL" -ErrorAction Stop | ForEach-Object {
                try {
                    Invoke-CimMethod -InputObject $_ -MethodName UninstallProductKey -ErrorAction Stop | Out-Null
                    $n++
                    Write-KATKUnLog "KEY   $($_.Name) (*$($_.PartialProductKey))"
                }
                catch { $st.Fail++; Write-KATKUnLog "LOI   key $($_.Name): $($_.Exception.Message)" }
            }
        }
        catch {}
    }
    Write-Host "  ✔ Đã gỡ $n key bản quyền Office" -ForegroundColor Green
}

function Remove-KATKOfficeServices {
    foreach ($s in 'ClickToRunSvc', 'osppsvc', 'ose', 'ose64') {
        if (-not (Get-Service -Name $s -ErrorAction SilentlyContinue)) { continue }
        Stop-Service -Name $s -Force -ErrorAction SilentlyContinue
        & sc.exe delete $s | Out-Null
        if ($LASTEXITCODE -eq 0) { Write-Host "  ✔ Service $s" -ForegroundColor Green; Write-KATKUnLog "SVC   $s" }
        else { $st.Fail++; Write-Host "  ⚠ Không xóa được service $s" -ForegroundColor Yellow; Write-KATKUnLog "LOI   khong xoa duoc service $s (ma $LASTEXITCODE)" }
    }
    Remove-KATKRegKey $hklm 'SYSTEM\CurrentControlSet\Services\EventLog\Microsoft Office Alerts'
    $n = 0
    foreach ($t in @(Get-ScheduledTask -ErrorAction SilentlyContinue)) {
        $hit = $t.TaskPath -like '\Microsoft\Office\*'
        if (-not $hit) { foreach ($ac in $t.Actions) { if ("$($ac.Execute) $($ac.Arguments)" -match $pathRx) { $hit = $true } } }
        if (-not $hit) { continue }
        try {
            Unregister-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath -Confirm:$false -ErrorAction Stop
            $n++
            Write-KATKUnLog "TASK  $($t.TaskPath)$($t.TaskName)"
        }
        catch { $st.Fail++ }
    }
    Write-Host "  ✔ Đã xóa $n tác vụ hẹn giờ" -ForegroundColor Green
}

function Remove-KATKMsiRegistration([string[]]$Packed) {
    if (-not $Packed.Count) { return }
    $set = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($p in $Packed) { [void]$set.Add($p) }
    $patches = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $ud = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData'
    foreach ($sid in Get-KATKSubKeys $hklm $ud) {
        foreach ($p in $Packed) {
            $prod = "$ud\$sid\Products\$p"
            if (-not (Test-KATKRegKey $hklm $prod)) { continue }
            $lp = Get-KATKRegValue $hklm "$prod\InstallProperties" 'LocalPackage'
            if ($lp) { Remove-KATKPath $lp }
            foreach ($pp in Get-KATKSubKeys $hklm "$prod\Patches") { [void]$patches.Add($pp) }
            $pk = $hklm.OpenSubKey("$prod\Patches")
            if ($pk) { foreach ($v in $pk.GetValueNames()) { if ($v -match '^[0-9A-F]{32}$') { [void]$patches.Add($v) } }; $pk.Close() }
            Remove-KATKRegKey $hklm $prod
        }
        foreach ($pp in $patches) {
            $pkey = "$ud\$sid\Patches\$pp"
            $lp = Get-KATKRegValue $hklm $pkey 'LocalPackage'
            if ($lp) { Remove-KATKPath $lp }
            Remove-KATKRegKey $hklm $pkey
        }
    }
    foreach ($p in $Packed) {
        Remove-KATKRegKey $hklm "SOFTWARE\Classes\Installer\Products\$p"
        Remove-KATKRegKey $hklm "SOFTWARE\Classes\Installer\Features\$p"
        Remove-KATKPath "$env:SystemRoot\Installer\$(ConvertFrom-KATKPacked $p)"
    }
    foreach ($pp in $patches) { Remove-KATKRegKey $hklm "SOFTWARE\Classes\Installer\Patches\$pp" }
    Write-Host "  → Đang quét bảng thành phần Windows Installer..." -ForegroundColor DarkGray
    $compBases = @('SOFTWARE\Classes\Installer\Components', 'SOFTWARE\Classes\Installer\UpgradeCodes')
    foreach ($sid in Get-KATKSubKeys $hklm $ud) { $compBases += "$ud\$sid\Components" }
    foreach ($base in $compBases) {
        foreach ($c in Get-KATKSubKeys $hklm $base) {
            $k = $hklm.OpenSubKey("$base\$c")
            if ($null -eq $k) { continue }
            $names = $k.GetValueNames()
            $k.Close()
            $hits = @($names | Where-Object { $set.Contains($_) })
            if (-not $hits.Count) { continue }
            if ($hits.Count -eq @($names | Where-Object { $_ -ne '' }).Count) { Remove-KATKRegKey $hklm "$base\$c" }
            else { foreach ($h in $hits) { Remove-KATKRegValue $hklm "$base\$c" $h } }
        }
    }
}

function Remove-KATKOfficeArp {
    foreach ($a in (Get-KATKOfficeInventory).Arp) { Remove-KATKRegKey $hklm $a.Key }
}

function Remove-KATKOfficeMachineRegistry {
    $keys = @(
        'SOFTWARE\Microsoft\Office',
        'SOFTWARE\WOW6432Node\Microsoft\Office',
        'SOFTWARE\Microsoft\AppVISV',
        'SOFTWARE\Microsoft\OfficeSoftwareProtectionPlatform',
        'SOFTWARE\WOW6432Node\Microsoft\OfficeSoftwareProtectionPlatform',
        "SOFTWARE\Microsoft\Windows NT\CurrentVersion\SoftwareProtectionPlatform\$officeApp",
        "SOFTWARE\WOW6432Node\Microsoft\Windows NT\CurrentVersion\SoftwareProtectionPlatform\$officeApp",
        'SOFTWARE\Policies\Microsoft\Office',
        'SOFTWARE\Clients\Mail\Microsoft Outlook',
        'SOFTWARE\Clients\Calendar\Microsoft Outlook',
        'SOFTWARE\Clients\Contacts\Microsoft Outlook',
        'SOFTWARE\Clients\News\Microsoft Outlook',
        'SOFTWARE\Clients\Internet Call\Microsoft Outlook',
        'SOFTWARE\WOW6432Node\Clients\Mail\Microsoft Outlook'
    )
    foreach ($k in $keys) { Remove-KATKRegKey $hklm $k }
    foreach ($ra in 'SOFTWARE\RegisteredApplications', 'SOFTWARE\WOW6432Node\RegisteredApplications') {
        $k = $hklm.OpenSubKey($ra)
        if ($null -eq $k) { continue }
        $vals = @(foreach ($v in $k.GetValueNames()) { $d = [string]$k.GetValue($v); if ($d -match '(?i)^Software\\(WOW6432Node\\)?Microsoft\\Office\\|\\Microsoft Outlook\\') { $v } })
        $k.Close()
        foreach ($v in $vals) { Remove-KATKRegValue $hklm $ra $v }
    }
    foreach ($ap in 'SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths', 'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths') {
        foreach ($n in Get-KATKSubKeys $hklm $ap) {
            $d = "$(Get-KATKRegValue $hklm "$ap\$n") $(Get-KATKRegValue $hklm "$ap\$n" 'Path')"
            if ($d -match $pathRx) { Remove-KATKRegKey $hklm "$ap\$n" }
        }
    }
}

function Remove-KATKOfficeComRegistry {
    $clsids = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    Write-Host "  → Quét COM (CLSID)..." -ForegroundColor DarkGray
    foreach ($base in 'SOFTWARE\Classes\CLSID', 'SOFTWARE\Classes\WOW6432Node\CLSID') {
        foreach ($c in Get-KATKSubKeys $hklm $base) {
            foreach ($srv in 'InprocServer32', 'LocalServer32', 'InprocHandler32', 'LocalServer') {
                $v = Get-KATKRegValue $hklm "$base\$c\$srv"
                if ($v -and ([string]$v -match $pathRx)) { [void]$clsids.Add($c); Remove-KATKRegKey $hklm "$base\$c"; break }
            }
        }
    }
    Write-Host "  → Quét TypeLib..." -ForegroundColor DarkGray
    $tl = 'SOFTWARE\Classes\TypeLib'
    foreach ($g in Get-KATKSubKeys $hklm $tl) {
        foreach ($ver in Get-KATKSubKeys $hklm "$tl\$g") {
            $hit = $false
            foreach ($lcid in Get-KATKSubKeys $hklm "$tl\$g\$ver") {
                foreach ($plat in 'win32', 'win64') {
                    $v = Get-KATKRegValue $hklm "$tl\$g\$ver\$lcid\$plat"
                    if ($v -and ([string]$v -match $pathRx)) { $hit = $true }
                }
            }
            if ($hit) { Remove-KATKRegKey $hklm "$tl\$g\$ver" }
        }
        if ((Test-KATKRegKey $hklm "$tl\$g") -and -not @(Get-KATKSubKeys $hklm "$tl\$g").Count) { Remove-KATKRegKey $hklm "$tl\$g" }
    }
    Write-Host "  → Quét liên kết tệp (ProgID)..." -ForegroundColor DarkGray
    $progIds = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $winNative = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($w in '*', 'AllFilesystemObjects', 'Applications', 'callto', 'CompressedFolder', 'Directory', 'Drive', 'Folder', 'ftp', 'feed', 'feeds',
                   'htmlfile', 'http', 'https', 'im', 'inifile', 'InternetShortcut', 'ldap', 'lnkfile', 'mailto', 'mhtmlfile', 'news', 'nntp',
                   'search', 'search-ms', 'sip', 'sms', 'snews', 'SystemFileAssociations', 'tel', 'txtfile', 'Unknown', 'webcal', 'webcals',
                   'xmlfile', 'xslfile', 'regfile', 'batfile', 'cmdfile', 'textfile', 'giffile', 'jpegfile', 'pngfile', 'icsfile', 'vcard_wab_auto_file') { [void]$winNative.Add($w) }
    $cls = 'SOFTWARE\Classes'
    $all = Get-KATKSubKeys $hklm $cls
    foreach ($n in $all) {
        if ($n.StartsWith('.') -or $n -eq 'CLSID' -or $n -eq 'TypeLib' -or $n -eq 'Installer' -or $n -eq 'WOW6432Node' -or $n -eq 'Interface') { continue }
        if ($winNative.Contains($n)) {
            foreach ($verb in Get-KATKSubKeys $hklm "$cls\$n\shell") {
                $v = Get-KATKRegValue $hklm "$cls\$n\shell\$verb\command"
                if ($v -and ([string]$v -match $pathRx)) { Remove-KATKRegKey $hklm "$cls\$n\shell\$verb" }
            }
            $v = Get-KATKRegValue $hklm "$cls\$n\DefaultIcon"
            if ($v -and ([string]$v -match $pathRx)) { Remove-KATKRegKey $hklm "$cls\$n\DefaultIcon" }
            continue
        }
        $hit = $false
        $cid = Get-KATKRegValue $hklm "$cls\$n\CLSID"
        if ($cid -and $clsids.Contains([string]$cid)) { $hit = $true }
        if (-not $hit) {
            foreach ($probe in "$cls\$n\shell\open\command", "$cls\$n\shell\edit\command", "$cls\$n\DefaultIcon") {
                $v = Get-KATKRegValue $hklm $probe
                if ($v -and ([string]$v -match $pathRx)) { $hit = $true; break }
            }
        }
        if ($hit) { [void]$progIds.Add($n); Remove-KATKRegKey $hklm "$cls\$n" }
    }
    foreach ($n in Get-KATKSubKeys $hklm "$cls\Applications") {
        $v = Get-KATKRegValue $hklm "$cls\Applications\$n\shell\open\command"
        if ($v -and ([string]$v -match $pathRx)) { Remove-KATKRegKey $hklm "$cls\Applications\$n" }
    }
    foreach ($ext in $all) {
        if (-not $ext.StartsWith('.')) { continue }
        $def = Get-KATKRegValue $hklm "$cls\$ext"
        if ($def -and $progIds.Contains([string]$def)) {
            try { $k = $hklm.OpenSubKey("$cls\$ext", $true); $k.DeleteValue('', $false); $k.Close(); $st.Reg++ } catch {}
        }
        foreach ($sub in Get-KATKSubKeys $hklm "$cls\$ext") { if ($progIds.Contains($sub)) { Remove-KATKRegKey $hklm "$cls\$ext\$sub" } }
        $ow = $hklm.OpenSubKey("$cls\$ext\OpenWithProgids")
        if ($ow) {
            $vals = @($ow.GetValueNames() | Where-Object { $progIds.Contains($_) })
            $ow.Close()
            foreach ($v in $vals) { Remove-KATKRegValue $hklm "$cls\$ext\OpenWithProgids" $v }
        }
    }
    foreach ($se in 'SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Approved', 'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Shell Extensions\Approved') {
        $k = $hklm.OpenSubKey($se)
        if ($null -eq $k) { continue }
        $vals = @($k.GetValueNames() | Where-Object { $clsids.Contains($_) })
        $k.Close()
        foreach ($v in $vals) { Remove-KATKRegValue $hklm $se $v }
    }
    Write-Host "  ✔ COM: $($clsids.Count) · Liên kết tệp: $($progIds.Count)" -ForegroundColor Green
}

function Remove-KATKOfficeShortcuts([string[]]$Folders) {
    $sh = New-Object -ComObject WScript.Shell
    $nameRx = '(?i)^(Word|Excel|PowerPoint|Outlook|OneNote|Access|Publisher|Visio|Project|Skype for Business|Lync|OneNote for Windows 10|Office|Microsoft (Office|365|Word|Excel|PowerPoint|Outlook|Access|Publisher|OneNote|Visio|Project).*)( 20\d\d)?( \(.*\))?\.lnk$'
    $n = 0
    foreach ($f in $Folders) {
        if (-not (Test-Path -LiteralPath $f)) { continue }
        foreach ($l in @(Get-ChildItem -LiteralPath $f -Filter *.lnk -Recurse -Force -ErrorAction SilentlyContinue)) {
            $target = ""
            try { $target = $sh.CreateShortcut($l.FullName).TargetPath } catch {}
            $broken = (-not $target) -or (-not (Test-Path -LiteralPath $target))
            if (($target -match $pathRx) -or ($broken -and $l.Name -match $nameRx)) {
                Remove-Item -LiteralPath $l.FullName -Force -ErrorAction SilentlyContinue
                $n++
                Write-KATKUnLog "LNK   $($l.FullName)"
            }
        }
        foreach ($d in @(Get-ChildItem -LiteralPath $f -Directory -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '(?i)^Microsoft Office' } | Sort-Object { $_.FullName.Length } -Descending)) {
            if (-not @(Get-ChildItem -LiteralPath $d.FullName -Recurse -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'desktop.ini' }).Count) { Remove-KATKPath $d.FullName }
        }
    }
    return $n
}

function Remove-KATKOfficeUserData {
    $count = 0
    foreach ($pr in Get-KATKProfiles) {
        $loaded = $false
        $root = $pr.Sid
        if (-not (Test-KATKRegKey $hku $root)) {
            $dat = Join-Path $pr.Path 'NTUSER.DAT'
            if (Test-Path -LiteralPath $dat) {
                $root = "KATK_$($pr.Sid -replace '-', '_')"
                & reg.exe load "HKU\$root" "$dat" 2>$null | Out-Null
                if ($LASTEXITCODE -eq 0) { $loaded = $true } else { $root = $null }
            }
            else { $root = $null }
        }
        if ($root) {
            Remove-KATKRegKey $hku "$root\Software\Microsoft\Office"
            Remove-KATKRegKey $hku "$root\Software\Wow6432Node\Microsoft\Office"
            Remove-KATKRegKey $hku "$root\Software\Policies\Microsoft\Office"
            Remove-KATKRegKey $hku "$root\Software\Microsoft\AppV\ISV"
            if ($loaded) {
                [GC]::Collect()
                [GC]::WaitForPendingFinalizers()
                & reg.exe unload "HKU\$root" 2>$null | Out-Null
            }
        }
        Remove-KATKPath (Join-Path $pr.Path 'AppData\Local\Microsoft\Office')
        Remove-KATKPath (Join-Path $pr.Path 'AppData\Roaming\Microsoft\Office')
        $count += Remove-KATKOfficeShortcuts @(
            (Join-Path $pr.Path 'Desktop'),
            (Join-Path $pr.Path 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs'),
            (Join-Path $pr.Path 'AppData\Roaming\Microsoft\Internet Explorer\Quick Launch')
        )
    }
    $count += Remove-KATKOfficeShortcuts @("$env:ProgramData\Microsoft\Windows\Start Menu\Programs", "$env:PUBLIC\Desktop")
    Write-Host "  ✔ Đã dọn $(@(Get-KATKProfiles).Count) tài khoản · $count shortcut" -ForegroundColor Green
}

function Remove-KATKOfficeFirewall {
    try {
        $rules = @(Get-NetFirewallApplicationFilter -ErrorAction Stop | Where-Object { $_.Program -match $pathRx } | Get-NetFirewallRule -ErrorAction SilentlyContinue)
        foreach ($r in $rules) { Remove-NetFirewallRule -Name $r.Name -ErrorAction SilentlyContinue; Write-KATKUnLog "FW    $($r.DisplayName)" }
        Write-Host "  ✔ Đã xóa $($rules.Count) quy tắc tường lửa" -ForegroundColor Green
    }
    catch { Write-Host "  ⚠ Bỏ qua tường lửa: $($_.Exception.Message)" -ForegroundColor Yellow; Write-KATKUnLog "CANH  bo qua tuong lua: $($_.Exception.Message)" }
}

function Uninstall-Office {
    Clear-Host
    Show-KATKHeader "GỠ SẠCH OFFICE"

    $hklm = Get-KATKHive 'LocalMachine'
    $hku = Get-KATKHive 'Users'
    $officeApp = '0ff1ce15-a989-479d-af46-f275c6370663'
    $pathRx = '(?i)\\Microsoft Office( 1[5-6])?\\|\\Microsoft Shared\\(ClickToRun|OFFICE1[1-6]|Source Engine|OfficeSoftwareProtectionPlatform)\\|OfficeClickToRun\.exe|\\MSOCache\\'
    $st = @{ Reg = 0; Files = 0; Pending = 0; Fail = 0; Log = (Get-KATKUnLogPath) }

    Write-Host ""
    Write-Host "→ Đang quét Office trên máy..." -ForegroundColor Cyan
    $inv = Get-KATKOfficeInventory
    Show-KATKOfficeInventory $inv
    Write-KATKUnLogHeader
    Write-KATKInventoryLog "QUET TRUOC KHI GO" $inv

    Write-Host ""
    Write-Host "SẼ THỰC HIỆN:" -ForegroundColor Yellow
    Write-Host " • Gỡ toàn bộ Office (Word, Excel, Outlook, Visio, Project, Access Database Engine...)" -ForegroundColor White
    Write-Host " • Xóa key bản quyền Office (bản Retail cần nhập lại key, Microsoft 365 đăng nhập lại)" -ForegroundColor White
    Write-Host " • Dọn sạch file, registry, service, tác vụ, shortcut, liên kết tệp của Office cho mọi tài khoản" -ForegroundColor White
    Write-Host ""
    Write-Host "GIỮ LẠI (dữ liệu người dùng):" -ForegroundColor Green
    Write-Host " • Tài liệu, Templates (Normal.dotm), chữ ký và dữ liệu Outlook (PST/OST), file AutoRecover, từ điển riêng" -ForegroundColor Gray
    Write-Host ""
    Write-Host "⚠  Lưu và đóng mọi tài liệu Office trước khi tiếp tục. Quá trình có thể mất 5-30 phút." -ForegroundColor DarkYellow
    Write-KATKLine
    $confirm = Read-Host "Xác nhận gỡ sạch Office? (Y/N)"
    if ($confirm -notmatch '^[Yy]$') { Write-KATKUnLog "NGUOI DUNG HUY"; Write-Host "Đã hủy." -ForegroundColor Yellow; return }

    $sw = [Diagnostics.Stopwatch]::StartNew()
    Write-KATKUnLog "NGUOI DUNG XAC NHAN - BAT DAU GO"
    $msiPacked = @($inv.Msi | ForEach-Object { $_.Packed })

    Start-KATKUnStep "[1/10] TẠO ĐIỂM KHÔI PHỤC HỆ THỐNG"
    try {
        Checkpoint-Computer -Description "KATK - Truoc khi go Office" -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        Write-Host "  ✔ Đã tạo điểm khôi phục" -ForegroundColor Green
        Write-KATKUnLog "OK    da tao diem khoi phuc"
    }
    catch {
        Write-Host "  ⚠ Không tạo được điểm khôi phục ($($_.Exception.Message)) - tiếp tục." -ForegroundColor Yellow
        Write-KATKUnLog "CANH  khong tao duoc diem khoi phuc: $($_.Exception.Message)"
    }

    Start-KATKUnStep "[2/10] ĐÓNG ỨNG DỤNG OFFICE"
    Stop-KATKOfficeApps
    Write-Host "  ✔ Đã đóng ứng dụng Office" -ForegroundColor Green

    Start-KATKUnStep "[3/10] GỠ BẢN CLICK-TO-RUN (TRÌNH GỠ CHUẨN CỦA OFFICE)"
    Invoke-KATKC2RUninstall $inv

    Start-KATKUnStep "[4/10] GỠ GÓI MSI"
    Invoke-KATKMsiUninstall (Get-KATKOfficeInventory)

    Start-KATKUnStep "[5/10] GỠ OFFICE BẢN MICROSOFT STORE"
    if ($inv.Appx.Count) {
        foreach ($a in $inv.Appx) {
            try { Remove-AppxPackage -Package $a.PackageFullName -AllUsers -ErrorAction Stop; Write-Host "  ✔ $($a.Name)" -ForegroundColor Green; Write-KATKUnLog "APPX  $($a.PackageFullName)" }
            catch { $st.Fail++; Write-Host "  ⚠ $($a.Name): $($_.Exception.Message)" -ForegroundColor Yellow; Write-KATKUnLog "LOI   appx $($a.PackageFullName): $($_.Exception.Message)" }
        }
    }
    else { Write-Host "  Không có." -ForegroundColor DarkGray }

    Start-KATKUnStep "[6/10] GỠ KEY BẢN QUYỀN OFFICE"
    Remove-KATKOfficeKeys

    Start-KATKUnStep "[7/10] XÓA SERVICE VÀ TÁC VỤ HẸN GIỜ"
    Stop-KATKOfficeApps -Engine
    Remove-KATKOfficeServices

    Start-KATKUnStep "[8/10] XÓA FILE VÀ THƯ MỤC"
    $after = Get-KATKOfficeInventory
    $msiPacked = @(($msiPacked + @($after.Msi | ForEach-Object { $_.Packed })) | Select-Object -Unique)
    foreach ($d in Get-KATKOfficeDirs) { Remove-KATKPath $d }
    Write-Host "  ✔ Đã xử lý thư mục Office" -ForegroundColor Green

    Start-KATKUnStep "[9/10] DỌN REGISTRY"
    Remove-KATKMsiRegistration $msiPacked
    Remove-KATKOfficeArp
    Remove-KATKOfficeMachineRegistry
    Remove-KATKOfficeComRegistry
    Remove-KATKOfficeFirewall

    Start-KATKUnStep "[10/10] DỌN DỮ LIỆU OFFICE CỦA TỪNG TÀI KHOẢN"
    Remove-KATKOfficeUserData

    Show-Step "KIỂM TRA LẠI"
    $final = Get-KATKOfficeInventory
    $sw.Stop()
    if (Test-KATKInventoryEmpty $final) { Write-Host "  ✔ Không còn dấu vết Office." -ForegroundColor Green }
    else {
        Write-Host "  ⚠ Còn sót:" -ForegroundColor Yellow
        Show-KATKOfficeInventory $final
    }
    Write-KATKInventoryLog "QUET LAI SAU KHI GO" $final
    $mins = [math]::Floor($sw.Elapsed.TotalMinutes)
    Write-KATKUnLog "KET THUC: registry=$($st.Reg) thu-muc=$($st.Files) cho-khoi-dong-lai=$($st.Pending) loi=$($st.Fail) thoi-gian=$mins phut $($sw.Elapsed.Seconds) giay"

    Show-KATKBox "HOÀN TẤT GỠ SẠCH OFFICE" -Color Green -TextColor Yellow
    Write-Host " • Registry đã xóa      : $($st.Reg)" -ForegroundColor White
    Write-Host " • Thư mục đã xóa       : $($st.Files)" -ForegroundColor White
    Write-Host " • Xóa khi khởi động lại: $($st.Pending) mục (file đang bị khóa)" -ForegroundColor White
    Write-Host " • Lỗi                  : $($st.Fail)" -ForegroundColor $(if ($st.Fail) { 'Yellow' } else { 'White' })
    Write-Host " • Thời gian            : $mins phút $($sw.Elapsed.Seconds) giây" -ForegroundColor White
    Write-Host " • Nhật ký (trên Desktop): $($st.Log)" -ForegroundColor Gray
    Write-Host "   Nếu Office chưa gỡ sạch hoặc báo lỗi, hãy gửi file này cho KATK." -ForegroundColor Gray
    Write-Host ""
    Write-Host "💡 BẮT BUỘC khởi động lại máy trước khi cài Office mới." -ForegroundColor Cyan
    if (-not (Test-KATKInventoryEmpty $final) -or $st.Pending) {
        Write-Host "💡 Sau khi khởi động lại, chạy lại 'Gỡ sạch Office' một lần nữa để dọn phần còn sót." -ForegroundColor Cyan
    }
    Write-Host ""
    $rb = Read-Host "Khởi động lại máy ngay? (Y/N)"
    if ($rb -match '^[Yy]$') { Restart-Computer -Force }
}
