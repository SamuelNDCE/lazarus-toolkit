# Exercises the ACTUAL watchdog functions out of Repair-Health.ps1.
#
# The call sites live inside the SFC/DISM repair, which cannot be run
# casually. Everything so far has tested a COPY of the watchdog body,
# which proves the algorithm and not the shipped function. This lifts the
# real definitions out of the real file by AST and calls them, so a
# rename, a signature change or a bad return value cannot hide.
param([string]$Root)
if (-not $Root) { $Root = Join-Path (Split-Path $PSScriptRoot -Parent) 'Tools' }
$file = Join-Path $Root 'Repair-Health.ps1'
$ast  = [System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$null, [ref]$null)

$wanted = 'Start-StallWatch','Start-DismWatchdog','Start-SfcWatchdog','Stop-StallWatch'
$defs = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) |
        Where-Object { $_.Name -in $wanted }

Write-Output "found $($defs.Count) of $($wanted.Count) watchdog functions in the real file"
if ($defs.Count -ne $wanted.Count) {
    Write-Output ("MISSING: {0}" -f (($wanted | Where-Object { $_ -notin $defs.Name }) -join ', '))
    exit 1
}
foreach ($d in $defs) { . ([scriptblock]::Create($d.Extent.Text)) }

$fail = 0

Write-Output ''
Write-Output '1. Start-SfcWatchdog returns a usable handle'
$w = Start-SfcWatchdog
if ($w -and $w.PS -and $w.Handle) { Write-Output '   PASS' }
else { Write-Output "   FAIL (got '$w')"; $fail++ }

Write-Output ''
Write-Output '2. Stop-StallWatch accepts that handle without throwing'
try { Stop-StallWatch $w; Write-Output '   PASS' }
catch { Write-Output "   FAIL: $($_.Exception.Message)"; $fail++ }

Write-Output ''
Write-Output '3. Stop-StallWatch tolerates $null (the guard for a failed start)'
try { Stop-StallWatch $null; Write-Output '   PASS' }
catch { Write-Output "   FAIL: $($_.Exception.Message)"; $fail++ }

Write-Output ''
Write-Output '4. Start-DismWatchdog still works after the rename'
$d2 = Start-DismWatchdog
if ($d2 -and $d2.PS) { Write-Output '   PASS' } else { Write-Output '   FAIL'; $fail++ }
try { Stop-StallWatch $d2 } catch { }

Write-Output ''
if ($fail -eq 0) { Write-Output 'PASS: the shipped watchdog functions all behave'; exit 0 }
Write-Output "FAIL: $fail case(s)"
exit 1
