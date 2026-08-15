# Proves the report still lands somewhere when the tool folder is not
# writable. Lifts the real Get-ReportPath out of Health-Report.ps1 by AST
# so this tests the shipped function, not a copy of it.
param([string]$Root)
if (-not $Root) { $Root = Join-Path (Split-Path $PSScriptRoot -Parent) 'HealthReport' }
$src = Join-Path $Root 'Health-Report.ps1'
$ast = [System.Management.Automation.Language.Parser]::ParseFile($src, [ref]$null, [ref]$null)
$fn = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-ReportPath' }, $true) | Select-Object -First 1
if (-not $fn) { Write-Output 'FAIL: Get-ReportPath not found in the shipped script'; exit 1 }
. ([scriptblock]::Create($fn.Extent.Text))

$fail = 0

Write-Output '1. writable tool folder is preferred'
# Passed explicitly. Assigning $PSScriptRoot did nothing, because the
# function read the CALLER's script root, and the first version of this
# test reported a failure that existed only in the test.
$p = Get-ReportPath -Leaf 'report-TEST.txt' -PrimaryDir $env:TEMP
if ($p -and (Split-Path $p -Parent) -eq $env:TEMP) { Write-Output "   PASS -> $p" }
else { Write-Output "   FAIL -> $p"; $fail++ }

Write-Output ''
Write-Output '2. unwritable tool folder falls back, does not lose the report'
# A path that cannot be created or written: a file used as a directory.
$blocker = Join-Path $env:TEMP ('blocker-' + [guid]::NewGuid().ToString('N').Substring(0,6) + '.txt')
[System.IO.File]::WriteAllText($blocker, 'x')
$PSScriptRoot = Join-Path $blocker 'cannot-exist'
$p2 = Get-ReportPath -Leaf 'report-TEST.txt' -PrimaryDir $PSScriptRoot
if ($p2) {
    Write-Output "   PASS -> $p2"
    if ((Split-Path $p2 -Parent) -like '*Lazarus Reports*') { Write-Output '   (landed in the Documents fallback, as intended)' }
} else { Write-Output '   FAIL: returned nothing, the report would be lost'; $fail++ }
[System.IO.File]::Delete($blocker)

Write-Output ''
Write-Output '3. the returned path is genuinely writable'
if ($p2) {
    try {
        [System.IO.File]::WriteAllText($p2, 'probe')
        $back = [System.IO.File]::ReadAllText($p2)
        [System.IO.File]::Delete($p2)
        if ($back -eq 'probe') { Write-Output '   PASS' } else { Write-Output '   FAIL: read back wrong'; $fail++ }
    } catch { Write-Output "   FAIL: $($_.Exception.Message)"; $fail++ }
}

Write-Output ''
if ($fail -eq 0) { Write-Output 'PASS: the report always lands somewhere'; exit 0 }
Write-Output "FAIL: $fail case(s)"
exit 1

