if (-not (Get-Command Show-KATKHeader -ErrorAction SilentlyContinue)) {
    $katkBase = if ($global:KATK_BaseUrl) { $global:KATK_BaseUrl } else { "https://raw.githubusercontent.com/katk410/KATK-Tools/stable" }
    Invoke-Expression ((Invoke-RestMethod -Uri "$katkBase/core/UI.ps1" -UseBasicParsing).TrimStart([char]0xFEFF))
}
[System.Net.ServicePointManager]::DefaultConnectionLimit = 80
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

Clear-Host
Show-KATKHeader "KATK SETUP APP"

$tempDir = "C:\KATK-Tools"
$taskName = "KATK_Cleanup"
$taskCommand = "cmd.exe /c rmdir /s /q C:\KATK-Tools"

schtasks /delete /tn $taskName /f 2>$null | Out-Null
schtasks /create /tn $taskName /tr "$taskCommand" /sc onstart /ru SYSTEM /rl HIGHEST /f | Out-Null

if (Test-Path $tempDir) {
    Remove-Item -Recurse -Force $tempDir -ErrorAction SilentlyContinue
}

$softwareList = @(
    @{Name = "Google Chrome"; URL = "https://dl.google.com/tag/s/appguid%3D%7B8A69D345-D564-463C-AFF1-A69D9E530F96%7D%26iid%3D%7B960E1864-5062-01F2-96D9-DEBC3B1E15A2%7D%26lang%3Dvi%26browser%3D4%26usagestats%3D1%26appname%3DGoogle%2520Chrome%26needsadmin%3Dprefers%26ap%3D-arch_x64-statsdef_1%26installdataindex%3Dempty/update2/installers/ChromeSetup.exe"; Type = "exe"},
    @{Name = "CocCoc"; URL = "https://files1.coccoc.com/browser/coccoc_vi_machine.exe"; Type = "exe"},
    @{Name = "WinRAR"; URL = "https://www.win-rar.com/fileadmin/winrar-versions/winrar-x64-713vn.exe"; Type = "exe"},
    @{Name = "Zalo"; URL = "https://res-download-pc-te-vnso-ne-2.zadn.vn/win/ZaloSetup-26.6.20.exe"; Type = "exe"},
    @{Name = "UltraViewer"; URL = "https://dl2.ultraviewer.net/UltraViewer_setup_6.6_vi.exe"; Type = "exe"},
    @{Name = "Unikey"; URL = "https://www.unikey.org/assets/release/unikey46RC2-230919-win64.zip"; Type = "zip"},
    @{Name = "K-Lite Codec Pack"; URL = "https://files2.codecguide.com/K-Lite_Codec_Pack_1982_Standard.exe"; Type = "exe"},
    @{Name = "DeskIn"; URL = "https://dl.deskin.io/windows/DeskIn_Setup_v3.3.2.3_x64.exe"; Type = "exe"},
    @{Name = "EVKey"; URL = "https://release-assets.githubusercontent.com/github-production-release-asset/131986042/771182af-94c1-403a-973a-bf33fe1e2b5a?sp=r&sv=2018-11-09&sr=b&spr=https&se=2025-12-28T04%3A03%3A48Z&rscd=attachment%3B+filename%3DEVKey.zip&rsct=application%2Foctet-stream&skoid=96c2d410-5711-43a1-aedd-ab1947aa7ab0&sktid=398a6654-997b-47e9-b12b-9515b896b4de&skt=2025-12-28T03%3A03%3A13Z&ske=2025-12-28T04%3A03%3A48Z&sks=b&skv=2018-11-09&sig=iMTs9VbmaOkECQP%2BvIn0msrF%2B8AcA360T5NfUVG1JLs%3D&jwt=eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJnaXRodWIuY29tIiwiYXVkIjoicmVsZWFzZS1hc3NldHMuZ2l0aHVidXNlcmNvbnRlbnQuY29tIiwia2V5Ijoia2V5MSIsImV4cCI6MTc2Njg5MTc3NywibmJmIjoxNzY2ODkxNDc3LCJwYXRoIjoicmVsZWFzZWFzc2V0cHJvZHVjdGlvbi5ibG9iLmNvcmUud2luZG93cy5uZXQifQ.eQCmI5o5z4thx9kr8ruFfEmEBDuwVsP2yF99i58Yrlg&response-content-disposition=attachment%3B%20filename%3DEVKey.zip&response-content-type=application%2Foctet-stream"; Type ="zip"},
    @{Name = "TeamView"; URL = "https://dl.teamviewer.com/download/version_15x/TeamViewer_Setup_x64.exe?_gl=1*1ig1cir*_gcl_au*MTIwMjQ5NzkxNC4xNzMxNjY0MTUz*_ga*OTQ0NzMxNTUwLjE3MTg1MjQ3NjM.*_ga_2HQ69V81Q2*MTczMTY2NDE1Mi4xLjEuMTczMTY2NDI1Mi41MS4wLjY5NTk5Njc0OQ..&ref=https%3A%2F%2Fwww.teamviewer.com%2Fvi%2Fdownload%2Fwindows%2F"; Type = "exe"},
    @{Name = "Zoom"; URL = "https://cdn.zoom.us/prod/6.6.11.23272/ZoomInstaller.exe"; Type = "exe"},
    @{Name = "Webex"; URL = "https://binaries.webex.com/WebexTeamsDesktop-Windows-Web-Installer/Webex.exe"; Type = "exe"},
    @{Name = "Discord"; URL = "https://stable.dl2.discordapp.net/distro/app/stable/win/x64/1.0.9219/DiscordSetup.exe"; Type = "exe"},
    @{Name = "EsetNod32"; URL = "https://download.eset.com/com/eset/tools/installers/live_eav/latest/eset_nod32_antivirus_live_installer.exe"; Type = "exe"},
    @{Name = "LibreOffice"; URL = "https://ftp.halifax.rwth-aachen.de/tdf/libreoffice/stable/26.2.4/win/x86_64/LibreOffice_26.2.4_Win_x86-64.msi"; Type = "msi"},
    @{Name = "7Zip"; URL = "https://release-assets.githubusercontent.com/github-production-release-asset/466446150/daf05d0d-b9b7-4aa7-99e6-5e7afbb980fd?sp=r&sv=2018-11-09&sr=b&spr=https&se=2026-06-17T15%3A24%3A03Z&rscd=attachment%3B+filename%3D7z2601-x64.exe&rsct=application%2Foctet-stream&skoid=96c2d410-5711-43a1-aedd-ab1947aa7ab0&sktid=398a6654-997b-47e9-b12b-9515b896b4de&skt=2026-06-17T14%3A23%3A47Z&ske=2026-06-17T15%3A24%3A03Z&sks=b&skv=2018-11-09&sig=35smycAP0ql1W51l9wTnB40avDryX%2Bu9AzyJzvRQu0I%3D&jwt=eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJnaXRodWIuY29tIiwiYXVkIjoicmVsZWFzZS1hc3NldHMuZ2l0aHVidXNlcmNvbnRlbnQuY29tIiwia2V5Ijoia2V5MSIsImV4cCI6MTc4MTcwNzI3MCwibmJmIjoxNzgxNzA2OTcwLCJwYXRoIjoicmVsZWFzZWFzc2V0cHJvZHVjdGlvbi5ibG9iLmNvcmUud2luZG93cy5uZXQifQ.Yj37pUgyISBPBFZBZpZTwZ7oe_hCBOHBGIxzcDEIsTw&response-content-disposition=attachment%3B%20filename%3D7z2601-x64.exe&response-content-type=application%2Foctet-stream"; Type ="exe"},
    @{Name = "Rufus"; URL = "https://github.com/pbatard/rufus/releases/download/v4.15/rufus-4.15p.exe"; Type = "exe"}
)

$packageBasic = @(1, 2, 3, 4, 5, 6, 7, 8)
$packageEVKey = @(1, 2, 3, 4, 5, 9, 7, 8)

function Show-SoftwareMenu {
    param([int]$Columns = 4)
    Write-Host "═══════ DANH SÁCH PHẦN MỀM ════════`n" -ForegroundColor Cyan
    $rows = [math]::Ceiling($softwareList.Count / $Columns)
    for ($row = 0; $row -lt $rows; $row++) {
        $line = ""
        for ($col = 0; $col -lt $Columns; $col++) {
            $index = $row + ($col * $rows)
            if ($index -lt $softwareList.Count) {
                $software = $softwareList[$index]
                $line += "  {0,2}. {1,-20}" -f ($index + 1), $software.Name
            }
        }
        Write-Host $line -ForegroundColor White
    }
    Write-Host "`n═══════════════════════════════════" -ForegroundColor Cyan
    Write-Host " 0. Cài đặt gói cơ bản (Chrome, CocCoc, Zalo, Unikey, Ultraview, Deskin, WinRAR, K-Lite)" -ForegroundColor Yellow
    Write-Host " A. Cài gói EVKey (giống gói cơ bản nhưng thay Unikey bằng EVKey)" -ForegroundColor Yellow
    if ($global:KATK_InMenu) { Write-Host " Q. Quay lại menu chính" -ForegroundColor Red } else { Write-Host " Q. Thoát" -ForegroundColor Red }
    Write-Host "───────────────────────────────────" -ForegroundColor Gray
}

function Get-UserSelection {
    Show-SoftwareMenu
    Write-Host "`n👉 VUI LÒNG CHỌN PHẦN MỀM ĐỂ CÀI ĐẶT:" -ForegroundColor Yellow
    Write-Host "   - Nhập số thứ tự phần mềm, có thể chọn gói và phần mềm riêng lẻ (cách nhau bằng dấu cách, ví dụ: A 1 3 5)" -ForegroundColor Gray
    Write-Host "   - Khi cài đặt LibreOffice vui lòng chạy tools xóa Microsoft Office trên máy để tránh xung đột phần mềm" -ForegroundColor Gray
    Write-Host "   - Nhập 0 để cài đặt GÓI CƠ BẢN" -ForegroundColor Gray
    Write-Host "   - Nhập A để cài đặt GÓI EVKEY" -ForegroundColor Gray
    while ($true) {
        Write-Host "`nNhập lựa chọn của bạn và nhấn Enter: " -ForegroundColor Yellow -NoNewline
        $input = Read-Host
        if ([string]::IsNullOrWhiteSpace($input)) {
            Write-Host "⚠️ Vui lòng nhập ít nhất một lựa chọn!" -ForegroundColor Red
            continue
        }
        $selectedNumbers = @()
        if ($input.Trim() -match '^[Qq]$') { Exit-KATKModule }
        $inputParts = $input -split '\s+' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
        $hasPackage = $false
        $hasError = $false
        foreach ($part in $inputParts) {
            if ($part -eq "0") {
                if ($hasPackage) {
                    Write-Host "❌ Chỉ được chọn một gói duy nhất (0 hoặc A)" -ForegroundColor Red
                    $hasError = $true
                    break
                }
                $hasPackage = $true
                $selectedNumbers += $packageBasic
                Write-Host "✅ Đã chọn gói cơ bản" -ForegroundColor Green
            }
            elseif ($part -eq "A" -or $part -eq "a") {
                if ($hasPackage) {
                    Write-Host "❌ Chỉ được chọn một gói duy nhất (0 hoặc A)" -ForegroundColor Red
                    $hasError = $true
                    break
                }
                $hasPackage = $true
                $selectedNumbers += $packageEVKey
                Write-Host "✅ Đã chọn gói EVKey" -ForegroundColor Green
            }
            elseif ($part -match '^\d+$') {
                $num = [int]$part
                if ($num -ge 1 -and $num -le $softwareList.Count) {
                    $selectedNumbers += $num
                } else {
                    Write-Host "❌ Số $num không hợp lệ (phải từ 1 đến $($softwareList.Count))" -ForegroundColor Red
                    $hasError = $true
                }
            } else {
                Write-Host "❌ '$part' không phải là lựa chọn hợp lệ" -ForegroundColor Red
                $hasError = $true
            }
        }
        if ($hasError) {
            Write-Host "⚠️ Vui lòng nhập lại lựa chọn!" -ForegroundColor Red
            continue
        }
        if ($selectedNumbers.Count -eq 0) {
            Write-Host "⚠️ Không có phần mềm nào được chọn!" -ForegroundColor Red
            continue
        }
        $uniqueSelections = $selectedNumbers | Sort-Object | Get-Unique
        $selectedSoftware = @()
        foreach ($index in $uniqueSelections) {
            $selectedSoftware += $softwareList[$index - 1]
        }
        Write-Host "`n📋 DANH SÁCH PHẦN MỀM SẼ CÀI ĐẶT:" -ForegroundColor Cyan
        Write-Host "───────────────────────────────────" -ForegroundColor Gray
        foreach ($software in $selectedSoftware) {
            Write-Host "   • $($software.Name)" -ForegroundColor White
        }
        Write-Host "───────────────────────────────────" -ForegroundColor Gray
        Write-Host "   Tổng cộng: $($selectedSoftware.Count) phần mềm" -ForegroundColor Cyan
        while ($true) {
            Write-Host "`n👉 NHẤN ENTER để bắt đầu cài đặt, hoặc nhập 'R' để chọn lại danh sách phần mềm" -ForegroundColor Yellow
            Write-Host "   Lựa chọn của bạn: " -ForegroundColor Yellow -NoNewline
            $confirm = Read-Host
            if ($confirm -eq '' -or $confirm -eq 'y' -or $confirm -eq 'Y') {
                Write-Host "`n🚀 Bắt đầu quá trình tải và khởi chạy cài đặt..." -ForegroundColor Green
                return $selectedSoftware
            }
            elseif ($confirm -eq 'r' -or $confirm -eq 'R') {
                Write-Host "`n🔄 Quay lại chọn danh sách phần mềm..." -ForegroundColor Cyan
                return $null
            }
            else {
                Write-Host "⚠️ Lựa chọn không hợp lệ! Vui lòng nhấn Enter hoặc nhập 'R'" -ForegroundColor Red
            }
        }
    }
}

function Format-FileSize {
    param([long]$Size)
    if ($Size -lt 1KB) { return "$Size bytes" }
    elseif ($Size -lt 1MB) { return "$([math]::Round($Size / 1KB, 2)) KB" }
    elseif ($Size -lt 1GB) { return "$([math]::Round($Size / 1MB, 2)) MB" }
    else { return "$([math]::Round($Size / 1GB, 2)) GB" }
}

function Get-FileNameFromUrl {
    param([string]$Url, [string]$SoftwareName, [string]$Type)
    try {
        $uri = [System.Uri]$Url
        $fileName = [System.IO.Path]::GetFileName($uri.LocalPath)
        if ([string]::IsNullOrEmpty($fileName)) { $fileName = "$SoftwareName.$Type" }
        $invalidChars = [System.IO.Path]::GetInvalidFileNameChars()
        foreach ($char in $invalidChars) { $fileName = $fileName.Replace($char, '_') }
        $extension = [System.IO.Path]::GetExtension($fileName)
        if ([string]::IsNullOrEmpty($extension)) { $fileName = "$fileName.$Type" }
        if ($Type -eq "exe" -and $extension -ne ".exe") { $fileName = $fileName -replace "\.[^\.]+$", ".exe" }
        elseif ($Type -eq "zip" -and $extension -ne ".zip") { $fileName = $fileName -replace "\.[^\.]+$", ".zip" }
        if ($fileName -notlike "*$SoftwareName*") {
            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
            $ext = [System.IO.Path]::GetExtension($fileName)
            $fileName = "${SoftwareName}_$baseName$ext"
        }
        return $fileName
    } catch {
        $safeName = $SoftwareName -replace '[^\w\-]', '_'
        return "$safeName.$Type"
    }
}

function Find-ExecutableFile {
    param([string]$Directory, [string]$SoftwareName)
    $commonPatterns = @("$SoftwareName*.exe", "*.exe")
    foreach ($pattern in $commonPatterns) {
        $exeFiles = Get-ChildItem -Path $Directory -Filter $pattern -Recurse -File |
                    Where-Object { $_.Name -notlike "*uninstall*" -and $_.Name -notlike "*setup*" -and $_.Name -notlike "*install*" }
        if ($exeFiles) {
            $preferredFile = $exeFiles | Where-Object { $_.Name -like "$SoftwareName*" } | Select-Object -First 1
            if ($preferredFile) { return $preferredFile.FullName }
            return $exeFiles[0].FullName
        }
    }
    return $null
}

function Create-PortableShortcut {
    param([string]$SoftwareName, [string]$ExePath)
    try {
        $desktopPath = [Environment]::GetFolderPath("Desktop")
        $shortcutPath = Join-Path $desktopPath "$SoftwareName.lnk"
        if (Test-Path $shortcutPath) {
            Write-Host "      ℹ️ Shortcut '$SoftwareName' đã có trên desktop" -ForegroundColor Blue
            return $false
        }
        if (-not (Test-Path $ExePath)) {
            Write-Host "      ⚠️ Không tìm thấy file: $(Split-Path $ExePath -Leaf)" -ForegroundColor Yellow
            return $false
        }
        $WshShell = New-Object -ComObject WScript.Shell
        $Shortcut = $WshShell.CreateShortcut($shortcutPath)
        $Shortcut.TargetPath = $ExePath
        $Shortcut.WorkingDirectory = (Split-Path $ExePath)
        $Shortcut.IconLocation = $ExePath
        $Shortcut.Save()
        Write-Host "      📝 Đã thêm shortcut '$SoftwareName' ra desktop" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "      ❗ Lỗi tạo shortcut: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Start-Installation {
    param([hashtable]$Software, [string]$FilePath)
    try {
        if ($Software.Type -eq "exe") {
            if (-not (Test-Path $FilePath)) {
                Write-Host "      ❌ File không tồn tại: $FilePath" -ForegroundColor Red
                return @{ Success = $false; Name = $Software.Name; Error = "File không tồn tại" }
            }
            try {
                $process = Start-Process -FilePath $FilePath -NoNewWindow -PassThru -ErrorAction Stop
                Start-Sleep -Milliseconds 500
                return @{ Success = $true; Name = $Software.Name; Type = $Software.Type }
            }
            catch [System.ComponentModel.Win32Exception] {
                if ($_.Exception.NativeErrorCode -eq 740) {
                    Write-Host "      🔑 Thử khởi chạy với quyền Administrator..." -ForegroundColor Yellow
                    try {
                        $process = Start-Process -FilePath $FilePath -Verb RunAs -NoNewWindow -PassThru -ErrorAction Stop
                        Start-Sleep -Milliseconds 500
                        return @{ Success = $true; Name = $Software.Name; Type = $Software.Type }
                    } catch {
                        Write-Host "      ❌ Lỗi khi chạy với quyền Admin: $($_.Exception.Message)" -ForegroundColor Red
                        return @{ Success = $false; Name = $Software.Name; Error = $_.Exception.Message }
                    }
                } else {
                    Write-Host "      ❌ Lỗi Win32: $($_.Exception.Message)" -ForegroundColor Red
                    return @{ Success = $false; Name = $Software.Name; Error = $_.Exception.Message }
                }
            }
            catch {
                Write-Host "      ❌ Lỗi khởi chạy: $($_.Exception.Message)" -ForegroundColor Red
                return @{ Success = $false; Name = $Software.Name; Error = $_.Exception.Message }
            }
        }
        elseif ($Software.Type -eq "zip") {
            Write-Host "      📦 Đang giải nén: $($Software.Name)" -ForegroundColor Magenta
            $extractPath = Join-Path $portableDir $Software.Name
            if (!(Test-Path $extractPath)) {
                New-Item -ItemType Directory -Path $extractPath -Force | Out-Null
            }
            try {
                Expand-Archive -Path $FilePath -DestinationPath $extractPath -Force -ErrorAction Stop
                $exePath = Find-ExecutableFile -Directory $extractPath -SoftwareName $Software.Name
                if ($exePath) {
                    Write-Host "      🔍 Tìm thấy file thực thi: $(Split-Path $exePath -Leaf)" -ForegroundColor Cyan
                    $shortcutCreated = Create-PortableShortcut -SoftwareName $Software.Name -ExePath $exePath
                } else {
                    Write-Host "      ⚠️ Không tìm thấy file thực thi trong thư mục" -ForegroundColor Yellow
                }
                return @{ Success = $true; Name = $Software.Name; Type = $Software.Type }
            } catch {
                Write-Host "      ❌ Lỗi giải nén: $($_.Exception.Message)" -ForegroundColor Red
                return @{ Success = $false; Name = $Software.Name; Error = $_.Exception.Message }
            }
        }
        elseif ($Software.Type -eq "msi") {
            Write-Host "      ⚙️ Đang chạy cài đặt MSI: $($Software.Name)" -ForegroundColor Magenta
            if (-not (Test-Path $FilePath)) {
                Write-Host "      ❌ File MSI không tồn tại: $FilePath" -ForegroundColor Red
                return @{ Success = $false; Name = $Software.Name; Error = "File MSI không tồn tại" }
            }
            try {
                $msiArgs = "/i `"$FilePath`" /passive"
                $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $msiArgs -NoNewWindow -PassThru -ErrorAction Stop
                Start-Sleep -Milliseconds 500
                return @{ Success = $true; Name = $Software.Name; Type = $Software.Type }
            } catch {
                Write-Host "      ❌ Lỗi chạy MSI: $($_.Exception.Message)" -ForegroundColor Red
                return @{ Success = $false; Name = $Software.Name; Error = $_.Exception.Message }
            }
        }
        else {
            Write-Host "      ⚠️ Loại file không được hỗ trợ: $($Software.Type)" -ForegroundColor Yellow
            return @{ Success = $false; Name = $Software.Name; Error = "Loại file không hỗ trợ" }
        }
    } catch {
        Write-Host "      ❌ Lỗi khi khởi chạy cài đặt: $($_.Exception.Message)" -ForegroundColor Red
        return @{ Success = $false; Name = $Software.Name; Error = $_.Exception.Message }
    }
}

function Start-ParallelDownloads {
    param([array]$SoftwareItems)

    $downloadJobs = @{}
    $jobStatusDir = Join-Path $tempDir "JobStatus"
    if (-not (Test-Path $jobStatusDir)) { New-Item -ItemType Directory -Path $jobStatusDir -Force | Out-Null }

    foreach ($software in $SoftwareItems) {
        $fileName = Get-FileNameFromUrl -Url $software.URL -SoftwareName $software.Name -Type $software.Type
        $filePath = Join-Path $tempDir $fileName
        if (Test-Path $filePath) { Remove-Item -Force $filePath -ErrorAction SilentlyContinue }

        $statusFile = Join-Path $jobStatusDir "$($software.Name).status"
        "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')|0|0|0|Đang khởi tạo" | Out-File -FilePath $statusFile -Force

        Write-Host "   📥 Bắt đầu tải: $($software.Name)" -ForegroundColor Cyan

        $job = Start-Job -Name $software.Name -ScriptBlock {
            param($url, $outPath, $statusFile, $name)
            try {
                [System.Net.ServicePointManager]::DefaultConnectionLimit = 80
                [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
                Add-Type -AssemblyName System.Net.Http -ErrorAction Stop

                $httpClient = New-Object System.Net.Http.HttpClient
                $httpClient.DefaultRequestHeaders.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
                $httpClient.DefaultRequestHeaders.Add("Accept", "*/*")
                $response = $httpClient.GetAsync($url, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).Result
                $response.EnsureSuccessStatusCode() | Out-Null
                $totalBytes = $response.Content.Headers.ContentLength
                if (-not $totalBytes) { $totalBytes = 0 }

                $buffer = New-Object byte[] 8192
                $stream = $response.Content.ReadAsStreamAsync().Result
                $fileStream = [System.IO.File]::OpenWrite($outPath)
                $totalRead = 0
                $lastUpdate = 0
                do {
                    $read = $stream.Read($buffer, 0, $buffer.Length)
                    if ($read -eq 0) { break }
                    $fileStream.Write($buffer, 0, $read)
                    $totalRead += $read
                    $now = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
                    if ($totalBytes -gt 0) {
                        $percent = [math]::Round(($totalRead / $totalBytes) * 100, 2)
                        if ($percent -ne $lastUpdate) {
                            "$now|$percent|$totalRead|$totalBytes|Đang tải" | Out-File -FilePath $statusFile -Force
                            $lastUpdate = $percent
                        }
                    } else {
                        "$now|0|$totalRead|0|Đang tải" | Out-File -FilePath $statusFile -Force
                    }
                } while ($true)
                $fileStream.Close()
                $stream.Close()
                $response.Dispose()
                $httpClient.Dispose()

                if (Test-Path $outPath) {
                    $size = (Get-Item $outPath).Length
                    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')|100|$size|$size|Hoàn tất" | Out-File -FilePath $statusFile -Force
                    return @{ Success = $true; Path = $outPath; Name = $name; Size = $size }
                } else {
                    throw "File không tồn tại sau khi tải"
                }
            } catch {
                "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')|0|0|0|Lỗi: $($_.Exception.Message)" | Out-File -FilePath $statusFile -Force
                return @{ Success = $false; Name = $name; Error = $_.Exception.Message }
            }
        } -ArgumentList $software.URL, $filePath, $statusFile, $software.Name

        $downloadJobs[$software.Name] = @{
            Job = $job
            Software = $software
            FilePath = $filePath
            StatusFile = $statusFile
            Status = "Đang khởi tạo"
            Percent = 0
            Transferred = 0
            Total = 0
            Completed = $false
        }
    }
    return $downloadJobs
}

function Monitor-ParallelDownloads {
    param([hashtable]$DownloadJobs)

    $totalJobs = $DownloadJobs.Count
    $allDone = $false

    Write-Host "`n ⏳ Đang theo dõi tiến trình tải..." -ForegroundColor Yellow
    Write-Host "   💡 Các phần mềm sẽ được khởi chạy cài đặt ngay khi tải xong!" -ForegroundColor Cyan

    while (-not $allDone) {
        Clear-Host
        foreach ($key in $DownloadJobs.Keys) {
            $item = $DownloadJobs[$key]
            $statusFile = $item.StatusFile
            if (Test-Path $statusFile) {
                $content = Get-Content -Path $statusFile -Raw
                if ($content -match '^([^|]+)\|([^|]+)\|([^|]+)\|([^|]+)\|(.+)$') {
                    $status = $matches[5]
                    $percent = [double]$matches[2]
                    $transferred = [long]$matches[3]
                    $total = [long]$matches[4]
                    $item.Status = $status
                    $item.Percent = $percent
                    $item.Transferred = $transferred
                    $item.Total = $total
                    if ($status -eq "Hoàn tất") {
                        $item.Completed = $true
                    }
                }
            }
        }

        foreach ($key in @($DownloadJobs.Keys)) {
            $item = $DownloadJobs[$key]
            if ($item.Completed) { continue }

            if ($item.Job.State -eq 'Completed') {
                $result = Receive-Job -Job $item.Job -Keep:$false
                Remove-Job -Job $item.Job -Force -ErrorAction SilentlyContinue
                if ($result.Success) {
                    $installResult = Start-Installation -Software $item.Software -FilePath $result.Path
                    if (-not $installResult.Success) {
                        Write-Host "   ❌ Không thể khởi chạy cài đặt: $($item.Software.Name)" -ForegroundColor Red
                        if ($installResult.Error) { Write-Host "   💬 $($installResult.Error)" -ForegroundColor Gray }
                    }
                } else {
                    Write-Host "   ❌ LỖI TẢI: $($result.Name) - $($result.Error)" -ForegroundColor Red
                }
                $item.Completed = $true
                $item.Status = "Hoàn tất"
            } elseif ($item.Job.State -eq 'Failed') {
                Receive-Job -Job $item.Job | Out-Null
                Remove-Job -Job $item.Job -Force -ErrorAction SilentlyContinue
                Write-Host "   ❌ JOB THẤT BẠI: $($item.Software.Name)" -ForegroundColor Red
                $item.Completed = $true
                $item.Status = "Lỗi"
            }
        }

        $completedCount = 0
        foreach ($key in $DownloadJobs.Keys) {
            if ($DownloadJobs[$key].Completed) { $completedCount++ }
        }

        Write-Host " Tên phần mềm".PadRight(25) -NoNewline
        Write-Host " Tiến trình".PadRight(14) -NoNewline
        Write-Host " Dung lượng".PadRight(20) -NoNewline
        Write-Host " Trạng thái" -ForegroundColor Yellow
        Write-Host ("─" * 75) -ForegroundColor DarkGray

        foreach ($key in $DownloadJobs.Keys) {
            $item = $DownloadJobs[$key]
            $name = if ($item.Software.Name.Length -gt 24) { $item.Software.Name.Substring(0,24) } else { $item.Software.Name.PadRight(24) }
            $isCompleted = $item.Completed
            $percentStr = if ($item.Percent -gt 0) { "$([math]::Round($item.Percent, 2))%".PadRight(14) } else { "".PadRight(14) }
            if ($item.Total -gt 0) {
                $sizeStr = "$(Format-FileSize $item.Transferred)/$(Format-FileSize $item.Total)".PadRight(20)
            } elseif ($item.Transferred -gt 0) {
                $sizeStr = "$(Format-FileSize $item.Transferred)".PadRight(20)
            } else {
                $sizeStr = "".PadRight(20)
            }
            $status = $item.Status
            $colorStatus = if ($isCompleted) { "Green" } elseif ($status -match "Lỗi") { "Red" } else { "White" }
            $colorPercent = if ($isCompleted) { "Green" } else { "White" }
            $colorSize = if ($isCompleted) { "DarkGray" } else { "White" }

            Write-Host " $name" -NoNewline
            Write-Host " $percentStr" -ForegroundColor $colorPercent -NoNewline
            Write-Host " $sizeStr" -ForegroundColor $colorSize -NoNewline
            Write-Host " $status" -ForegroundColor $colorStatus
        }

        Write-Host ("─" * 75) -ForegroundColor DarkGray
        Write-Host " 📊 Đã hoàn thành: $completedCount / $totalJobs phần mềm" -ForegroundColor Gray

        if ($completedCount -eq $totalJobs) {
            $allDone = $true
            Write-Host "`n ✅ TẤT CẢ PHẦN MỀM ĐÃ TẢI XONG!" -ForegroundColor Green
            break
        }

        Start-Sleep -Seconds 1
    }
}

while ($true) {
    do {
        $selectedSoftware = Get-UserSelection
    } while ($selectedSoftware -eq $null)

    if ($selectedSoftware.Count -eq 0) {
        Write-Host "Không có phần mềm nào được chọn." -ForegroundColor Yellow
        Exit-KATKModule
    }

    $totalSoftware = $selectedSoftware.Count
    $portableDir = "C:\Programs"
    New-Item -ItemType Directory -Path $portableDir -Force -ErrorAction SilentlyContinue | Out-Null
    Write-Host " 🛠️ Chuẩn bị tải và khởi chạy cài đặt $totalSoftware phần mềm!" -ForegroundColor Yellow
    Write-Host " ℹ️ Các phần mềm sẽ được khởi chạy tự động, bạn có thể thao tác cài đặt từng phần mềm" -ForegroundColor Cyan
    Write-Host ""

    Write-Host "🚀 Khởi động quá trình tải..." -ForegroundColor Yellow
    $downloadJobs = Start-ParallelDownloads -SoftwareItems $selectedSoftware
    Monitor-ParallelDownloads -DownloadJobs $downloadJobs

    Write-Host "`n═════ 🎉 HOÀN TẤT TẢI VÀ KHỞI CHẠY CÀI ĐẶT ═════" -ForegroundColor Green
    Write-Host " ✅ Đã tải và khởi chạy cài đặt cho $totalSoftware phần mềm" -ForegroundColor Cyan
    Write-Host " 📁 Phần mềm portable được lưu tại: $portableDir" -ForegroundColor Cyan
    Write-Host "───────────────────────────────────`n" -ForegroundColor Gray

    Read-Host "Nhấn Enter để quay lại danh sách phần mềm..."
}
