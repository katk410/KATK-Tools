function Stop-OfficeProcesses {
    Show-Step "ĐANG DỪNG TIẾN TRÌNH OFFICE"
    $processes = @(
        "WINWORD", "EXCEL", "POWERPNT", "OUTLOOK", "ONENOTE", "MSACCESS", "MSPUB",
        "VISIO", "LYNC", "TEAMS", "OfficeClickToRun", "MicrosoftOffice", "Osa",
        "OsaAddin", "OsaUI", "MSOSYNC", "ONENOTEM", "OUTLOOKEXE"
    )
    foreach ($proc in $processes) {
        try {
            Get-Process -Name $proc -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        } catch {}
    }
    Write-Host "✔ Đã dừng toàn bộ tiến trình Office." -ForegroundColor Green
}

function Uninstall-ClickToRun {
    Show-Step "ĐANG GỠ CLICK-TO-RUN"
    $ctrPath = "C:\Program Files\Common Files\Microsoft Shared\ClickToRun\OfficeClickToRun.exe"
    if (Test-Path $ctrPath) {
        try {
            Start-Process $ctrPath -ArgumentList "scenario=install scenariosubtype=ARP sourcetype=None productstoremove=All" -Wait -NoNewWindow
            Write-Host "✔ Đã gỡ Click-to-Run." -ForegroundColor Green
        } catch {
            Write-Host "⚠ Không thể gỡ bằng Click-to-Run." -ForegroundColor Yellow
        }
    }
}

function Uninstall-MSI {
    Show-Step "ĐANG GỠ OFFICE BẢN MSI"
    try {
        $products = Get-WmiObject Win32_Product | Where-Object {
            $_.Name -match "Microsoft Office|Office 365|Microsoft 365|Visio|Project|Access|Excel|Outlook|PowerPoint|Word|Publisher|OneNote"
        }
        foreach ($product in $products) {
            Write-Host "→ Gỡ: $($product.Name)" -ForegroundColor Gray
            $product.Uninstall() | Out-Null
        }
        Write-Host "✔ Đã gỡ bản MSI." -ForegroundColor Green
    } catch {
        Write-Host "⚠ Không tìm thấy MSI package nào." -ForegroundColor Yellow
    }
}

function Remove-OfficeFiles {
    Show-Step "ĐANG XÓA FILE VÀ THƯ MỤC OFFICE..."
    $paths = @(
        "C:\Program Files\Microsoft Office",
        "C:\Program Files (x86)\Microsoft Office",
        "C:\Program Files\Common Files\Microsoft Shared\ClickToRun",
        "C:\ProgramData\Microsoft\Office",
        "$env:ProgramData\Microsoft\Office",
        "$env:LOCALAPPDATA\Microsoft\Office",
        "$env:APPDATA\Microsoft\Office",
        "$env:USERPROFILE\Documents\Microsoft Office",
        "$env:USERPROFILE\OneDrive - *",
        "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Microsoft Office Tools",
        "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Microsoft Office"
    )
    foreach ($path in $paths) {
        try {
            if (Test-Path $path) {
                Remove-Item $path -Recurse -Force -ErrorAction SilentlyContinue
                Write-Host "✔ Đã xóa: $path" -ForegroundColor Green
            }
        } catch {}
    }
}

function Remove-OfficeShortcuts {
    Show-Step "ĐANG XÓA SHORTCUT OFFICE"
    
    $shortcutNames = @(
        "Word", "Excel", "PowerPoint", "Outlook", "OneNote", 
        "Access", "Publisher", "Visio", "Skype for Business", 
        "Microsoft 365", "Office"
    )

    $desktop = [Environment]::GetFolderPath("Desktop")
    foreach ($name in $shortcutNames) {
        $shortcut = Join-Path $desktop "$name.lnk"
        if (Test-Path $shortcut) {
            Remove-Item $shortcut -Force -ErrorAction SilentlyContinue
            Write-Host "✔ Đã xóa shortcut Desktop: $name" -ForegroundColor Green
        }
    }

    $startMenuPaths = @(
        "$env:ProgramData\Microsoft\Windows\Start Menu\Programs",
        "$env:APPDATA\Microsoft\Windows\Start Menu\Programs"
    )
    foreach ($basePath in $startMenuPaths) {
        if (Test-Path $basePath) {
            foreach ($name in $shortcutNames) {
                $shortcut = Join-Path $basePath "$name.lnk"
                if (Test-Path $shortcut) {
                    Remove-Item $shortcut -Force -ErrorAction SilentlyContinue
                    Write-Host "✔ Đã xóa shortcut Start Menu: $name" -ForegroundColor Green
                }
            }
            $officeFolder = Join-Path $basePath "Microsoft Office"
            if (Test-Path $officeFolder) {
                Remove-Item $officeFolder -Recurse -Force -ErrorAction SilentlyContinue
                Write-Host "✔ Đã xóa thư mục Microsoft Office trong Start Menu" -ForegroundColor Green
            }
            $officeFolder2 = Join-Path $basePath "Microsoft Office Tools"
            if (Test-Path $officeFolder2) {
                Remove-Item $officeFolder2 -Recurse -Force -ErrorAction SilentlyContinue
                Write-Host "✔ Đã xóa thư mục Microsoft Office Tools trong Start Menu" -ForegroundColor Green
            }
        }
    }
}

function Remove-OfficeRegistry {
    Show-Step "ĐANG XÓA REGISTRY OFFICE..."
    $regPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Office",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office",
        "HKCU:\Software\Microsoft\Office",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\*\Products\*"
    )
    foreach ($reg in $regPaths) {
        try {
            if (Test-Path $reg) {
                Remove-Item $reg -Recurse -Force -ErrorAction SilentlyContinue
                Write-Host "✔ Đã xóa registry: $reg" -ForegroundColor Green
            }
        } catch {}
    }
    try {
        Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall" | ForEach-Object {
            if ($_.GetValue("DisplayName") -match "Microsoft Office|Office 365|Microsoft 365") {
                Remove-Item $_.PsPath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    } catch {}
    Write-Host "✔ Đã dọn registry." -ForegroundColor Green
}

function Remove-OfficeServicesAndTasks {
    Show-Step "ĐANG XÓA SERVICE VÀ TASK SCHEDULER"
    $services = @("ClickToRunSvc", "OfficeSvc", "Microsoft Office Groove Audit Service")
    foreach ($svc in $services) {
        try {
            Stop-Service $svc -Force -ErrorAction SilentlyContinue
            Set-Service $svc -StartupType Disabled -ErrorAction SilentlyContinue
            sc.exe delete $svc | Out-Null
            Write-Host "✔ Đã xóa service: $svc" -ForegroundColor Green
        } catch {}
    }
    try {
        Get-ScheduledTask -TaskPath "\Microsoft\Office\" -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$false
        Write-Host "✔ Đã xóa scheduled tasks của Office." -ForegroundColor Green
    } catch {}
}

function Clear-TempAndCache {
    Show-Step "DỌN TEMP VÀ CACHE"
    $tempPaths = @(
        "$env:TEMP\*",
        "$env:WINDIR\Temp\*",
        "$env:LOCALAPPDATA\Temp\*",
        "$env:APPDATA\Microsoft\Templates\*",
        "$env:APPDATA\Microsoft\Document Building Blocks\*"
    )
    foreach ($path in $tempPaths) {
        try {
            Remove-Item $path -Recurse -Force -ErrorAction SilentlyContinue
        } catch {}
    }
    Write-Host "✔ Đã dọn sạch temp và cache." -ForegroundColor Green
}

function Uninstall-Office {
    Clear-Host
    Show-KATKHeader "UNINSTALL OFFICE"

    Write-Host "`n⚠  VUI LÒNG SAO LƯU DỮ LIỆU TRƯỚC KHI TIẾP TỤC!" -ForegroundColor DarkRed
    Write-Host "⚠  DEV không chịu trách nhiệm về việc mất dữ liệu cá nhân.`n" -ForegroundColor DarkRed

    Write-Host "────────────────────────────────────────" -ForegroundColor DarkGray
    $confirm = Read-Host "Xác nhận gỡ Office? (Y/N)"
    if ($confirm -notmatch '^[Yy]$') {
        Write-Host "Đã hủy." -ForegroundColor Yellow
        return
    }
    Stop-OfficeProcesses
    Uninstall-ClickToRun
    Uninstall-MSI
    Remove-OfficeFiles
    Remove-OfficeShortcuts
    Remove-OfficeRegistry
    Remove-OfficeServicesAndTasks
    Clear-TempAndCache
    Show-Step "HOÀN TẤT GỠ OFFICE"
    Write-Host "✔ Đã gỡ Office thành công!" -ForegroundColor Green
    Write-Host "💡 Khuyến nghị khởi động lại máy trước khi cài mới." -ForegroundColor Cyan
}