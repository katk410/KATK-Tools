if (-not (Get-Command Show-KATKHeader -ErrorAction SilentlyContinue)) {
    $katkBase = if ($global:KATK_BaseUrl) { $global:KATK_BaseUrl } else { "https://raw.githubusercontent.com/katk410/KATK-Tools/stable" }
    Invoke-Expression ((Invoke-RestMethod -Uri "$katkBase/core/UI.ps1" -UseBasicParsing).TrimStart([char]0xFEFF))
}
Assert-KATKAdmin
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

try {
    if ($global:KATK_PrnLocal) {
        $global:KP_CoreText = [IO.File]::ReadAllText((Join-Path $global:KATK_PrnLocal 'PrinterCore.ps1'))
        $global:KP_HostText = [IO.File]::ReadAllText((Join-Path $global:KATK_PrnLocal 'PrinterHost.ps1'))
        $global:KP_VendorText = [IO.File]::ReadAllText((Join-Path $global:KATK_PrnLocal 'vendors.json'))
    }
    else {
        $prnBase = "$(if ($global:KATK_BaseUrl) { $global:KATK_BaseUrl } else { 'https://raw.githubusercontent.com/katk410/KATK-Tools/stable' })/modules/Printer"
        $global:KP_CoreText = (Invoke-RestMethod -Uri "$prnBase/PrinterCore.ps1" -UseBasicParsing -ErrorAction Stop).TrimStart([char]0xFEFF)
        $global:KP_HostText = (Invoke-RestMethod -Uri "$prnBase/PrinterHost.ps1" -UseBasicParsing -ErrorAction Stop).TrimStart([char]0xFEFF)
    }
    if (-not $global:KATK_PrnLocal) {

        $global:KP_VendorText = $null
        try { $global:KP_VendorText = (Invoke-WebRequest -Uri "$prnBase/vendors.json" -UseBasicParsing -ErrorAction Stop).Content.TrimStart([char]0xFEFF) } catch { Write-Host "⚠ Chưa tải được danh mục driver của hãng" -ForegroundColor Yellow }
    }
    . ([ScriptBlock]::Create($global:KP_CoreText.TrimStart([char]0xFEFF)))
}
catch {
    Write-Host "❌ Không tải được KATK Printer, vui lòng kiểm tra mạng hoặc liên hệ ADMIN!" -ForegroundColor Red
    Write-Host "Chi tiết: $($_.Exception.Message)" -ForegroundColor DarkGray
    Wait-KATKBack
    return
}

function Read-KPNumbers([string]$Text, [int]$Max) {
    $out = @()
    foreach ($tok in ($Text -split '[\s,;]+' | Where-Object { $_ })) {
        if ($tok -match '^(\d+)-(\d+)$') { foreach ($n in [int]$Matches[1]..[int]$Matches[2]) { $out += $n } }
        elseif ($tok -match '^\d+$') { $out += [int]$tok }
    }
    return @($out | Where-Object { $_ -ge 1 -and $_ -le $Max } | Select-Object -Unique)
}

function Format-KPAgo([string]$Stamp) {
    try { $t = [datetime]::ParseExact($Stamp, 'yyyy-MM-dd HH:mm:ss', $null) } catch { return $Stamp }
    $m = [int]((Get-Date) - $t).TotalMinutes
    if ($m -lt 1) { return "vừa xong" } elseif ($m -lt 60) { return "$m phút trước" } elseif ($m -lt 1440) { return "$([int]($m / 60)) giờ trước" } else { return $t.ToString('dd/MM HH:mm') }
}

function Show-KPAttached {
    Clear-Host
    Show-KATKHeader "KATK PRINTER - DRIVER MÁY IN"
    $arch = (Get-KPArch).ToUpper()
    Write-Host ""
    Write-Host "Máy này: Windows $arch" -ForegroundColor Gray
    Write-Host "Đang tìm máy in cắm trên máy (USB / LPT)..." -ForegroundColor Gray
    $devs = @(Get-KPAttachedPrinters)
    if ($devs.Count -eq 0) {
        Write-Host ""
        Write-Host "Không thấy máy in nào đang cắm." -ForegroundColor Yellow
        Write-Host "- Kiểm tra cáp USB và bật nguồn máy in" -ForegroundColor Gray
        Write-Host "- Máy in Wi-Fi / mạng: dùng mục Thêm máy in của Windows" -ForegroundColor Gray
        Wait-KATKBack; return
    }
    Write-Host ""
    for ($i = 0; $i -lt $devs.Count; $i++) {
        $d = $devs[$i]
        Write-Host ("[{0}] {1}" -f ($i + 1), $d.Name) -ForegroundColor White -NoNewline
        if ($d.HasDriver) { Write-Host "  ✔ đã có driver" -ForegroundColor Green } else { Write-Host "  ✖ chưa có driver" -ForegroundColor Yellow }
        Write-Host "    $($d.HwIds[0])" -ForegroundColor DarkGray
    }
    $need = @($devs | Where-Object { -not $_.HasDriver })
    Write-Host ""
    if ($need.Count -eq 0) { Write-Host "Mọi máy in đều đã có driver." -ForegroundColor Green }
    Write-Host "Nhập số máy in cần cài driver (vd: 1 2), Enter = tất cả máy in chưa có driver, 0 = quay lại" -ForegroundColor Yellow
    $c = Read-Host "Chọn"
    if ($c -eq '0') { return }
    $pick = if ([string]::IsNullOrWhiteSpace($c)) { $need } else { @(Read-KPNumbers $c $devs.Count | ForEach-Object { $devs[$_ - 1] }) }
    if ($pick.Count -eq 0) { Write-Host "Không có máy in nào để cài." -ForegroundColor Gray; Wait-KATKBack; return }
    foreach ($d in $pick) {
        Write-Host ""
        Write-Host "▶ $($d.Name)" -ForegroundColor Cyan
        if (Install-KPAttachedDriver -Device $d) { Write-Host "   ✔ Đã cài driver" -ForegroundColor Green }
        else {
            Write-Host "   ❌ Không tìm được driver $arch cho máy in này" -ForegroundColor Red
            if ($arch -eq 'ARM64') { Write-Host "   - Nhiều hãng chưa có driver ARM64; máy in đời mới thường in được bằng driver chung của Windows (Mopria)" -ForegroundColor Gray }
            Write-Host "   - Tải driver trên trang của hãng rồi dùng mục [2] Cài từ gói đã tải" -ForegroundColor Gray
        }
    }
    Wait-KATKBack
}

function Select-KPPackage {
    Write-Host ""
    Write-Host "Nhận: .exe .msi .zip .cab .7z .rar .inf hoặc thư mục đã giải nén" -ForegroundColor Gray
    Write-Host "Enter = mở cửa sổ chọn tệp, hoặc dán đường dẫn tệp / thư mục, 0 = quay lại" -ForegroundColor Yellow
    $p = "$(Read-Host 'Gói driver')".Trim().Trim('"')
    if ($p -eq '0') { return $null }
    if ($p) { return $p }
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Title = "Chọn gói driver máy in"
        $dlg.Filter = "Gói driver|*.exe;*.msi;*.zip;*.cab;*.7z;*.rar;*.inf|Mọi tệp|*.*"
        $down = Join-Path $env:USERPROFILE 'Downloads'
        if (Test-Path $down) { $dlg.InitialDirectory = $down }
        $own = New-Object System.Windows.Forms.Form -Property @{ TopMost = $true; ShowInTaskbar = $false }
        $r = $dlg.ShowDialog($own); $own.Dispose()
        if ($r -eq 'OK') { return $dlg.FileName }
    }
    catch { Write-Host "⚠ Không mở được cửa sổ chọn tệp, hãy dán đường dẫn" -ForegroundColor Yellow; Start-Sleep 2 }
    return $null
}

function Install-KPOffline {
    Clear-Host
    Show-KATKHeader "KATK PRINTER - CÀI TỪ GÓI ĐÃ TẢI"
    $arch = Get-KPArch
    Write-Host ""
    Write-Host "Máy này: Windows $($arch.ToUpper()). Không cần mạng, chưa cắm máy in cũng cài được." -ForegroundColor Gray
    $path = Select-KPPackage
    if (-not $path) { return }
    if (-not (Test-Path -LiteralPath $path)) { Write-Host "❌ Không thấy: $path" -ForegroundColor Red; Wait-KATKBack; return }
    $item = Get-Item -LiteralPath $path
    Initialize-KPDir
    $work = Join-Path $global:KP_Dir ('import-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Force $work | Out-Null
    try {
        Write-Host ""
        Write-Host "▶ $($item.Name)" -ForegroundColor Cyan
        $infs = @()
        if ($item.PSIsContainer) { $infs = @(Get-KPPackageInfs $item.FullName $arch) }
        elseif ($item.Extension -eq '.inf') { $x = Get-KPInfInfo -InfPath $item.FullName -Arch $arch; if ($x -and @($x.Models).Count) { $infs = @($x) } }
        else { $infs = @(Expand-KPPackage $item.FullName $work $arch) }

        if ($infs.Count -eq 0 -and $item.Extension -in '.exe', '.msi') {
            $sg = Get-AuthenticodeSignature -LiteralPath $item.FullName
            Write-Host ""
            Write-Host "Không lấy được driver $($arch.ToUpper()) bằng cách giải nén." -ForegroundColor Yellow
            Write-Host "Có thể mở bộ cài của hãng, KATK sẽ lấy driver khi nó tự bung ra:" -ForegroundColor Gray
            if ($sg.Status -eq 'Valid') { Write-Host "- Chữ ký: $($sg.SignerCertificate.GetNameInfo('SimpleName', $false))" -ForegroundColor Green }
            else { Write-Host "- ⚠ Tệp KHÔNG có chữ ký hợp lệ, chỉ tiếp tục nếu tải từ trang chính hãng" -ForegroundColor Red }
            Write-Host "- Bộ cài có thể cài thêm phần mềm của hãng" -ForegroundColor Gray
            Write-Host "- Cứ cài bình thường, hoặc đóng lại khi nó hỏi cắm máy in" -ForegroundColor Gray
            Write-Host "- Xong thì quay lại cửa sổ này nhấn Enter" -ForegroundColor Gray
            if ((Read-Host "Y = mở bộ cài, Enter = Hủy") -match '^[yY]') {
                $before = @(Get-PrinterDriver -ErrorAction SilentlyContinue | ForEach-Object Name)
                Write-Host "   Đang chờ bộ cài... (nhấn Enter khi xong)" -ForegroundColor Cyan
                $infs = @(Watch-KPVendorSetup $item.FullName $work $arch)
                $new = @(Get-PrinterDriver -ErrorAction SilentlyContinue | ForEach-Object Name | Where-Object { $before -notcontains $_ })
                if ($new.Count) { Write-Host "✔ Bộ cài đã thêm driver: $($new -join ', ')" -ForegroundColor Green; if ($infs.Count -eq 0) { Write-Host "Cắm máy in là dùng được." -ForegroundColor Green; return } }
            }
            else { return }
        }
        if ($infs.Count -eq 0) {
            Write-Host "❌ Không thấy driver máy in $($arch.ToUpper()) trong gói này" -ForegroundColor Red
            Write-Host "- Kiểm tra đã tải đúng bản cho Windows $($arch.ToUpper())" -ForegroundColor Gray
            Write-Host "- Gói chỉ có phần mềm quét / tiện ích thì không có driver in" -ForegroundColor Gray
            if ($item.Extension -in '.7z', '.rar') { Write-Host "- Thử cài 7-Zip rồi chạy lại, hoặc tự giải nén và chọn thư mục" -ForegroundColor Gray }
            return
        }

        $models = @($infs | ForEach-Object { $_.Models } | ForEach-Object Name | Select-Object -Unique | Sort-Object)
        Write-Host "   Gói có $($models.Count) model: $(@($models | Select-Object -First 4) -join ', ')$(if ($models.Count -gt 4) { '...' })" -ForegroundColor Gray
        $need = @(Get-KPAttachedPrinters | Where-Object { -not $_.HasDriver })
        if ($need.Count) {
            foreach ($d in $need) {
                Write-Host ""
                Write-Host "▶ $($d.Name)" -ForegroundColor Cyan
                if (Complete-KPOfflineDevice -Device $d -Infs $infs) { Write-Host "   ✔ Đã cài xong, máy in dùng được" -ForegroundColor Green }
            }
            return
        }

        $sel = $infs
        if ($models.Count -gt 1) {
            Write-Host ""
            Write-Host "Nhập tên model máy in của bạn (vd: P1102), Enter = nạp cả gói, 0 = quay lại" -ForegroundColor Yellow
            $f = "$(Read-Host 'Model')".Trim()
            if ($f -eq '0') { return }
            if ($f) {
                $models = @($models | Where-Object { $_.IndexOf($f, [StringComparison]::OrdinalIgnoreCase) -ge 0 })
                if ($models.Count -eq 0) { Write-Host "Không có model nào khớp '$f'" -ForegroundColor Yellow; return }
                $sel = @($infs | Where-Object { @(@($_.Models).Name | Where-Object { $models -contains $_ }).Count })
            }
        }
        $ok = 0; $fail = 0
        $seen = @{}
        foreach ($i in $sel) {
            $key = (Get-FileHash -LiteralPath $i.Inf).Hash
            if ($seen.ContainsKey($key)) { continue }
            $seen[$key] = 1
            if (-not (Test-KPInfSigned $i)) { Write-Host "   ⚠ Bỏ qua $([IO.Path]::GetFileName($i.Inf)): không có chữ ký hợp lệ" -ForegroundColor Yellow; $fail++; continue }
            Write-Host "   Nạp: $([IO.Path]::GetFileName($i.Inf))" -ForegroundColor Gray
            if (Add-KPInfToStore $i) { $ok++ } else { $fail++; Write-Host "   ❌ Windows từ chối gói driver này" -ForegroundColor Red }
        }
        if ($ok -eq 0) { Write-Host "❌ Chưa nạp được driver nào" -ForegroundColor Red; return }
        if ($models.Count -le 3) { foreach ($m in $models) { try { Add-PrinterDriver -Name $m -ErrorAction Stop } catch { } } }
        Write-Host ""
        Write-Host "✔ Đã nạp driver vào Windows" -ForegroundColor Green
        Write-Host "- Cắm máy in và bật nguồn, Windows tự nhận, không cần mạng" -ForegroundColor Gray
        Write-Host "- Đang chờ máy in (tối đa 3 phút, phím bất kỳ = thôi chờ)..." -ForegroundColor Gray
        $known = @(Get-KPAttachedPrinters | ForEach-Object DeviceId)
        $end = (Get-Date).AddMinutes(3)
        while ((Get-Date) -lt $end) {
            try { if ([Console]::KeyAvailable) { [void][Console]::ReadKey($true); return } } catch { return }
            Start-Sleep -Seconds 1
            $d = Get-KPAttachedPrinters | Where-Object { $known -notcontains $_.DeviceId } | Select-Object -First 1
            if (-not $d) { continue }
            Write-Host "▶ Thấy $($d.Name)" -ForegroundColor Cyan
            for ($w = 0; $w -lt 15 -and -not $d.HasDriver; $w++) { Start-Sleep 2; $n = Get-KPAttachedPrinters | Where-Object DeviceId -eq $d.DeviceId | Select-Object -First 1; if ($n) { $d = $n } }
            if ($d.HasDriver -or (Complete-KPOfflineDevice -Device $d -Infs $infs)) { Write-Host "✔ Máy in dùng được" -ForegroundColor Green }
            return
        }
    }
    catch { Write-Host "❌ $($_.Exception.Message)" -ForegroundColor Red }
    finally {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
        Wait-KATKBack
    }
}

function Show-KPDriverMenu {
    while ($true) {
        Clear-Host
        Show-KATKHeader "KATK PRINTER - CÀI DRIVER"
        Write-Host ""
        Write-Host " [1] Tự tìm và cài" -ForegroundColor White
        Write-Host "     Cho máy in đang cắm, cần mạng`n" -ForegroundColor DarkGray
        Write-Host " [2] Cài từ gói đã tải của hãng" -ForegroundColor White
        Write-Host "     Không cần mạng: .exe .msi .zip .cab .7z .rar .inf / thư mục`n" -ForegroundColor DarkGray
        Write-Host " [0] Quay lại" -ForegroundColor Red
        switch (Read-Host "`nChọn") {
            '1' { Show-KPAttached }
            '2' { Install-KPOffline }
            '0' { return }
        }
    }
}

function Show-KPServerStatus {
    $cfg = Get-KPServerConfig
    $ips = @(Get-KPLanIPs)
    Write-Host ""
    Write-Host "TÊN MÁY CHỦ : $env:COMPUTERNAME" -ForegroundColor White
    if ($ips.Count) { foreach ($x in $ips) { Write-Host ("IP          : {0}  ({1})" -f $x.IP, $x.Adapter) -ForegroundColor White } }
    else { Write-Host "IP          : chưa có mạng LAN / Wi-Fi" -ForegroundColor Yellow }
    if (-not $cfg -or @($cfg.printers).Count -eq 0) { Write-Host "Trạng thái  : chưa chia sẻ máy in nào" -ForegroundColor DarkGray; return }
    $run = Test-KPServerRunning
    Write-Host ("Trạng thái  : " + $(if ($run) { "đang chạy (tự chạy khi khởi động máy)" } else { "chưa chạy - chọn [1] để bật lại" })) -ForegroundColor $(if ($run) { 'Green' } else { 'Red' })
    Write-Host "Máy in đang chia sẻ:" -ForegroundColor Gray
    foreach ($p in @($cfg.printers)) { Write-Host ("   • {0}  (cổng {1})" -f $p.name, $p.port) -ForegroundColor Gray }
}

function Show-KPClients {
    $cl = @(Get-KPClients | Sort-Object lastSeen -Descending)
    Write-Host ""
    Write-Host "MÁY CON ĐÃ KẾT NỐI ($($cl.Count)):" -ForegroundColor Yellow
    Write-KATKLine
    if ($cl.Count -eq 0) { Write-Host "Chưa có máy con nào. Trên máy con: KATK Printer > [3] Máy con." -ForegroundColor DarkGray; return }
    $i = 0
    foreach ($c in $cl) {
        $i++
        $online = $false
        try { $online = ((Get-Date) - [datetime]::ParseExact($c.lastSeen, 'yyyy-MM-dd HH:mm:ss', $null)).TotalMinutes -le 15 } catch { }
        Write-Host ("[{0}] {1}" -f $i, $c.name) -ForegroundColor White -NoNewline
        Write-Host ("  {0}" -f $c.ip) -ForegroundColor Cyan -NoNewline
        Write-Host ("  {0}" -f $(if ($online) { '● đang kết nối' } else { '○ lần cuối ' + (Format-KPAgo $c.lastSeen) })) -ForegroundColor $(if ($online) { 'Green' } else { 'DarkGray' })
        Write-Host ("    Mã {0} · {1} · {2}" -f $c.code, $c.arch, $c.user) -ForegroundColor Gray
        if ($c.os) { Write-Host "    $($c.os)" -ForegroundColor DarkGray }
        if (@($c.printers).Count) { Write-Host ("    Máy in: " + (@($c.printers) -join ', ')) -ForegroundColor Gray }
        if ($c.lastJob) { Write-Host "    In gần nhất: $($c.lastJob)" -ForegroundColor DarkGray }
    }
}

function Select-KPServerPrinters {
    $all = @(Get-KPLocalPrinters)
    if ($all.Count -eq 0) { Write-Host ""; Write-Host "Máy này chưa có máy in nào để chia sẻ. Cài driver máy in trước ([1] ở menu KATK Printer)." -ForegroundColor Yellow; Wait-KATKBack; return }
    $cfg = Get-KPServerConfig
    $shared = @(if ($cfg) { @($cfg.printers) | ForEach-Object { $_.name } })
    Write-Host ""
    Write-Host "MÁY IN TRÊN MÁY NÀY:" -ForegroundColor Yellow
    for ($i = 0; $i -lt $all.Count; $i++) {
        $p = $all[$i]
        Write-Host ("[{0}] {1}" -f ($i + 1), $p.Name) -ForegroundColor White -NoNewline
        if ($shared -contains $p.Name) { Write-Host "  ✔ đang chia sẻ" -ForegroundColor Green } else { Write-Host "" }
        Write-Host "    $($p.DriverName) · $($p.PortName)" -ForegroundColor DarkGray
    }
    Write-Host ""
    Write-Host "Nhập số máy in cần chia sẻ (vd: 1 3). Máy in không nhập sẽ ngừng chia sẻ. 0 = quay lại" -ForegroundColor Yellow
    $c = Read-Host "Chọn"
    if ($c -eq '0' -or [string]::IsNullOrWhiteSpace($c)) { return }
    $nums = @(Read-KPNumbers $c $all.Count)
    if ($nums.Count -eq 0) { Write-Host "❌ Lựa chọn không hợp lệ" -ForegroundColor Red; Start-Sleep 1; return }
    $names = @($nums | ForEach-Object { $all[$_ - 1].Name })
    Write-Host ""
    Write-Host "Đang bật máy chủ..." -ForegroundColor Gray
    try {
        $r = Set-KPServer -Printers $names
        $ok = $false
        for ($i = 0; $i -lt 20 -and -not $ok; $i++) { Start-Sleep -Milliseconds 500; $ok = Test-KPServerRunning }
        if ($ok) { Write-Host "✔ Máy chủ đang chạy, chia sẻ $(@($r.printers).Count) máy in" -ForegroundColor Green }
        else { Write-Host "⚠ Đã cài nhưng máy chủ chưa trả lời. Xem $($global:KP_Dir)\server.log" -ForegroundColor Yellow }
    }
    catch { Write-Host "❌ Không bật được máy chủ: $($_.Exception.Message)" -ForegroundColor Red; Wait-KATKBack; return }

    if (Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue) {
        Write-Host ""
        Write-Host "Máy này là laptop: khi máy ngủ, máy con sẽ không in được." -ForegroundColor Yellow
        if ((Read-Host "Tắt chế độ ngủ khi cắm sạc? (Y = có, Enter = bỏ qua)") -match '^[yY]') { & powercfg.exe /change standby-timeout-ac 0; Write-Host "✔ Đã tắt ngủ khi cắm sạc" -ForegroundColor Green }
    }
    Write-Host ""
    Write-Host "Giữ IP không đổi:" -ForegroundColor Gray
    Write-Host "- Tên máy chủ luôn cố định; nếu IP đổi, máy con tự tìm lại máy chủ" -ForegroundColor Gray
    $mac = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object Status -eq 'Up' | ForEach-Object { "$($_.Name): $($_.MacAddress)" })
    if ($mac) { Write-Host "- Muốn IP cố định hẳn: đặt IP tĩnh cho MAC này trong modem (DHCP Reservation): $($mac -join ' · ')" -ForegroundColor Gray }
    Wait-KATKBack
}

function Watch-KPClients {
    while ($true) {
        Clear-Host
        Show-KATKHeader "KATK PRINTER - MÁY CHỦ"
        Show-KPServerStatus
        Show-KPClients
        Write-Host ""
        Write-Host "Tự làm mới mỗi 5 giây · nhấn phím bất kỳ để quay lại" -ForegroundColor DarkGray
        $end = (Get-Date).AddSeconds(5)
        while ((Get-Date) -lt $end) {
            try { if ([Console]::KeyAvailable) { [void][Console]::ReadKey($true); return } } catch { Read-Host | Out-Null; return }
            Start-Sleep -Milliseconds 200
        }
    }
}

function Show-KPServer {
    while ($true) {
        Clear-Host
        Show-KATKHeader "KATK PRINTER - MÁY CHỦ"
        Show-KPServerStatus
        Show-KPClients
        Write-Host ""
        Write-KATKLine
        Write-Host "[1] Chọn máy in chia sẻ / bật máy chủ" -ForegroundColor White
        Write-Host "[2] Theo dõi máy con (tự làm mới)" -ForegroundColor White
        Write-Host "[3] Tắt chia sẻ trên máy này" -ForegroundColor White
        Write-Host "[0] Quay lại" -ForegroundColor Red
        switch (Read-Host "`nChọn") {
            '1' { Select-KPServerPrinters }
            '2' { Watch-KPClients }
            '3' {
                Write-Host ""
                Write-Host "Sẽ tắt chia sẻ:" -ForegroundColor Yellow
                Write-Host "- Dừng và gỡ tác vụ $($global:KP_SrvTask)" -ForegroundColor Gray
                Write-Host "- Xoá luật tường lửa KATK Printer" -ForegroundColor Gray
                Write-Host "- Xoá danh sách máy con và gói driver chia sẻ" -ForegroundColor Gray
                Write-Host "- Máy con sẽ không in qua máy này được nữa" -ForegroundColor Gray
                if ((Read-Host "Y = tắt chia sẻ, Enter = Hủy") -match '^[yY]') { Remove-KPServer; Write-Host "✔ Đã tắt chia sẻ" -ForegroundColor Green; Start-Sleep 1 }
            }
            '0' { return }
        }
    }
}

function Connect-KPServerUI([string]$Ip, $Info) {
    $ps = @($Info.printers)
    Clear-Host
    Show-KATKHeader "KATK PRINTER - MÁY CON"
    Write-Host ""
    Write-Host "Máy chủ: $($Info.name)  ($Ip)" -ForegroundColor White
    if ($ps.Count -eq 0) { Write-Host "Máy chủ chưa chia sẻ máy in nào." -ForegroundColor Yellow; Wait-KATKBack; return }
    $cfg = Get-KPClientConfig
    $mine = @(@($cfg.servers) | Where-Object { $_.id -eq $Info.id } | ForEach-Object { @($_.printers) } | ForEach-Object { $_.remote })
    Write-Host ""
    Write-Host "MÁY IN ĐANG CHIA SẺ:" -ForegroundColor Yellow
    for ($i = 0; $i -lt $ps.Count; $i++) {
        Write-Host ("[{0}] {1}" -f ($i + 1), $ps[$i].name) -ForegroundColor White -NoNewline
        if ($mine -contains $ps[$i].name) { Write-Host "  ✔ đã kết nối" -ForegroundColor Green } else { Write-Host "" }
        Write-Host "    $($ps[$i].driver)" -ForegroundColor DarkGray
    }
    Write-Host ""
    Write-Host "Nhập số máy in cần dùng (vd: 1 3), 0 = quay lại" -ForegroundColor Yellow
    $c = Read-Host "Chọn"
    if ($c -eq '0' -or [string]::IsNullOrWhiteSpace($c)) { return }
    $sel = @(Read-KPNumbers $c $ps.Count | ForEach-Object { $ps[$_ - 1] })
    if ($sel.Count -eq 0) { Write-Host "❌ Lựa chọn không hợp lệ" -ForegroundColor Red; Start-Sleep 1; return }
    $res = @(Connect-KPPrinters -ServerIp $Ip -Info $Info -Selected $sel)
    Write-Host ""
    Write-KATKLine
    foreach ($r in $res) {
        if ($r.Ok) { Write-Host "✔ $($r.Queue)" -ForegroundColor Green } else { Write-Host "✖ $($r.Printer): $($r.Note)" -ForegroundColor Red }
    }
    if (@($res | Where-Object Ok).Count) {
        $code = New-KPShortCode (Get-KPClientConfig).id
        Write-Host ""
        Write-Host "- Trang in thử có tên máy này và mã $code" -ForegroundColor Gray
        Write-Host "- Tắt KATK Tools vẫn in được; IP máy chủ đổi thì máy này tự tìm lại" -ForegroundColor Gray
    }
    Wait-KATKBack
}

function Show-KPClient {
    $servers = $null
    while ($true) {
        Clear-Host
        Show-KATKHeader "KATK PRINTER - MÁY CON"
        $cfg = Get-KPClientConfig
        if (@($cfg.servers).Count) {
            Write-Host ""
            Write-Host "ĐÃ KẾT NỐI:" -ForegroundColor Yellow
            foreach ($s in @($cfg.servers)) { foreach ($p in @($s.printers)) { Write-Host "   • $($p.queue)  ← $($s.name) $($s.ip)" -ForegroundColor Gray } }
        }
        if ($null -eq $servers) { Write-Host ""; Write-Host "Đang tìm máy chủ KATK Printer trong mạng..." -ForegroundColor Gray; $servers = @(Find-KPServers 3000) }
        Write-Host ""
        Write-Host "MÁY CHỦ TÌM THẤY ($($servers.Count)):" -ForegroundColor Yellow
        Write-KATKLine
        for ($i = 0; $i -lt $servers.Count; $i++) {
            $s = $servers[$i]
            Write-Host ("[{0}] {1}" -f ($i + 1), $s.Name) -ForegroundColor White -NoNewline
            Write-Host ("  {0}" -f $s.IP) -ForegroundColor Cyan -NoNewline
            Write-Host ("  · {0} máy in" -f @($s.Printers).Count) -ForegroundColor Gray
        }
        if ($servers.Count -eq 0) {
            Write-Host "Không thấy máy chủ nào." -ForegroundColor DarkGray
            Write-Host "- Trên máy có máy in: KATK Printer > [2] Máy chủ > [1]" -ForegroundColor DarkGray
            Write-Host "- Hai máy phải cùng mạng; Wi-Fi khách / cách ly thiết bị sẽ chặn" -ForegroundColor DarkGray
        }
        Write-Host ""
        Write-Host "[N] Nhập tên hoặc IP máy chủ" -ForegroundColor White
        Write-Host "[R] Tìm lại" -ForegroundColor White
        Write-Host "[0] Quay lại" -ForegroundColor Red
        $c = Read-Host "`nChọn"
        if ($c -eq '0') { return }
        if ($c -match '^[rR]$') { $servers = $null; continue }
        if ($c -match '^[nN]$') {
            $t = Read-Host "Tên máy hoặc IP máy chủ"
            if ([string]::IsNullOrWhiteSpace($t)) { continue }
            Write-Host "Đang kết nối $t..." -ForegroundColor Gray
            $r = Resolve-KPServer $t
            if (-not $r) {
                Write-Host "❌ Không kết nối được máy chủ '$t'" -ForegroundColor Red
                Write-Host "- Kiểm tra máy chủ đã bật ([2] Máy chủ) và cùng mạng" -ForegroundColor Gray
                Write-Host "- Thử nhập IP thay cho tên máy" -ForegroundColor Gray
                Wait-KATKBack; continue
            }
            Connect-KPServerUI $r.IP $r.Info; continue
        }
        if ($c -match '^\d+$' -and [int]$c -ge 1 -and [int]$c -le $servers.Count) {
            $s = $servers[[int]$c - 1]
            $info = Get-KPServerInfo $s.IP $s.CtlPort
            if (-not $info) { Write-Host "❌ Máy chủ $($s.Name) không trả lời" -ForegroundColor Red; Wait-KATKBack; continue }
            Connect-KPServerUI $s.IP $info
        }
    }
}

function Show-KPRemove {
    Clear-Host
    Show-KATKHeader "KATK PRINTER - XOÁ MÁY IN"
    $all = @(Get-Printer -ErrorAction SilentlyContinue | Sort-Object Name)
    if ($all.Count -eq 0) { Write-Host ""; Write-Host "Máy này không có máy in nào." -ForegroundColor Gray; Wait-KATKBack; return }
    Write-Host ""
    for ($i = 0; $i -lt $all.Count; $i++) {
        $p = $all[$i]
        Write-Host ("[{0}] {1}" -f ($i + 1), $p.Name) -ForegroundColor White
        Write-Host "    $($p.DriverName) · $($p.PortName)" -ForegroundColor DarkGray
    }
    Write-Host ""
    Write-Host "Nhập số máy in cần xoá (vd: 1 3), 0 = quay lại" -ForegroundColor Yellow
    $c = Read-Host "Chọn"
    if ($c -eq '0' -or [string]::IsNullOrWhiteSpace($c)) { return }
    $sel = @(Read-KPNumbers $c $all.Count | ForEach-Object { $all[$_ - 1] })
    if ($sel.Count -eq 0) { Write-Host "❌ Lựa chọn không hợp lệ" -ForegroundColor Red; Start-Sleep 1; return }
    $delDrv = (Read-Host "Xoá luôn driver nếu không còn máy in nào dùng? (Y = có, Enter = không)") -match '^[yY]'
    $srv = Get-KPServerConfig
    $sharedNames = @(if ($srv) { @($srv.printers) | ForEach-Object { $_.name } })
    $others = @($all | Where-Object { $sel.Name -notcontains $_.Name })
    Write-Host ""
    Write-Host "SẼ XOÁ:" -ForegroundColor Yellow
    $shownDrv = @()
    foreach ($p in $sel) {
        Write-Host "- Máy in: $($p.Name)" -ForegroundColor White
        if ($p.PortName -like 'KATK_*' -or $p.PortName -match '^\d{1,3}(\.\d{1,3}){3}' -or $p.PortName -like 'IP_*') {
            if (-not ($others | Where-Object PortName -eq $p.PortName)) { Write-Host "  · cổng $($p.PortName)" -ForegroundColor Gray }
        }
        if ($delDrv -and $shownDrv -notcontains $p.DriverName -and -not ($others | Where-Object DriverName -eq $p.DriverName)) { $shownDrv += $p.DriverName; Write-Host "  · driver $($p.DriverName)" -ForegroundColor Gray }
        if ($sharedNames -contains $p.Name) { Write-Host "  · ngừng chia sẻ cho máy con" -ForegroundColor Gray }
    }
    Write-Host ""
    if ((Read-Host "Y = xoá, Enter = Hủy") -notmatch '^[yY]') { Write-Host "Đã hủy." -ForegroundColor Gray; Start-Sleep 1; return }
    $unshare = @()
    foreach ($p in $sel) {
        try {
            [void](Wait-KPSpooler)
            try { Remove-Printer -InputObject $p -ErrorAction Stop }
            catch {

                Start-Sleep -Seconds 3
                if (-not (Wait-KPSpooler)) { throw "Dịch vụ in (Spooler) không chạy" }
                $again = Get-KPPrinterExact $p.Name; if ($again) { Remove-Printer -InputObject $again -ErrorAction Stop }
            }
            Write-Host "✔ Đã xoá $($p.Name)" -ForegroundColor Green
            if ($p.Name -like "*$($global:KP_QueueTag)*") { Remove-KPClientEntry $p.Name }
            if ($sharedNames -contains $p.Name) { $unshare += $p.Name }
            $still = @(Get-Printer -ErrorAction SilentlyContinue)
            if (($p.PortName -like 'KATK_*' -or $p.PortName -match '^\d{1,3}(\.\d{1,3}){3}' -or $p.PortName -like 'IP_*') -and -not ($still | Where-Object PortName -eq $p.PortName)) {
                Remove-KPPort $p.PortName
            }
        }
        catch { Write-Host "❌ $($p.Name): $($_.Exception.Message)" -ForegroundColor Red }
    }
    if ($delDrv -and (Wait-KPSpooler)) {
        $still = @(Get-Printer -ErrorAction SilentlyContinue)
        $restarted = $false
        foreach ($dn in @($sel.DriverName | Select-Object -Unique | Where-Object { $still.DriverName -notcontains $_ })) {
            for ($try = 1; $try -le 4; $try++) {
                try { Remove-PrinterDriver -InputObject (Get-KPDriverExact $dn) -RemoveFromDriverStore -ErrorAction Stop; Write-Host "✔ Đã xoá driver $dn" -ForegroundColor Green; break }
                catch {
                    $err = $_.Exception.Message
                    if ((Wait-KPSpooler) -and -not (@(Get-PrinterDriver -ErrorAction SilentlyContinue).Name -contains $dn)) { Write-Host "✔ Đã gỡ driver $dn (gói cài vẫn giữ trong Windows)" -ForegroundColor Green; break }

                    $jobs = @($still | ForEach-Object { Get-PrintJob -PrinterObject $_ -ErrorAction SilentlyContinue })
                    if (-not $restarted -and $jobs.Count -eq 0) { Restart-Service Spooler -Force -ErrorAction SilentlyContinue; $restarted = $true }
                    if ($try -lt 4) { Start-Sleep -Seconds 3; continue }
                    try { Remove-PrinterDriver -InputObject (Get-KPDriverExact $dn) -ErrorAction Stop; Write-Host "✔ Đã gỡ driver $dn (gói cài vẫn giữ trong Windows)" -ForegroundColor Green }
                    catch { Write-Host "⚠ Chưa xoá được driver $dn (Windows đang dùng): $err" -ForegroundColor Yellow }
                }
            }
        }
    }
    if ($unshare.Count) {
        $rest = @($sharedNames | Where-Object { $unshare -notcontains $_ })
        if ($rest.Count) { [void](Set-KPServer -Printers $rest) } else { Remove-KPServer }
        Write-Host "✔ Đã cập nhật danh sách chia sẻ" -ForegroundColor Green
    }
    Wait-KATKBack
}

function Show-KPMenu {
    Clear-Host
    Show-KATKHeader "KATK PRINTER (BETA)"
    Write-Host ""
    Write-Host "LỰA CHỌN CÔNG CỤ:" -ForegroundColor Yellow
    Write-KATKLine
    Write-Host " [1] Cài driver máy in" -ForegroundColor White
    Write-Host "     Tự tìm driver, hoặc cài từ gói đã tải của hãng`n" -ForegroundColor DarkGray
    Write-Host " [2] Máy chủ - chia sẻ máy in" -ForegroundColor White
    Write-Host "     Chạy trên máy đang cắm máy in`n" -ForegroundColor DarkGray
    Write-Host " [3] Máy con - dùng máy in qua mạng" -ForegroundColor White
    Write-Host "     Tìm máy chủ trong mạng LAN / Wi-Fi và kết nối`n" -ForegroundColor DarkGray
    Write-Host " [4] Xoá máy in" -ForegroundColor White
    Write-Host "     Xoá máy in chỉ định (kèm cổng / driver)`n" -ForegroundColor DarkGray
    Write-KATKBackOption
    Write-KATKLine
}

if (-not $global:KATK_PrnNoMenu) {
    do {
        Show-KPMenu
        switch (Read-Host "`nNhập lựa chọn của bạn") {
            '1' { Show-KPDriverMenu }
            '2' { Show-KPServer }
            '3' { Show-KPClient }
            '4' { Show-KPRemove }
            '0' { Exit-KATKModule }
            default { Write-Host "❌ Lựa chọn không hợp lệ!" -ForegroundColor Red; Start-Sleep 1 }
        }
    } while ($true)
}
