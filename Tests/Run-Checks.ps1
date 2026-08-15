<#
=======================================================================
 RUN-CHECKS

 Every static check for this toolkit, in one command:

     .\Tests\Run-Checks.ps1

 Exits 0 if everything passes, non-zero with a count if not, so it can
 gate a commit.

 WHY THIS EXISTS, and why it is not just "does it parse".

 Three bugs shipped in this project that a parse check waved through:

   Info 'text'              called seven times, defined nowhere
   Spin'label' { }          a lost space turned a call into a command
   Start-DismWatchdog       called 400 lines above its own definition

 The first two vanished silently under SilentlyContinue. The third
 parsed, resolved, and died at runtime, because "the function exists
 somewhere in the file" is not the same as "the function exists yet".

 Every check here was added after something got through, and each one is
 proven against Fixtures\broken.ps1, a file that is deliberately wrong.
 A checker nobody has watched fail is not a checker.
=======================================================================
#>
param(
    # Defaults to the toolkit next to this script. Point it at a USB
    # stick to check a deployed copy: -Root D:\Tools\HealthReport
    [string]$Root,
    [switch]$SkipSelfTest
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
if (-not $Root) { $Root = Join-Path $repo 'HealthReport' }

$fail = 0
function Check($name, $ok, $detail = '') {
    if ($ok) { Write-Host ("  PASS  {0}" -f $name) -ForegroundColor Green }
    else     { Write-Host ("  FAIL  {0}  {1}" -f $name, $detail) -ForegroundColor Red; $script:fail++ }
}
function Section($t) { Write-Host ''; Write-Host $t -ForegroundColor Cyan }

$scripts = @('Common.ps1','Health-Report.ps1','Repair-Health.ps1') |
           ForEach-Object { Join-Path $Root $_ }

Section 'FILES'
foreach ($f in $scripts) { Check "$(Split-Path $f -Leaf) exists" (Test-Path $f) }
Check 'Health-Report.bat exists' (Test-Path (Join-Path $Root 'Health-Report.bat'))
if ($fail) { Write-Host ''; Write-Host 'Cannot continue without the scripts.' -ForegroundColor Red; exit $fail }

Section 'SYNTAX'
foreach ($f in $scripts) {
    $errs = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$null, [ref]$errs)
    Check "$(Split-Path $f -Leaf) parses" (-not ($errs -and $errs.Count)) `
          $(if ($errs -and $errs.Count) { "line $($errs[0].Extent.StartLineNumber): $($errs[0].Message)" })
}

# Sub-checker output is captured and only shown when something fails, so
# a clean run is a short readable list rather than three walls of detail.
function Run-SubCheck($script, $files) {
    $out = & (Join-Path $PSScriptRoot $script) -Files $files 2>&1
    return [pscustomobject]@{ Code = $LASTEXITCODE; Output = $out }
}

Section 'COMMANDS RESOLVE'
$r1 = Run-SubCheck 'check-commands.ps1' $scripts
Check 'every command resolves to a function, cmdlet or program' ($r1.Code -eq 0)
if ($r1.Code -ne 0) { $r1.Output | ForEach-Object { Write-Host "        $_" -ForegroundColor DarkGray } }

Section 'DEFINITION ORDER'
$r2 = Run-SubCheck 'check-order.ps1' $scripts
Check 'no function used before it is defined' ($r2.Code -eq 0)
if ($r2.Code -ne 0) { $r2.Output | ForEach-Object { Write-Host "        $_" -ForegroundColor DarkGray } }

Section 'STRUCTURE'
$r3 = Run-SubCheck 'audit.ps1' $scripts
Check 'no duplicate functions, no dead variables' ($r3.Code -eq 0)
if ($r3.Code -ne 0) { $r3.Output | Where-Object { $_ -match 'ISSUE' } | ForEach-Object { Write-Host "        $_" -ForegroundColor DarkGray } }

Section 'PROJECT RULES'
$repair = Get-Content (Join-Path $Root 'Repair-Health.ps1') -Raw
$common = Get-Content (Join-Path $Root 'Common.ps1') -Raw
$health = Get-Content (Join-Path $Root 'Health-Report.ps1') -Raw

$keys = @(([regex]"Key='([^']+)'").Matches($repair) | ForEach-Object { $_.Groups[1].Value })
$dupes = @($keys | Group-Object | Where-Object Count -gt 1)
Check "menu keys unique ($($keys.Count) tasks)" ($dupes.Count -eq 0) `
      $(if ($dupes.Count) { "duplicated: $(($dupes | ForEach-Object Name) -join ',')" })

# A lost space turns `Spin 'x' {}` into a command literally named
# `Spin'x'`. It parses, and the timeout it was carrying silently stops
# applying.
#
# Detected through the AST, not by searching the text. A text search for
# "Spin'" also matches the possessive in a comment ("Spin's timeout"),
# which made this check fail against a perfectly good file. Command names
# cannot be matched by accident.
$lostSpace = @()
foreach ($f in $scripts) {
    $a = [System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$null, [ref]$null)
    foreach ($c in $a.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)) {
        $n = $c.GetCommandName()
        if ($n -and $n -match "^Spin'") { $lostSpace += "$(Split-Path $f -Leaf):$($c.Extent.StartLineNumber)" }
    }
}
Check 'no lost-space Spin call sites' ($lostSpace.Count -eq 0) ($lostSpace -join ', ')

# Spin can return $null on timeout, and $null.Count is an error, so every
# array-valued call must go through AsArray or a stall becomes a crash.
Check 'no raw @(Spin ...) call sites' (-not ($repair -match '@\(Spin ' -or $health -match '@\(Spin '))

Check 'QuickEdit guard defined and invoked' `
      (($common -match 'function Disable-ConsoleQuickEdit') -and ($common -match '\$Script:QuickEditOff = Disable-ConsoleQuickEdit'))
Check 'AsArray helper defined'    ($common -match 'function AsArray')
Check 'Markdown report defined'   ($common -match 'function Write-MarkdownReport')
Check 'both tools load Common.ps1' (($health -match 'Common\.ps1') -and ($repair -match 'Common\.ps1'))
Check 'DISM watchdog wired to both DISM calls' `
      ((([regex]'Start-DismWatchdog').Matches($repair).Count) -ge 3)

$bat = Get-Content (Join-Path $Root 'Health-Report.bat') -Raw
Check 'launcher prefers Windows Terminal, with a fallback' `
      (($bat -match 'wt\.exe') -and ($bat -match ':classic') -and ($bat -match 'WT_SESSION'))
Check 'launcher still elevates' ($bat -match 'RunAs')

# ----------------------------------------------------------------------
# THE CHECKERS THEMSELVES, against a file that is deliberately wrong.
# Without this, a checker that silently stops working reports a clean
# project forever. That is not hypothetical: audit.ps1's dead-variable
# pass was a no-op for a while because a hashtable key called "keys"
# shadowed the .Keys member, and it cheerfully reported "no variables
# assigned and never read" having examined none.
# ----------------------------------------------------------------------
if (-not $SkipSelfTest) {
    Section 'THE CHECKERS CAN STILL FAIL'
    $fixture = Join-Path $PSScriptRoot 'Fixtures\broken.ps1'
    if (-not (Test-Path $fixture)) {
        Check 'broken fixture present' $false 'Tests\Fixtures\broken.ps1 is missing'
    } else {
        # Output suppressed. These runs are SUPPOSED to fail, so printing
        # their complaints would put alarming red text in a passing run.
        & (Join-Path $PSScriptRoot 'check-commands.ps1') -Files @($fixture) *>$null
        Check 'check-commands catches an undefined command' ($LASTEXITCODE -ne 0)

        & (Join-Path $PSScriptRoot 'check-order.ps1') -Files @($fixture) *>$null
        Check 'check-order catches use-before-definition' ($LASTEXITCODE -ne 0)

        & (Join-Path $PSScriptRoot 'audit.ps1') -Files @($fixture) *>$null
        Check 'audit catches a duplicate function and a dead variable' ($LASTEXITCODE -ne 0)
    }
}

Section 'RENDERING'
# Boxes are drawn by Show-Box, which sizes itself, but the padding
# arithmetic was wrong by one when first written and every box came out
# ragged. This renders the real function and measures the result.
$boxTest = Join-Path $PSScriptRoot 'test-boxes.ps1'
if (Test-Path $boxTest) {
    & $boxTest *>$null
    Check 'every box renders as a true rectangle' ($LASTEXITCODE -eq 0) `
          'run Tests\test-boxes.ps1 to see them'
} else {
    Check 'box renderer test present' $false 'Tests\test-boxes.ps1 is missing'
}

Write-Host ''
if ($fail -eq 0) { Write-Host 'ALL CHECKS PASSED' -ForegroundColor Green }
else { Write-Host "$fail CHECK(S) FAILED" -ForegroundColor Red }
exit $fail
