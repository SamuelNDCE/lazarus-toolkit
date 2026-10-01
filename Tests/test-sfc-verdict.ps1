# Proves the SFC verdict is read correctly out of CBS.log [SR] lines.
#
# Field bug: SFC printed "found corrupt files and successfully repaired
# them", and the tool then said "no integrity violations. Skipping DISM",
# because the verdict only recognised particular repair wording and called
# everything else clean. A clean pass writes exactly three kinds of [SR]
# line, so clean is now the absence of anything else.
#
# Runs the real functions out of Repair-Health.ps1 (lifted by AST, since
# the script itself would start a repair if dot-sourced).
$fail = 0
$src  = Join-Path (Split-Path $PSScriptRoot -Parent) 'Tools\Repair-Health.ps1'
$ast  = [System.Management.Automation.Language.Parser]::ParseFile($src, [ref]$null, [ref]$null)
foreach ($name in 'Test-SrRoutine', 'Get-SfcVerdict', 'Get-SfcDetail') {
    $fn = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
    if (-not $fn) { Write-Output "FAIL: $name not found in Repair-Health.ps1"; exit 1 }
    . ([scriptblock]::Create($fn.Extent.Text))
}

function L($m) { "2026-10-01 00:21:10, Info                  CSI    00000001 [SR] $m" }
$clean = @(
    (L 'Beginning Verify and Repair transaction'),
    (L 'Verifying 100 components'),
    (L 'Verifying 100 components'),
    (L 'Verify complete')
)

function Case($label, $lines, $want) {
    $got = Get-SfcVerdict $lines
    if ($got -eq $want) { Write-Output "   PASS  $label -> $got" }
    else { Write-Output "   FAIL  $label -> $got (wanted $want)"; $script:fail++ }
}

Write-Output 'Verdict'
Case 'a clean pass'                                   $clean 'clean'
Case 'nothing read at all'                            @() 'unknown'
Case 'the field bug: a repair in unfamiliar wording'  ($clean + (L 'Repairing 1 components') + (L 'Repair complete')) 'repaired'
Case 'a repair in the old wording'                    ($clean + (L 'Repairing corrupted file \??\C:\Windows\x.dll from store')) 'repaired'
Case 'damage it could not fix'                        ($clean + (L 'Cannot repair member file [l:10]"x.dll" of Y in the store, file is missing')) 'stuck'
Case 'stuck wins over repaired'                       ($clean + (L 'Repairing corrupted file x') + (L 'Cannot repair member file x')) 'stuck'
Case 'verify never finished'                          @((L 'Beginning Verify and Repair transaction')) 'unknown'

Write-Output ''
Write-Output 'Detail'
$d = Get-SfcDetail ($clean + (L 'Repair complete'))
if (($d -join ' ') -match 'Repair complete') { Write-Output '   PASS  a repair is shown in the words Windows used' }
else { Write-Output '   FAIL  the repair line was not shown'; $fail++ }
$d = Get-SfcDetail $clean
if (($d -join ' ') -match 'no integrity violations') { Write-Output '   PASS  a clean pass says nothing needed repairing' }
else { Write-Output '   FAIL  clean pass detail wrong'; $fail++ }

Write-Output ''
if ($fail -eq 0) { Write-Output 'PASS: SFC verdict reads correctly'; exit 0 }
Write-Output "FAIL: $fail case(s)"
exit 1
