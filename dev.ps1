[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
$katkRef = "dev"
try {
    $katkRef = (Invoke-RestMethod -Uri "https://api.github.com/repos/katk410/KATK-Tools/commits/dev" -Headers @{ "User-Agent" = "KATK-Tools" } -UseBasicParsing -ErrorAction Stop).sha
}
catch { Write-Host "⚠ Không lấy được commit mới nhất, dùng nhánh dev (có thể chậm ~5 phút)." -ForegroundColor Yellow }
$global:KATK_NextBranch = $katkRef
$global:KATK_NextLabel = "DEV"
Invoke-Expression ((Invoke-RestMethod -Uri "https://raw.githubusercontent.com/katk410/KATK-Tools/$katkRef/KATK.ps1" -UseBasicParsing).TrimStart([char]0xFEFF))
