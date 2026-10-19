$global:KATK_Author = "DEV BY KATK"

function global:Show-KATKHeader {
    param(
        [string]$Title,
        [string]$Subtitle = $global:KATK_Author
    )

    $minWidth = 47
    $longest = [Math]::Max($Title.Length, $Subtitle.Length)
    $width = [Math]::Max($minWidth, $longest + 6)

    Write-Host ""
    Write-Host ("╔" + ("═" * $width) + "╗") -ForegroundColor Cyan
    Write-Host "║" -ForegroundColor Cyan -NoNewline
    Write-Host (Get-KATKCenter $Title $width) -ForegroundColor Yellow -NoNewline
    Write-Host "║" -ForegroundColor Cyan
    Write-Host "║" -ForegroundColor Cyan -NoNewline
    Write-Host (Get-KATKCenter $Subtitle $width) -ForegroundColor White -NoNewline
    Write-Host "║" -ForegroundColor Cyan
    Write-Host ("╚" + ("═" * $width) + "╝") -ForegroundColor Cyan
}

function global:Get-KATKCenter([string]$Text, [int]$Width) {
    $padding = [Math]::Max(0, $Width - $Text.Length)
    $left = [math]::Floor($padding / 2)
    return (" " * $left) + $Text + (" " * ($padding - $left))
}

function global:Show-KATKBox {
    param(
        [string]$Text,
        [string]$Color = "Cyan",
        [string]$TextColor = "White"
    )
    $Text = $Text.Trim()
    $width = [Math]::Max(47, $Text.Length + 6)
    Write-Host ""
    Write-Host ("╔" + ("═" * $width) + "╗") -ForegroundColor $Color
    Write-Host "║" -ForegroundColor $Color -NoNewline
    Write-Host (Get-KATKCenter $Text $width) -ForegroundColor $TextColor -NoNewline
    Write-Host "║" -ForegroundColor $Color
    Write-Host ("╚" + ("═" * $width) + "╝") -ForegroundColor $Color
}

function global:Write-KATKLine { Write-Host "────────────────────────────────────────" -ForegroundColor DarkGray }

function global:Show-Step([string]$Text) {
    Write-Host ""
    Write-Host "────────────────────────────────────────" -ForegroundColor Cyan
    Write-Host $Text -ForegroundColor Yellow
    Write-Host "────────────────────────────────────────" -ForegroundColor Cyan
    Write-Host ""
}

function global:Show-Banner([string]$Text) { Show-Step "▶ $Text" }

function global:Write-KATKBackOption([string]$Key = "0") {
    if ($global:KATK_InMenu) { Write-Host "[$Key] Quay lại menu chính" -ForegroundColor Red }
    else { Write-Host "[$Key] Thoát" -ForegroundColor Red }
}

function global:Exit-KATKModule {
    if ($global:KATK_InMenu) { throw "KATK_BACK" }
    exit
}

function global:Wait-KATKBack {
    Write-Host ""
    Write-KATKLine
    if ($global:KATK_InMenu) { Write-Host "Nhấn phím bất kỳ để quay lại menu chính..." -ForegroundColor Gray }
    else { Write-Host "Nhấn phím bất kỳ để thoát..." -ForegroundColor Gray }
    try { $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") } catch { $null = Read-Host }
}

function global:Test-KATKAdmin {
    $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function global:Assert-KATKAdmin {
    if (Test-KATKAdmin) { return }
    Show-KATKBox "⛔ VUI LÒNG CHẠY VỚI QUYỀN ADMINISTRATOR!" -Color Red -TextColor Yellow
    Wait-KATKBack
    Exit-KATKModule
}
