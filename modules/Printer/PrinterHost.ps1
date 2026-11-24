param([ValidateSet('Server', 'Keeper', 'TestPage')][string]$Mode = 'Server')
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'PrinterCore.ps1')
if ($Mode -eq 'Server') {
    try { [KATKPrn.Server]::Run($global:KP_Dir) }
    catch {
        try { Add-Content -LiteralPath (Join-Path $global:KP_Dir 'server.log') -Value ((Get-Date).ToString('yyyy-MM-dd HH:mm:ss') + "  Dừng vì lỗi: " + $_.Exception.Message) -Encoding UTF8 } catch { }
        exit 1
    }
}
elseif ($Mode -eq 'TestPage') {
    $out = 'OK'
    try {
        $q = Read-KPJson (Join-Path $global:KP_Dir 'testpage.json')
        Invoke-KPTestPage -Queue $q.queue -ServerName $q.serverName -ServerPrinter $q.serverPrinter -Identity $q.identity
    } catch { $out = "$($_.Exception.Message)" }
    [IO.File]::WriteAllText((Join-Path $global:KP_Dir 'testpage.result'), $out)
}
else {

    $global:KP_CoreText = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'PrinterCore.ps1'))
    $global:KP_HostText = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'PrinterHost.ps1'))
    try { [void](Invoke-KPKeeper) } catch { }
}
