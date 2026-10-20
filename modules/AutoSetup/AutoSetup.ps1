if (-not (Get-Command Show-KATKHeader -ErrorAction SilentlyContinue)) {
    $katkBase = if ($global:KATK_BaseUrl) { $global:KATK_BaseUrl } else { "https://raw.githubusercontent.com/katk410/KATK-Tools/stable" }
    Invoke-Expression ((Invoke-RestMethod -Uri "$katkBase/core/UI.ps1" -UseBasicParsing).TrimStart([char]0xFEFF))
}

Clear-Host
Show-KATKHeader "AUTO SETUP WINDOWS 11"
Assert-KATKAdmin

function Get-DriveType {
    param([string]$DriveLetter)
    try {
        $drive = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$DriveLetter`:'" -ErrorAction SilentlyContinue
        if ($drive) {
            return $drive.DriveType
        }
    } catch {}
    return $null
}

function Reset-TimeAndRegionAuto {
    try {
        Set-Service W32Time -StartupType Automatic -ErrorAction SilentlyContinue
        Start-Service W32Time -ErrorAction SilentlyContinue

        w32tm /config /manualpeerlist:"time.windows.com,0x8" /syncfromflags:MANUAL /update 2>&1 | Out-Null
        Start-Sleep -Seconds 2
        w32tm /resync /force 2>&1 | Out-Null

        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters" -Name "Type" -Value "NTP" -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\TimeProviders\NtpClient" -Name "Enabled" -Value 1 -Force -ErrorAction SilentlyContinue

        $tzKey = "HKLM:\SYSTEM\CurrentControlSet\Services\tzautoupdate"
        if (Test-Path $tzKey) {
            Set-ItemProperty -Path $tzKey -Name "Start" -Value 2 -Force -ErrorAction SilentlyContinue
            Start-Service tzautoupdate -ErrorAction SilentlyContinue
        }
    }
    catch {
    }
}

function Get-CurrentSystemTime { return Get-Date }
function Format-DateTime($time) { return $time.ToString("yyyy-MM-dd HH:mm:ss") }
function Format-Duration($timespan) {
    if (-not $timespan) { return "00:00:00" }
    return $timespan.ToString("hh\:mm\:ss")
}
function Format-FileSize {
    param([long]$Size)
    if ($Size -lt 1KB) { return "$Size bytes" }
    elseif ($Size -lt 1MB) { return "$([math]::Round($Size / 1KB, 2)) KB" }
    elseif ($Size -lt 1GB) { return "$([math]::Round($Size / 1MB, 2)) MB" }
    else { return "$([math]::Round($Size / 1GB, 2)) GB" }
}

function Send-LogToGoogleSheet {
    param(
        [string]$StartTime, [string]$EndTime, [string]$TotalTime, [string]$Inside,
        [string]$ComputerName, [string]$Model, [string]$SerialNumber,
        [string]$CPU, [string]$RAM, [string]$Storage, [string]$Wifi,
        [string]$Graphics, [string]$NPU
    )
    try {
        $webAppUrl = "https://script.google.com/macros/s/AKfycbzOvyJjJnf5Nqcz2C7k2tP7DlXqnV2vmKtshqnA035RxdvuK8uGBnIXi2Ld5CX8hqIu/exec"
        $payload = @{
            startTime    = $StartTime
            endTime      = $EndTime
            totalTime    = $TotalTime
            inside       = $Inside
            computerName = $ComputerName
            model        = $Model
            serialNumber = $SerialNumber
            cpu          = $CPU
            ram          = $RAM
            storage      = $Storage
            wifi         = $Wifi
            graphics     = $Graphics
            npu          = $NPU
        }
        Invoke-RestMethod -Uri $webAppUrl -Method Post -Body ($payload | ConvertTo-Json) -ContentType "application/json" | Out-Null
    } catch {}
}

function Schedule-RemoveTempFolder {
    param([string]$FolderPath)
    try {
        $taskName = "RemoveKATKTools"
        schtasks /delete /tn $taskName /f 2>$null | Out-Null
        $command = "cmd.exe /c rmdir /s /q `"$FolderPath`""
        schtasks /create /tn $taskName /tr "$command" /sc onstart /ru SYSTEM /rl HIGHEST /f | Out-Null
    } catch {
    }
}

function Invoke-InstallSoftware {
    param([string]$RootTempDir)

    Write-Host "`n🚀 ĐANG MỞ CỬA SỔ CÀI ĐẶT PHẦN MỀM..." -ForegroundColor Magenta
    Write-Host "   💡 Vui lòng thao tác cài đặt phần mềm tự động tại cửa sổ mới" -ForegroundColor Cyan
    Write-Host "   ⚠️ VUI LÒNG KHÔNG ĐÓNG CỬA SỔ NÀY!" -ForegroundColor Yellow

    $katkBase = if ($global:KATK_BaseUrl) { $global:KATK_BaseUrl } else { "https://raw.githubusercontent.com/katk410/KATK-Tools/stable" }
    $command = "`$global:KATK_BaseUrl='$katkBase'; irm $katkBase/modules/AutoSetup/AppModule.ps1 | iex"

    try {
        $wtPath = Get-Command "wt.exe" -ErrorAction SilentlyContinue
        if ($wtPath) {
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = "wt.exe"
            $psi.Arguments = "-w -1 nt -p `"Windows PowerShell`" powershell.exe -NoExit -Command `"$command`""
            $psi.Verb = "RunAs"
            $psi.UseShellExecute = $true
            [System.Diagnostics.Process]::Start($psi) | Out-Null
        } else {
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = "powershell.exe"
            $psi.Arguments = "-NoExit -Command `"$command`""
            $psi.Verb = "RunAs"
            $psi.UseShellExecute = $true
            [System.Diagnostics.Process]::Start($psi) | Out-Null
        }
        Write-Host "   🔄 Bạn có thể tiếp tục các bước setup khác ở cửa sổ này." -ForegroundColor Cyan
    }
    catch {
        Write-Host "   ❌ Lỗi khi mở cửa sổ mới: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "   💡 Vui lòng chạy script với quyền Administrator và thử lại." -ForegroundColor Yellow
    }
}

function Invoke-DisableBitLocker {
    try {
        $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            Write-Host " ❗ VUI LÒNG CHẠY SCRIPT VỚI QUYỀN ADMINISTRATOR!" -ForegroundColor Red
            return
        }

        if (-not (Get-Module -Name "BitLocker" -ListAvailable)) {
            Write-Host " ⚠️ Module BitLocker không khả dụng trên hệ thống này" -ForegroundColor Yellow
            Write-Host "   Hệ thống có thể không hỗ trợ BitLocker hoặc chưa cài đặt tính năng" -ForegroundColor Gray
            return
        }

        Import-Module BitLocker -DisableNameChecking -ErrorAction SilentlyContinue

        Write-Host " 🔍 Đang kiểm tra trạng thái BitLocker..." -ForegroundColor Cyan

        $bitlockerVolumes = Get-BitLockerVolume -ErrorAction SilentlyContinue |
            Where-Object {
                $_.VolumeStatus -eq "FullyEncrypted" -or
                $_.VolumeStatus -eq "EncryptionInProgress" -or
                $_.ProtectionStatus -eq "On"
            }

        if (-not $bitlockerVolumes) {
            Write-Host " ⚡ Đang kiểm tra nhanh qua Manage-BDE..." -ForegroundColor Cyan
            try {
                $bdeStatus = & manage-bde -status 2>$null
                if ($bdeStatus -match "Protection Status:.*On") {
                    Write-Host " 📌 Phát hiện BitLocker đang bật qua Manage-BDE" -ForegroundColor Yellow
                    $bitlockerVolumes = @(
                        [PSCustomObject]@{
                            MountPoint = "C:"
                            VolumeStatus = "FullyEncrypted"
                            ProtectionStatus = "On"
                            EncryptionMethod = "Unknown"
                        }
                    )
                }
            }
            catch {
                Write-Host " ⚠️ Không thể kiểm tra BitLocker qua Manage-BDE" -ForegroundColor Yellow
            }
        }

        if (-not $bitlockerVolumes) {
            Write-Host " ✅ Không có ổ đĩa nào đang được bật BitLocker" -ForegroundColor Green
            Write-Host "   Tất cả ổ đĩa đã ở trạng thái không mã hóa" -ForegroundColor Gray
            return
        }

        $foundEncryptedVolume = $false

        foreach ($volume in $bitlockerVolumes) {
            $foundEncryptedVolume = $true
            Write-Host " 📌 Phát hiện ổ $($volume.MountPoint) đang được mã hóa:" -ForegroundColor Yellow
            Write-Host "   • Trạng thái: $($volume.VolumeStatus)" -ForegroundColor Gray
            Write-Host "   • Bảo vệ: $($volume.ProtectionStatus)" -ForegroundColor Gray

            Write-Host "`n 🔄 Đang tắt BitLocker cho ổ $($volume.MountPoint)..." -ForegroundColor Yellow

            try {
                $disableParams = @{
                    MountPoint = $volume.MountPoint
                    ErrorAction = "Stop"
                }
                try {
                    $disableParams["DisableHardwareEncryption"] = $true
                } catch {
                }

                Disable-BitLocker @disableParams

                Write-Host "   🚀 Đã bắt đầu quá trình giải mã nền!" -ForegroundColor Green
                Write-Host "   💡 Tiến trình sẽ tiếp tục chạy ngầm" -ForegroundColor Cyan
                Write-Host "   📊 Kiểm tra tiến trình: manage-bde -status $($volume.MountPoint)" -ForegroundColor Gray

                Write-Host "   ✅ Đã hoàn thành khởi tạo tắt BitLocker!" -ForegroundColor Green
            }
            catch {
                Write-Host "   ⚠️ Thử phương pháp thay thế..." -ForegroundColor Yellow
                try {
                    & manage-bde -off $volume.MountPoint
                    Write-Host "   ✅ Đã bắt đầu quá trình giải mã với Manage-BDE" -ForegroundColor Green
                    Write-Host "   📊 Kiểm tra tiến trình: manage-bde -status $($volume.MountPoint)" -ForegroundColor Gray
                }
                catch {
                    Write-Host "   ❗ Không thể tắt BitLocker: $($_.Exception.Message)" -ForegroundColor Red
                    Write-Host "   💡 Hãy thử tắt thủ công qua Control Panel" -ForegroundColor Yellow
                }
            }
            Write-Host ""
        }

        if ($foundEncryptedVolume) {
            Write-Host " 🎉 ĐÃ BẮT ĐẦU QUÁ TRÌNH TẮT BITLOCKER!" -ForegroundColor Green
            Write-Host " 📋 Quá trình giải mã sẽ tiếp tục trong nền" -ForegroundColor Gray
            Write-Host " 💡 Kiểm tra tiến trình sau: manage-bde -status" -ForegroundColor Cyan
            Write-Host " ⚡ Script hoàn thành nhanh chóng - BitLocker đang được tắt trong nền" -ForegroundColor Green
        }
    }
    catch {
        Write-Host " ❗ Lỗi hệ thống: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host " 💡 Nguyên nhân có thể:" -ForegroundColor Yellow
        Write-Host "   • Thiếu quyền Administrator" -ForegroundColor Gray
        Write-Host "   • Hệ thống không hỗ trợ BitLocker" -ForegroundColor Gray
        Write-Host "   • Chính sách nhóm (Group Policy) chặn thao tác" -ForegroundColor Gray
    }

    Write-Host ""
}

function Invoke-DesktopIcons {
    function Set-DesktopIcon {
        param([string]$IconName, [string]$RegistryPath, [int]$Value)
        try {
            $currentValue = Get-ItemProperty -Path $RegistryPath -Name $IconName -ErrorAction SilentlyContinue
            if ($currentValue.$IconName -ne $Value) {
                Set-ItemProperty -Path $RegistryPath -Name $IconName -Value $Value -ErrorAction Stop
                Write-Host " ✅ Đã thêm $IconName ra màn hình Desktop" -ForegroundColor Green
            } else {
                Write-Host " ℹ️ $IconName đã có sẵn trên màn hình desktop" -ForegroundColor Blue
            }
        }
        catch {
            Write-Host " ❗ Lỗi ${IconName}: $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    function Create-OfficeShortcut {
        param([string]$AppName, [string]$ExecutableName, [string]$DisplayName)
        try {
            $desktopPath = [Environment]::GetFolderPath("Desktop")
            $shortcutPath = Join-Path $desktopPath "$DisplayName.lnk"

            if (Test-Path $shortcutPath) {
                Write-Host " ℹ️ $DisplayName đã có sẵn trên desktop" -ForegroundColor Blue
                return
            }

            $officePaths = @(
                "C:\Program Files\Microsoft Office\root\Office16\$ExecutableName",
                "C:\Program Files (x86)\Microsoft Office\root\Office16\$ExecutableName",
                "C:\Program Files\Microsoft Office\Office16\$ExecutableName",
                "C:\Program Files (x86)\Microsoft Office\Office16\$ExecutableName",
                "C:\Program Files\Microsoft Office\Office15\$ExecutableName",
                "C:\Program Files (x86)\Microsoft Office\Office15\$ExecutableName"
            )

            $foundPath = $null
            foreach ($path in $officePaths) {
                if (Test-Path $path) {
                    $foundPath = $path
                    break
                }
            }

            if (-not $foundPath) {
                $registryPaths = @(
                    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\$ExecutableName",
                    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\$ExecutableName"
                )

                foreach ($regPath in $registryPaths) {
                    if (Test-Path $regPath) {
                        $foundPath = (Get-ItemProperty -Path $regPath -Name "(Default)" -ErrorAction SilentlyContinue)."(Default)"
                        if ($foundPath -and (Test-Path $foundPath)) {
                            break
                        }
                    }
                }
            }

            if ($foundPath) {
                $WshShell = New-Object -comObject WScript.Shell
                $Shortcut = $WshShell.CreateShortcut($shortcutPath)
                $Shortcut.TargetPath = $foundPath
                $Shortcut.WorkingDirectory = Split-Path $foundPath
                $Shortcut.Save()

                Write-Host " ✅ Đã thêm $DisplayName ra màn hình desktop" -ForegroundColor Green
            } else {
                Write-Host " ⚠️ Không tìm thấy $AppName trên hệ thống" -ForegroundColor Yellow
            }
        }
        catch {
            Write-Host " ❗ Lỗi khi tạo shortcut cho {$DisplayName}: $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    $registryPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel"

    try {
        if (!(Test-Path $registryPath)) {
            New-Item -Path $registryPath -Force | Out-Null
            Write-Host " ✅ Đã tạo registry key cho desktop icons" -ForegroundColor Green
        }

        Write-Host "`n🖥️ Đang thêm biểu tượng hệ thống..." -ForegroundColor Yellow
        Set-DesktopIcon -IconName "{20D04FE0-3AEA-1069-A2D8-08002B30309D}" -RegistryPath $registryPath -Value 0
        Set-DesktopIcon -IconName "{5399E694-6CE5-4D6C-8FCE-1D8870FDCBA0}" -RegistryPath $registryPath -Value 0

        Write-Host "`n📊 Đang thêm ứng dụng Office..." -ForegroundColor Yellow
        Create-OfficeShortcut -AppName "Word" -ExecutableName "WINWORD.EXE" -DisplayName "Microsoft Word"
        Create-OfficeShortcut -AppName "Excel" -ExecutableName "EXCEL.EXE" -DisplayName "Microsoft Excel"
        Create-OfficeShortcut -AppName "PowerPoint" -ExecutableName "POWERPNT.EXE" -DisplayName "Microsoft PowerPoint"

        Write-Host "`n🔄 Đang làm mới màn hình desktop..." -ForegroundColor Yellow
        Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3

        Write-Host "`n ✅ THIẾT LẬP DESKTOP ICON THÀNH CÔNG!" -ForegroundColor Green
        Write-Host " 📋 Đã thêm: This PC, Control Panel, Word, Excel, PowerPoint" -ForegroundColor Cyan
    }
    catch {
        Write-Host " ❗ Lỗi thiết lập desktop icons: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Invoke-PartitionDrive {
    $script:PartitionDriveLetter = $null
    try {
        $dDrive = Get-Partition -DriveLetter D -ErrorAction SilentlyContinue
        $driveTypeD = if ($dDrive) { Get-DriveType -DriveLetter "D" } else { $null }
        if ($dDrive -and $driveTypeD -eq 3) {
            Write-Host " ✅ PHÂN VÙNG D: ĐÃ TỒN TẠI - BỎ QUA" -ForegroundColor Blue
            $script:PartitionDriveLetter = "D"
            return
        }

        if ($dDrive -and $driveTypeD -eq 2) {
            Write-Host "`n ⚠️ Phát hiện thiết bị lưu trữ gắn ngoài!" -ForegroundColor Red
            Write-Host "   Phân vùng mới sẽ được gán ký tự ngẫu nhiên" -ForegroundColor Yellow
        }

        $cDrive = Get-Partition -DriveLetter C -ErrorAction Stop
        $cVolume = Get-Volume -DriveLetter C -ErrorAction Stop

        $cDriveFreeSpaceGB = [math]::Round($cVolume.SizeRemaining / 1GB, 2)
        $cDriveTotalSizeGB = [math]::Round($cDrive.Size / 1GB, 2)

        Write-Host " 📊 PHÂN VÙNG C: hiện tại: $cDriveTotalSizeGB GB (trống: $cDriveFreeSpaceGB GB)" -ForegroundColor Cyan

        if ($cDriveFreeSpaceGB -lt 20) {
            Write-Host " ❗ Cần ít nhất 20GB trống trên Phân vùng C:" -ForegroundColor Red
            return
        }

        $suggestedSize = [math]::Min(300, [math]::Round($cDriveFreeSpaceGB * 0.8))
        $suggestedSize = [math]::Max($suggestedSize, 20)

        do {
            Write-Host "`n 💾 NHẬP DUNG LƯỢNG CHO PHÂN VÙNG MỚI" -ForegroundColor Cyan
            Write-Host "   📏 Đề xuất: $suggestedSize GB" -ForegroundColor Green
            Write-Host "   📏 Tối đa: $([math]::Round($cDriveFreeSpaceGB - 10)) GB" -ForegroundColor Gray
            Write-Host "   ❗ Nên giữ lại cho Phân vùng C: tối thiểu 150GB để hệ thống hoạt động ổn định!"
            Write-Host "   ⏩ Nhập 0 để bỏ qua" -ForegroundColor Gray
            $inputSize = Read-Host "   ➡️ Dung lượng (GB)"

            if ($inputSize -eq "0") {
                Write-Host "`n ✅ ĐÃ BỎ QUA CHIA PHÂN VÙNG" -ForegroundColor Blue
                return
            }

            $sizeGB = 0
            $isValid = [double]::TryParse($inputSize, [ref]$sizeGB)

            if (-not $isValid -or $sizeGB -le 0) {
                Write-Host " ❗ Vui lòng ký tự hợp lệ" -ForegroundColor Red
                continue
            }

            if ($sizeGB -lt 10) {
                Write-Host " ❗ Dung lượng tối thiểu: 10GB!" -ForegroundColor Red
                continue
            }

            if ($sizeGB -gt ($cDriveFreeSpaceGB - 10)) {
                Write-Host " ❗ Vượt quá dung lượng khả dụng!" -ForegroundColor Red
                continue
            }

            break
        } while ($true)

        Write-Host "`n 🚀 ĐANG CHIA PHÂN VÙNG..." -ForegroundColor Magenta
        Write-Host "   ⏳ Vui lòng chờ trong giây lát..." -ForegroundColor Gray

        $shrinkSizeMB = [int]($sizeGB * 1024)
        $targetLetter = "D"
        if ($dDrive) {
            $usedLetters = (Get-Partition -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter }) | ForEach-Object { $_.DriveLetter }
            $candidate = "E"
            while ($candidate -le "Z") {
                if ($usedLetters -notcontains $candidate) {
                    $targetLetter = $candidate
                    break
                }
                $candidate = [char]([int][char]$candidate + 1)
            }
            if ($targetLetter -eq "D") {
                Write-Host " ❗ Không tìm thấy ký tự ổ trống!" -ForegroundColor Red
                return
            }
            Write-Host "   Ký tự phân vùng mới: $targetLetter`:" -ForegroundColor Cyan
        }

        $diskpartScript = @"
select volume c
shrink desired=$shrinkSizeMB
create partition primary
format quick fs=ntfs label="Data"
assign letter=$targetLetter
exit
"@

        $diskpartScript | diskpart | Out-Null

        if (Get-Partition -DriveLetter $targetLetter -ErrorAction SilentlyContinue) {
            $newPart = Get-Partition -DriveLetter $targetLetter
            $newSizeGB = [math]::Round($newPart.Size / 1GB, 2)

            Write-Host "`n ✅ KHỞI TẠO THÀNH CÔNG PHÂN VÙNG $targetLetter`:" -ForegroundColor Green
            Write-Host "   • Dung lượng: $newSizeGB GB" -ForegroundColor Gray
            Write-Host "   • Hệ thống file: NTFS" -ForegroundColor Gray
            Write-Host "   • Nhãn: Data" -ForegroundColor Gray
            $script:PartitionDriveLetter = $targetLetter
        } else {
            Write-Host " ❗ Không thể tạo Phân vùng $targetLetter`:" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "`n ❗ Lỗi: $($_.Exception.Message)" -ForegroundColor Red
    }

    Write-Host ""
}

function Invoke-SetDefaultSavePath {
    $driveLetter = $script:PartitionDriveLetter
    if (-not $driveLetter) {
        if (Test-Path "D:\") {
            $dt = Get-DriveType -DriveLetter "D"
            if ($dt -eq 3) {
                $driveLetter = "D"
            } else {
                Write-Host "`n ❌ Phân vùng D: đang là USB/Removable, không thể đặt vị trí lưu mặc định." -ForegroundColor Red
                return
            }
        } else {
            Write-Host "`n ❌ Phân vùng D: không tồn tại - BỎ QUA QUÁ TRÌNH THIẾT LẬP!" -ForegroundColor Red
            return
        }
    }

    $rootPath = "${driveLetter}:\"

    function Set-UserFolderPath {
        param([string]$FolderName, [string]$DisplayName, [string]$NewPath)
        try {
            if (!(Test-Path $NewPath)) {
                New-Item -Path $NewPath -ItemType Directory -Force | Out-Null
                Write-Host " 🔄 Khởi tạo thư mục: $NewPath" -ForegroundColor Gray
            }

            Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -Name $FolderName -Value $NewPath -ErrorAction Stop
            Write-Host " ✅ Đã chuyển $DisplayName sang: $NewPath" -ForegroundColor Green
        }
        catch {
            Write-Host " ❗ Lỗi {$DisplayName}: $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    try {
        Write-Host "`n 🔄 Đang thiết lập vị trí lưu trữ mặc định sang phân vùng $driveLetter`:" -ForegroundColor Yellow

        Set-UserFolderPath -FolderName "Personal" -DisplayName "Documents" -NewPath (Join-Path $rootPath "Documents")
        Set-UserFolderPath -FolderName "My Pictures" -DisplayName "Pictures" -NewPath (Join-Path $rootPath "Pictures")
        Set-UserFolderPath -FolderName "My Music" -DisplayName "Music" -NewPath (Join-Path $rootPath "Music")
        Set-UserFolderPath -FolderName "My Video" -DisplayName "Videos" -NewPath (Join-Path $rootPath "Videos")
        Set-UserFolderPath -FolderName "{374DE290-123F-4565-9164-39C4925E467B}" -DisplayName "Downloads" -NewPath (Join-Path $rootPath "Downloads")

        Write-Host "`n 🔄 Đang khởi động lại Explorer để áp dụng thay đổi..." -ForegroundColor Yellow
        Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3

        Write-Host " ✅ HOÀN TẤT THIẾT LẬP VỊ TRÍ LƯU TRỮ!" -ForegroundColor Green
    }
    catch {
        Write-Host " ❗ Lỗi thực thi: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Reset-TimeAndRegionAuto

Show-KATKBox "🖥️  THÔNG TIN HỆ THỐNG" -Color Yellow -TextColor White

$cimClasses = @('Win32_ComputerSystem','Win32_BIOS','Win32_Processor','Win32_PhysicalMemory','Win32_DiskDrive','Win32_VideoController')
$cimData = foreach ($class in $cimClasses) {
    Get-CimInstance -ClassName $class -ErrorAction SilentlyContinue
}

$computer   = $cimData | Where-Object { $_.CimClass.CimClassName -eq 'Win32_ComputerSystem' } | Select-Object -First 1
$bios       = $cimData | Where-Object { $_.CimClass.CimClassName -eq 'Win32_BIOS' } | Select-Object -First 1
$cpu        = $cimData | Where-Object { $_.CimClass.CimClassName -eq 'Win32_Processor' } | Select-Object -First 1
$ramModules = $cimData | Where-Object { $_.CimClass.CimClassName -eq 'Win32_PhysicalMemory' }
$diskDrives = $cimData | Where-Object { $_.CimClass.CimClassName -eq 'Win32_DiskDrive' }
$videoCards = $cimData | Where-Object { $_.CimClass.CimClassName -eq 'Win32_VideoController' }

$computerName = $env:COMPUTERNAME
$model = if ($computer) { $computer.Model } else { "N/A" }
$serialNumber = if ($bios) { $bios.SerialNumber } else { "N/A" }
$cpuInfo = if ($cpu) { " $($cpu.Name)" } else { " N/A" }

Write-Host ""
Write-Host " • Tên Máy:" -ForegroundColor White -NoNewline
Write-Host " $computerName" -ForegroundColor Cyan

Write-Host " • Model:" -ForegroundColor White -NoNewline
Write-Host " $model" -ForegroundColor Cyan

Write-Host " • S/N:" -ForegroundColor White -NoNewline
Write-Host " $serialNumber" -ForegroundColor Red

Write-Host " • CPU:" -ForegroundColor White -NoNewline
Write-Host $cpuInfo -ForegroundColor Cyan

$totalRam = 0
$ramDetail = @()
if ($ramModules) {
    $totalRam = [math]::Round(($ramModules | Measure-Object Capacity -Sum).Sum / 1GB)
    foreach ($stick in $ramModules) {
        $size = [math]::Round($stick.Capacity / 1GB)
        $speed = $stick.Speed
        $ramDetail += "$size GB $speed MHz"
    }
}
Write-Host " • RAM:" -ForegroundColor White -NoNewline
Write-Host " $totalRam GB ($($ramDetail -join ' + '))" -ForegroundColor Cyan
$ramInfo = " $totalRam GB ($($ramDetail -join ' + '))"

Write-Host " • Storage:" -ForegroundColor White
$storageDetails = @()
if ($diskDrives) {
    foreach ($disk in $diskDrives) {
        $sizeGB = [math]::Round($disk.Size / 1GB)
        $type = "SSD"
        if ($disk.Model -match "NVMe") { $type = "NVMe" }
        elseif ($disk.MediaType -match "HDD") { $type = "HDD" }
        elseif ($disk.Model -match "ST|WD|TOSHIBA") { $type = "HDD" }
        $diskInfo = "$($disk.Model) | $type | $sizeGB GB"
        Write-Host "   $diskInfo" -ForegroundColor Cyan
        $storageDetails += $diskInfo
    }
}
$storageInfo = $storageDetails -join ' | '

$dedicatedGPUs = @()
$integratedGPUs = @()
if ($videoCards) {
    foreach ($gpu in $videoCards) {
        $gpuName = $gpu.Name.Trim()
        if ($gpuName.Length -gt 90) { $gpuName = $gpuName.Substring(0,88) + "..." }
        if ($gpuName -match "NVIDIA|GeForce|RTX|GTX|AMD Radeon RX|AMD FirePro") {
            $dedicatedGPUs += $gpuName
        } elseif ($gpuName -notmatch "Remote|Mirror|Basic|Virtual|VMware|Hyper-V") {
            $integratedGPUs += $gpuName
        }
    }
}

if ($integratedGPUs.Count -gt 0) {
    Write-Host " • Card đồ họa tích hợp:" -ForegroundColor White
    foreach ($gpu in $integratedGPUs) { Write-Host "   $gpu" -ForegroundColor Cyan }
}
if ($dedicatedGPUs.Count -gt 0) {
    Write-Host " • Card đồ họa rời:" -ForegroundColor White
    foreach ($gpu in $dedicatedGPUs) { Write-Host "   $gpu" -ForegroundColor Green }
}
$graphicsParts = @()
if ($integratedGPUs.Count -gt 0) { $graphicsParts += "Onboard: " + ($integratedGPUs -join ", ") }
if ($dedicatedGPUs.Count -gt 0) { $graphicsParts += "Dedicated: " + ($dedicatedGPUs -join ", ") }
$graphicsInfo = $graphicsParts -join " | "

try {
    $realNPUs = @()
    $npuPattern = "NPU|Neural|AI|VPU|IPU|AI Boost|AI Engine|Hexagon"
    $npuDevices = Get-CimInstance -ClassName Win32_PnPEntity -Filter "Name LIKE '%$npuPattern%' AND ConfigManagerErrorCode = 0" -ErrorAction SilentlyContinue |
                  Where-Object { $_.Name -notmatch "HID|USB|Input|Virtual|Audio|Camera|Bluetooth|Firmware|Display" }
    foreach ($npu in $npuDevices) {
        if ($npu.Name) { $realNPUs += $npu.Name.Trim() }
    }
    if ($realNPUs.Count -eq 0 -and $cpu) {
        $cpuName = $cpu.Name
        if ($cpuName -match "Intel\(R\) Core\(TM\) Ultra") { $realNPUs += "Intel AI Boost (từ CPU)" }
        elseif ($cpuName -match "Ryzen.*AI") { $realNPUs += "AMD Ryzen AI (từ CPU)" }
        elseif ($cpuName -match "Snapdragon") { $realNPUs += "Qualcomm Hexagon NPU (từ CPU)" }
    }
    $realNPUs = $realNPUs | Sort-Object -Unique
    if ($realNPUs.Count -gt 0) {
        Write-Host " • NPU:" -ForegroundColor White
        foreach ($npu in $realNPUs) { Write-Host "   $npu" -ForegroundColor Green }
        $npuInfo = ($realNPUs -join " | ")
    } else { $npuInfo = "" }
} catch { $npuInfo = "" }

Write-Host " • Thông tin kết nối mạng:" -ForegroundColor White
$activeAdapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" -and $_.InterfaceDescription -notmatch "VMware|Virtual|Hyper-V" }
$ssid = try { (netsh wlan show interfaces | Select-String "SSID" | Select-Object -First 1).ToString().Split(":")[1].Trim() } catch { "" }
$publicIP = try { Invoke-RestMethod -Uri "https://api.ipify.org" -TimeoutSec 5 -ErrorAction Stop } catch { "Không lấy được IP Public" }

$wifiDetails = ""
foreach ($adapter in $activeAdapters) {
    $speedText = $adapter.LinkSpeed
    $ip = (Get-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress
    Write-Host "   Adapter: $($adapter.Name)" -ForegroundColor Cyan
    Write-Host "   Speed: $speedText" -ForegroundColor Gray
    if ($ssid) { Write-Host "   Mạng WiFi: $ssid" -ForegroundColor Gray }
    $numericSpeed = 0
    if ($speedText -match "([\d\.]+)\s*Gbps") { $numericSpeed = [double]$matches[1] * 1000 }
    elseif ($speedText -match "([\d\.]+)\s*Mbps") { $numericSpeed = [double]$matches[1] }
    if ($numericSpeed -ge 1000) { Write-Host "   Đánh giá: ⚡ Tốc độ rất nhanh" -ForegroundColor Green }
    elseif ($numericSpeed -ge 300) { Write-Host "   Đánh giá: ⚡ Tốc độ tốt" -ForegroundColor Green }
    elseif ($numericSpeed -ge 100) { Write-Host "   Đánh giá: ⚠️ Tốc độ trung bình" -ForegroundColor Yellow }
    else { Write-Host "   Đánh giá: ⚠️ Tốc độ thấp" -ForegroundColor Red }
    Write-Host ""
    if (-not $wifiDetails) {
        $wifiDetails = "WiFi: $ssid | Adapter: $($adapter.Name) | Speed: $speedText | IP Local: $ip | IP Public: $publicIP"
    }
}

$StartTimeObj = Get-CurrentSystemTime
$startTime = Format-DateTime $StartTimeObj

Write-Host " • Thời gian bắt đầu:" -ForegroundColor White -NoNewline
Write-Host " $startTime" -ForegroundColor Cyan

Show-KATKBox "⚠️  THÔNG BÁO QUAN TRỌNG" -Color Red -TextColor Yellow

Write-Host "   • Công cụ này sẽ thay đổi cấu hình hệ thống của bạn" -ForegroundColor Yellow
Write-Host "   • Sao lưu dữ liệu quan trọng trước khi tiếp tục" -ForegroundColor Yellow
Write-Host "   • Người dùng tự chịu trách nhiệm với các rủi ro phát sinh" -ForegroundColor Yellow
Write-Host "   • Nhà phát triển không chịu trách nhiệm về mất mát dữ liệu" -ForegroundColor Yellow

Show-KATKBox "💡  HƯỚNG DẪN NHANH" -Color Cyan -TextColor White

Write-Host "   • Tool sẽ tự động tải các phần mềm, người dùng thao tác cài đặt thủ công từng phần mềm" -ForegroundColor Gray
Write-Host "   • Sau khi hoàn tất cài đặt hãy đóng cửa sổ ứng dụng để update tiến trình" -ForegroundColor Gray
Write-Host "   • Có thể lựa chọn hủy cài đặt nếu không cần phần mềm đó" -ForegroundColor Gray
Write-Host "   • Tool sẽ yêu cầu nhập tay một số giá trị, vui lòng làm theo hướng dẫn" -ForegroundColor Gray
Write-Host "   • Quá trình có thể mất 05-10 phút tùy cấu hình" -ForegroundColor Gray

$insideCode = $null
do {
    Write-Host "`nNhập mã Inside để tiếp tục, hoặc nhập 'E' để hủy..." -ForegroundColor Green -NoNewline
    $userInput = Read-Host " "
    if ($userInput -eq 'E' -or $userInput -eq 'e') {
        Write-Host "`n❌ Đã hủy" -ForegroundColor Yellow
        return
    }
    if ($userInput -match '^\d+$') {
        Show-KATKBox "✅ Xác thực Inside hoàn tất! Chào mừng $userInput !" -Color Green -TextColor Yellow
        $insideCode = $userInput
        break
    } else {
        Show-KATKBox "❌ Mã Inside không hợp lệ! Vui lòng nhập một số hoặc 'E' để hủy." -Color Red -TextColor Yellow
    }
} while ($true)

$rootTempDir = "C:\KATK-Tools"
if (!(Test-Path $rootTempDir)) { New-Item -ItemType Directory -Path $rootTempDir -Force | Out-Null }

Show-KATKBox "✅ Đã xác nhận, bắt đầu quá trình cài đặt..." -Color Green -TextColor Yellow

Show-KATKBox "CÀI ĐẶT PHẦN MỀM" -Color Cyan -TextColor White
Invoke-InstallSoftware -RootTempDir $rootTempDir

Show-KATKBox "TẮT BITLOCKER" -Color Cyan -TextColor White
Invoke-DisableBitLocker

Show-KATKBox "THIẾT LẬP DESKTOP ICONS" -Color Cyan -TextColor White
Invoke-DesktopIcons

Show-KATKBox "CHIA PHÂN VÙNG" -Color Cyan -TextColor White
Invoke-PartitionDrive

Show-KATKBox "THIẾT LẬP VỊ TRÍ LƯU MẶC ĐỊNH" -Color Cyan -TextColor White
Invoke-SetDefaultSavePath

$EndTimeObj = Get-CurrentSystemTime
$EndTime = Format-DateTime $EndTimeObj
$totalTime = $EndTimeObj - $StartTimeObj
$totalTimeFormatted = Format-Duration $totalTime

Send-LogToGoogleSheet -StartTime $startTime `
                      -EndTime $EndTime `
                      -TotalTime $totalTimeFormatted `
                      -Inside $insideCode `
                      -ComputerName $computerName `
                      -Model $model `
                      -SerialNumber $serialNumber `
                      -CPU $cpuInfo `
                      -RAM $ramInfo `
                      -Storage $storageInfo `
                      -Wifi $wifiDetails `
                      -Graphics $graphicsInfo `
                      -NPU $npuInfo

Schedule-RemoveTempFolder -FolderPath $rootTempDir

Show-KATKBox "✅ CÀI ĐẶT HOÀN TẤT!" -Color Cyan -TextColor Yellow
Write-Host "   • Mọi vấn đề phát sinh vui lòng liên hệ: 107941" -ForegroundColor Gray
Write-Host "   • DEV BY KATK" -ForegroundColor Gray
Write-Host "   • Thư mục tạm $rootTempDir sẽ được xóa sau khi máy khởi động lại." -ForegroundColor Cyan

Wait-KATKBack
