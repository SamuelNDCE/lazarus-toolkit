# Proves Show-Box aligns and Start-ProgressTicker animates.
#
# Calls the REAL Show-Box and captures it via the information stream
# (6>&1), which is where Write-Host goes on PowerShell 5+. The first
# version of this test re-implemented Show-Box's arithmetic and compared
# that against itself, which would have passed happily while the shipped
# function stayed wrong. A test must exercise the thing, not a copy.
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'Tools\HealthReport\Common.ps1')

$cases = @(
    ,@('DOWNLOADING AND INSTALLING DRIVERS. DO NOT CLOSE THIS.',
       'Each driver is named below as it is installed.')
    ,@('SFC and DISM show their own percentage below.',
       'It can sit on one number for several minutes. That is normal.',
       'DO NOT CLOSE THIS WINDOW.')
    ,@('STALL DETECTED',
       'reading the system make and model',
       'did not respond in 20s. Skipped, the run continues.')
    ,@('one')
    ,@('a', 'considerably longer second line than the first one here')
)

$bad = 0
Write-Output 'BOXES (rendered by the real Show-Box)'
Write-Output '-------------------------------------'
foreach ($c in $cases) {
    $captured = @(Show-Box -Lines $c 6>&1 | ForEach-Object { [string]$_ })
    $lens = @($captured | ForEach-Object { $_.Length } | Sort-Object -Unique)
    if ($lens.Count -eq 1) {
        Write-Output ("  aligned    {0} lines, all {1} chars" -f $captured.Count, $lens[0])
    } else {
        Write-Output ("  MISALIGNED widths: {0}" -f ($lens -join ', '))
        $bad++
    }
    $captured | ForEach-Object { Write-Output "  $_" }
    Write-Output ''
}

Write-Output 'TICKER'
Write-Output '------'
# Two correct outcomes here, and which one applies depends on where this
# is running. In a real console the ticker animates and returns a handle.
# Redirected to a file or a pipe, \r cannot rewrite a line, so it prints
# one plain line and returns $null on purpose. Asserting a handle always
# comes back would fail this test precisely when the degradation it is
# meant to allow is working.
$t = Start-ProgressTicker 'pretending to download something'
if ([Console]::IsOutputRedirected) {
    if ($null -eq $t) { Write-Output '  output is redirected: ticker correctly degraded to one line' }
    else { Write-Output '  FAIL: ticker animated into a redirected stream'; $bad++ }
} else {
    if ($t -and $t.PS) { Write-Output '  real console: ticker started' }
    else { Write-Output '  FAIL: ticker did not start in a real console'; $bad++ }
}
Start-Sleep -Seconds 2
Stop-ProgressTicker $t
Write-Output '  ticker stopped cleanly'

Write-Output ''
if ($bad -eq 0) { Write-Output 'PASS: every box is perfectly rectangular'; exit 0 }
Write-Output "FAIL: $bad problem(s)"
exit 1
