[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

$global:KATK_Branch = if ($global:KATK_NextBranch) { $global:KATK_NextBranch } else { "stable" }
$global:KATK_NextBranch = $null

$global:KATK_BaseUrl = "https://raw.githubusercontent.com/katk410/KATK-Tools/$global:KATK_Branch"

$global:KATK_Version = "3.0"

try { Invoke-Expression (Invoke-RestMethod -Uri "$global:KATK_BaseUrl/core/UI.ps1" -UseBasicParsing -ErrorAction Stop) }
catch { Write-Host "❌ Không tải được giao diện KATK: $($_.Exception.Message)" -ForegroundColor Red; return }
$global:KATK_InMenu = $true

$KATK_Modules = [ordered]@{
    '1' = @{ Name = "KATK Setup";                   Desc = "Cài đặt tự động hệ thống cơ bản";                          Path = "modules/AutoSetup/AutoSetup.ps1" }
    '2' = @{ Name = "KATK Setup App";               Desc = "Chỉ cài đặt ứng dụng";                                     Path = "modules/AutoSetup/AppModule.ps1" }
    '3' = @{ Name = "KATK DisplaySetting";          Desc = "Thay đổi ngôn ngữ hiển thị Windows Home Single Language";  Path = "modules/DisplayLanguage/DisplayLanguage.ps1" }
    '4' = @{ Name = "KATK Windows Changes License"; Desc = "Thay đổi phiên bản Windows";                               Path = "modules/WindowsLicense/WindowsLicense.ps1" }
    '5' = @{ Name = "KATK Windows Configuration";   Desc = "Tối ưu hóa hệ thống Windows";                              Path = "modules/WindowsConfiguration/WindowsConfiguration.ps1" }
    '6' = @{ Name = "KATK Office Tools";            Desc = "Tools Uninstall và Install Office";                        Path = "modules/OfficeTools/OfficeTools.ps1" }
}

function Invoke-KATKModule {

    param([string]$Path)

    $url = "$global:KATK_BaseUrl/$Path"
    try {
        $code = Invoke-RestMethod -Uri $url -UseBasicParsing -ErrorAction Stop
    }
    catch {
        Write-Host "❌ Không thể tải module, vui lòng kiểm tra mạng hoặc liên hệ ADMIN!" -ForegroundColor Red
        Write-Host "   URL: $url" -ForegroundColor DarkGray
        Write-Host "   Chi tiết: $($_.Exception.Message)" -ForegroundColor DarkGray
        Wait-KATKBack
        return
    }
    try {
        Invoke-Expression $code
    }
    catch {

        if ("$($_.Exception.Message)" -ne "KATK_BACK") {
            Write-Host ""
            Write-Host "❌ Module gặp lỗi: $($_.Exception.Message)" -ForegroundColor Red
            Wait-KATKBack
        }
    }
}

function Show-KATKMenu {

    Clear-Host

    $title = "KATK TOOLS - VERSION $global:KATK_Version"; if ($global:KATK_Branch -ne "stable") { $title += " [$($global:KATK_Branch.ToUpper())]" }
    Show-KATKHeader $title "DEV BY KATK"

    Write-Host ""
    Write-Host "LỰA CHỌN CÔNG CỤ:" -ForegroundColor Yellow
    Write-Host "────────────────────────────────────────" -ForegroundColor DarkGray

    foreach ($key in $KATK_Modules.Keys) {
        Write-Host "[$key] $($KATK_Modules[$key].Name)" -ForegroundColor White
        Write-Host "    $($KATK_Modules[$key].Desc)" -ForegroundColor DarkGray
        Write-Host ""
    }

    Write-Host "[0] Thoát" -ForegroundColor Red
    Write-Host "────────────────────────────────────────" -ForegroundColor DarkGray
}

function Execute-Choice {

    param([string]$Choice)

    if ($Choice -eq '0') {
        Write-Host ""
        Write-Host "Đang thoát..." -ForegroundColor Yellow
        return $false
    }

    if ($KATK_Modules.Contains($Choice)) {
        $m = $KATK_Modules[$Choice]
        Show-Banner "Đang thực thi $($m.Name)"
        Invoke-KATKModule $m.Path
    }
    else {
        Write-Host ""
        Write-Host "❌ Lựa chọn không hợp lệ! Vui lòng chọn từ 0-$($KATK_Modules.Count)" -ForegroundColor Red
    }

    return $true
}

do {

    Show-KATKMenu

    $choice = Read-Host "`nNhập lựa chọn và nhấn Enter (0-$($KATK_Modules.Count))"

    $continue = Execute-Choice $choice

    if ($continue -and -not $KATK_Modules.Contains($choice)) { Start-Sleep -Seconds 1 }

} while ($continue)

$global:KATK_InMenu = $false
Write-Host ""
Write-Host "Cảm ơn bạn đã sử dụng KATK Setup!" -ForegroundColor Cyan
Write-Host "Nhấn phím bất kỳ để thoát..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
