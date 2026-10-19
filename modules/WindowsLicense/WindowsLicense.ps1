if (-not (Get-Command Show-KATKHeader -ErrorAction SilentlyContinue)) {
    $katkBase = if ($global:KATK_BaseUrl) { $global:KATK_BaseUrl } else { "https://raw.githubusercontent.com/katk410/KATK-Tools/stable" }
    Invoke-Expression (Invoke-RestMethod -Uri "$katkBase/core/UI.ps1" -UseBasicParsing)
}
Remove-Item Function:\Get-WindowsEdition -ErrorAction SilentlyContinue
Remove-Item Alias:\Get-WindowsEdition -ErrorAction SilentlyContinue

function Show-FramedBox {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Lines,
        [string]$BorderColor = "Cyan",
        [string]$TextColor = "White",
        [string[]]$LineColors = @(),
        [string]$Title = "",
        [string]$TitleColor = "Yellow",
        [int]$Padding = 2,
        [int]$MinWidth = 40
    )

    if ($LineColors.Count -eq 0) {
        $LineColors = @($TextColor) * $Lines.Count
    }
    while ($LineColors.Count -lt $Lines.Count) {
        $LineColors += $LineColors[-1]
    }

    $allTexts = @()
    if ($Title) { $allTexts += $Title }
    $allTexts += $Lines

    $maxLen = 0
    foreach ($line in $allTexts) {
        if ($line.Length -gt $maxLen) { $maxLen = $line.Length }
    }
    $width = [Math]::Max($maxLen + $Padding * 2, $MinWidth)

    function CenterText($text, $width) {
        $padding = $width - $text.Length
        $left = [math]::Floor($padding / 2)
        $right = $padding - $left
        return (" " * $left) + $text + (" " * $right)
    }

    Write-Host ("╔" + ("═" * $width) + "╗") -ForegroundColor $BorderColor

    if ($Title) {
        Write-Host "║" -ForegroundColor $BorderColor -NoNewline
        Write-Host (CenterText $Title $width) -ForegroundColor $TitleColor -NoNewline
        Write-Host "║" -ForegroundColor $BorderColor
        Write-Host "╠" -ForegroundColor $BorderColor -NoNewline
        Write-Host ("═" * $width) -ForegroundColor $BorderColor -NoNewline
        Write-Host "╣" -ForegroundColor $BorderColor
    }

    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $line = $Lines[$i]
        $color = $LineColors[$i]
        Write-Host "║" -ForegroundColor $BorderColor -NoNewline
        $padded = $line.PadRight($width)
        Write-Host $padded -ForegroundColor $color -NoNewline
        Write-Host "║" -ForegroundColor $BorderColor
    }

    Write-Host ("╚" + ("═" * $width) + "╝") -ForegroundColor $BorderColor
}

function Get-SystemPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ($env:windir) {
        $sysnative = Join-Path $env:windir "Sysnative\$Name"
        if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess -and (Test-Path $sysnative)) {
            return $sysnative
        }

        $system32 = Join-Path $env:windir "System32\$Name"
        if (Test-Path $system32) {
            return $system32
        }
    }

    return $Name
}

function Get-WindowsEdition {
    try {
        if ($PSVersionTable.PSVersion.Major -ge 3) {
            $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        } else {
            $osInfo = Get-WmiObject -Class Win32_OperatingSystem -ErrorAction Stop
        }

        $caption = $osInfo.Caption
        $version = $osInfo.Version

        if ($caption -match "Windows 10|Windows 11") {
            if ($caption -match "Pro") {
                $edition = "Pro"
            } elseif ($caption -match "Home") {
                if ($caption -match "Single Language") {
                    $edition = "Home Single Language"
                } else {
                    $edition = "Home"
                }
            } elseif ($caption -match "Enterprise") {
                $edition = "Enterprise"
            } elseif ($caption -match "Education") {
                $edition = "Education"
            } else {
                $edition = "Unknown"
            }
        } else {
            $edition = "Unknown or Unsupported"
        }

        return @{
            Caption     = $caption
            Version     = $version
            Edition     = $edition
            BuildNumber = [System.Environment]::OSVersion.Version.Build
        }
    }
    catch {
        Write-Warning "Không thể lấy thông tin Windows: $_"
        return @{
            Caption     = "Unknown"
            Version     = "0.0.0.0"
            Edition     = "Unknown"
            BuildNumber = 0
        }
    }
}

function Get-ReleaseName {
    param([int]$BuildNumber)

    $map = @{
        10240 = "1507"
        10586 = "1511"
        14393 = "1607"
        15063 = "1703"
        16299 = "1709"
        17134 = "1803"
        17763 = "1809"
        18362 = "1903"
        18363 = "1909"
        19041 = "2004"
        19042 = "20H2"
        19043 = "21H1"
        19044 = "21H2"
        19045 = "22H2"
        22000 = "21H2"
        22621 = "22H2"
        22631 = "23H2"
        26100 = "24H2"
        26200 = "25H2"
    }

    if ($map.ContainsKey($BuildNumber)) {
        return $map[$BuildNumber]
    } else {
        return "Build $BuildNumber"
    }
}

function Show-WindowsInfo {
    $winInfo = Get-WindowsEdition
    $release = Get-ReleaseName -BuildNumber $winInfo.BuildNumber
    $lines = @(
        " Phiên bản:  $($winInfo.Edition)",
        " Build:     $($winInfo.BuildNumber) ($release)",
        " Phiên bản:  $($winInfo.Version)"
    )
    $colors = @("Yellow", "White", "White")

    Show-FramedBox -Lines $lines -LineColors $colors -BorderColor "Cyan" -Title "THÔNG TIN WINDOWS HIỆN TẠI" -TitleColor "Yellow" -MinWidth 45
}

function Test-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Wait-Key {
    param(
        [string]$Message = "Nhấn phím bất kỳ để tiếp tục..."
    )

    Write-Host $Message -ForegroundColor Gray
    try {
        $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    }
    catch {
        $null = Read-Host "Nhấn Enter để tiếp tục"
    }
}

function Invoke-Slmgr {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $cscript = Get-SystemPath -Name "cscript.exe"
    $slmgr = Get-SystemPath -Name "slmgr.vbs"
    $output = & $cscript //NoLogo $slmgr @Arguments 2>&1

    return @{
        ExitCode = $LASTEXITCODE
        Output   = (($output | Out-String).Trim())
    }
}

function Show-SlmgrResult {
    param(
        [string]$Title,
        [hashtable]$Result
    )

    $color = if ($Result.ExitCode -eq 0) { "Green" } else { "Yellow" }
    Write-Host "  ↳ $Title..." -NoNewline -ForegroundColor Gray
    if ($Result.ExitCode -eq 0) {
        Write-Host " [OK]" -ForegroundColor $color
    } else {
        Write-Host " [MÃ LỖI: $($Result.ExitCode)]" -ForegroundColor $color
    }

    if (-not [string]::IsNullOrWhiteSpace($Result.Output)) {
        $Result.Output -split "`r?`n" | ForEach-Object {
            Write-Host "    $_" -ForegroundColor DarkGray
        }
    }
}

function Read-ProductKey {
    Clear-Host
    Show-KATKHeader "WINDOWS CHANGES LICENSE"

    Write-Host ""
    Write-Host "    Vui lòng nhập Product Key:" -ForegroundColor Yellow
    Write-Host "    Nhấn ESC để thoát" -ForegroundColor Gray
    Write-Host ""

    $mask = "XXXXX-XXXXX-XXXXX-XXXXX-XXXXX"
    $keyChars = [System.Collections.Generic.List[char]]::new()
    $cursorPos = 0
    $maxLen = 25
    $validChars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

    $bgColor = [ConsoleColor]::Black
    $fgMask = [ConsoleColor]::DarkGray
    $fgInput = [ConsoleColor]::White
    $borderColor = [ConsoleColor]::Gray

    $padding = 2
    $innerWidth = $mask.Length
    $totalWidth = $innerWidth + $padding * 2

    [Console]::ForegroundColor = $borderColor
    Write-Host ("┌" + ("─" * $totalWidth) + "┐")
    [Console]::ResetColor()

    [Console]::ForegroundColor = $borderColor
    Write-Host "│" -NoNewline
    [Console]::ResetColor()

    [Console]::BackgroundColor = $bgColor
    [Console]::ForegroundColor = $fgMask
    Write-Host (" " * $padding) -NoNewline
    Write-Host $mask -NoNewline
    Write-Host (" " * $padding) -NoNewline
    [Console]::ResetColor()

    [Console]::ForegroundColor = $borderColor
    Write-Host "│"
    [Console]::ResetColor()

    [Console]::ForegroundColor = $borderColor
    Write-Host ("└" + ("─" * $totalWidth) + "┘")
    [Console]::ResetColor()

    $inputStartLeft = $padding + 1
    $inputStartTop = [System.Console]::CursorTop - 2

    $display = $mask.ToCharArray()
    $filled = @($false) * $mask.Length

    function UpdateDisplay {
        $display = $mask.ToCharArray()
        $filled = @($false) * $mask.Length

        $idx = 0
        foreach ($ch in $keyChars) {
            while ($idx -lt $display.Length -and $display[$idx] -eq '-') { $idx++ }
            if ($idx -lt $display.Length) {
                $display[$idx] = $ch
                $filled[$idx] = $true
                $idx++
            }
        }
        $displayStr = -join $display

        [System.Console]::SetCursorPosition($inputStartLeft, $inputStartTop)
        [Console]::BackgroundColor = $bgColor
        for ($i = 0; $i -lt $displayStr.Length; $i++) {
            $ch = $displayStr[$i]
            if ($filled[$i]) {
                [Console]::ForegroundColor = $fgInput
            } else {
                [Console]::ForegroundColor = $fgMask
            }
            Write-Host $ch -NoNewline
        }
        [Console]::ResetColor()

        $pos = 0
        for ($i = 0; $i -lt $cursorPos; $i++) {
            while ($pos -lt $mask.Length -and $mask[$pos] -eq '-') { $pos++ }
            $pos++
        }
        while ($pos -lt $mask.Length -and $mask[$pos] -eq '-') { $pos++ }
        $col = $inputStartLeft + $pos
        [System.Console]::SetCursorPosition($col, $inputStartTop)
    }

    UpdateDisplay

    while ($true) {
        $keyInfo = [System.Console]::ReadKey($true)
        $char = $keyInfo.KeyChar

        if ($keyInfo.Key -eq [ConsoleKey]::Enter) {
            if ($keyChars.Count -eq $maxLen) {
                $fullKey = -join $keyChars
                Write-Host ""
                return $fullKey
            }
            continue
        }

        if ($keyInfo.Key -eq [ConsoleKey]::Escape) {
            Write-Host ""
            return $null
        }

        if ($keyInfo.Key -eq [ConsoleKey]::Backspace) {
            if ($cursorPos -gt 0) {
                $cursorPos--
                if ($cursorPos -lt $keyChars.Count) {
                    $keyChars.RemoveAt($cursorPos)
                }
                UpdateDisplay
            }
            continue
        }

        if ($keyInfo.Key -eq [ConsoleKey]::Delete) {
            if ($cursorPos -lt $keyChars.Count) {
                $keyChars.RemoveAt($cursorPos)
                UpdateDisplay
            }
            continue
        }

        if ($keyInfo.Key -eq [ConsoleKey]::LeftArrow -or $keyInfo.Key -eq [ConsoleKey]::RightArrow) {
            continue
        }

        if ($keyChars.Count -ge $maxLen) {
            continue
        }

        $upperChar = $char.ToString().ToUpper()
        if ($validChars.Contains($upperChar)) {
            if ($cursorPos -lt $keyChars.Count) {
                $keyChars[$cursorPos] = $upperChar
            } else {
                $keyChars.Add($upperChar)
            }
            $cursorPos++
            UpdateDisplay
        }
    }
}

function Invoke-ActivateWithKey {
    do {
        Clear-Host
        Show-KATKHeader "WINDOWS CHANGES LICENSE"

        $key = Read-ProductKey
        if (-not $key) {
            Write-Host "`nĐã hủy nhập key." -ForegroundColor Yellow
            Wait-Key
            return
        }

        $formattedKey = $key.Substring(0,5) + "-" + $key.Substring(5,5) + "-" + $key.Substring(10,5) + "-" + $key.Substring(15,5) + "-" + $key.Substring(20,5)

        Write-Host "`nKey đã nhập: $formattedKey" -ForegroundColor White
        $confirm = Read-Host "`nXác nhận active với key này? (Y/N)"
        if ($confirm -notmatch '^[Yy]') {
            Write-Host "Đã hủy active, quay lại nhập key." -ForegroundColor Yellow
            Wait-Key
            continue
        }

        Show-Banner "Đang thực thi active với key $formattedKey"

        try {
            $ipkResult = Invoke-Slmgr -Arguments @("/ipk", $formattedKey)
            Show-SlmgrResult -Title "Cài đặt Product Key" -Result $ipkResult

            if ($ipkResult.ExitCode -ne 0) {
                Write-Host "`nCài đặt key thất bại. Vui lòng kiểm tra key." -ForegroundColor Red
                Wait-Key
                continue
            }

            $atoResult = Invoke-Slmgr -Arguments @("/ato")
            Show-SlmgrResult -Title "Kích hoạt Windows" -Result $atoResult

            $resultLines = @()
            if ($atoResult.ExitCode -eq 0) {
                $resultLines = @(
                    " Trạng thái:  Kích hoạt thành công",
                    " Key:        $formattedKey"
                )
                Show-FramedBox -Lines $resultLines -BorderColor "Green" -TextColor "White" -Title "KẾT QUẢ ACTIVE" -TitleColor "White" -MinWidth 50
            } else {
                $resultLines = @(
                    " Trạng thái:  Kích hoạt thất bại (mã lỗi $($atoResult.ExitCode))",
                    " Key:        $formattedKey"
                )
                Show-FramedBox -Lines $resultLines -BorderColor "Yellow" -TextColor "Yellow" -Title "KẾT QUẢ ACTIVE" -TitleColor "Red" -MinWidth 50
            }
            break
        }
        catch {
            Write-Host "`n[LỖI] $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "Vui lòng thử lại với quyền Administrator đầy đủ." -ForegroundColor Yellow
            Wait-Key
            return
        }
    } while ($true)

    Wait-Key
}

function Remove-WindowsFppLicense {
    Clear-Host
    Show-KATKHeader "WINDOWS CHANGES LICENSE"

    Show-WindowsInfo

    Write-Host "GỠ LICENSE WINDOWS FPP/RETAIL" -ForegroundColor Green
    Write-Host "──────────────────────────────" -ForegroundColor Gray
    Write-Host "Hướng dẫn: Tính năng này dùng khi bạn cần gỡ Product Key FPP/Retail" -ForegroundColor Yellow
    Write-Host "trên máy cũ để chuyển key hợp lệ sang máy mới." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Lưu ý: Hãy chắc chắn bạn đã lưu lại Product Key trước khi tiếp tục." -ForegroundColor Yellow
    Write-Host "Việc gỡ key trên máy cũ không đảm bảo máy chủ Microsoft giải phóng license ngay lập tức." -ForegroundColor DarkRed
    Write-Host ""

    $confirm = Read-Host "Nhấn Enter để xác nhận gỡ License Windows, hoặc nhập N để hủy"
    if ($confirm -match '^[Nn]') {
        Write-Host "Đã hủy thao tác." -ForegroundColor Yellow
        Wait-Key "Nhấn phím bất kỳ để trở về menu chính..."
        return
    }

    try {
        Show-Banner "Đang thực thi gỡ License Windows FPP/Retail"

        $upkResult = Invoke-Slmgr -Arguments @("/upk")
        Show-SlmgrResult -Title "Gỡ Product Key khỏi Windows (/upk)" -Result $upkResult

        $cpkyResult = Invoke-Slmgr -Arguments @("/cpky")
        Show-SlmgrResult -Title "Xóa Product Key khỏi Registry (/cpky)" -Result $cpkyResult

        $resultLines = @(
            " Trạng thái:  Hoàn tất",
            " Lệnh đã chạy: slmgr /upk và slmgr /cpky"
        )
        Show-FramedBox -Lines $resultLines -BorderColor "Green" -TextColor "White" -Title "KẾT QUẢ GỠ LICENSE" -TitleColor "White" -MinWidth 45

        Write-Host ""
        Write-Host "Bạn có thể dùng Product Key FPP/Retail hợp lệ để kích hoạt trên máy mới." -ForegroundColor White
        Write-Host "Nếu key báo đã được sử dụng, hãy thử kích hoạt qua điện thoại hoặc liên hệ Microsoft." -ForegroundColor Yellow
    }
    catch {
        Write-Host "`n[LỖI] $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Vui lòng thử lại với quyền Administrator đầy đủ." -ForegroundColor Yellow
    }

    Write-Host ""
    Wait-Key "Nhấn phím bất kỳ để trở về menu chính..."
}

if (-not (Test-Admin)) {
    Clear-Host
    Show-KATKHeader "WINDOWS CHANGES LICENSE"
    $errorLines = @(
        " Script này yêu cầu quyền Administrator!",
        " ",
        " Vui lòng thực hiện các bước sau:",
        " 1. Đóng cửa sổ này",
        " 2. Mở PowerShell/Terminal với quyền Admin",
        " 3. Chạy lại file tool này"
    )
    Show-FramedBox -Lines $errorLines -BorderColor "Red" -TextColor "White" -Title "LỖI" -TitleColor "Yellow" -MinWidth 45
    Write-Host ""
    Wait-KATKBack
    Exit-KATKModule
}

function Show-MainMenu {
    Clear-Host
    Show-KATKHeader "WINDOWS CHANGES LICENSE"

    Show-WindowsInfo

    Write-Host "LỰA CHỌN PHIÊN BẢN CHUYỂN ĐỔI:" -ForegroundColor Yellow
    Write-Host "──────────────────────────────" -ForegroundColor DarkGray
    Write-Host "[1] Windows Home" -ForegroundColor White
    Write-Host "    Windows 11 Home" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "[2] Windows Home Single Language" -ForegroundColor White
    Write-Host "    Windows 11 Home Single Language" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "[3] Windows Pro" -ForegroundColor White
    Write-Host "    Windows 11 Pro" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "[4] Gỡ License Windows FPP/Retail" -ForegroundColor White
    Write-Host "    Dùng khi cần chuyển key hợp lệ sang máy mới" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "[5] Active Windows" -ForegroundColor White
    Write-Host "    Nhập Product Key" -ForegroundColor DarkGray
    Write-Host ""
    Write-KATKBackOption
    Write-Host "──────────────────────────────" -ForegroundColor DarkGray
}

do {
    Show-MainMenu

    $choice = Read-Host "`nNhập lựa chọn và nhấn Enter (0-5)"
    Write-Host ""

    if ($choice -eq '4') {
        Remove-WindowsFppLicense
        continue
    }

    if ($choice -eq '5') {
        Invoke-ActivateWithKey
        continue
    }

    $keyMap = @{
        '1' = @{Name = "Home"; Key = 'TX9XD-98N7V-6WMQ6-BX7FG-H8Q99'}
        '2' = @{Name = "Home Single Language"; Key = '7HNRX-D7KGG-3K4RQ-4WPJ4-YTDFH'}
        '3' = @{Name = "Pro"; Key = 'VK7JG-NPHTM-C97JM-9MPGT-3V66T'}
    }

    if ($choice -eq '0') {
        Exit-KATKModule
    }

    if (-not $keyMap.ContainsKey($choice)) {
        Write-Host "Lựa chọn không hợp lệ!" -ForegroundColor Red
        Wait-Key "Nhấn phím bất kỳ để tiếp tục..."
        continue
    }

    $selected = $keyMap[$choice]
    $currentInfo = Get-WindowsEdition

    Write-Host "THÔNG TIN CHUYỂN ĐỔI:" -ForegroundColor Cyan
    Write-Host "──────────────────────────────" -ForegroundColor DarkGray
    Write-Host "Windows hiện tại: $($currentInfo.Edition)" -ForegroundColor White
    Write-Host "Chuyển đổi thành:   Windows $($selected.Name)" -ForegroundColor Green
    Write-Host ""

    $confirm = Read-Host "Xác nhận chuyển đổi? (Y/N)"
    if ($confirm -notmatch '^[Yy]') {
        Write-Host "Đã hủy thao tác." -ForegroundColor Yellow
        Wait-Key "Nhấn phím bất kỳ để tiếp tục..."
        continue
    }

    Show-Banner "Đang thực thi chuyển đổi sang Windows $($selected.Name)"

    try {
        $services = @('LicenseManager', 'wuauserv')
        foreach ($service in $services) {
            Write-Host "  ↳ Cấu hình dịch vụ $service..." -NoNewline -ForegroundColor Gray
            sc.exe config $service start= auto 2>&1 | Out-Null
            Start-Service $service -ErrorAction SilentlyContinue
            Write-Host " [OK]" -ForegroundColor Green
        }

        Write-Host "  ↳ Áp dụng Product Key..." -NoNewline -ForegroundColor Gray
        $process = Start-Process "changepk.exe" -ArgumentList "/productkey `"$($selected.Key)`"" -Wait -NoNewWindow -PassThru

        if ($process.ExitCode -eq 0) {
            Write-Host " [THÀNH CÔNG]" -ForegroundColor Green
            $success = $true
        } else {
            Write-Host " [MÃ LỖI: $($process.ExitCode)]" -ForegroundColor Yellow
            $success = $false
        }

        $borderColor = if ($success) { "Green" } else { "Yellow" }
        $statusColor = if ($success) { "White" } else { "Yellow" }
        $titleColor = if ($success) { "White" } else { "Red" }

        $resultLines = @(
            " Trạng thái:  $(if ($success) { 'Thành công' } else { 'Có vấn đề' })",
            " Phiên bản:   Windows $($selected.Name)",
            " Mã lỗi:      $($process.ExitCode)"
        )
        $lineColors = @($statusColor, "White", "White")

        Show-FramedBox -Lines $resultLines -LineColors $lineColors -BorderColor $borderColor -Title "KẾT QUẢ CHUYỂN ĐỔI" -TitleColor $titleColor -MinWidth 45

        if (-not $success) {
            Write-Host "[!] Có thể cần khởi động lại và thử lại" -ForegroundColor Yellow
            Write-Host "    Hoặc key không tương thích với phiên bản Windows hiện tại." -ForegroundColor Yellow
        }

    }
    catch {
        Write-Host "`n[LỖI] $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Vui lòng thử lại với quyền Administrator đầy đủ." -ForegroundColor Yellow
    }

    Write-Host "`nTÙY CHỌN:" -ForegroundColor Cyan
    Write-Host "[1] Khởi động lại máy ngay" -ForegroundColor White
    Write-Host "[2] Trở về menu chính" -ForegroundColor White
    Write-Host ""

    $exitChoice = Read-Host "Chọn (1-2)"
    if ($exitChoice -eq '1') {
        Write-Host "Máy tính sẽ khởi động lại trong 5 giây..." -ForegroundColor Yellow
        Start-Sleep -Seconds 5
        Restart-Computer -Force
    }
    else {
        Write-Host "`nĐang trở về menu chính..." -ForegroundColor Gray
        Start-Sleep -Seconds 1
    }
} while ($true)
