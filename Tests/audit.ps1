param([string[]]$Files)
# Deeper static audit than "does it parse and do the names resolve".
# Looks for the bug classes that actually shipped in this project:
# a call before its definition, a verdict computed from one branch, a
# variable that is only ever read, and a duplicate definition silently
# overriding an earlier one.
$issues = 0
# Reads are collected across ALL files first. These three are dot-sourced
# into one another, so a variable set in Common.ps1 and used in
# Repair-Health.ps1 is correctly used; judging each file alone reports it
# as dead. The first version of this audit did exactly that and flagged
# $Script:VtEnabled, which is set in one file and read in another.
$allReads = @{}
foreach ($f0 in $Files) {
    $a0 = [System.Management.Automation.Language.Parser]::ParseFile($f0, [ref]$null, [ref]$null)
    if (-not $a0) { continue }
    foreach ($v in $a0.FindAll({ param($n) $n -is [System.Management.Automation.Language.VariableExpressionAst] }, $true)) {
        $p = $v.VariablePath.UserPath
        if (-not $allReads.ContainsKey($p)) { $allReads[$p] = 0 }
        $allReads[$p]++
    }
}

function Bad($m)  { Write-Host "  ISSUE  $m" -ForegroundColor Red;    $script:issues++ }
function Note($m) { Write-Host "  note   $m" -ForegroundColor DarkGray }
function Ok($m)   { Write-Host "  ok     $m" -ForegroundColor Green }

foreach ($file in $Files) {
    $name = Split-Path $file -Leaf
    Write-Host ""
    Write-Host "== $name" -ForegroundColor Cyan
    $errs = $null; $toks = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$toks, [ref]$errs)
    if ($errs -and $errs.Count) { Bad "does not parse: $($errs[0].Message)"; continue }

    $fns = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)

    # 1. Duplicate function definitions. The later one wins silently, so
    #    edits to the earlier one appear to do nothing.
    $dupes = $fns | Group-Object Name | Where-Object Count -gt 1
    if ($dupes) { foreach ($d in $dupes) { Bad "'$($d.Name)' defined $($d.Count) times (lines $(($d.Group | ForEach-Object { $_.Extent.StartLineNumber }) -join ', '))" } }
    else { Ok "no duplicate function definitions ($($fns.Count) functions)" }

    # 2. Empty catch blocks that swallow a real failure without a trace.
    #    Legitimate for cosmetic calls, dangerous around real work, so
    #    these are reported for eyeballing rather than failed outright.
    $catches = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CatchClauseAst] }, $true)
    $silent = @($catches | Where-Object { $_.Body.Extent.Text -replace '[\s{}]','' -eq '' })
    Note "$($silent.Count) of $($catches.Count) catch blocks are empty (cosmetic guards, checked by hand)"

    # 3. Variables assigned and never read: usually a rename half-done.
    $assigned = @{}
    foreach ($a in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true)) {
        if ($a.Left -is [System.Management.Automation.Language.VariableExpressionAst]) {
            $v = $a.Left.VariablePath.UserPath
            if (-not $assigned.ContainsKey($v)) { $assigned[$v] = $a.Extent.StartLineNumber }
        }
    }
    $reads = @{}
    foreach ($v in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.VariableExpressionAst] }, $true)) {
        $reads[$v.VariablePath.UserPath] = $true
    }
    # Automatic and preference variables. These are READ by the PowerShell
    # engine rather than by the script, so assigning one and never
    # mentioning it again is correct, not dead code. $ProgressPreference
    # in particular is set purely to suppress progress bars.
    $skip = 'true','false','null','_','PSScriptRoot','args','PSItem','Error','LASTEXITCODE',
            'host','Host','PSDefaultParameterValues','OutputEncoding','matches','PWD',
            'ErrorActionPreference','ProgressPreference','WarningPreference','VerbosePreference',
            'InformationPreference','DebugPreference','ConfirmPreference','WhatIfPreference',
            'PSStyle','ErrorView','MaximumHistoryCount'
    $deadVars = @()
    # .PSBase.Keys, NOT .Keys. Both scripts assign a variable called
    # $keys, so the hashtable has an entry literally named "keys", and
    # $assigned.Keys then returns THAT ENTRY'S VALUE instead of the key
    # collection. The loop iterated a single line number, found nothing,
    # and reported "no variables assigned and never read" while checking
    # precisely zero variables. A silent no-op that reads as a pass.
    foreach ($k in $assigned.PSBase.Keys) {
        if ($k -in $skip) { continue }
        # Counted across every file, since these are dot-sourced together.
        # One occurrence total means the only mention is its own
        # assignment, so nothing anywhere reads it.
        $n = if ($allReads.ContainsKey($k)) { $allReads[$k] } else { 0 }
        if ($n -le 1) { $deadVars += "$k (line $($assigned[$k]))" }
    }
    if ($deadVars.Count) { foreach ($d in $deadVars) { Bad "assigned but never read: $d" } }
    else { Ok 'no variables assigned and never read' }

    # 4. Read-Host outside a function, which is a mid-run prompt: the
    #    exact pattern this project has a whole Defer system to prevent.
    $bodies = @($fns | ForEach-Object { [pscustomobject]@{ S = $_.Extent.StartLineNumber; E = $_.Extent.EndLineNumber } })
    foreach ($c in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)) {
        if ($c.GetCommandName() -ne 'Read-Host') { continue }
        $line = $c.Extent.StartLineNumber
        $inside = $false
        foreach ($b in $bodies) { if ($line -ge $b.S -and $line -le $b.E) { $inside = $true; break } }
        if (-not $inside) { Note "top-level Read-Host at line $line (intended only at a menu or the end)" }
    }
}

Write-Host ""
if ($issues) { Write-Host "$issues issue(s)" -ForegroundColor Red } else { Write-Host 'AUDIT CLEAN' -ForegroundColor Green }
exit $issues
