Add-Type -AssemblyName System.Net.Http

function Test-OfficeInstalled {
    $regPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office",
        "HKCU:\Software\Microsoft\Office"
    )
    foreach ($path in $regPaths) {
        if (Test-Path $path) {
            $officePaths = @(
                "$env:ProgramFiles\Microsoft Office\root\Office16\WINWORD.EXE",
                "${env:ProgramFiles(x86)}\Microsoft Office\root\Office16\WINWORD.EXE",
                "$env:ProgramFiles\Microsoft Office\Office16\WINWORD.EXE",
                "${env:ProgramFiles(x86)}\Microsoft Office\Office16\WINWORD.EXE"
            )
            foreach ($officePath in $officePaths) {
                if (Test-Path $officePath) {
                    return $true
                }
            }
            return $false
        }
    }
    return $false
}

function Get-OfficeLanguage {
    do {
        Clear-Host
        Show-KATKHeader "CHỌN NGÔN NGỮ HIỂN THỊ"
        Write-Host ""
        Write-Host "DANH SÁCH NGÔN NGỮ:" -ForegroundColor Yellow
        Write-Host "────────────────────────────────────────" -ForegroundColor DarkGray

        Write-Host "  [1] Tiếng Việt" -ForegroundColor White
        Write-Host "  [2] English" -ForegroundColor White
        Write-Host "  [3] 中文(简体) - Tiếng Trung Giản Thể" -ForegroundColor White
        Write-Host "  [4] 中文(繁體) - Tiếng Trung Phồn Thể" -ForegroundColor White

        Write-Host "  [0] Quay lại" -ForegroundColor Yellow
        Write-Host "  [E] Menu Office Tools" -ForegroundColor Red
        Write-Host "────────────────────────────────────────" -ForegroundColor DarkGray
        $langChoice = Read-Host "`nChọn ngôn ngữ hiển thị Office..."
        switch ($langChoice.ToUpper()) {
            '1' { return "vi-vn" }
            '2' { return "en-us" }
            '3' { return "zh-cn" }
            '4' { return "zh-tw" }
            '0' { return "BACK" }
            'E' { return "EXIT" }
            default {
                Write-Host "❌ Lựa chọn không hợp lệ" -ForegroundColor Red
                Read-Host "Nhấn Enter để thử lại"
            }
        }
    } while ($true)
}

function Get-OfficeSuiteType {
    do {
        Clear-Host
        Show-KATKHeader "CHỌN SKU OFFICE"
        Write-Host ""
        Write-Host "DANH SÁCH SKU:" -ForegroundColor Yellow
        Write-Host "────────────────────────────────────────" -ForegroundColor DarkGray

        Write-Host "  [1] Pro Plus" -ForegroundColor White
        Write-Host "  [2] Business" -ForegroundColor White
        Write-Host "  [3] Home & Student" -ForegroundColor White
        Write-Host "  [4] Home & Business" -ForegroundColor White
        Write-Host "  [5] Home" -ForegroundColor White

        Write-Host "  `n[0] Quay lại menu" -ForegroundColor Red
        Write-Host "────────────────────────────────────────" -ForegroundColor DarkGray
        $choice = Read-Host "`nChọn gói"
        switch ($choice) {
            '1' { return '1' }
            '2' { return '2' }
            '3' { return '3' }
            '4' { return '4' }
            '5' { return '5' }
            '0' { return 'EXIT' }
            default {
                Write-Host "❌ Lựa chọn không hợp lệ" -ForegroundColor Red
                Read-Host "Nhấn Enter để thử lại"
            }
        }
    } while ($true)
}

function Show-VersionMenu {
    param([string]$suiteChoice)
    Show-KATKHeader "CHỌN VERSION OFFICE"
    Write-Host "────────────────────────────────────────`n" -ForegroundColor DarkGray
    switch ($suiteChoice) {
        '1' { Write-Host " [1] 365`n [2] 2024`n [3] 2021" }
        '2' { Write-Host " [1] 365" }
        '3' { Write-Host " [1] 2021" }
        '4' { Write-Host " [1] 2024`n [2] 2021" }
        '5' { Write-Host " [1] 365`n [2] 2024" }
    }
    Write-Host "`n [0] Quay lại" -ForegroundColor Yellow
    Write-Host " [E] Menu Office Tools" -ForegroundColor Red
    Write-Host "────────────────────────────────────────" -ForegroundColor DarkGray
}

function Get-OfficeProductID {
    param([string]$suiteChoice, [string]$versionChoice)
    switch ($suiteChoice) {
        '1' { switch ($versionChoice) {
                '1' { return "O365ProPlusRetail" }
                '2' { return "ProPlus2024Retail" }
                '3' { return "ProPlus2021Retail" }
            }
        }
        '2' { switch ($versionChoice) { '1' { return "O365BusinessRetail" } } }
        '3' { switch ($versionChoice) { '1' { return "HomeStudent2021Retail" } } }
        '4' { switch ($versionChoice) {
                '1' { return "HomeBusiness2024Retail" }
                '2' { return "HomeBusiness2021Retail" }
            }
        }
        '5' { switch ($versionChoice) {
                '1' { return "O365HomePremRetail" }
                '2' { return "Home2024Retail" }
            }
        }
    }
    return $null
}

function Get-DownloadURL {
    param([string]$productID, [string]$language)
    $baseUrl = "https://officecdn.microsoft.com/db/492350F6-3A01-4F97-B9C0-C7C6DDF67D60/media"
    $langCode = $language
    if ($language -eq "vi-vn") { $langCode = "vi-vn" }
    if ($language -eq "en-us") { $langCode = "en-us" }
    if ($language -eq "zh-cn") { $langCode = "zh-cn" }
    if ($language -eq "zh-tw") { $langCode = "zh-tw" }
    return "$baseUrl/$langCode/$productID.img"
}

function Create-DesktopShortcuts {
    $desktop = [Environment]::GetFolderPath("Desktop")
    $shell = New-Object -ComObject WScript.Shell
    $officePaths = @(
        "$env:ProgramFiles\Microsoft Office\root\Office16",
        "${env:ProgramFiles(x86)}\Microsoft Office\root\Office16"
    )
    $apps = @{ "Word" = "WINWORD.EXE"; "Excel" = "EXCEL.EXE"; "PowerPoint" = "POWERPNT.EXE" }
    foreach ($basePath in $officePaths) {
        if (-not (Test-Path $basePath)) { continue }
        foreach ($app in $apps.GetEnumerator()) {
            $target = Join-Path $basePath $app.Value
            if (Test-Path $target) {
                $shortcut = $shell.CreateShortcut("$desktop\$($app.Key).lnk")
                $shortcut.TargetPath = $target
                $shortcut.Save()
            }
        }
        break
    }
}

function Get-SystemArchitecture {
    if ($ForceARM) { return "ARM64" }
    $arch = $env:PROCESSOR_ARCHITECTURE
    if ($arch -eq "ARM64") { return "ARM64" }
    if ($arch -eq "AMD64") { return "AMD64" }
    if ($arch -eq "x86") {
        $arch6432 = $env:PROCESSOR_ARCHITEW6432
        if ($arch6432 -eq "ARM64") { return "ARM64" }
        if ($arch6432 -eq "AMD64") { return "AMD64" }
    }
    return "UNKNOWN"
}

function Install-OfficeWithODT {
    param(
        [string]$ProductID,
        [string]$Language
    )

    $workDir = Join-Path $global:tempDir "ODT"
    if (Test-Path $workDir) {
        Remove-Item -Recurse -Force $workDir -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Path $workDir -Force | Out-Null

    try {
        $odtUrl = "https://download.microsoft.com/download/2/7/A/27AF1BE6-DD20-4CB4-B154-EBAB8A7D4A7E/officedeploymenttool_13407-20325.exe"
        $odtExe = Join-Path $workDir "ODT.exe"
        Write-Host "⏳ Đang chuẩn bị công cụ cài đặt..." -ForegroundColor Cyan
        Invoke-WebRequest -Uri $odtUrl -OutFile $odtExe -UseBasicParsing

        Start-Process -FilePath $odtExe -ArgumentList "/quiet /extract:`"$workDir`"" -Wait
        Remove-Item $odtExe -Force

        $setupExe = Join-Path $workDir "setup.exe"

        $xmlDownload = @"
<Configuration>
  <Add OfficeClientEdition="ARM64" Channel="Current">
    <Product ID="$ProductID">
      <Language ID="$Language" />
    </Product>
  </Add>
  <Display Level="None" AcceptEULA="TRUE" />
</Configuration>
"@
        $configDownload = Join-Path $workDir "download.xml"
        Set-Content -Path $configDownload -Value $xmlDownload -Encoding UTF8

        $sourceDir = Join-Path $workDir "Source"
        New-Item -ItemType Directory -Path $sourceDir -Force | Out-Null

        Write-Host "`n⏳ Đang tải gói Office ARM64 (khoảng 2.5 GB)..." -ForegroundColor Cyan
        Push-Location $sourceDir
        $proc = Start-Process -FilePath $setupExe -ArgumentList "/download `"$configDownload`"" -PassThru -WindowStyle Hidden
        Pop-Location

        $totalMB = 2500
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $lastSize = 0
        $lastCheck = Get-Date

        while (-not $proc.HasExited) {
            Start-Sleep -Milliseconds 500
            if (Test-Path $sourceDir) {
                $currentSize = (Get-ChildItem $sourceDir -Recurse -File | Measure-Object -Property Length -Sum).Sum
                if ($currentSize -gt 0) {
                    $currentMB = [math]::Round($currentSize / 1MB, 2)
                    $percent = [math]::Min(100, [math]::Round(($currentSize / ($totalMB * 1MB)) * 100, 2))
                    $elapsed = $sw.Elapsed.TotalSeconds
                    if ($elapsed -gt 1) {
                        $speed = ($currentSize - $lastSize) / ($elapsed - $lastCheck.TotalSeconds)
                        $speedMB = [math]::Round($speed / 1MB, 2)
                        Write-Host -NoNewline "`r→ Tiến trình: $currentMB MB / ~$totalMB MB ($percent%) - $speedMB MB/s    " -ForegroundColor Cyan
                    }
                    $lastSize = $currentSize
                    $lastCheck = Get-Date
                }
            }
        }
        $proc.WaitForExit()
        Write-Host "`r                                                           `r" -NoNewline
        if ($proc.ExitCode -ne 0) {
            throw "Lỗi khi tải gói Office (mã: $($proc.ExitCode))"
        }
        $finalSize = [math]::Round((Get-ChildItem $sourceDir -Recurse -File | Measure-Object -Property Length -Sum).Sum / 1MB, 2)
        Write-Host "✔ Đã tải xong $finalSize MB" -ForegroundColor Green

        Write-Host "`n⏳ Đang cài đặt Office (từ source đã tải)..." -ForegroundColor Cyan
        $xmlInstall = @"
<Configuration>
  <Add OfficeClientEdition="ARM64" Channel="Current" SourcePath="$sourceDir">
    <Product ID="$ProductID">
      <Language ID="$Language" />
    </Product>
  </Add>
  <Display Level="None" AcceptEULA="TRUE" />
</Configuration>
"@
        $configInstall = Join-Path $workDir "install.xml"
        Set-Content -Path $configInstall -Value $xmlInstall -Encoding UTF8

        $proc = Start-Process -FilePath $setupExe -ArgumentList "/configure `"$configInstall`"" -Wait -PassThru
        if ($proc.ExitCode -ne 0) {
            throw "Lỗi khi cài đặt Office (mã: $($proc.ExitCode))"
        }
        Write-Host "✔ Cài đặt hoàn tất!" -ForegroundColor Green
    }
    catch {
        Write-Host "❌ LỖI: $_" -ForegroundColor Red
        Read-Host "Nhấn Enter để quay lại"
    }
    finally {
        if (Test-Path $workDir) {
            Remove-Item -Recurse -Force $workDir -ErrorAction SilentlyContinue
            Write-Host "✔ Đã xóa file tạm" -ForegroundColor Gray
        }
    }
}

function Install-Office {
    if (-not (Test-Path variable:global:tempDir) -or -not $global:tempDir) {
        $global:tempDir = "C:\KATK-Tools"
    }
    if (-not (Test-Path $global:tempDir)) {
        New-Item -ItemType Directory -Path $global:tempDir -Force | Out-Null
    }

    do {
        $suiteChoice = Get-OfficeSuiteType
        if ($suiteChoice -eq 'EXIT') { return }

        do {
            Clear-Host
            Show-VersionMenu $suiteChoice
            $versionChoice = Read-Host "`nChọn phiên bản"
            if ($versionChoice.ToUpper() -eq '0') { break }
            if ($versionChoice.ToUpper() -eq 'E') { return }

            $productID = Get-OfficeProductID $suiteChoice $versionChoice
            if (-not $productID) {
                Write-Host "❌ Lựa chọn không hợp lệ" -ForegroundColor Red
                Read-Host "Nhấn Enter để thử lại"
                continue
            }

            $language = Get-OfficeLanguage
            if ($language -eq 'BACK') { continue }
            if ($language -eq 'EXIT') { return }

            if (Test-OfficeInstalled) {
                Write-Host "`n⚠ ĐÃ PHÁT HIỆN OFFICE TRÊN MÁY" -ForegroundColor Yellow
                Write-Host "Vui lòng gỡ Office cũ trước khi cài đặt mới!" -ForegroundColor Gray
                Read-Host "Nhấn Enter để quay về menu Office Tools"
                return
            }

            $arch = Get-SystemArchitecture
            if ($arch -eq "ARM64") {
                Write-Host "`n🔍 Phát hiện kiến trúc ARM64 – Sử dụng ODT để tải và cài." -ForegroundColor Cyan
                Install-OfficeWithODT -ProductID $productID -Language $language
                Create-DesktopShortcuts
                Write-Host "`n✔ CÀI ĐẶT HOÀN TẤT!" -ForegroundColor Green
                Read-Host "`nNhấn Enter để quay lại menu Office Tools"
                return
            }
            elseif ($arch -ne "AMD64") {
                Write-Host "`n⚠ Không xác định được kiến trúc ($arch). Vẫn thử dùng phương thức AMD64." -ForegroundColor Yellow
            }

            $downloadUrl = Get-DownloadURL -productID $productID -language $language
            $imgFile = Join-Path $global:tempDir "$productID.img"

            Clear-Host
            Show-Step "ĐANG TẢI FILE CÀI ĐẶT (4~6GB)"
            try {
                [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
                $httpClient = New-Object System.Net.Http.HttpClient
                $httpClient.DefaultRequestHeaders.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
                $httpClient.DefaultRequestHeaders.Add("Accept", "*/*")
                $response = $httpClient.GetAsync($downloadUrl, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).Result
                $response.EnsureSuccessStatusCode() | Out-Null
                $totalBytes = $response.Content.Headers.ContentLength
                if (-not $totalBytes) { $totalBytes = 0 }

                $buffer = New-Object byte[] 8192
                $stream = $response.Content.ReadAsStreamAsync().Result
                $fileStream = [System.IO.File]::OpenWrite($imgFile)
                $totalRead = 0
                $lastPercent = -1
                $sw = [System.Diagnostics.Stopwatch]::StartNew()
                $lastSpeedUpdate = 0
                $speedBytes = 0
                do {
                    $read = $stream.Read($buffer, 0, $buffer.Length)
                    if ($read -eq 0) { break }
                    $fileStream.Write($buffer, 0, $read)
                    $totalRead += $read
                    $speedBytes += $read
                    $elapsed = $sw.Elapsed.TotalSeconds
                    if ($elapsed - $lastSpeedUpdate -ge 1) {
                        $speed = $speedBytes / ($elapsed - $lastSpeedUpdate)
                        $speedMB = [math]::Round($speed / 1MB, 2)
                        $lastSpeedUpdate = $elapsed
                        $speedBytes = 0
                        if ($totalBytes -gt 0) {
                            $percent = [math]::Round(($totalRead / $totalBytes) * 100, 2)
                            $transferredMB = [math]::Round($totalRead / 1MB, 2)
                            $totalMB = [math]::Round($totalBytes / 1MB, 2)
                            Write-Host -NoNewline "`r→ Tiến trình: $transferredMB MB / $totalMB MB ($percent%) - $speedMB MB/s    " -ForegroundColor Cyan
                        } else {
                            $transferredMB = [math]::Round($totalRead / 1MB, 2)
                            Write-Host -NoNewline "`r→ Đã tải: $transferredMB MB - $speedMB MB/s    " -ForegroundColor Cyan
                        }
                    }
                } while ($true)
                $fileStream.Close()
                $stream.Close()
                $response.Dispose()
                $httpClient.Dispose()
                Write-Host "`r                                                           `r" -NoNewline
                Write-Host "✔ TẢI HOÀN TẤT!" -ForegroundColor Green
                if (Test-Path $imgFile) {
                    $fileName = Split-Path $imgFile -Leaf
                    $fileSize = [math]::Round((Get-Item $imgFile).Length / 1MB, 2)
                    Write-Host "→ $fileName ($fileSize MB)" -ForegroundColor Gray
                } else {
                    throw "File không tồn tại sau khi tải"
                }
            }
            catch {
                Write-Host "`n❌ LỖI TẢI FILE: $_" -ForegroundColor Red
                try { Remove-Item $imgFile -Force -ErrorAction SilentlyContinue } catch { }
                Read-Host "Nhấn Enter để quay lại"
                return
            }

            Show-Step "ĐANG MOUNT FILE CÀI ĐẶT"
            try {
                $mountResult = Mount-DiskImage -ImagePath $imgFile -PassThru
                $driveLetter = $null
                for ($i = 0; $i -le 10; $i++) {
                    $driveLetter = ($mountResult | Get-Volume).DriveLetter
                    if ($driveLetter) { break }
                    Start-Sleep -Seconds 1
                }
                if (-not $driveLetter) {
                    throw "Không xác định được ổ đĩa sau khi mount"
                }
                $driveRoot = "$driveLetter`:\"
                Write-Host "✔ Đã mount thành công tại ổ $driveRoot" -ForegroundColor Green
            }
            catch {
                Write-Host "❌ LỖI MOUNT FILE IMG: $_" -ForegroundColor Red
                Read-Host "Nhấn Enter để quay lại"
                return
            }

            Show-Step "ĐANG TIẾN HÀNH CÀI ĐẶT"
            Write-Host "→ Đang xác định file cài đặt..." -ForegroundColor Cyan

            if (-not $driveRoot.EndsWith('\')) { $driveRoot = $driveRoot + '\' }
            $setupFile = $driveRoot + 'Office\Setup64.exe'

            if (-not (Test-Path -LiteralPath $setupFile)) {
                Write-Host "❌ KHÔNG TÌM THẤY FILE CÀI ĐẶT TẠI $setupFile" -ForegroundColor Red
                Read-Host "Nhấn Enter để quay lại"
                return
            }

            $fileInfo = Get-Item -LiteralPath $setupFile
            Write-Host "→ Tìm thấy: $($fileInfo.FullName)" -ForegroundColor Gray
            Write-Host "→ Kích thước: $([math]::Round($fileInfo.Length/1MB,2)) MB" -ForegroundColor Gray
            Write-Host "→ Đang chạy trình cài đặt, vui lòng chờ..." -ForegroundColor Cyan

            try {
                $process = Start-Process -FilePath $fileInfo.FullName -Wait -PassThru
                if ($process.ExitCode -ne 0) {
                    Write-Host "⚠ Trình cài đặt kết thúc với mã: $($process.ExitCode)" -ForegroundColor Yellow
                }
            } catch {
                Write-Host "⚠ Không thể khởi chạy tự động, vui lòng chạy thủ công: $($fileInfo.FullName)" -ForegroundColor Yellow
            }

            Show-Step "ĐANG DỌN DẸP..."
            try {
                Dismount-DiskImage -ImagePath $imgFile
                Write-Host "✔ Đã unmount ổ đĩa ảo" -ForegroundColor Green
            }
            catch { }
            try {
                Remove-Item $imgFile -Force -ErrorAction SilentlyContinue
            }
            catch { }

            Show-Step "ĐANG TẠO SHORTCUT..."
            Create-DesktopShortcuts

            Write-Host "`n✔ CÀI ĐẶT HOÀN TẤT!" -ForegroundColor Green
            Read-Host "`nNhấn Enter để quay lại menu Office Tools"
            return

        } while ($true)
    } while ($true)
}